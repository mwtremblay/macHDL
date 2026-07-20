import Foundation

/// A PS1 game installed for PopStarter -- a single `.VCD` file directly at
/// the root of the `__.POPS` PFS partition (see PFSDestinationPaths for why
/// there's no subdirectory).
struct PS1Game: Identifiable, Hashable {
    /// The VCD filename at the partition root -- also the only identity
    /// pfsutil gives us, there's no separate internal ID.
    let vcdFilename: String

    var id: String { vcdFilename }
    var displayName: String {
        vcdFilename.hasSuffix(".VCD") ? String(vcdFilename.dropLast(4)) : vcdFilename
    }
}
