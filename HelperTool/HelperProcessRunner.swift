import Foundation

/// Runs a bundled one-shot CLI binary (hdl_dump or pfsutil) as a direct
/// child process, running as root and giving the daemon a live process
/// handle it can signal for cancellation.
final class HelperProcessRunner {
    struct RunResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private var currentInstallProcess: Process?
    private let lock = NSLock()

    func run(
        binary: URL,
        arguments: [String],
        workingDirectory: URL,
        onOutputLine: ((String) -> Void)?,
        trackForCancellation: Bool
    ) async throws -> RunResult {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBuffer = LineRedrawBuffer(onLine: onOutputLine)
            let stderrBuffer = LineRedrawBuffer(onLine: onOutputLine)
            var stdoutData = Data()
            var stderrData = Data()
            let dataLock = NSLock()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                dataLock.lock(); stdoutData.append(chunk); dataLock.unlock()
                stdoutBuffer.append(chunk)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                dataLock.lock(); stderrData.append(chunk); dataLock.unlock()
                stderrBuffer.append(chunk)
            }

            process.terminationHandler = { [weak self] proc in
                // Nil-ing readabilityHandler cancels its dispatch source, but
                // Foundation gives no guarantee terminationHandler fires
                // after the last readabilityHandler callback has run -- so a
                // final synchronous drain is needed or the last chunk of
                // output (sometimes the one line that actually matters, e.g.
                // an "Operation not permitted" error) can be silently lost.
                // readDataToEndOfFile() returns promptly here since the
                // child has already exited and closed its end of the pipe.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if trackForCancellation {
                    self?.clearTrackedProcess(proc)
                }
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                dataLock.lock()
                if !remainingStdout.isEmpty {
                    stdoutData.append(remainingStdout)
                    stdoutBuffer.append(remainingStdout)
                }
                if !remainingStderr.isEmpty {
                    stderrData.append(remainingStderr)
                    stderrBuffer.append(remainingStderr)
                }
                let out = String(data: stdoutData, encoding: .utf8) ?? ""
                let err = String(data: stderrData, encoding: .utf8) ?? ""
                dataLock.unlock()
                continuation.resume(returning: RunResult(
                    exitCode: proc.terminationStatus,
                    stdout: out,
                    stderr: err
                ))
            }

            do {
                if trackForCancellation {
                    self.setTrackedProcess(process)
                }
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if trackForCancellation {
                    self.clearTrackedProcess(process)
                }
                continuation.resume(throwing: error)
            }
        }
    }

    /// Sends SIGINT (Process.interrupt(), not .terminate() which sends
    /// SIGTERM) to the currently-tracked install process, if any. hdl_dump
    /// installs its own SIGINT handler and aborts cleanly -- verified safe by
    /// reading the vendored source directly, see the plan for details.
    func cancelCurrentInstall() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let process = currentInstallProcess, process.isRunning else { return false }
        process.interrupt()
        return true
    }

    private func setTrackedProcess(_ process: Process) {
        lock.lock()
        currentInstallProcess = process
        lock.unlock()
    }

    private func clearTrackedProcess(_ process: Process) {
        lock.lock()
        if currentInstallProcess === process {
            currentInstallProcess = nil
        }
        lock.unlock()
    }
}

/// Splits raw process output on `\r` or `\n` (hdl_dump's progress bar redraws
/// with `\r`, not `\n`) and forwards each complete segment. Buffers partial
/// segments across `Data` chunk boundaries.
private final class LineRedrawBuffer {
    /// Undecoded trailing bytes -- a pipe read can end mid-way through a
    /// multi-byte UTF-8 character, and decoding a chunk in isolation (rather
    /// than accumulating raw bytes first) would fail and silently drop the
    /// whole chunk. Buffering raw `Data` here instead means a split
    /// character just waits for its remaining bytes on the next call.
    private var pendingBytes = Data()
    private var pendingText = ""
    private let onLine: ((String) -> Void)?
    private let lock = NSLock()

    init(onLine: ((String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard let onLine else { return }

        lock.lock()
        pendingBytes.append(data)
        guard let (text, consumedByteCount) = Self.decodeLongestValidPrefix(of: pendingBytes) else {
            lock.unlock()
            return
        }
        pendingBytes.removeFirst(consumedByteCount)
        pendingText += text
        let segments = pendingText.split(omittingEmptySubsequences: false) { $0 == "\r" || $0 == "\n" }
        pendingText = segments.last.map(String.init) ?? ""
        let complete = segments.dropLast().map(String.init)
        lock.unlock()

        for segment in complete where !segment.isEmpty {
            onLine(segment)
        }
    }

    /// Trims trailing bytes one at a time until the remainder decodes as
    /// UTF-8 -- at most 3 trims for a real split multi-byte character, since
    /// UTF-8's longest encoding is 4 bytes. Returns nil only if no prefix at
    /// all is valid yet (keeps accumulating rather than losing data).
    private static func decodeLongestValidPrefix(of data: Data) -> (text: String, consumedByteCount: Int)? {
        var candidate = data
        while !candidate.isEmpty {
            if let text = String(data: candidate, encoding: .utf8) {
                return (text, candidate.count)
            }
            candidate.removeLast()
        }
        return nil
    }
}
