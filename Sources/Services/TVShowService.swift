import Foundation

/// Installs/lists/deletes converted TV episodes under `SMS_Media`'s
/// `Shows/<Show Name>/Season <N>/` -- a sibling to SMSMediaService, composing
/// PS1GameService's generic PFS primitives via composition rather than
/// duplicating them (same reasoning as SMSMediaService/AppsService's own doc
/// comments). Shares the `SMS_Media` partition with SMSMediaService rather
/// than getting its own: SMS browses directories fine (see
/// PFSDestinationPaths.smsMediaPartitionName's doc comment), and this is
/// still just "media" from the console's perspective.
final class TVShowService {
    private let ps1Service: PS1GameService

    init(ps1Service: PS1GameService) {
        self.ps1Service = ps1Service
    }

    /// Lists every installed episode by walking `Shows/` three levels deep:
    /// show folders, then each show's season folders, then each season's
    /// episode files. Returns an empty list (not an error) if the partition
    /// or `Shows/` itself doesn't exist yet, same "nothing installed"
    /// semantics as an empty games/apps list. A season folder that doesn't
    /// match `smsMediaSeasonFolderName`'s "Season N" convention (e.g. hand-
    /// edited on the drive) is skipped rather than crashing the whole list --
    /// there's no sane season number to show it under.
    ///
    /// Shows are walked concurrently (one listDirectories per show, each an
    /// independent hdl_dump/pfsutil subprocess round-trip against the real
    /// drive), and within each show, seasons are walked concurrently too --
    /// these are read-only listings with no ordering dependency on each
    /// other, unlike the partition-table writes elsewhere in this app that
    /// genuinely do need to stay sequential.
    func listEpisodes(on disk: Disk) async throws -> [TVEpisode] {
        guard try await ps1Service.partitionExists(named: PFSDestinationPaths.smsMediaPartitionName, on: disk) else {
            return []
        }
        let showNames = (try? await ps1Service.listDirectories(
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: PFSDestinationPaths.smsMediaShowsSubdirectory,
            on: disk
        )) ?? []

        return try await withThrowingTaskGroup(of: [TVEpisode].self) { group in
            for showName in showNames {
                group.addTask {
                    try await self.episodes(forShow: showName, on: disk)
                }
            }
            var episodes: [TVEpisode] = []
            for try await showEpisodes in group {
                episodes.append(contentsOf: showEpisodes)
            }
            return episodes
        }
    }

    private func episodes(forShow showName: String, on disk: Disk) async throws -> [TVEpisode] {
        let showPath = "\(PFSDestinationPaths.smsMediaShowsSubdirectory)/\(showName)"
        let seasonFolders = try await ps1Service.listDirectories(
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: showPath,
            on: disk
        )
        return try await withThrowingTaskGroup(of: [TVEpisode].self) { group in
            for seasonFolder in seasonFolders {
                guard let seasonNumber = Self.seasonNumber(fromFolderName: seasonFolder) else { continue }
                group.addTask {
                    let seasonPath = "\(showPath)/\(seasonFolder)"
                    let filenames = try await self.ps1Service.listFiles(
                        partitionName: PFSDestinationPaths.smsMediaPartitionName,
                        pfsPath: seasonPath,
                        on: disk
                    )
                    return filenames.map { TVEpisode(showName: showName, seasonNumber: seasonNumber, filename: $0) }
                }
            }
            var episodes: [TVEpisode] = []
            for try await seasonEpisodes in group {
                episodes.append(contentsOf: seasonEpisodes)
            }
            return episodes
        }
    }

    /// Whether `SMS_Media` already exists -- same purpose as
    /// SMSMediaService.smsMediaPartitionExists (shared partition, Shows and
    /// Movies just live in different subtrees of it), checked by
    /// AddTVEpisodeViewModel before installing so it can show
    /// PartitionSizePromptSheet first if it doesn't.
    func smsMediaPartitionExists(on disk: Disk) async throws -> Bool {
        try await ps1Service.partitionExists(named: PFSDestinationPaths.smsMediaPartitionName, on: disk)
    }

    /// Copies an already-converted episode at `localURL` into
    /// `Shows/<showName>/Season <seasonNumber>/<filename>`.
    /// `partitionSizeBytesIfCreating` is only used if `SMS_Media` doesn't
    /// exist yet -- see `smsMediaPartitionExists`'s doc comment; callers
    /// must have already resolved a size, never a silent hardcoded default.
    /// pfsutil creates every intermediate directory itself (see
    /// AppsDestination.appPFSPath's doc comment for the identical
    /// Apps-feature precedent) -- no separate mkdir step needed here.
    /// Conversion itself (VideoConverter) happens before this is called --
    /// this method only ever touches the PS2 HDD.
    func addEpisode(localURL: URL, showName: String, seasonNumber: Int, filename: String, partitionSizeBytesIfCreating: Int64, on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await ps1Service.createSMSMediaPartitionIfNeeded(sizeBytes: partitionSizeBytesIfCreating, on: disk)
        try await ps1Service.putFile(
            localURL: localURL,
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: PFSDestinationPaths.smsMediaShowEpisodePFSPath(showName: showName, seasonNumber: seasonNumber, filename: filename),
            on: disk
        )
    }

    /// Removes a single episode file. Uses removeFile (not removeTree) --
    /// this only ever removes one episode, never a whole season/show folder.
    /// Leftover empty season/show folders aren't cleaned up: SMS lists
    /// directories fine whether or not they're empty, and pfsutil has no
    /// bulk "remove if empty" primitive to reuse here.
    func deleteEpisode(showName: String, seasonNumber: Int, filename: String, on disk: Disk) async throws {
        try await ps1Service.removeFile(
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: PFSDestinationPaths.smsMediaShowEpisodePFSPath(showName: showName, seasonNumber: seasonNumber, filename: filename),
            on: disk
        )
    }

    /// Parses a season folder name back into its number, the inverse of
    /// PFSDestinationPaths.smsMediaSeasonFolderName -- e.g. "Season 3" -> 3.
    /// nil for anything that doesn't match that exact "Season <N>" shape.
    static func seasonNumber(fromFolderName folderName: String) -> Int? {
        let prefix = "Season "
        guard folderName.hasPrefix(prefix) else { return nil }
        return Int(folderName.dropFirst(prefix.count))
    }
}
