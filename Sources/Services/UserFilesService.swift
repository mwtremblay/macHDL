import Foundation

/// Installs/lists/deletes arbitrary user files and folders under the
/// dedicated `USERFILES` partition -- a sibling to SMSMediaService/
/// AppsService, composing PS1GameService's generic PFS primitives via
/// composition rather than duplicating them. Unlike every other content
/// service in this app, this one is a genuine file browser: entries can be
/// files or folders, and folders can be navigated into and created empty
/// (via the new `makeDirectory` primitive -- see PS1GameService's doc
/// comment).
final class UserFilesService {
    private let ps1Service: PS1GameService

    init(ps1Service: PS1GameService) {
        self.ps1Service = ps1Service
    }

    func userFilesPartitionExists(on disk: Disk) async throws -> Bool {
        try await ps1Service.partitionExists(named: PFSDestinationPaths.userFilesPartitionName, on: disk)
    }

    /// Lists both files and folders at `path` (relative to the partition
    /// root) together, typed -- unlike SMSMediaService.filesOnly, which
    /// deliberately discards directories, a real file browser needs to show
    /// both. `listFiles` returns every entry (see its own doc comment for
    /// why, despite the name); `listDirectories` filters to directories
    /// only, so subtracting one from the other splits them cleanly. Returns
    /// an empty list (not an error) only when the partition itself doesn't
    /// exist yet, same "nothing here" semantics as every other listing in
    /// this app -- a real failure listing an existing partition (permission
    /// denied, I/O error, daemon failure) propagates instead of being
    /// swallowed as an empty list, so callers can actually surface it.
    func listEntries(atPath path: String, on disk: Disk) async throws -> [UserFileEntry] {
        guard try await userFilesPartitionExists(on: disk) else { return [] }
        let (allNames, directoryNames) = try await ps1Service.listEntriesSplitByDirectory(
            partitionName: PFSDestinationPaths.userFilesPartitionName,
            pfsPath: path,
            on: disk
        )
        return allNames.map { UserFileEntry(name: $0, isDirectory: directoryNames.contains($0)) }
    }

    /// Copies `localURL` into `path` (relative to the partition root) as
    /// `filename`. `partitionSizeBytesIfCreating` is only used if
    /// `USERFILES` doesn't exist yet -- callers must have already resolved
    /// a size via PartitionSizePromptSheet (or the setup wizard), never a
    /// silent hardcoded default (this partition genuinely scales with drive
    /// size, see PartitionSizeSuggestions). Nested directories in `path` are
    /// auto-created by pfsutil's own mkdir_recursive, same as every other
    /// put in this app.
    func addFile(localURL: URL, filename: String, atPath path: String, partitionSizeBytesIfCreating: Int64, on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await ps1Service.createUserFilesPartitionIfNeeded(sizeBytes: partitionSizeBytesIfCreating, on: disk)
        let pfsPath = path.isEmpty ? filename : "\(path)/\(filename)"
        try await ps1Service.putFile(localURL: localURL, partitionName: PFSDestinationPaths.userFilesPartitionName, pfsPath: pfsPath, on: disk)
    }

    /// Creates a genuinely empty folder at `path/name` -- see
    /// PS1GameService.makeDirectory's doc comment for why this needs the
    /// new mkdir primitive rather than relying on putFile's implicit
    /// directory creation. Same `partitionSizeBytesIfCreating` reasoning as
    /// addFile.
    func createFolder(name: String, atPath path: String, partitionSizeBytesIfCreating: Int64, on disk: Disk) async throws {
        try await ps1Service.guardNotBootDisk(disk)
        try await ps1Service.createUserFilesPartitionIfNeeded(sizeBytes: partitionSizeBytesIfCreating, on: disk)
        let pfsPath = path.isEmpty ? name : "\(path)/\(name)"
        try await ps1Service.makeDirectory(partitionName: PFSDestinationPaths.userFilesPartitionName, pfsPath: pfsPath, on: disk)
    }

    /// Deletes a single entry at `path/entry.name` -- a file via removeFile,
    /// a folder (and everything in it) via removeTree.
    func deleteEntry(_ entry: UserFileEntry, atPath path: String, on disk: Disk) async throws {
        let pfsPath = path.isEmpty ? entry.name : "\(path)/\(entry.name)"
        if entry.isDirectory {
            try await ps1Service.removeTree(partitionName: PFSDestinationPaths.userFilesPartitionName, pfsPath: pfsPath, on: disk)
        } else {
            try await ps1Service.removeFile(partitionName: PFSDestinationPaths.userFilesPartitionName, pfsPath: pfsPath, on: disk)
        }
    }
}
