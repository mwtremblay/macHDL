import Foundation

/// A FreeMcBoot/FreeHDBoot homebrew app installed under `+OPL/APPS/` -- one
/// folder per app (e.g. "wLaunchELF", "Neutrino"), matching OPL's own
/// convention (see PFSDestinationPaths.oplAppsSubdirectory). No cover art, no
/// per-app metadata -- deliberately as thin as PS1Game, since this feature
/// doesn't need more than a name to list/add/delete.
struct InstalledApp: Identifiable, Hashable {
    /// The top-level folder name under `+OPL/APPS/` -- also the only
    /// identity pfsutil gives us, there's no separate internal ID.
    let folderName: String

    var id: String { folderName }
    var displayName: String { folderName }
}
