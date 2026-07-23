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
    /// its root -- no per-game subdirectory. PopStarter also recognizes
    /// `__.POPS1` through `__.POPS10` as overflow partitions -- PFS
    /// partitions can't be resized in place (confirmed: pfsshell's full
    /// command table has no resize/grow command), so once `__.POPS` fills
    /// up, this app automatically creates and installs into the next
    /// overflow partition rather than failing the install. See
    /// `allGamesPartitionNamesInOrder` and `PS1GameService.
    /// installGameWithOverflow`.
    static let gamesPartitionName = "__.POPS"

    /// PopStarter's own documented overflow-partition cap.
    static let maxGamesPartitionOverflowIndex = 10

    /// `__.POPS`, then `__.POPS1` through `__.POPS10`, in the order this app
    /// tries them (both for installing a new game and for enumerating
    /// existing ones).
    static var allGamesPartitionNamesInOrder: [String] {
        [gamesPartitionName] + (1...maxGamesPartitionOverflowIndex).map { "\(gamesPartitionName)\($0)" }
    }

    /// The dedicated PFS partition holding POPStarter's shared emulator
    /// binaries -- POPS.ELF/IOPRP252.IMG (Sony-copyrighted, user-supplied)
    /// and POPSTARTER.ELF (freely redistributable, bundled by this app).
    /// This is a partition in its own right, not a subdirectory of `__.POPS`.
    static let commonPartitionName = "__common"

    /// POPS.ELF/IOPRP252.IMG/POPSTARTER.ELF/POPSLOADER.ELF/PATCH_5.BIN/
    /// POPS.PAK/POPS_IOX.PAK are all small system files -- this only needs
    /// to comfortably fit those seven plus headroom. Single source of truth
    /// shared by PopStarterSetupViewModel and PopStarterSystemFilesService,
    /// which both need to create `__common` if it doesn't exist yet.
    static let commonPartitionSizeBytes: Int64 = 64_000_000

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

    /// Open PS2 Loader's own dedicated PFS partition for its configuration,
    /// game-list cache, and artwork -- entirely separate from `__common`/
    /// `__.POPS`. Per OPL's own README: if `__common/OPL/conf_hdd.cfg`
    /// doesn't specify a custom partition name, OPL auto-creates and uses a
    /// 128MB PFS partition literally named `+OPL`. This app deliberately
    /// targets only that literal name -- it does not read or write
    /// `conf_hdd.cfg`, so a user who has already customized their OPL
    /// partition name won't have artwork installed to the right place until
    /// that's supported.
    static let oplPartitionName = "+OPL"
    static let oplArtSubdirectory = "ART"

    /// FreeMcBoot/FreeHDBoot homebrew "apps" (ELF applications) -- confirmed
    /// against OPL's own `sbCreateFolders()` (src/supportbase.c), which lists
    /// `APPS` as a top-level folder sibling to `ART`/`CFG`/`VMC`/etc. under
    /// whichever partition OPL manages, same as `oplArtSubdirectory` above.
    /// Each installed app is its own subfolder here (e.g. `APPS/wLaunchELF/`),
    /// preserving whatever internal folder structure the app's own archive
    /// had. Path-building for this lives on `AppsDestination.oplApps`
    /// (`appFolderPFSPath`/`appPFSPath`), not here -- that's also what
    /// `AppsDestination.fhdbApps` (Core Apps) uses, sharing the same
    /// path-building logic with a different partition/subdirectory.
    static let oplAppsSubdirectory = "APPS"

    /// PS2 cover art is keyed by Game ID (e.g. `SLES_544.39`), confirmed
    /// against the official OPL docs (ps2homebrew.org/Open-PS2-Loader-User-
    /// Guide/art.html): `<game_ID>_COV.{jpg|png}`. This app only ever writes
    /// `.png`.
    static func oplCoverArtFilename(forGameID gameID: String) -> String {
        "\(gameID)_COV.png"
    }

    static func oplCoverArtPFSPath(forGameID gameID: String) -> String {
        "\(oplArtSubdirectory)/\(oplCoverArtFilename(forGameID: gameID))"
    }

    /// PS1 cover art, unlike OPL's, is matched by exact VCD filename, not
    /// Game ID -- confirmed verbatim from the POPSLoader README: "The PNG
    /// filename must match the .VCD game filename." Lives inside the same
    /// `__common/POPS/` folder already used for the system files above, in
    /// its own `ART` subdirectory.
    static var popsArtSubdirectory: String { "\(popsSubdirectory)/ART" }

    static func popsCoverArtFilename(forVCDFilename vcdFilename: String) -> String {
        var base = vcdFilename
        if base.uppercased().hasSuffix(".VCD") {
            base.removeLast(4)
        }
        return base + ".png"
    }

    static func popsCoverArtPFSPath(forVCDFilename vcdFilename: String) -> String {
        "\(popsArtSubdirectory)/\(popsCoverArtFilename(forVCDFilename: vcdFilename))"
    }

    /// A tiny plain-text sidecar (just the detected Game ID, e.g.
    /// "SLUS_123.45") stored alongside a PS1 game's cover art. PS1GameID-
    /// Detector's byte-pattern scan needs the original .cue/.bin, which this
    /// app doesn't retain after install -- storing the ID once it's detected
    /// (at install time, or the first time it's manually detected) means
    /// later artwork fetches for the same game never need the source disc
    /// image re-selected again. Lives on the drive itself (not a local Mac
    /// cache) so it travels with the drive across machines, matching this
    /// app's existing everything-lives-on-the-drive design.
    static func popsGameIDSidecarFilename(forVCDFilename vcdFilename: String) -> String {
        var base = vcdFilename
        if base.uppercased().hasSuffix(".VCD") {
            base.removeLast(4)
        }
        return base + ".gameid"
    }

    static func popsGameIDSidecarPFSPath(forVCDFilename vcdFilename: String) -> String {
        "\(popsArtSubdirectory)/\(popsGameIDSidecarFilename(forVCDFilename: vcdFilename))"
    }

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

    /// Simple Media System (SMS) is a general-purpose PFS file/media browser,
    /// not a fixed-path scanner -- confirmed by reading its own source
    /// (src/SMS_GUIDevMenu.c), it just lists whatever partitions/directories
    /// exist on a device. `SMS_Media` isn't a technical requirement, but it
    /// is SMS's own precedent: its README changelog names this exact
    /// partition as the convention for HDD-resident media. Adopted here as a
    /// dedicated partition, matching this app's existing one-partition-per-
    /// content-type pattern (`__.POPS`, `+OPL`).
    ///
    /// Movies live flat under a `Movies/` subdirectory; TV episodes live
    /// under `Shows/<Show Name>/Season <N>/`, mirroring how a real DVD/media
    /// library is organized -- both are just nested PFS paths, no different
    /// mechanically from `+OPL/APPS/<app>/`, since SMS browses directories
    /// fine either way. Movies originally lived directly at the partition
    /// root with no subdirectory at all; `smsMediaVideoPFSPath` is kept
    /// around so previously-installed movies at that legacy location are
    /// still found and playable, not orphaned by this change.
    static let smsMediaPartitionName = "SMS_Media"

    static let smsMediaMoviesSubdirectory = "Movies"
    static let smsMediaShowsSubdirectory = "Shows"

    /// The dedicated `USERFILES` partition for arbitrary user files/folders
    /// -- see UserFilesService. Like `SMS_Media`, genuinely scales with
    /// drive size (see PartitionSizeSuggestions), so unlike the fixed infra
    /// partitions there's no size constant here -- it's always
    /// caller-supplied at creation time.
    static let userFilesPartitionName = "USERFILES"

    /// The legacy PFS-side path for a movie file directly at the `SMS_Media`
    /// partition root, e.g. `smsMediaVideoPFSPath(filename: "Movie.avi")` ->
    /// `"Movie.avi"`. Superseded by `smsMediaMoviePFSPath` for new installs --
    /// kept so movies installed before the `Movies/` subdirectory existed are
    /// still found by SMSMediaService.listVideos/deleteVideo.
    static func smsMediaVideoPFSPath(filename: String) -> String {
        filename
    }

    /// The PFS-side path for a movie file under `SMS_Media`'s `Movies/`
    /// subdirectory, e.g. `smsMediaMoviePFSPath(filename: "Movie.avi")` ->
    /// `"Movies/Movie.avi"`. Where new movies are installed going forward.
    static func smsMediaMoviePFSPath(filename: String) -> String {
        "\(smsMediaMoviesSubdirectory)/\(filename)"
    }

    /// The folder name for a season within a show, e.g.
    /// `smsMediaSeasonFolderName(seasonNumber: 3)` -> `"Season 3"`. A single
    /// source of truth so building this name (installing an episode) and
    /// parsing it back (listing episodes, TVShowService.listEpisodes) can't
    /// drift out of sync.
    static func smsMediaSeasonFolderName(seasonNumber: Int) -> String {
        "Season \(seasonNumber)"
    }

    /// The PFS-side path for a TV episode file, e.g.
    /// `smsMediaShowEpisodePFSPath(showName: "Firefly", seasonNumber: 1,
    /// filename: "01 - Serenity.avi")` ->
    /// `"Shows/Firefly/Season 1/01 - Serenity.avi"`.
    static func smsMediaShowEpisodePFSPath(showName: String, seasonNumber: Int, filename: String) -> String {
        "\(smsMediaShowsSubdirectory)/\(showName)/\(smsMediaSeasonFolderName(seasonNumber: seasonNumber))/\(filename)"
    }
}
