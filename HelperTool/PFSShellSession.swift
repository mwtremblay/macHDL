import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Drives the vendored `pfsshell` binary as a persistent interactive child
/// process (not a one-shot argv tool like hdl_dump -- HelperProcessRunner is
/// not reusable here). Each PFS operation gets its own short-lived session:
/// launch, `device <path>`, run one or more commands, `exit`.
///
/// pfsshell has no non-interactive/scriptable mode; commands are typed at a
/// REPL and the only way to know a command finished is that its prompt
/// reappears. Confirmed empirically (see project memory) that prompts are
/// always exactly "> " (no device open), "# " (device open with a valid APA
/// scheme), or "<partition-name>:/# " (partition mounted) -- all three end
/// in "> " or "# ", so completion is detected generically by checking the
/// buffered output's suffix rather than matching a specific prompt string.
///
/// Uses a pseudo-terminal, NOT a plain Pipe, for pfsshell's stdio. Confirmed
/// by reading pfsshell's own source (no setvbuf/fflush calls anywhere) that
/// it relies entirely on libc's default stdio buffering, which is
/// line-buffered when stdout is a real tty but fully block-buffered
/// (silent until ~4KB accumulates or the process exits) when it's a plain
/// pipe -- this caused real timeouts on real hardware when first driven
/// through the daemon (a plain-Pipe version had worked in some earlier
/// calls seemingly by chance, then hung indefinitely on a short first
/// prompt). Every manual verification during this project happened through
/// a real terminal (even `echo ... | pfsshell` keeps stdOUT attached to the
/// real tty), which is why this was never caught until driven end-to-end.
/// A pty makes pfsshell behave exactly as it did in every manual test.
actor PFSShellSession {
    enum SessionError: Error, CustomStringConvertible {
        case launchFailed(String)
        case timedOut(command: String)
        case processExited(exitCode: Int32, output: String)

        var description: String {
            switch self {
            case .launchFailed(let message):
                return "could not launch pfsshell: \(message)"
            case .timedOut(let command):
                return "pfsshell timed out waiting for a response to '\(command)'"
            case .processExited(let exitCode, let output):
                return "pfsshell exited unexpectedly (code \(exitCode)): \(output)"
            }
        }
    }

    private let process: Process
    private let masterHandle: FileHandle
    private var buffer = ""
    private var pendingWaiter: CheckedContinuation<String, Error>?
    /// 20s was too aggressive on real hardware: a `sample` of a genuinely
    /// blocked pfsshell process (confirmed via `sample`, not guessed) showed
    /// it stuck inside `ata_device_sector_io`'s raw `read()` syscall, reached
    /// through unmounted `ls`/`lspart` -- which enumerates every partition
    /// on the drive with (at least) one raw read per partition header. This
    /// project already found and patched this exact drive's cheap USB-SATA
    /// bridge for being slow on many small individual reads (see
    /// hdl-dump-macos.patch's IIN_NUM_SECTORS change) -- pfsshell's own raw
    /// I/O path never got an equivalent fix, so listing a drive with 46+
    /// partitions can legitimately take longer than 20s. Not a hang: the
    /// same call already completed successfully once (for the `__common`
    /// partition-existence check) before intermittently exceeding 20s here.
    private static let defaultTimeout: TimeInterval = 90

    private init(process: Process, masterHandle: FileHandle) {
        self.process = process
        self.masterHandle = masterHandle
    }

    /// Launches pfsshell attached to a fresh pty, waits for its initial
    /// prompt, then opens the given device.
    static func open(devicePath: String) async throws -> PFSShellSession {
        let binary = try HelperToolBinaryLocator.resolvePFSShell()

        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw SessionError.launchFailed("openpty failed: \(String(cString: strerror(errno)))")
        }

        // Disable local echo on the pty's line discipline -- otherwise every
        // command we write to the master side gets echoed straight back
        // into the same read stream, duplicating it ahead of pfsshell's
        // actual response and corrupting prompt detection.
        var attrs = termios()
        tcgetattr(slaveFD, &attrs)
        attrs.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(slaveFD, TCSANOW, &attrs)

        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)

        let process = Process()
        process.executableURL = binary
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        let session = PFSShellSession(process: process, masterHandle: masterHandle)

        masterHandle.readabilityHandler = { [weak session] handle in
            let chunk = handle.availableData
            Task { await session?.handleOutput(chunk) }
        }
        process.terminationHandler = { [weak session] proc in
            Task { await session?.handleTermination(proc.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            Darwin.close(slaveFD)
            throw SessionError.launchFailed("\(error)")
        }
        // The child now holds its own fd table entries for the slave side
        // (set up synchronously as part of the spawn); close our copy so
        // the master side behaves correctly once the child exits.
        Darwin.close(slaveFD)

        _ = try await session.waitForPrompt(context: "startup")
        _ = try await session.send("device \(devicePath)")
        return session
    }

    /// Sends a command and returns its output (excluding the trailing prompt).
    @discardableResult
    func send(_ command: String) async throws -> String {
        buffer = ""
        masterHandle.write((command + "\n").data(using: .utf8)!)
        return try await waitForPrompt(context: command)
    }

    /// Sends `exit` and tears the process down. Never call `send` after this.
    func close() async {
        _ = try? await send("exit")
        forceTerminate()
    }

    /// Unconditionally terminates the child process without attempting a
    /// clean `exit` first -- for use when a prior command already threw
    /// (timed out, or the process already exited), where sending another
    /// command would just throw again. Without this, an error partway
    /// through a session left the child process (and the pty it holds)
    /// running indefinitely.
    func forceTerminate() {
        if process.isRunning {
            process.terminate()
        }
        masterHandle.readabilityHandler = nil
    }

    private func waitForPrompt(context: String) async throws -> String {
        if let ready = extractIfPromptPresent() {
            return ready
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingWaiter = continuation
            let capturedContext = context
            Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.defaultTimeout * 1_000_000_000))
                self.timeoutIfStillWaiting(context: capturedContext)
            }
        }
    }

    private func extractIfPromptPresent() -> String? {
        guard buffer.hasSuffix("> ") || buffer.hasSuffix("# ") else { return nil }
        let output = buffer
        buffer = ""
        return output
    }

    private func handleOutput(_ chunk: Data) {
        guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
        buffer += text
        if let waiter = pendingWaiter, let output = extractIfPromptPresent() {
            pendingWaiter = nil
            waiter.resume(returning: output)
        }
    }

    private func handleTermination(_ status: Int32) {
        if let waiter = pendingWaiter {
            pendingWaiter = nil
            waiter.resume(throwing: SessionError.processExited(exitCode: status, output: buffer))
        }
    }

    private func timeoutIfStillWaiting(context: String) {
        guard let waiter = pendingWaiter else { return }
        pendingWaiter = nil
        waiter.resume(throwing: SessionError.timedOut(command: context))
    }
}
