import Foundation

/// Drives UserFilesView -- the one genuinely new UI pattern in this app
/// (every other tab is a flat list or a static-hierarchy tree; this is a
/// real, navigable file browser). `currentPath` is relative to the
/// `USERFILES` partition root; `navigate(into:)`/`navigateUp()`/
/// `navigateToBreadcrumb(index:)` move around it, `refresh` re-lists
/// whatever's at the current path.
@MainActor
final class UserFilesViewModel: ObservableObject {
    private enum PendingAction {
        case addFiles(urls: [URL])
        case createFolder(name: String)
    }

    @Published private(set) var currentPath: String = ""
    @Published private(set) var entries: [UserFileEntry] = []
    @Published private(set) var isLoading = false
    @Published var lastError: IdentifiableError?
    @Published var selectedEntryID: UserFileEntry.ID?

    @Published var pendingDeleteEntry: UserFileEntry?
    @Published private(set) var isDeleting = false

    /// Adding is always a batch of 1-or-more files (see `addFiles`) -- these
    /// mirror BatchInstallPS1GameViewModel's identical progress/cancel/
    /// summary shape, the established convention for multi-item operations
    /// in this app.
    @Published private(set) var isAddingFiles = false
    @Published private(set) var addFilesCurrentIndex = 0
    @Published private(set) var addFilesTotalCount = 0
    @Published private(set) var addFilesCurrentName = ""
    @Published var addFilesSummary: String?
    private var addFilesCancelRequested = false

    /// Set when `addFiles`/`createFolder` finds `USERFILES` doesn't exist yet
    /// -- see AddVideoViewModel.pendingPartitionSizePrompt's identical
    /// reasoning. `pendingAction` remembers which of the two triggered it,
    /// resumed by `confirmPartitionSize`.
    @Published var pendingPartitionSizePrompt: PartitionSizePromptRequest?
    /// Keyed by the disk it was confirmed for -- this view model is a
    /// persistent @StateObject that outlives any single disk selection (see
    /// ContentView.installSheets' comment), so a size confirmed while
    /// working on one disk must never be silently reused for a different
    /// one; that disk's own existence check/prompt still needs to run.
    private var confirmedPartitionSizeBytes: (diskID: Disk.ID, bytes: Int64)?
    private var pendingAction: PendingAction?

    private let service: UserFilesService

    init(service: UserFilesService) {
        self.service = service
    }

    var selectedEntry: UserFileEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    /// Path components for a breadcrumb bar, root first -- e.g. "A/B/C" ->
    /// ["A", "B", "C"].
    var breadcrumbComponents: [String] {
        currentPath.isEmpty ? [] : currentPath.split(separator: "/").map(String.init)
    }

    func refresh(disk: Disk?) async {
        guard let disk else {
            entries = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await service.listEntries(atPath: currentPath, on: disk)
            if let selectedEntryID, !entries.contains(where: { $0.id == selectedEntryID }) {
                self.selectedEntryID = nil
            }
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    func navigate(into entry: UserFileEntry, disk: Disk?) async {
        guard entry.isDirectory else { return }
        currentPath = currentPath.isEmpty ? entry.name : "\(currentPath)/\(entry.name)"
        selectedEntryID = nil
        await refresh(disk: disk)
    }

    func navigateUp(disk: Disk?) async {
        guard !currentPath.isEmpty else { return }
        var components = breadcrumbComponents
        components.removeLast()
        currentPath = components.joined(separator: "/")
        selectedEntryID = nil
        await refresh(disk: disk)
    }

    /// `index` is into `breadcrumbComponents` -- navigates to that level
    /// (e.g. index 0 with ["A", "B", "C"] navigates to just "A").
    func navigateToBreadcrumb(index: Int, disk: Disk?) async {
        let components = breadcrumbComponents
        guard index < components.count else { return }
        currentPath = components[0...index].joined(separator: "/")
        selectedEntryID = nil
        await refresh(disk: disk)
    }

    func navigateToRoot(disk: Disk?) async {
        guard !currentPath.isEmpty else { return }
        currentPath = ""
        selectedEntryID = nil
        await refresh(disk: disk)
    }

    func cancelAddFiles() {
        addFilesCancelRequested = true
    }

    /// One file to actually copy: `url` is the local file on disk,
    /// `relativeName` is the destination filename passed straight through to
    /// UserFilesService.addFile's `filename` -- which already supports nested
    /// paths (pfsutil's own mkdir_recursive creates the intermediate PFS
    /// folders), so a `relativeName` like "MyFolder/sub/img.png" just works.
    struct ExpandedFile {
        let url: URL
        let relativeName: String
    }

    /// Expands a raw file-picker selection (files and/or folders, mixed) into
    /// a flat list of individual files to copy. A plain file passes through
    /// unchanged. A folder is walked recursively, with the folder's own name
    /// kept as the first path component of each contained file's
    /// `relativeName` -- so picking "MyFolder" containing "sub/img.png"
    /// produces "MyFolder/sub/img.png", preserving the whole subtree once it
    /// lands on the PS2 drive.
    ///
    /// Symlinks are skipped rather than followed: one inside a picked folder
    /// could point anywhere on the user's disk, and neither this enumeration
    /// nor pfsutil's own file read resolves/rejects them safely -- skipping
    /// is safer than silently copying a symlink's target. (Unlike
    /// AppsService's identical-looking enumeration, which hard-rejects the
    /// whole install on a symlink: that's for untrusted downloaded archives,
    /// whereas this is the user's own local folder, so skip-and-continue is
    /// the right default rather than aborting their whole batch.) Hidden
    /// files are also skipped, matching AppsService's enumeration options.
    static func expand(urls: [URL], fileManager: FileManager = .default) -> [ExpandedFile] {
        var result: [ExpandedFile] = []
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else {
                result.append(ExpandedFile(url: url, relativeName: url.lastPathComponent))
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            let rootPath = url.path
            let folderName = url.lastPathComponent
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                if values.isSymbolicLink == true { continue }
                guard values.isDirectory != true else { continue }
                var relativePath = fileURL.path
                if relativePath.hasPrefix(rootPath) {
                    relativePath.removeFirst(rootPath.count)
                }
                while relativePath.hasPrefix("/") { relativePath.removeFirst() }
                result.append(ExpandedFile(url: fileURL, relativeName: "\(folderName)/\(relativePath)"))
            }
        }
        return result
    }

    /// Adds one or more files/folders at once -- always the single code path
    /// (a single file is just a 1-element batch), matching the
    /// continue-on-failure/cooperative-cancel/summary shape every other
    /// multi-item operation in this app already uses (see
    /// BatchInstallPS1GameViewModel). Folders are expanded to their
    /// contained files first (see `expand`), so the batch/progress below
    /// always operates on individual files. One partition-size decision
    /// covers the whole batch: the check only runs once, before the first
    /// file, not per-file -- confirmedPartitionSizeBytes being set from
    /// either an earlier call or confirmPartitionSize's resumption is what
    /// lets every subsequent file in the loop skip re-checking.
    func addFiles(urls: [URL], on disk: Disk) async {
        guard !urls.isEmpty else { return }
        let expandedFiles = Self.expand(urls: urls)
        guard !expandedFiles.isEmpty else {
            lastError = IdentifiableError(underlying: HDLDumpError.operationNotAllowed(message: "The selected item(s) contain no files to add."))
            return
        }

        let sizeBytesIfCreating: Int64
        switch await PartitionSizeGate.decide(
            confirmedSizeBytes: confirmedSizeBytes(for: disk),
            suggestedSizeBytes: PartitionSizeSuggestions.suggestions(forDriveSizeBytes: disk.sizeBytes).userFiles,
            partitionExists: { (try? await self.service.userFilesPartitionExists(on: disk)) ?? true }
        ) {
        case .proceed(let sizeBytes):
            sizeBytesIfCreating = sizeBytes
        case .awaitingPrompt(let suggestedSizeBytes):
            pendingAction = .addFiles(urls: urls)
            pendingPartitionSizePrompt = PartitionSizePromptRequest(partitionDisplayName: "User Files", suggestedSizeBytes: suggestedSizeBytes)
            return
        }

        isAddingFiles = true
        addFilesCancelRequested = false
        addFilesSummary = nil
        addFilesTotalCount = expandedFiles.count
        defer {
            isAddingFiles = false
            addFilesCurrentIndex = 0
            addFilesCurrentName = ""
        }

        var addedCount = 0
        var failedCount = 0
        for (index, file) in expandedFiles.enumerated() {
            if addFilesCancelRequested { break }
            addFilesCurrentIndex = index + 1
            addFilesCurrentName = file.relativeName
            do {
                try await service.addFile(localURL: file.url, filename: file.relativeName, atPath: currentPath, partitionSizeBytesIfCreating: sizeBytesIfCreating, on: disk)
                addedCount += 1
            } catch {
                // Continue with the rest of the batch rather than aborting
                // on one failure (e.g. one bad file shouldn't block 9 good
                // ones) -- same reasoning as BatchInstallPS1GameViewModel's
                // identical per-item catch.
                failedCount += 1
            }
        }

        var summaryText = "Added \(addedCount) file\(addedCount == 1 ? "" : "s")"
        if failedCount > 0 {
            summaryText += ", \(failedCount) failed"
        }
        if addFilesCancelRequested {
            summaryText += " (cancelled)"
        }
        addFilesSummary = summaryText
        await refresh(disk: disk)
    }

    func createFolder(name: String, on disk: Disk) async {
        let sizeBytesIfCreating: Int64
        switch await PartitionSizeGate.decide(
            confirmedSizeBytes: confirmedSizeBytes(for: disk),
            suggestedSizeBytes: PartitionSizeSuggestions.suggestions(forDriveSizeBytes: disk.sizeBytes).userFiles,
            partitionExists: { (try? await self.service.userFilesPartitionExists(on: disk)) ?? true }
        ) {
        case .proceed(let sizeBytes):
            sizeBytesIfCreating = sizeBytes
        case .awaitingPrompt(let suggestedSizeBytes):
            pendingAction = .createFolder(name: name)
            pendingPartitionSizePrompt = PartitionSizePromptRequest(partitionDisplayName: "User Files", suggestedSizeBytes: suggestedSizeBytes)
            return
        }
        do {
            try await service.createFolder(name: name, atPath: currentPath, partitionSizeBytesIfCreating: sizeBytesIfCreating, on: disk)
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    private func confirmedSizeBytes(for disk: Disk) -> Int64? {
        confirmedPartitionSizeBytes?.diskID == disk.id ? confirmedPartitionSizeBytes?.bytes : nil
    }

    /// Called by UserFilesView's PartitionSizePromptSheet once the user
    /// confirms a size -- resumes whichever of addFiles/createFolder
    /// triggered the prompt.
    func confirmPartitionSize(_ sizeBytes: Int64, on disk: Disk) async {
        confirmedPartitionSizeBytes = (diskID: disk.id, bytes: sizeBytes)
        pendingPartitionSizePrompt = nil
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .addFiles(let urls):
            await addFiles(urls: urls, on: disk)
        case .createFolder(let name):
            await createFolder(name: name, on: disk)
        }
    }

    func confirmDelete(entry: UserFileEntry, disk: Disk) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteEntry(entry, atPath: currentPath, on: disk)
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
