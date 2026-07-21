import Foundation

/// Orchestrates FreeHDBoot (FMCB) setup on a blank PS2 HDD -- entirely from
/// the Mac, no PS2 console needed for setup itself. The FreeHDBoot sibling
/// of PS1GameService: every operation routes through the same privileged
/// helper daemon. Reuses PS1GameService's generic PFS primitives
/// (guardNotBootDisk/putFile/throwIfFailed) via composition, the same
/// pattern GameArtworkService already uses, rather than duplicating them.
///
/// This is the single most destructive feature in the app -- it wipes an
/// entire disk's partition table, not one partition. Unlike a stricter
/// earlier version of this service, it does not require the target to be
/// blank: FreeHDBootSetupViewModel/Sheet show the user exactly what's on
/// the drive and get an explicit destructive-action confirmation before
/// this is ever called, the same "inform, don't gate" pattern this app
/// already uses for every other destructive action. The boot-disk check
/// (ps1Service.guardNotBootDisk) is the one thing that stays unconditional.
final class FreeHDBootService {
    enum ServiceError: Error, LocalizedError {
        case bundledMBRKelfMissing
        case bundledPayloadFileMissing(String)

        var errorDescription: String? {
            switch self {
            case .bundledMBRKelfMissing:
                return "The bundled FreeHDBoot MBR bootstrap could not be found. This build is broken -- it should be a static resource in the app bundle."
            case .bundledPayloadFileMissing(let name):
                return "The bundled FreeHDBoot file '\(name)' could not be found. This build is broken -- it should be a static resource in the app bundle."
            }
        }
    }

    private let helper: HDLDumpHelperClient
    private let discovery: DiskDiscoveryService
    private let ps1Service: PS1GameService

    init(
        helper: HDLDumpHelperClient,
        ps1Service: PS1GameService,
        discovery: DiskDiscoveryService = DiskDiscoveryService()
    ) {
        self.helper = helper
        self.ps1Service = ps1Service
        self.discovery = discovery
    }

    // MARK: - Reads

    /// Existing partition names on the drive, so the setup UI can show the
    /// user what's really there before any destructive action -- the same
    /// kind of verification opportunity `diskutil list` would give. Returns
    /// an empty list (not an error) when the drive has no valid partition
    /// table, since that's the expected "blank" case, not a failure.
    func existingPartitionNames(on disk: Disk) async throws -> [String] {
        try await discovery.unmountWholeDisk(deviceIdentifier: disk.deviceIdentifier)
        let (output, exitCode, _) = try await helper.listAllPartitions(devicePath: disk.devicePath)
        guard exitCode == 0 else { return [] }
        return PS1GameService.partitionNames(inTOCOutput: output ?? "").sorted()
    }

    // MARK: - Setup

    /// The full FreeHDBoot setup sequence: rebuild the disk's base APA/PFS
    /// layout from scratch, install the FreeHDBoot bootstrap into `__mbr`,
    /// then copy the FreeHDBoot menu/system files onto `__system`/
    /// `__sysconf`. See FreeHDBootDestinationPaths for the exact file list,
    /// read directly from the vendored FreeMcBoot-Installer's own installer
    /// source (installer/system.c), not guessed.
    ///
    /// Whether the resulting drive actually boots on a real PS2 cannot be
    /// verified by this app or by CI -- that can only be confirmed by
    /// testing on real hardware.
    func setUpFreeHDBoot(on disk: Disk, progress: ((String) -> Void)? = nil) async throws {
        try await ps1Service.guardNotBootDisk(disk)

        progress?("Initializing partition table…")
        try await initializeAPA(on: disk)

        progress?("Installing FreeHDBoot bootloader…")
        try await injectBootloader(on: disk, progress: progress)

        try await installPayloadFiles(on: disk, progress: progress)
    }

    // MARK: - Steps

    /// Internal, not private -- composable primitives, same convention as
    /// PS1GameService, in case a future caller needs to re-run a single step
    /// (e.g. re-injecting just the bootloader without reformatting).

    /// A failure here means pfsshell's `initialize` didn't complete cleanly
    /// -- see HDLDumpHelperService.initializeBlankAPADisk's post-`initialize`
    /// verification for why that can leave the disk in a half-rebuilt state
    /// rather than a clean "nothing happened" failure. Anything other than
    /// the unconditional boot-disk refusal gets wrapped as
    /// `.partitionTableMayBeInconsistent` so the user sees a categorically
    /// different warning than an ordinary file-write failure.
    func initializeAPA(on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        let (exitCode, stderr) = try await helper.initializeBlankAPADisk(devicePath: disk.devicePath)
        try throwPossiblyDiskCorrupting(exitCode: exitCode, stderr: stderr)
    }

    /// Same "may leave the disk inconsistent" reasoning as initializeAPA --
    /// a failed `inject_mbr` can leave `__mbr` partially rewritten.
    func injectBootloader(on disk: Disk, progress: ((String) -> Void)? = nil) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        guard let mbrKelfURL = Bundle.main.url(
            forResource: FreeHDBootDestinationPaths.mbrKelfResourceName,
            withExtension: FreeHDBootDestinationPaths.mbrKelfResourceExtension
        ) else {
            throw ServiceError.bundledMBRKelfMissing
        }
        let (exitCode, stderr) = try await helper.injectMBR(devicePath: disk.devicePath, mbrKelfPath: mbrKelfURL.path, onProgress: progress)
        try throwPossiblyDiskCorrupting(exitCode: exitCode, stderr: stderr)
    }

    /// By the time this runs, initializeAPA has already verified the base
    /// partition table is fully built -- a failure here is an ordinary file
    /// copy failure (routed through ps1Service.putFile's normal error
    /// mapping), not a partition-table-level concern.
    func installPayloadFiles(on disk: Disk, progress: ((String) -> Void)? = nil) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        let files = FreeHDBootDestinationPaths.payloadFiles
        for (index, file) in files.enumerated() {
            guard let url = Bundle.main.url(forResource: file.resourceName, withExtension: file.resourceExtension) else {
                throw ServiceError.bundledPayloadFileMissing("\(file.resourceName).\(file.resourceExtension)")
            }
            progress?("Installing FreeHDBoot system files (\(index + 1)/\(files.count))…")
            try await ps1Service.putFile(localURL: url, partitionName: file.partitionName, pfsPath: file.pfsPath, on: disk)
        }
    }

    // MARK: - Helpers

    /// Wraps initializeAPA/injectBootloader's failures as
    /// `.partitionTableMayBeInconsistent`, except for errors that mean
    /// nothing was actually written to the disk, which stay as themselves
    /// rather than getting a scary "may be corrupted" warning:
    /// - `.operationNotAllowed` -- the boot-disk refusal, fires before the
    ///   daemon ever opens the device.
    /// - `.daemonLaunchFailed` -- the daemon couldn't even launch pfsshell/
    ///   hdl_dump or open a session (e.g. the binary is missing), so nothing
    ///   ran against the disk at all.
    /// - anything `isLikelyMissingFullDiskAccess` -- a normal, recoverable
    ///   TCC permission issue with its own dedicated recovery UI elsewhere
    ///   in this app (see ContentView's FullDiskAccessSheet wiring); wrapping
    ///   it here would both bury it from that recovery path and needlessly
    ///   alarm the user about drive corruption for what's really a one-step
    ///   System Settings fix.
    private func throwPossiblyDiskCorrupting(exitCode: Int32, stderr: String) throws {
        guard exitCode != 0 else { return }
        let error = HDLDumpError(exitCode: exitCode, stderr: stderr)
        switch error {
        case .operationNotAllowed, .daemonLaunchFailed:
            throw error
        default:
            if error.isLikelyMissingFullDiskAccess {
                throw error
            }
            throw HDLDumpError.partitionTableMayBeInconsistent(underlying: error)
        }
    }
}
