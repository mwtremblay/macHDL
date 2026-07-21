import Foundation

/// Central wrapper other code calls for all hdl_dump-touching disk
/// operations. Every operation routes through the privileged helper daemon
/// via HDLDumpHelperClient -- reads need root on this hardware too (raw
/// device nodes are root:operator 0640), so there's no more unprivileged/
/// privileged split to maintain.
final class HDLDumpService {
    private let helper: HDLDumpHelperClient
    private let discovery: DiskDiscoveryService

    /// hdl_dump implicitly picks up boot.elf/list.ico/icon.sys from its
    /// current working directory during inject_cd/inject_dvd. Pinning this to
    /// a controlled, normally-empty directory means nothing gets injected by
    /// accident. Passed explicitly to the daemon per install call since the
    /// daemon shouldn't need to independently know app-owned config paths.
    private let workingDirectory: URL

    init(
        helper: HDLDumpHelperClient = HDLDumpHelperClient(),
        discovery: DiskDiscoveryService = DiskDiscoveryService()
    ) {
        self.helper = helper
        self.discovery = discovery

        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("macHDL", isDirectory: true)
            .appendingPathComponent("hdl_dump_cwd", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        self.workingDirectory = supportDir
    }

    // MARK: - Reads

    func listGames(on disk: Disk) async throws -> [HDLGame] {
        try await discovery.unmountWholeDisk(deviceIdentifier: disk.deviceIdentifier)
        let (data, exitCode, stderr) = try await helper.listGames(devicePath: disk.devicePath)
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
        let stdout = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return CSVGameListParser.parse(stdout: stdout)
    }

    /// v1 returns hdl_dump's raw stdout for `info` rather than parsing it --
    /// not core to the requested scope.
    func rawInfo(for game: HDLGame, on disk: Disk) async throws -> String {
        let (stdout, exitCode, stderr) = try await helper.gameInfo(devicePath: disk.devicePath, gameName: game.name)
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
        return stdout ?? ""
    }

    // MARK: - Writes

    func installGame(
        sourceISO: URL,
        name: String,
        isDVD: Bool,
        on disk: Disk,
        onProgress: ((String) -> Void)?
    ) async throws {
        try await guardNotBootDisk(disk)
        try await discovery.unmountWholeDisk(deviceIdentifier: disk.deviceIdentifier)

        let (exitCode, stderr) = try await helper.installGame(
            devicePath: disk.devicePath,
            gameName: name,
            isDVD: isDVD,
            sourcePath: sourceISO.path,
            workingDirectory: workingDirectory.path,
            onProgress: onProgress
        )
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
    }

    /// Sends SIGINT to the daemon's currently-running install, if any.
    /// Returns whether there was anything to cancel.
    func cancelInstall() async -> Bool {
        await helper.cancelCurrentInstall()
    }

    func deleteGame(_ game: HDLGame, on disk: Disk, onProgress: ((String) -> Void)?) async throws {
        try await guardNotBootDisk(disk)
        try await discovery.unmountWholeDisk(deviceIdentifier: disk.deviceIdentifier)

        let (exitCode, stderr) = try await helper.deleteGame(
            devicePath: disk.devicePath,
            gameName: game.name,
            onProgress: onProgress
        )
        try throwIfFailed(exitCode: exitCode, stderr: stderr)
    }

    // MARK: - Helpers

    /// Cheap client-side fail-fast, intentionally redundant with the daemon's
    /// own independent boot-disk re-check (HDLDumpHelperService.isBootDisk) --
    /// defense in depth, not duplication to clean up.
    private func guardNotBootDisk(_ disk: Disk) async throws {
        if await discovery.isBootDisk(deviceIdentifier: disk.deviceIdentifier) {
            throw HDLDumpError.operationNotAllowed(message: HDLDumpError.bootDiskRefusalMessage)
        }
    }

    private func throwIfFailed(exitCode: Int32, stderr: String) throws {
        guard exitCode != 0 else { return }
        throw HDLDumpError(exitCode: exitCode, stderr: stderr)
    }
}
