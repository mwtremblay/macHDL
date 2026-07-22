import Foundation

/// Lets a user view/replace/remove the individual fixed system files at
/// `__common/POPS/` after the fact -- a sibling to PopStarterSetupViewModel's
/// one-shot install flow, but for ad hoc single-file changes (e.g. swapping
/// in a different POPSTARTER.ELF build) rather than first-time setup.
/// Composes PS1GameService's generic PFS primitives via composition, same
/// reasoning as AppsService/GameArtworkService's own doc comments.
final class PopStarterSystemFilesService {
    private let ps1Service: PS1GameService

    init(ps1Service: PS1GameService) {
        self.ps1Service = ps1Service
    }

    /// Which of PopStarterSystemFile.all currently exist on the drive.
    /// Returns an empty set (not an error) if `__common` doesn't exist yet --
    /// same "nothing installed" semantics as AppsService/PS1GameService's own
    /// read methods.
    func installedFilenames(on disk: Disk) async throws -> Set<String> {
        guard try await ps1Service.partitionExists(named: PFSDestinationPaths.commonPartitionName, on: disk) else {
            return []
        }
        let names = try await ps1Service.listFiles(
            partitionName: PFSDestinationPaths.commonPartitionName,
            pfsPath: PFSDestinationPaths.popsSubdirectory,
            on: disk
        )
        return Set(names)
    }

    func replace(_ file: PopStarterSystemFile, localURL: URL, on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await ps1Service.createCommonPartitionIfNeeded(sizeBytes: PFSDestinationPaths.commonPartitionSizeBytes, on: disk)
        try await ps1Service.putFile(
            localURL: localURL,
            partitionName: PFSDestinationPaths.commonPartitionName,
            pfsPath: file.pfsPath,
            on: disk
        )
    }

    /// The view layer only ever offers this for `file.isOptional` files --
    /// removing one of the five required ones would silently break PS1
    /// support the next time a game is launched.
    func remove(_ file: PopStarterSystemFile, on disk: Disk) async throws {
        try await ps1Service.removeFile(
            partitionName: PFSDestinationPaths.commonPartitionName,
            pfsPath: file.pfsPath,
            on: disk
        )
    }
}
