import Foundation

/// Merges a "split" PS1 dump's multiple .bin files into a single combined
/// .bin/.cue pair via the vendored psx-vcd tool's `combine` subcommand --
/// the one thing cue2pops-mac cannot do (see CueSheetAnalyzer's doc comment
/// for cue2pops's exact rejection condition).
///
/// Deliberately narrow: this only ever invokes psx-vcd's `combine`
/// subcommand, never `auto`/`convert`. The merged .cue this produces is
/// still converted to .VCD via the existing, hardware-verified
/// PS1GameConverter/cue2pops-mac path, unchanged -- psx-vcd's own
/// VCD-writing behavior is never used by this app. This narrows the trust
/// placed in psx-vcd, a much lower-maturity tool (v0.1.1, single author, no
/// releases as of vendoring) than every other tool this app bundles.
///
/// Exit code convention confirmed by hands-on standalone testing before
/// this was written (not just reading psx-vcd's docs, per project
/// practice): 0 = success, non-zero = failure -- the ordinary Rust/anyhow
/// default, NOT cue2pops's inverted 1-means-success convention. Output
/// streams also confirmed empirically: progress goes to stdout on success,
/// error text goes to stderr on failure -- both are captured here (unlike
/// PS1GameConverter, which discards stderr because cue2pops is confirmed to
/// never use it).
struct SplitDumpCombiner {
    enum CombineError: Error, LocalizedError {
        case launchFailed(String)
        case combineFailed(output: String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let message):
                return "Could not launch psx-vcd: \(message)"
            case .combineFailed(let output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "psx-vcd failed to combine this split disc image." : trimmed
            }
        }
    }

    /// Combines the split dump referenced by `cueURL` into `scratchDir`
    /// (created by psx-vcd itself if it doesn't already exist -- confirmed
    /// empirically) and returns the URL of the resulting merged .cue.
    /// psx-vcd's `-f <name>` produces a BIN file literally named `<name>`
    /// (no extension appended) plus `<name>.cue` -- also confirmed
    /// empirically, not assumed from its --help text alone.
    func combine(cueURL: URL, into scratchDir: URL, onOutputLine: ((String) -> Void)? = nil) async throws -> URL {
        let binary = try BundledBinaryLocator.resolve(name: "psx-vcd", subdirectory: "psxvcd-bin")
        let baseName = "combined"
        let mergedCueURL = scratchDir.appendingPathComponent(baseName).appendingPathExtension("cue")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = ["combine", cueURL.path, "-o", scratchDir.path, "-f", baseName]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBuffer = LineBuffer(onLine: onOutputLine)
            let stderrBuffer = LineBuffer(onLine: onOutputLine)
            let stdoutData = SynchronizedDataBuffer()
            let stderrData = SynchronizedDataBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stdoutData.append(chunk)
                stdoutBuffer.append(chunk)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stderrData.append(chunk)
                stderrBuffer.append(chunk)
            }

            process.terminationHandler = { proc in
                // See HelperProcessRunner's identical fix -- terminationHandler
                // isn't guaranteed to fire after the last readabilityHandler
                // callback, so drain synchronously before reading the buffers.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !remainingStdout.isEmpty {
                    stdoutData.append(remainingStdout)
                    stdoutBuffer.append(remainingStdout)
                }
                if !remainingStderr.isEmpty {
                    stderrData.append(remainingStderr)
                    stderrBuffer.append(remainingStderr)
                }
                let out = stdoutData.text
                let err = stderrData.text

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: mergedCueURL)
                } else {
                    let combined = [err, out].filter { !$0.isEmpty }.joined(separator: "\n")
                    continuation.resume(throwing: CombineError.combineFailed(output: combined))
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: CombineError.launchFailed("\(error)"))
            }
        }
    }
}

/// Splits raw process output on `\n` and forwards each complete line.
/// Buffers raw bytes (not decoded-per-chunk text) across `Data` chunk
/// boundaries so a multi-byte UTF-8 character split across a pipe-read
/// doesn't silently drop the whole chunk -- see HelperProcessRunner's
/// LineRedrawBuffer/PS1GameConverter's LineBuffer for the identical,
/// already-fixed pattern this mirrors.
private final class LineBuffer {
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
