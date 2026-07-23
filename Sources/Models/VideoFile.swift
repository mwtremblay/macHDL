import Foundation

/// A converted video file installed under the `SMS_Media` partition -- no
/// per-video metadata beyond filename/location. Deliberately as thin as
/// InstalledApp/PS1Game otherwise.
struct VideoFile: Identifiable, Hashable {
    /// Where this file actually lives -- `SMSMediaService.listVideos` merges
    /// the current `Movies/` subdirectory with the legacy partition root
    /// (see `PFSDestinationPaths.smsMediaVideoPFSPath`'s doc comment), and a
    /// drive can genuinely have same-named files in both places. Tracking
    /// which one each entry came from is what lets `id` stay unique and lets
    /// `deleteVideo` target the exact file instead of guessing.
    enum Location: Hashable {
        case moviesSubdirectory
        case legacyRoot
    }

    let filename: String
    let location: Location

    var id: String {
        switch location {
        case .moviesSubdirectory: return "movies/\(filename)"
        case .legacyRoot: return "root/\(filename)"
        }
    }

    /// filename with its extension stripped, for display -- e.g.
    /// "Movie.avi" -> "Movie".
    var displayName: String {
        (filename as NSString).deletingPathExtension
    }
}
