import Foundation

/// One of the fixed, flat system files PopStarter needs at `__common/POPS/`
/// -- a closed set of exact filenames, never a user-named folder. Kept
/// deliberately separate from AppsDestination's folder-per-app model (see
/// AppsDestination's doc comment): a user "installing an app" via the
/// generic Core Apps archive flow can only ever create a new folder under
/// `PP.FHDB.APPS`, never touch one of these exact slots, and these slots can
/// only ever be replaced/removed by their own dedicated action here, never
/// created/renamed by a client-typed name. That split is what keeps the two
/// features from ever colliding on the same destination.
struct PopStarterSystemFile: Identifiable, Hashable {
    /// The exact on-disk filename, e.g. "POPSTARTER.ELF" -- also pfsutil's
    /// own listing identity, there's no separate internal ID.
    let id: String
    let pfsPath: String
    /// POPS.PAK/POPS_IOX.PAK only -- see PFSDestinationPaths' doc comments
    /// for why those two are optional and the other five aren't.
    let isOptional: Bool

    var displayName: String { id }
    var expectedFilenameExtension: String { (id as NSString).pathExtension }

    static let popsElf = PopStarterSystemFile(id: "POPS.ELF", pfsPath: PFSDestinationPaths.popsElfPFSPath, isOptional: false)
    static let ioprpImage = PopStarterSystemFile(id: "IOPRP252.IMG", pfsPath: PFSDestinationPaths.ioprpImagePFSPath, isOptional: false)
    static let popstarterElf = PopStarterSystemFile(id: "POPSTARTER.ELF", pfsPath: PFSDestinationPaths.popstarterElfPFSPath, isOptional: false)
    static let popsloaderElf = PopStarterSystemFile(id: "POPSLOADER.ELF", pfsPath: PFSDestinationPaths.popsloaderElfPFSPath, isOptional: false)
    static let patch5Bin = PopStarterSystemFile(id: "PATCH_5.BIN", pfsPath: PFSDestinationPaths.patch5BinPFSPath, isOptional: false)
    static let popsPak = PopStarterSystemFile(id: "POPS.PAK", pfsPath: PFSDestinationPaths.popsPakPFSPath, isOptional: true)
    static let popsIoxPak = PopStarterSystemFile(id: "POPS_IOX.PAK", pfsPath: PFSDestinationPaths.popsIoxPakPFSPath, isOptional: true)

    static let all: [PopStarterSystemFile] = [.popsElf, .ioprpImage, .popstarterElf, .popsloaderElf, .patch5Bin, .popsPak, .popsIoxPak]
}
