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

    /// Lists PS1 games as `.VCD` filenames across every existing overflow
    /// partition (`__.POPS`, `__.POPS1`-`__.POPS10` -- see
    /// PFSDestinationPaths.allGamesPartitionNamesInOrder), tagging each with
    /// the specific partition it lives in so delete/reinstall target the
    /// right one. A single `listAllPartitions` call (not one per candidate
    /// partition) is reused to check existence of all 11 possible names at
    /// once -- avoids up to 11 redundant full-partition-table reads over the
    /// slow USB bridge just to figure out which overflow partitions exist.
    func listGames(on disk: Disk) async throws -> [PS1Game] {
        try await discovery.unmountWholeDisk(deviceIdentifier: disk.deviceIdentifier)
        let (output, _, _) = try await helper.listAllPartitions(devicePath: disk.devicePath)
        let existingNames = Self.partitionNames(inTOCOutput: output ?? "")
        let existingGamesPartitions = PFSDestinationPaths.allGamesPartitionNamesInOrder.filter { existingNames.contains($0) }

        var games: [PS1Game] = []
        for partitionName in existingGamesPartitions {
            let (names, _, _) = try await helper.listPFSFiles(
                devicePath: disk.devicePath,
                partitionName: partitionName,
                pfsPath: "/"
            )
            games.append(contentsOf: (names ?? [])
                .filter { $0.uppercased().hasSuffix(".VCD") }
                .map { PS1Game(vcdFilename: $0, partitionName: partitionName) })
        }
        return games
    }

    func commonPartitionExists(on disk: Disk) async throws -> Bool {
        try await partitionExists(named: PFSDestinationPaths.commonPartitionName, on: disk)
    }

    func gamesPartitionExists(on disk: Disk) async throws -> Bool {
        try await partitionExists(named: PFSDestinationPaths.gamesPartitionName, on: disk)
    }

    /// Internal, not private -- reused directly by GameArtworkService for
    /// the `+OPL` partition, same reasoning as the helpers below.
    func partitionExists(named name: String, on disk: Disk) async throws -> Bool {
        try await discovery.unmountWholeDisk(deviceIdentifier: disk.deviceIdentifier)
        // hdl_dump's own `toc` (fast, single-pass APA read) rather than
        // pfsshell's `ls`/`lspart` (one raw device read per partition) --
        // the latter hung for minutes on this drive's 46+ partitions over
        // its slow USB-SATA bridge. See project memory for the incident.
        let (output, _, _) = try await helper.listAllPartitions(devicePath: disk.devicePath)
        return Self.partitionNames(inTOCOutput: output ?? "").contains(name)
    }

    /// Extracts exact partition names from `hdl_dump toc`'s output. Confirmed
    /// directly from source (`hdl_dump.c`'s `show_apa_slice2`): every real
    /// partition line matches `"0x%04x %06lx00%c%c %2lu %5luMB %s\n"` --
    /// always starts with `0x` (the hex type field), always ends with the
    /// name (`part->id`) as the last, space-preceded field with nothing
    /// after it. Filtering to `0x`-prefixed lines (skipping the header row
    /// and the trailing "Total slice size: ..." summary line) before taking
    /// each line's last token means a blind substring search
    /// (`output.contains(name)`, used before this fix) is no longer needed
    /// -- which mattered because `__.POPS1` and `__.POPS10` share a prefix,
    /// so `output.contains("__.POPS1")` would wrongly also match a line
    /// that's actually `__.POPS10`. Taking each partition line's own last
    /// token doesn't have that problem.
    static func partitionNames(inTOCOutput output: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("0x") else { return nil }
            return line.split(separator: " ").last.map(String.init)
        })
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
    /// extension convention are enforced in one place. partitionName must
    /// be one of PFSDestinationPaths.allGamesPartitionNamesInOrder -- most
    /// callers should use `installGameWithOverflow` instead of calling this
    /// directly, since it picks the right (or a new overflow) partition.
    func installGame(vcdURL: URL, vcdFilename: String, partitionName: String, on disk: Disk) async throws {
        try await guardNotBootDisk(disk)
        try await putFile(
            localURL: vcdURL,
            partitionName: partitionName,
            pfsPath: vcdFilename,
            on: disk
        )
    }

    /// Installs into `__.POPS`, falling through to `__.POPS1`,
    /// `__.POPS2`, ... `__.POPS10` in order -- creating the next partition
    /// (at `defaultPartitionSizeBytes`) and retrying whenever the current
    /// one is full, entirely transparent to the caller. PFS partitions
    /// can't be resized in place (confirmed: pfsshell has no resize/grow
    /// command in its command table), so growing the *effective* PS1 games
    /// partition capacity beyond the OS's original size ultimately means
    /// this, not making one partition bigger after the fact. Any failure
    /// that ISN'T specifically an out-of-space condition (see
    /// `HDLDumpError.isLikelyOutOfSpace`) is rethrown immediately rather
    /// than cascading through all 11 partitions on an unrelated error (e.g.
    /// missing Full Disk Access, boot-disk refusal).
    func installGameWithOverflow(vcdURL: URL, vcdFilename: String, defaultPartitionSizeBytes: Int64, on disk: Disk) async throws {
        var lastOutOfSpaceError: Error?
        for partitionName in PFSDestinationPaths.allGamesPartitionNamesInOrder {
            do {
                if try await !partitionExists(named: partitionName, on: disk) {
                    try await createPartition(name: partitionName, sizeBytes: defaultPartitionSizeBytes, on: disk)
                }
                try await installGame(vcdURL: vcdURL, vcdFilename: vcdFilename, partitionName: partitionName, on: disk)
                return
            } catch let error as HDLDumpError where error.isLikelyOutOfSpace {
                lastOutOfSpaceError = error
                continue
            }
        }
        // All 11 partitions (__.POPS through __.POPS10) are full -- a
        // genuinely exceptional amount of PS1 games. Surface the last
        // out-of-space error rather than a generic one.
        throw lastOutOfSpaceError ?? HDLDumpError.noSpace
    }

    func deleteGame(vcdFilename: String, partitionName: String, on disk: Disk) async throws {
        try await guardNotBootDisk(disk)
        let (exitCode, stderr) = try await helper.removePFSFile(
            devicePath: disk.devicePath,
            partitionName: partitionName,
            pfsPath: vcdFilename
        )
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
    }

    // MARK: - Helpers

    /// Internal, not private -- these are generic PFS primitives (not
    /// specific to PS1 games), reused directly by GameArtworkService via
    /// composition so it doesn't have to duplicate already-correct,
    /// hardware-verified partition/file-write/error-mapping logic.

    func createPartition(name: String, sizeBytes: Int64, on disk: Disk) async throws {
        try await guardNotBootDisk(disk)
        let (exitCode, stderr) = try await helper.createPOPSPartition(devicePath: disk.devicePath, partitionName: name, sizeBytes: sizeBytes)
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
    }

    /// Reads a small file's contents back from a PFS partition -- e.g. to
    /// display previously-installed cover art. See HDLDumpHelperProtocol's
    /// getPFSFile doc comment for why this is only meant for small files.
    func getFile(partitionName: String, pfsPath: String, on disk: Disk) async throws -> Data {
        let (data, exitCode, stderr) = try await helper.getPFSFile(
            devicePath: disk.devicePath,
            partitionName: partitionName,
            pfsPath: pfsPath
        )
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
        guard let data else { throw HDLDumpError.fileNotFound }
        return data
    }

    func putFile(localURL: URL, partitionName: String, pfsPath: String, on disk: Disk) async throws {
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
    func guardNotBootDisk(_ disk: Disk) async throws {
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
    func throwIfFailed(exitCode: Int32, stderr: String) throws {
        guard exitCode != 0 else { return }
        throw HDLDumpError(exitCode: exitCode, stderr: stderr)
    }
}
