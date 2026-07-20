import Foundation

/// Central wrapper for all PFS/PopStarter-touching operations -- the PS1
/// sibling of HDLDumpService. Every operation routes through the same
/// privileged helper daemon, via HDLDumpHelperClient's PFS methods.
final class PS1GameService {
    enum ServiceError: Error, LocalizedError {
        case bundledPopstarterMissing
        case bundledPopsloaderMissing
        case bundledPatch5Missing

        var errorDescription: String? {
            switch self {
            case .bundledPopstarterMissing:
                return "The bundled POPSTARTER.ELF could not be found. This build is broken -- it should be a static resource in the app bundle."
            case .bundledPopsloaderMissing:
                return "The bundled POPSLOADER.ELF could not be found. This build is broken -- it should be a static resource in the app bundle."
            case .bundledPatch5Missing:
                return "The bundled PATCH_5.BIN could not be found. This build is broken -- it should be a static resource in the app bundle."
            }
        }
    }

    private let helper: HDLDumpHelperClient
    private let discovery: DiskDiscoveryService

    init(
        helper: HDLDumpHelperClient,
        discovery: DiskDiscoveryService = DiskDiscoveryService()
    ) {
        self.helper = helper
        self.discovery = discovery
    }

    // MARK: - Reads

    /// Lists PS1 games as `.VCD` filenames directly at the `__.POPS`
    /// partition's root (see PFSDestinationPaths -- no per-game
    /// subdirectory). If that partition doesn't exist yet (nothing
    /// installed), `pfsutil`'s mount would fail outright -- checked for
    /// explicitly first and short-circuited to an empty list, since "nothing
    /// set up yet" isn't a real failure. Filters to `.VCD` names
    /// defensively -- the partition root should only ever contain this
    /// app's own game files, but never trust that blindly.
    func listGames(on disk: Disk) async throws -> [PS1Game] {
        guard try await gamesPartitionExists(on: disk) else { return [] }
        let (names, _, _) = try await helper.listPFSFiles(
            devicePath: disk.devicePath,
            partitionName: PFSDestinationPaths.gamesPartitionName,
            pfsPath: "/"
        )
        return (names ?? [])
            .filter { $0.uppercased().hasSuffix(".VCD") }
            .map { PS1Game(vcdFilename: $0) }
    }

    func commonPartitionExists(on disk: Disk) async throws -> Bool {
        try await partitionExists(named: PFSDestinationPaths.commonPartitionName, on: disk)
    }

    func gamesPartitionExists(on disk: Disk) async throws -> Bool {
        try await partitionExists(named: PFSDestinationPaths.gamesPartitionName, on: disk)
    }

    private func partitionExists(named name: String, on disk: Disk) async throws -> Bool {
        try await discovery.unmountWholeDisk(deviceIdentifier: disk.deviceIdentifier)
        // hdl_dump's own `toc` (fast, single-pass APA read) rather than
        // pfsshell's `ls`/`lspart` (one raw device read per partition) --
        // the latter hung for minutes on this drive's 46+ partitions over
        // its slow USB-SATA bridge. See project memory for the incident.
        let (output, _, _) = try await helper.listAllPartitions(devicePath: disk.devicePath)
        return (output ?? "").contains(name)
    }

    // MARK: - Setup (PopStarter system partitions)

    func createGamesPartitionIfNeeded(sizeBytes: Int64, on disk: Disk) async throws {
        guard try await !gamesPartitionExists(on: disk) else { return }
        try await createPartition(name: PFSDestinationPaths.gamesPartitionName, sizeBytes: sizeBytes, on: disk)
    }

    func createCommonPartitionIfNeeded(sizeBytes: Int64, on disk: Disk) async throws {
        guard try await !commonPartitionExists(on: disk) else { return }
        try await createPartition(name: PFSDestinationPaths.commonPartitionName, sizeBytes: sizeBytes, on: disk)
    }

    /// Copies the user-supplied POPS.ELF/IOPRP252.IMG (Sony-copyrighted,
    /// never bundled by this app, required) plus this app's own bundled
    /// POPSTARTER.ELF/POPSLOADER.ELF/PATCH_5.BIN (all freely redistributable,
    /// GPLv3, required) into the `__common` partition. POPSLOADER.ELF and
    /// PATCH_5.BIN were added after real-hardware testing showed OPL
    /// wouldn't actually launch a game without them present alongside
    /// POPSTARTER.ELF, even though no documentation states this as a hard
    /// requirement.
    ///
    /// popsPakURL/popsIoxPakURL are optional -- also Sony-copyrighted and
    /// user-supplied like POPS.ELF/IOPRP252.IMG, but real-hardware testing
    /// showed a game launches fine without them (POPS_IOX.PAK in particular
    /// is understood to only matter for PopStarter's network modes).
    func installPopStarterSystemFiles(popsElfURL: URL, ioprpImageURL: URL, popsPakURL: URL?, popsIoxPakURL: URL?, on disk: Disk) async throws {
        try await guardNotBootDisk(disk)
        try await putFile(localURL: popsElfURL, partitionName: PFSDestinationPaths.commonPartitionName, pfsPath: PFSDestinationPaths.popsElfPFSPath, on: disk)
        try await putFile(localURL: ioprpImageURL, partitionName: PFSDestinationPaths.commonPartitionName, pfsPath: PFSDestinationPaths.ioprpImagePFSPath, on: disk)

        guard let bundledPopstarter = Bundle.main.url(forResource: "POPSTARTER", withExtension: "ELF") else {
            throw ServiceError.bundledPopstarterMissing
        }
        try await putFile(localURL: bundledPopstarter, partitionName: PFSDestinationPaths.commonPartitionName, pfsPath: PFSDestinationPaths.popstarterElfPFSPath, on: disk)

        guard let bundledPopsloader = Bundle.main.url(forResource: "POPSLOADER", withExtension: "ELF") else {
            throw ServiceError.bundledPopsloaderMissing
        }
        try await putFile(localURL: bundledPopsloader, partitionName: PFSDestinationPaths.commonPartitionName, pfsPath: PFSDestinationPaths.popsloaderElfPFSPath, on: disk)

        guard let bundledPatch5 = Bundle.main.url(forResource: "PATCH_5", withExtension: "BIN") else {
            throw ServiceError.bundledPatch5Missing
        }
        try await putFile(localURL: bundledPatch5, partitionName: PFSDestinationPaths.commonPartitionName, pfsPath: PFSDestinationPaths.patch5BinPFSPath, on: disk)

        if let popsPakURL {
            try await putFile(localURL: popsPakURL, partitionName: PFSDestinationPaths.commonPartitionName, pfsPath: PFSDestinationPaths.popsPakPFSPath, on: disk)
        }
        if let popsIoxPakURL {
            try await putFile(localURL: popsIoxPakURL, partitionName: PFSDestinationPaths.commonPartitionName, pfsPath: PFSDestinationPaths.popsIoxPakPFSPath, on: disk)
        }
    }

    // MARK: - Writes

    /// vcdFilename is the exact destination filename at the partition
    /// root -- callers build it via PFSDestinationPaths.gameVCDFilename(
    /// forGameNamed:) so the 73-character POPStarter limit and ".VCD"
    /// extension convention are enforced in one place.
    func installGame(vcdURL: URL, vcdFilename: String, on disk: Disk) async throws {
        try await guardNotBootDisk(disk)
        try await putFile(
            localURL: vcdURL,
            partitionName: PFSDestinationPaths.gamesPartitionName,
            pfsPath: vcdFilename,
            on: disk
        )
    }

    func deleteGame(vcdFilename: String, on disk: Disk) async throws {
        try await guardNotBootDisk(disk)
        let (exitCode, stderr) = try await helper.removePFSFile(
            devicePath: disk.devicePath,
            partitionName: PFSDestinationPaths.gamesPartitionName,
            pfsPath: vcdFilename
        )
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
    }

    // MARK: - Helpers

    private func createPartition(name: String, sizeBytes: Int64, on disk: Disk) async throws {
        try await guardNotBootDisk(disk)
        let (exitCode, stderr) = try await helper.createPOPSPartition(devicePath: disk.devicePath, partitionName: name, sizeBytes: sizeBytes)
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
    }

    private func putFile(localURL: URL, partitionName: String, pfsPath: String, on disk: Disk) async throws {
        let (exitCode, stderr) = try await helper.putPFSFile(
            devicePath: disk.devicePath,
            partitionName: partitionName,
            localSourcePath: localURL.path,
            pfsDestPath: pfsPath
        )
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
    }

    /// Cheap client-side fail-fast, intentionally redundant with the daemon's
    /// own independent boot-disk re-check -- defense in depth, matching
    /// HDLDumpService's identical guard.
    private func guardNotBootDisk(_ disk: Disk) async throws {
        if await discovery.isBootDisk(deviceIdentifier: disk.deviceIdentifier) {
            throw HDLDumpError.operationNotAllowed
        }
    }

    /// Routes through HDLDumpError's typed initializer (not the bare
    /// .unknown case) so exit code 1 -- the only failure code pfsshell/
    /// pfsutil ever produce -- maps to .ioError, which is what
    /// isLikelyMissingFullDiskAccess actually checks. Using .unknown here
    /// silently disabled the FullDiskAccessSheet recovery flow for every
    /// PS1/PopStarter operation.
    private func throwIfFailed(exitCode: Int32, stderr: String) throws {
        guard exitCode != 0 else { return }
        throw HDLDumpError(exitCode: exitCode, stderr: stderr)
    }
}
