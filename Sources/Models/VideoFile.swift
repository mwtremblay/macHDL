import Foundation

/// A converted video file installed at the `SMS_Media` partition root -- one
/// file, no subdirectory, no per-video metadata. Deliberately as thin as
/// InstalledApp/PS1Game, since this feature doesn't need more than a
/// filename to list/add/delete.
struct VideoFile: Identifiable, Hashable {
    /// The exact filename at the `SMS_Media` partition root -- also the only
    /// identity pfsutil gives us, there's no separate internal ID.
    let filename: String

    var id: String { filename }

    /// filename with its extension stripped, for display -- e.g.
    /// "Movie.avi" -> "Movie".
    var displayName: String {
        (filename as NSString).deletingPathExtension
    }
}
