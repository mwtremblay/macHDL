import Foundation

/// Converts a PS1 .cue/.bin pair to a POPStarter-compatible IMAGE0.VCD file
/// via the vendored cue2pops-mac tool. Runs unprivileged, directly from the
/// app (never through the daemon, unlike hdl_dump/pfsshell) -- this is pure
/// local-filesystem conversion and never touches the PS2 HDD.
struct PS1GameConverter {
    enum ConversionError: Error, LocalizedError {
        case launchFailed(String)
        case conversionFailed(output: String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let message):
                return "Could not launch cue2pops: \(message)"
            case .conversionFailed(let output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "cue2pops failed to convert this disc image." : trimmed
            }
        }
    }

    /// Converts `cueURL` to `outputVCDURL`. cue2pops resolves its referenced
    /// .bin using the .cue argument's own path (not the process's CWD) --
    /// confirmed by reading its source -- so `cueURL` must be an absolute
    /// path, which NSOpenPanel selections already are.
    ///
    /// Unlike hdl_dump/pfsshell, cue2pops uses an INVERTED exit-code
    /// convention -- 1 means success, 0 means failure -- confirmed by
    /// reading its source and testing standalone (see project memory). All
    /// of its output, including errors, goes to stdout, not stderr.
    func convert(cueURL: URL, outputVCDURL: URL, onOutputLine: ((String) -> Void)? = nil) async throws -> URL {
        let binary = try BundledBinaryLocator.resolve(name: "cue2pops", subdirectory: "cue2pops-bin")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = [cueURL.path, outputVCDURL.path]

            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = Pipe() // discarded -- cue2pops never writes to stderr

            let lineBuffer = LineBuffer(onLine: onOutputLine)
            let stdoutData = SynchronizedDataBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stdoutData.append(chunk)
                lineBuffer.append(chunk)
            }

            process.terminationHandler = { proc in
                // See HelperProcessRunner's identical fix -- terminationHandler
                // isn't guaranteed to fire after the last readabilityHandler
                // callback, so drain synchronously before reading the buffer.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty {
                    stdoutData.append(remaining)
                    lineBuffer.append(remaining)
                }
                let output = stdoutData.text

                if proc.terminationStatus == 1 {
                    continuation.resume(returning: outputVCDURL)
                } else {
                    continuation.resume(throwing: ConversionError.conversionFailed(output: output))
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: ConversionError.launchFailed("\(error)"))
            }
        }
    }
}

/// Splits raw process output on `\n` (cue2pops prints plain lines via printf,
/// not `\r` progress redraws like hdl_dump) and forwards each complete line.
private final class LineBuffer {
    /// See HelperProcessRunner.LineRedrawBuffer's identical field -- buffers
    /// raw bytes rather than decoding each chunk in isolation, so a
    /// multi-byte UTF-8 character split across a pipe-read boundary doesn't
    /// silently drop the whole chunk.
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
        var candidate = pendingBytes
        var decoded: String?
        while !candidate.isEmpty {
            if let text = String(data: candidate, encoding: .utf8) {
                decoded = text
                break
            }
            candidate.removeLast()
        }
        guard let decoded else {
            lock.unlock()
            return
        }
        pendingBytes.removeFirst(candidate.count)
        pendingText += decoded
        let lines = pendingText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        pendingText = lines.last ?? ""
        let complete = lines.dropLast()
        lock.unlock()

        for line in complete where !line.isEmpty {
            onLine(line)
        }
    }
}
