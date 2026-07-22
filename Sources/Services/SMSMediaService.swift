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

    /// Lists installed videos by enumerating the `SMS_Media` partition
    /// root -- every entry there is a converted video file, sitting flat
    /// (see PFSDestinationPaths.smsMediaVideoPFSPath's doc comment). Returns
    /// an empty list (not an error) if the partition doesn't exist yet, same
    /// "nothing installed" semantics as an empty games/apps list.
    func listVideos(on disk: Disk) async throws -> [VideoFile] {
        guard try await ps1Service.partitionExists(named: PFSDestinationPaths.smsMediaPartitionName, on: disk) else {
            return []
        }
        let names = try await ps1Service.listFiles(
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: "/",
            on: disk
        )
        return names.map { VideoFile(filename: $0) }
    }

    /// Copies an already-converted video at `localURL` into the `SMS_Media`
    /// partition root as `filename`, creating the partition first if needed.
    /// Conversion itself (VideoConverter) happens before this is called --
    /// this method only ever touches the PS2 HDD.
    func addVideo(localURL: URL, filename: String, on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await ps1Service.createSMSMediaPartitionIfNeeded(on: disk)
        try await ps1Service.putFile(
            localURL: localURL,
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: PFSDestinationPaths.smsMediaVideoPFSPath(filename: filename),
            on: disk
        )
    }

    /// Removes a single video file. Uses removeFile (not removeTree) --
    /// videos are flat files at the partition root, not directories. See
    /// PS1GameService.removeFile's doc comment for why rmtree wouldn't work
    /// here.
    func deleteVideo(filename: String, on disk: Disk) async throws {
        try await ps1Service.removeFile(
            partitionName: PFSDestinationPaths.smsMediaPartitionName,
            pfsPath: PFSDestinationPaths.smsMediaVideoPFSPath(filename: filename),
            on: disk
        )
    }
}
