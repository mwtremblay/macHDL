import Foundation

/// Installs/lists/deletes FreeMcBoot/FreeHDBoot homebrew apps at whatever
/// `AppsDestination` this instance is configured for -- `+OPL/APPS/` for the
/// user-driven "Apps" tab by default, or `PP.FHDB.APPS` for the "Core Apps"
/// tab (see AppsDestination). A sibling to GameArtworkService/PS1GameService,
/// composing PS1GameService's generic PFS primitives via composition rather
/// than duplicating them -- same reasoning as GameArtworkService's own doc
/// comment.
final class AppsService {
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

        func relativeFiles() throws -> [URL] {
            guard let enumerator = fileManager.enumerator(
                at: extracted.rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw HDLDumpError.fileNotFound
            }
            var files: [URL] = []
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
                files.append(fileURL)
            }
            return files
        }

        let files = try relativeFiles()
        for (index, fileURL) in files.enumerated() {
            var relativePath = fileURL.path
            if relativePath.hasPrefix(rootPath) {
                relativePath.removeFirst(rootPath.count)
            }
            while relativePath.hasPrefix("/") { relativePath.removeFirst() }

            onFileProgress?(index + 1, files.count, relativePath)

            let pfsPath = destination.appPFSPath(appFolderName: appFolderName, relativePath: relativePath)
            try await ps1Service.putFile(
                localURL: fileURL,
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
}
