import Foundation

/// Writes fetched cover art to the exact locations OPL (PS2) and POPSLoader
/// (PS1) expect. A sibling to PS1GameService, not a modification of it --
/// keeps that already-hardware-verified surface untouched. Reuses
/// PS1GameService's generic PFS primitives (partitionExists/createPartition/
/// putFile/guardNotBootDisk/throwIfFailed, widened from private to internal
/// for this purpose) via composition, rather than duplicating them.
final class GameArtworkService {
    private let ps1Service: PS1GameService

    init(ps1Service: PS1GameService) {
        self.ps1Service = ps1Service
    }

    /// Forwards to PS1GameService -- hoisted there so the Apps feature's
    /// AppsService can create the same `+OPL` partition without depending on
    /// this (artwork-specific) service. Kept here too since GameListViewModel
    /// already depends on GameArtworkService, not PS1GameService directly.
    func createOPLPartitionIfNeeded(on disk: Disk) async throws {
        try await ps1Service.createOPLPartitionIfNeeded(on: disk)
    }

    /// Writes `imageData` to `+OPL/ART/<gameID>_COV.png`.
    func installPS2CoverArt(gameID: String, imageData: Data, on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await ps1Service.createOPLPartitionIfNeeded(on: disk)
        let localURL = try writeToScratchFile(imageData, named: PFSDestinationPaths.oplCoverArtFilename(forGameID: gameID))
        defer { try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent()) }
        try await ps1Service.putFile(
            localURL: localURL,
            partitionName: PFSDestinationPaths.oplPartitionName,
            pfsPath: PFSDestinationPaths.oplCoverArtPFSPath(forGameID: gameID),
            on: disk
        )
    }

    /// Writes `imageData` to `__common/POPS/ART/<vcdBaseName>.png`.
    func installPS1CoverArt(vcdFilename: String, imageData: Data, on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await ps1Service.createCommonPartitionIfNeeded(sizeBytes: PFSDestinationPaths.commonPartitionSizeBytes, on: disk)
        let filename = PFSDestinationPaths.popsCoverArtFilename(forVCDFilename: vcdFilename)
        let localURL = try writeToScratchFile(imageData, named: filename)
        defer { try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent()) }
        try await ps1Service.putFile(
            localURL: localURL,
            partitionName: PFSDestinationPaths.commonPartitionName,
            pfsPath: PFSDestinationPaths.popsCoverArtPFSPath(forVCDFilename: vcdFilename),
            on: disk
        )
    }

    /// Reads back a previously-installed PS2 cover from `+OPL/ART/`, for
    /// display in the app. Throws `HDLDumpError.fileNotFound` if none has
    /// been installed for this game -- callers should treat that as "no
    /// artwork to show", not a real error.
    func fetchInstalledPS2CoverArt(gameID: String, on disk: Disk) async throws -> Data {
        try await ps1Service.getFile(
            partitionName: PFSDestinationPaths.oplPartitionName,
            pfsPath: PFSDestinationPaths.oplCoverArtPFSPath(forGameID: gameID),
            on: disk
        )
    }

    /// Reads back a previously-installed PS1 cover from `__common/POPS/ART/`.
    func fetchInstalledPS1CoverArt(vcdFilename: String, on disk: Disk) async throws -> Data {
        try await ps1Service.getFile(
            partitionName: PFSDestinationPaths.commonPartitionName,
            pfsPath: PFSDestinationPaths.popsCoverArtPFSPath(forVCDFilename: vcdFilename),
            on: disk
        )
    }

    /// Persists a detected PS1 Game ID as a small sidecar file so future
    /// artwork fetches for this game never need the source disc image
    /// re-selected again. Best-effort by design at every call site (a
    /// failure here shouldn't block whatever succeeded already).
    func storeGameID(_ gameID: String, forVCDFilename vcdFilename: String, on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await ps1Service.createCommonPartitionIfNeeded(sizeBytes: PFSDestinationPaths.commonPartitionSizeBytes, on: disk)
        guard let data = gameID.data(using: .utf8) else { return }
        let filename = PFSDestinationPaths.popsGameIDSidecarFilename(forVCDFilename: vcdFilename)
        let localURL = try writeToScratchFile(data, named: filename)
        defer { try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent()) }
        try await ps1Service.putFile(
            localURL: localURL,
            partitionName: PFSDestinationPaths.commonPartitionName,
            pfsPath: PFSDestinationPaths.popsGameIDSidecarPFSPath(forVCDFilename: vcdFilename),
            on: disk
        )
    }

    /// Throws `HDLDumpError.fileNotFound` if no Game ID has been detected
    /// and stored for this game yet -- callers should fall back to prompting
    /// for the source disc image in that case.
    func fetchStoredGameID(forVCDFilename vcdFilename: String, on disk: Disk) async throws -> String {
        let data = try await ps1Service.getFile(
            partitionName: PFSDestinationPaths.commonPartitionName,
            pfsPath: PFSDestinationPaths.popsGameIDSidecarPFSPath(forVCDFilename: vcdFilename),
            on: disk
        )
        guard let gameID = String(data: data, encoding: .utf8), !gameID.isEmpty else {
            throw HDLDumpError.fileNotFound
        }
        return gameID
    }

    /// `putPFSFile`'s XPC signature takes a local file path, not raw `Data`
    /// -- write to a scratch temp file first, matching the same pattern
    /// InstallPS1GameViewModel already uses for the VCD itself.
    private func writeToScratchFile(_ data: Data, named filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macHDL-artwork-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let fileURL = url.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
}
