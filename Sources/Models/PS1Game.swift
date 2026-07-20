import Foundation

/// A PS1 game installed for PopStarter -- a single `.VCD` file directly at
/// the root of a PS1 games PFS partition (see PFSDestinationPaths for why
/// there's no subdirectory). That partition is usually `__.POPS`, but may be
/// an overflow partition (`__.POPS1`-`__.POPS10`) once `__.POPS` fills up --
/// see `PS1GameService.installGameWithOverflow`. `partitionName` records
/// which one this specific game actually lives in, so delete/reinstall
/// target the right partition instead of always assuming `__.POPS`.
struct PS1Game: Identifiable, Hashable {
    /// The VCD filename at the partition root -- also the only identity
    /// pfsutil gives us, there's no separate internal ID.
    let vcdFilename: String
    let partitionName: String

    var id: String { vcdFilename }
    var displayName: String {
        vcdFilename.hasSuffix(".VCD") ? String(vcdFilename.dropLast(4)) : vcdFilename
    }
}
