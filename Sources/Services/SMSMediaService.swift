import Foundation

/// Installs/lists/deletes converted video files under the dedicated
/// `SMS_Media` partition -- a sibling to AppsService, composing
/// PS1GameService's generic PFS primitives via composition rather than
/// duplicating them (same reasoning as AppsService/GameArtworkService's own
/// doc comments). Not folded into AppsService itself: `SMS_Media` is a
/// structurally different, brand-new dedicated partition, not a subfolder of
/// `+OPL/APPS/` the way SMS the *app* is.
final class SMSMediaService {
    private let ps1Service: PS1GameService

    init(ps1Service: PS1GameService) {
        self.ps1Service = ps1Service
    }

    /// Lists installed movies by merging two locations: the `Movies/`
    /// subdirectory (where new movies are installed, see addVideo) and the
    /// partition root (where movies installed before the `Movies/`
    /// subdirectory existed still sit -- see
    /// PFSDestinationPaths.smsMediaVideoPFSPath's doc comment). Either
    /// listing is skipped (not an error) if that path doesn't exist yet, same
    /// "nothing installed" semantics as an empty games/apps list.
    func listVideos(on disk: Disk) async throws -> [VideoFile] {
        guard try await ps1Service.partitionExists(named: PFSDestinationPaths.smsMediaPartitionName, on: disk) else {
            return []
        }
        // `Movies/` may not exist yet on an older/legacy drive -- treat that
        // the same as "no movies there yet" rather than failing the whole
        // list, matching partitionExists's own "nothing installed" semantics
        // above.
        let moviesNames = (try? await filesOnly(pfsPath: PFSDestinationPaths.smsMediaMoviesSubdirectory, on: disk)) ?? []
        let legacyRootNames = try await filesOnly(pfsPath: "/", on: disk)
        return moviesNames.map { VideoFile(filename: $0, location: .moviesSubdirectory) }
            + legacyRootNames.map { VideoFile(filename: $0, location: .legacyRoot) }
    }

    /// `PS1GameService.listFiles` actually returns every entry at pfsPath --
    /// files AND subdirectories -- with just the type suffix stripped,
    /// despite the name (confirmed in pfsutil's `cmd_list`/
    /// HDLDumpHelperService.listPFSFiles, which both just list-and-strip
    /// everything; `listDirectories` is the one that actually filters to
    /// directories). Found on real hardware: `SMS_Media`'s `Shows/`
    /// subdirectory was showing up in the Movies list because the root
    /// listing above never subtracted it out. `listDirectories` DOES filter
    /// to directories only, so subtracting its result from listFiles' is how
    /// this gets an actual files-only listing.
    private func filesOnly(pfsPath: String, on disk: Disk) async throws -> [String] {
        let (allNames, directoryNames) = try await ps1Service.listEntriesSplitByDirectory(
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: pfsPath,
            on: disk
        )
        return allNames.filter { !directoryNames.contains($0) }
    }

    /// Whether `SMS_Media` already exists -- checked by AddVideoViewModel/
    /// AddTVEpisodeViewModel before installing, so they can show
    /// PartitionSizePromptSheet first if it doesn't (this partition
    /// genuinely scales with drive size, see PartitionSizeSuggestions, so
    /// there's a real decision to surface rather than a silent default).
    func smsMediaPartitionExists(on disk: Disk) async throws -> Bool {
        try await ps1Service.partitionExists(named: PFSDestinationPaths.smsMediaPartitionName, on: disk)
    }

    /// Copies an already-converted video at `localURL` into the `SMS_Media`
    /// partition's `Movies/` subdirectory as `filename`. `partitionSizeBytesIfCreating`
    /// is only used if `SMS_Media` doesn't exist yet -- see
    /// `smsMediaPartitionExists`'s doc comment; callers must have already
    /// resolved a size via PartitionSizePromptSheet (or the setup wizard) in
    /// that case, never a silent hardcoded default. Conversion itself
    /// (VideoConverter) happens before this is called -- this method only
    /// ever touches the PS2 HDD.
    func addVideo(localURL: URL, filename: String, partitionSizeBytesIfCreating: Int64, on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await ps1Service.createSMSMediaPartitionIfNeeded(sizeBytes: partitionSizeBytesIfCreating, on: disk)
        try await ps1Service.putFile(
            localURL: localURL,
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: PFSDestinationPaths.smsMediaMoviePFSPath(filename: filename),
            on: disk
        )
    }

    /// Removes a single movie file, targeting the exact location `video`
    /// came from (`Movies/` subdirectory or legacy partition root -- see
    /// `VideoFile.location`'s doc comment). Deliberately not a
    /// try-the-current-location-then-fall-back-on-any-error scheme: a real
    /// failure at the correct location (permission denied, I/O error) would
    /// otherwise trigger a retry at the WRONG location, masking the actual
    /// error behind a misleading "not found" failure from the retry. Uses
    /// removeFile (not removeTree) -- movies are flat files, not
    /// directories. See PS1GameService.removeFile's doc comment for why
    /// rmtree wouldn't work here.
    func deleteVideo(_ video: VideoFile, on disk: Disk) async throws {
        let pfsPath: String
        switch video.location {
        case .moviesSubdirectory:
            pfsPath = PFSDestinationPaths.smsMediaMoviePFSPath(filename: video.filename)
        case .legacyRoot:
            pfsPath = PFSDestinationPaths.smsMediaVideoPFSPath(filename: video.filename)
        }
        try await ps1Service.removeFile(
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: pfsPath,
            on: disk
        )
    }
}
