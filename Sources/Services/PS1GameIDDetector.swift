import Foundation

/// Detects a PS1 game's Game ID (e.g. `SLUS_123.45`) from its original
/// `.cue`/`.bin` via the vendored `psx-vcd`'s `detect` subcommand -- needed
/// only to look up cover art (POPSLoader's own file-write convention is
/// filename-based, not Game-ID-based; see PFSDestinationPaths). Reuses the
/// already-vendored psx-vcd binary from split-dump support -- no new tool.
///
/// Confirmed empirically before writing this (per project practice --
/// psx-vcd's exit-code convention already burned this project once with
/// cue2pops's inverted convention, so nothing here is assumed from reading
/// `Vendor/psx-vcd/src/main.rs`'s `run_detect_mode` alone): non-verbose
/// `detect` prints a few progress lines to stdout, with the actual answer
/// always on the LAST line -- either the bare Game ID or the literal
/// sentinel `NOT_FOUND`. **Exit code 0 in both the found and not-found
/// cases** -- only a genuinely bad/unreadable input file (bad extension,
/// missing path) produces a non-zero exit, with the error on stderr.
struct PS1GameIDDetector {
    enum DetectError: Error, LocalizedError {
        case launchFailed(String)
        /// Non-zero exit -- bad/unreadable input, not just "no ID found".
        case detectionFailed(output: String)
        /// Exit 0, but the last stdout line was the `NOT_FOUND` sentinel --
        /// an expected outcome (psx-vcd's detection is a crude byte-pattern
        /// scan over only the first 150KB of the .bin, see utils.rs), not a
        /// real error.
        case notFound

        var errorDescription: String? {
            switch self {
            case .launchFailed(let message):
                return "Could not launch psx-vcd: \(message)"
            case .detectionFailed(let output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "psx-vcd failed to read this disc image." : trimmed
            case .notFound:
                return "Could not detect a Game ID for this disc image."
            }
        }
    }

    private static let notFoundSentinel = "NOT_FOUND"

    func detectGameID(cueOrBinURL: URL) async throws -> String {
        let binary = try BundledBinaryLocator.resolve(name: "psx-vcd", subdirectory: "psxvcd-bin")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = ["detect", cueOrBinURL.path]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutData = SynchronizedDataBuffer()
            let stderrData = SynchronizedDataBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stdoutData.append(chunk)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stderrData.append(chunk)
            }

            process.terminationHandler = { proc in
                // See HelperProcessRunner/SplitDumpCombiner's identical fix --
                // terminationHandler isn't guaranteed to fire after the last
                // readabilityHandler callback, so drain synchronously first.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !remainingStdout.isEmpty { stdoutData.append(remainingStdout) }
                if !remainingStderr.isEmpty { stderrData.append(remainingStderr) }
                let out = stdoutData.text
                let err = stderrData.text

                guard proc.terminationStatus == 0 else {
                    let combined = [err, out].filter { !$0.isEmpty }.joined(separator: "\n")
                    continuation.resume(throwing: DetectError.detectionFailed(output: combined))
                    return
                }

                let lastLine = out
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .last { !$0.isEmpty } ?? ""

                if lastLine == Self.notFoundSentinel {
                    continuation.resume(throwing: DetectError.notFound)
                } else {
                    continuation.resume(returning: lastLine)
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: DetectError.launchFailed("\(error)"))
            }
        }
    }
}
