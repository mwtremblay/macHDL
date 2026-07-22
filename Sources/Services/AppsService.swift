import Foundation

/// Installs/lists/deletes FreeMcBoot/FreeHDBoot homebrew apps at whatever
/// `AppsDestination` this instance is configured for -- `+OPL/APPS/` for the
/// user-driven "Apps" tab by default, or `PP.FHDB.APPS` for the "Core Apps"
/// tab (see AppsDestination). A sibling to GameArtworkService/PS1GameService,
/// composing PS1GameService's generic PFS primitives via composition rather
/// than duplicating them -- same reasoning as GameArtworkService's own doc
/// comment.
final class AppsService {
    enum ServiceError: Error, LocalizedError {
        case noBootELFFound

        var errorDescription: String? {
            switch self {
            case .noBootELFFound:
                return "No .ELF file was found in this app archive, so OPL wouldn't be able to launch it. Install cancelled."
            }
        }
    }

    private let ps1Service: PS1GameService
    private let destination: AppsDestination

    init(ps1Service: PS1GameService, destination: AppsDestination = .oplApps) {
        self.ps1Service = ps1Service
        self.destination = destination
    }

    /// Lists installed apps by enumerating the destination's directory-only
    /// entries -- every entry there is expected to be an installed app's own
    /// folder (see listPFSDirectories's doc comment for why this uses a
    /// directory-only listing rather than listPFSFiles). Returns an empty
    /// list (not an error) if the destination partition doesn't exist yet --
    /// same "nothing installed" semantics as an empty games list.
    func listInstalledApps(on disk: Disk) async throws -> [InstalledApp] {
        guard try await ps1Service.partitionExists(named: destination.partitionName, on: disk) else {
            return []
        }
        let names = try await ps1Service.listDirectories(
            partitionName: destination.partitionName,
            pfsPath: destination.appsSubdirectory,
            on: disk
        )
        return names.map { InstalledApp(folderName: $0) }
    }

    /// Installs `extracted`'s content root into the destination's
    /// `<appFolderName>/` folder, preserving whatever relative folder
    /// structure it had. The caller's typed name always wins over whatever
    /// `extracted.suggestedAppFolderName` was -- see AddAppViewModel's doc
    /// comment for why. `onFileProgress` (index starting at 1, total,
    /// relative path just copied) is best-effort UI feedback -- some apps
    /// (e.g. wLaunchELF's theme/font files) install dozens of small files
    /// one XPC round-trip at a time, matching this project's existing "no
    /// batching" style throughout, so without this the UI would otherwise
    /// look frozen for several seconds.
    func installApp(
        extracted: AppArchiveExtractor.ExtractedApp,
        appFolderName: String,
        on disk: Disk,
        onFileProgress: ((Int, Int, String) -> Void)? = nil
    ) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await destination.ensurePartitionExists(ps1Service, disk)

        let fileManager = FileManager.default
        let rootPath = extracted.rootDirectory.path

        func relativeFiles() throws -> [(url: URL, relativePath: String)] {
            guard let enumerator = fileManager.enumerator(
                at: extracted.rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw HDLDumpError.fileNotFound
            }
            var files: [(url: URL, relativePath: String)] = []
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                // App archives come from the internet (community homebrew
                // sites), same threat model as any other downloaded
                // archive. unar preserves symlink entries verbatim on
                // extraction, and neither this enumeration nor pfsutil's
                // `open()` of the eventual local_source_path (no
                // O_NOFOLLOW) resolves/rejects them -- a symlink pointing
                // at, say, ~/.ssh/id_rsa would otherwise have its *target's*
                // contents silently copied onto the PS2 drive. Refuse
                // loudly rather than silently skip, so a malicious archive
                // can't quietly install everything except the payload with
                // no visible sign anything was withheld.
                if resourceValues.isSymbolicLink == true {
                    throw HDLDumpError.operationNotAllowed(
                        message: "This app archive contains a symbolic link (\(fileURL.lastPathComponent)), which is not supported for security reasons."
                    )
                }
                guard resourceValues.isDirectory != true else { continue } // pfsutil's `put` creates intermediate dirs itself
                var relativePath = fileURL.path
                if relativePath.hasPrefix(rootPath) {
                    relativePath.removeFirst(rootPath.count)
                }
                while relativePath.hasPrefix("/") { relativePath.removeFirst() }
                files.append((fileURL, relativePath))
            }
            return files
        }

        let files = try relativeFiles()

        if destination.requiresOPLTitleConfig {
            try await installOPLTitleConfigIfNeeded(files: files, appFolderName: appFolderName, on: disk)
        }

        for (index, file) in files.enumerated() {
            onFileProgress?(index + 1, files.count, file.relativePath)

            let pfsPath = destination.appPFSPath(appFolderName: appFolderName, relativePath: file.relativePath)
            try await ps1Service.putFile(
                localURL: file.url,
                partitionName: destination.partitionName,
                pfsPath: pfsPath,
                on: disk
            )
        }
    }

    /// Recursively removes an installed app's whole folder at the destination.
    func deleteApp(folderName: String, on disk: Disk) async throws {
        try await ps1Service.removeTree(
            partitionName: destination.partitionName,
            pfsPath: destination.appFolderPFSPath(appFolderName: folderName),
            on: disk
        )
    }

    /// OPL's own APPS-menu scanner (`src/opl.c`'s `scanApps()`) only
    /// recognizes a folder under `+OPL/APPS/` as an app if it directly
    /// contains a `title.cfg` with `title=`/`boot=` keys (`src/
    /// appsupport.c`'s `appScanCallback` silently skips the folder --
    /// "item has no boot/title" -- if either is missing); `boot=` is a path
    /// relative to that same folder and may itself contain further
    /// subfolders. Confirmed by reading OPL's own source directly (`src/
    /// opl.c`, `src/appsupport.c`, `include/appsupport.h`), not assumed --
    /// most community-distributed homebrew archives are packaged for
    /// uLaunchELF, not OPL specifically, and don't ship their own
    /// title.cfg, so without this an installed app is silently invisible
    /// in OPL's Apps menu no matter how correctly everything else was
    /// copied. `configWrite`'s own format (`src/config.c`) is a plain
    /// `key=value\r\n` pair per line -- matched exactly here.
    private func installOPLTitleConfigIfNeeded(
        files: [(url: URL, relativePath: String)],
        appFolderName: String,
        on disk: Disk
    ) async throws {
        let relativePaths = files.map(\.relativePath)
        guard !Self.hasExistingTitleConfig(relativePaths: relativePaths) else { return }

        guard let bootELF = Self.bestBootELFCandidate(relativePaths: relativePaths, appFolderName: appFolderName) else {
            throw ServiceError.noBootELFFound
        }

        guard let data = Self.titleConfigContents(appFolderName: appFolderName, bootRelativePath: bootELF).data(using: .utf8) else { return }
        let scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macHDL-title-cfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDir) }
        let localURL = scratchDir.appendingPathComponent("title.cfg")
        try data.write(to: localURL)

        try await ps1Service.putFile(
            localURL: localURL,
            partitionName: destination.partitionName,
            pfsPath: destination.appPFSPath(appFolderName: appFolderName, relativePath: "title.cfg"),
            on: disk
        )
    }

    /// Whether `relativePaths` (an installed app's own files, relative to
    /// its folder root) already includes an OPL-recognizable `title.cfg`
    /// at that root -- if so, the archive's own title.cfg is trusted as-is
    /// and never overwritten. Case-insensitive since OPL's own filesystem
    /// layer isn't guaranteed to distinguish case even though the literal
    /// constant OPL looks for (`APP_TITLE_CONFIG_FILE`) is lowercase.
    static func hasExistingTitleConfig(relativePaths: [String]) -> Bool {
        relativePaths.contains { $0.caseInsensitiveCompare("title.cfg") == .orderedSame }
    }

    /// Picks which `.elf` becomes title.cfg's `boot=` value when
    /// `relativePaths` has no title.cfg of its own -- see
    /// installOPLTitleConfigIfNeeded's doc comment for the full reasoning.
    /// nil if `relativePaths` contains no `.elf` file at all.
    static func bestBootELFCandidate(relativePaths: [String], appFolderName: String) -> String? {
        let elfCandidates = relativePaths.filter { $0.lowercased().hasSuffix(".elf") }
        guard !elfCandidates.isEmpty else { return nil }

        // Prefer an ELF whose own filename matches the app's folder name
        // (the common case for a well-packaged app); otherwise the
        // shallowest one (fewest path components) as the least-surprising
        // default; otherwise the alphabetically-first for a deterministic
        // result.
        return elfCandidates.first { path in
            (path as NSString).lastPathComponent
                .replacingOccurrences(of: ".elf", with: "", options: [.caseInsensitive])
                .caseInsensitiveCompare(appFolderName) == .orderedSame
        } ?? elfCandidates.min {
            let leftDepth = $0.components(separatedBy: "/").count
            let rightDepth = $1.components(separatedBy: "/").count
            return leftDepth != rightDepth ? leftDepth < rightDepth : $0 < $1
        }
    }

    /// Matches OPL's own `configWrite` format (`src/config.c`) exactly --
    /// plain `key=value` pairs, one per line, CRLF line endings.
    static func titleConfigContents(appFolderName: String, bootRelativePath: String) -> String {
        "title=\(appFolderName)\r\nboot=\(bootRelativePath)\r\n"
    }
}
