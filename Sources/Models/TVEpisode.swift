import Foundation

/// A converted TV episode installed under `SMS_Media`'s
/// `Shows/<Show Name>/Season <N>/` -- flat, not a nested Show/Season/Episode
/// tree of its own types, matching this codebase's preference for thin
/// models (see VideoFile/InstalledApp's own doc comments). TVShowListView
/// groups a `[TVEpisode]` array into a Show > Season > Episode tree for
/// display; the model itself doesn't need to.
struct TVEpisode: Identifiable, Hashable {
    let showName: String
    let seasonNumber: Int
    /// The exact filename within its season folder -- the only identity
    /// pfsutil gives us for the file itself.
    let filename: String

    var id: String { "\(showName)/\(seasonNumber)/\(filename)" }

    /// filename with its extension stripped, for display -- e.g.
    /// "01 - Serenity.avi" -> "01 - Serenity".
    var displayName: String {
        (filename as NSString).deletingPathExtension
    }
}
