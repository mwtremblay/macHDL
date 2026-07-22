import Foundation

/// Extracts a FreeMcBoot/FreeHDBoot homebrew app archive (.zip/.7z/.rar) via
/// the vendored `unar` tool. Runs unprivileged, directly from the app (never
/// through the daemon, like PS1GameConverter) -- this is pure local-
/// filesystem extraction and never touches the PS2 HDD. See Scripts/
/// build-unar.sh for how the binary is vendored (LGPL-2.1-or-later,
/// MacPaw/XADMaster) -- running it as a subprocess, never linking it into
/// this app's own binary, keeps LGPL compliance simple, same reasoning as
/// hdl_dump (GPL) being vendored the same way.
struct AppArchiveExtractor {
    struct ExtractedApp {
        /// The directory whose *contents* should be walked and installed --
        /// either the archive's own single wrapping folder, or the scratch
        /// root itself for a flat archive. Not necessarily == scratchRoot.
        let rootDirectory: URL
        /// The whole scratch tree to delete once installation is done.
        let scratchRoot: URL
        /// Pre-filled default for the app's destination folder name -- the
        /// caller (AddAppViewModel) may let the user override this; it is
        /// NOT necessarily used as the actual destination name.
        let suggestedAppFolderName: String
    }

    enum ExtractionError: Error, LocalizedError {
        case launchFailed(String)
        case extractionFailed(output: String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let message):
                return "Could not launch unar: \(message)"
            case .extractionFailed(let output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "unar failed to extract this archive." : trimmed
            }
        }
    }

    /// Extracts `archiveURL` into a fresh scratch temp directory, then
    /// determines the app's content root and suggested folder name (see
    /// ExtractedApp's doc comments). Confirmed by direct experimentation
    /// (not assumed) against the real vendored `unar`: given
    /// `-output-directory <scratchDir>`, unar ALWAYS produces exactly one
    /// top-level child of scratchDir, a directory -- reusing the archive's
    /// own folder name if the archive already has exactly one top-level
    /// entry that's a directory, or otherwise synthesizing one named after
    /// the archive's own filename (e.g. "FlatTool.zip" containing loose
    /// files extracts to "scratchDir/FlatTool/..."; a zip with a real
    /// "RealApp/" folder plus a spurious "__MACOSX/" sibling extracts to
    /// "scratchDir/WithJunk/{RealApp/,__MACOSX/}", not "scratchDir/RealApp/"
    /// directly). So this always drills one level in unconditionally, then
    /// checks whether THAT wrapper's own children (ignoring `__MACOSX`/
    /// `.DS_Store`) are themselves just a single real subfolder -- if so,
    /// that inner folder is the true content root and its name is used
    /// instead of unar's synthetic one; otherwise unar's own wrapper
    /// (whatever it's named) is the content root.
    func extract(archiveURL: URL) async throws -> ExtractedApp {
        let binary = try BundledBinaryLocator.resolve(name: "unar", subdirectory: "unar-bin")

        let scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macHDL-app-extract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)

        try await runUnar(binary: binary, archiveURL: archiveURL, outputDirectory: scratchDir)

        guard let wrapperDir = try Self.singleRealSubdirectory(of: scratchDir) else {
            // Should not happen (unar always produces exactly one top-level
            // directory), but fall back to scratchDir itself rather than
            // crashing if some archive format ever behaves differently.
            return ExtractedApp(
                rootDirectory: scratchDir,
                scratchRoot: scratchDir,
                suggestedAppFolderName: archiveURL.deletingPathExtension().lastPathComponent
            )
        }

        if let innerDir = try Self.singleRealSubdirectory(of: wrapperDir) {
            return ExtractedApp(rootDirectory: innerDir, scratchRoot: scratchDir, suggestedAppFolderName: innerDir.lastPathComponent)
        }

        return ExtractedApp(rootDirectory: wrapperDir, scratchRoot: scratchDir, suggestedAppFolderName: wrapperDir.lastPathComponent)
    }

    /// Returns `directory`'s single child if -- after filtering out
    /// `__MACOSX`/`.DS_Store` junk entries real-world Mac-built .zip archives
    /// often contain -- there is exactly one entry left and it's itself a
    /// directory. Returns nil otherwise (multiple entries, a single loose
    /// file, or nothing).
    private static func singleRealSubdirectory(of directory: URL) throws -> URL? {
        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" }

        guard children.count == 1,
              try children[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            return nil
        }
        return children[0]
    }

    private func runUnar(binary: URL, archiveURL: URL, outputDirectory: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = binary
            // -force-overwrite is defensive, not load-bearing (outputDirectory
            // is always a fresh UUID-named scratch dir). Deliberately preserve
            // unar's own top-level wrapping-folder behavior (no -no-directory
            // flag) -- that structure is exactly what the single-folder
            // detection above needs to see.
            process.arguments = ["-force-overwrite", "-output-directory", outputDirectory.path, archiveURL.path]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let outputData = SynchronizedDataBuffer()
            for pipe in [stdoutPipe, stderrPipe] {
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { return }
                    outputData.append(chunk)
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                outputData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                outputData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                let output = outputData.text

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ExtractionError.extractionFailed(output: output))
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: ExtractionError.launchFailed("\(error)"))
            }
        }
    }
}
