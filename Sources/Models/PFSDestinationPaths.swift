import Foundation

/// Centralizes PopStarter/OPL's PFS path conventions -- confirmed against
/// the POPSLoader project's own README
/// (https://github.com/NathanNeurotic/POPSLoader), not just community
/// tutorials. An earlier version of this file put each game in its own
/// subdirectory inside `__.POPS` with a fixed `IMAGE0.VCD` filename -- that
/// was WRONG, confirmed by a real hardware test where a game installed that
/// way never appeared in POPStarter's menu. The README states this
/// explicitly, twice: the game layout table gives `hdd:/__.POPS/GameName.VCD`
/// (no subdirectory, named after the game), and the Troubleshooting section
/// says outright: "Verify that VCD files are placed directly in the `POPS`
/// (or `__.POPS`) folder, not inside subfolders." The `IMAGE0.VCD`
/// fixed-filename convention belongs to a *different*, separate scheme
/// (`PP.GameName/IMAGE0.VCD`, one whole APA partition per game) that the
/// README itself marks "new, validating on hardware" -- not what this app
/// uses. See project memory for the full incident.
enum PFSDestinationPaths {
    /// The dedicated PFS partition holding every PS1 game's VCD, directly at
    /// its root -- no per-game subdirectory. (PopStarter also recognizes
    /// `__.POPS1` through `__.POPS10` as overflow partitions -- unused by
    /// this app, everything goes in the single `__.POPS` partition.)
    static let gamesPartitionName = "__.POPS"

    /// The dedicated PFS partition holding POPStarter's shared emulator
    /// binaries -- POPS.ELF/IOPRP252.IMG (Sony-copyrighted, user-supplied)
    /// and POPSTARTER.ELF (freely redistributable, bundled by this app).
    /// This is a partition in its own right, not a subdirectory of `__.POPS`.
    static let commonPartitionName = "__common"

    static let popsSubdirectory = "POPS"

    static let popsElfFilename = "POPS.ELF"
    static let ioprpImageFilename = "IOPRP252.IMG"
    static let popstarterElfFilename = "POPSTARTER.ELF"
    /// POPSLOADER.ELF and PATCH_5.BIN (both freely redistributable, GPLv3,
    /// bundled by this app) -- confirmed via real hardware testing (2026-07-20)
    /// that OPL needed both of these, alongside POPSTARTER.ELF, in the same
    /// `POPS` folder to actually launch a game; not documented as a hard
    /// requirement anywhere, found by the user having to manually add them.
    static let popsloaderElfFilename = "POPSLOADER.ELF"
    static let patch5BinFilename = "PATCH_5.BIN"

    /// POPS.PAK/POPS_IOX.PAK -- like POPS.ELF/IOPRP252.IMG, these are
    /// Sony-copyrighted, BIOS-derived files this app never bundles; the user
    /// must supply their own. Unlike POPS.ELF/IOPRP252.IMG, real-hardware
    /// testing (2026-07-20) showed a game launches fine without them, so
    /// they're treated as optional (POPS_IOX.PAK in particular is understood
    /// to only matter for PopStarter's network modes, unused by this app).
    static let popsPakFilename = "POPS.PAK"
    static let popsIoxPakFilename = "POPS_IOX.PAK"

    /// POPStarter (not POPSLoader) enforces this as a hard cap on the VCD
    /// filename -- confirmed in the POPSLoader README's Troubleshooting
    /// section: a 73-character filename launches, a 74-character one does
    /// not, in their own testing. Includes the ".VCD" extension.
    static let maxGameFilenameLength = 73

    /// Builds the destination filename for a game's VCD from its display
    /// name -- always an uppercase ".VCD" extension (recommended by the
    /// README for case-sensitive detection), truncated to fit
    /// `maxGameFilenameLength` if needed. This is also the file's PFS-side
    /// path directly, since it sits at the partition root.
    static func gameVCDFilename(forGameNamed name: String) -> String {
        let suffix = ".VCD"
        let maxBaseLength = maxGameFilenameLength - suffix.count
        let base = String(name.prefix(maxBaseLength))
        return base + suffix
    }

    /// PFS-side paths (within the `__common` partition) for the shared
    /// PopStarter system files.
    static var popsElfPFSPath: String { "\(popsSubdirectory)/\(popsElfFilename)" }
    static var ioprpImagePFSPath: String { "\(popsSubdirectory)/\(ioprpImageFilename)" }
    static var popstarterElfPFSPath: String { "\(popsSubdirectory)/\(popstarterElfFilename)" }
    static var popsloaderElfPFSPath: String { "\(popsSubdirectory)/\(popsloaderElfFilename)" }
    static var patch5BinPFSPath: String { "\(popsSubdirectory)/\(patch5BinFilename)" }
    static var popsPakPFSPath: String { "\(popsSubdirectory)/\(popsPakFilename)" }
    static var popsIoxPakPFSPath: String { "\(popsSubdirectory)/\(popsIoxPakFilename)" }
}
