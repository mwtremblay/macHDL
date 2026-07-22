import Foundation

/// Modeled on InstallPS1GameViewModel, single archive at a time (not batch,
/// no bulk install per requirements) -- extraction replaces PS1's convert
/// step.
@MainActor
final class AddAppViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case extracting
        case copyingToDrive
    }

    @Published var sourceURL: URL? {
        didSet { onSourceURLChanged() }
    }
    @Published var appFolderName: String = ""
    @Published private(set) var phase: Phase = .idle
    @Published var lastError: IdentifiableError?
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var currentFileIndex: Int = 0
    @Published private(set) var totalFileCount: Int = 0

    private let service: AppsService
    private let extractor: AppArchiveExtractor
    private var elapsedTimer: Timer?
    private var startedAt: Date?

    init(service: AppsService, extractor: AppArchiveExtractor = AppArchiveExtractor()) {
        self.service = service
        self.extractor = extractor
    }

    var isAppFolderNameValid: Bool {
        Self.isValidFolderName(appFolderName)
    }

    /// `appFolderName` becomes a single PFS path component (`APPS/<name>/...`)
    /// on a real PS2 HDD's partition -- see PFSPathComponentValidation for
    /// why this must reject `/`/`.`/`..`. A static, dependency-free function
    /// so it's directly unit-testable without constructing the
    /// AppsService/PS1GameService object graph.
    nonisolated static func isValidFolderName(_ name: String) -> Bool {
        PFSPathComponentValidation.isValid(name)
    }

    var isInstalling: Bool {
        phase != .idle
    }

    var canSubmit: Bool {
        sourceURL != nil && isAppFolderNameValid && !isInstalling
    }

    var phaseText: String {
        switch phase {
        case .idle:
            return ""
        case .extracting:
            return "Extracting archive…"
        case .copyingToDrive:
            return totalFileCount > 0 ? "Copying to drive… (\(currentFileIndex) of \(totalFileCount))" : "Copying to drive…"
        }
    }

    var progressFraction: Double? {
        guard phase == .copyingToDrive, totalFileCount > 0 else { return nil }
        return Double(currentFileIndex) / Double(totalFileCount)
    }

    func reset() {
        sourceURL = nil
        appFolderName = ""
        lastError = nil
        elapsedSeconds = 0
        currentFileIndex = 0
        totalFileCount = 0
    }

    /// Extraction only happens here, at Install time -- not eagerly when
    /// `sourceURL` is set -- so picking a file never triggers a background
    /// `Process` shell-out as a side effect. Whatever folder name the user
    /// has typed by the time they press Install always wins as the
    /// destination folder name, even if the archive itself turns out to
    /// have a different single wrapping folder inside it (see
    /// AppArchiveExtractor/AppsService's doc comments) -- simpler than
    /// reconciling the two, and the user's explicit choice is authoritative
    /// either way.
    func install(on disk: Disk, completion: @escaping () async -> Void) async {
        guard let sourceURL, isAppFolderNameValid else { return }
        let folderName = appFolderName.trimmingCharacters(in: .whitespaces)
        startElapsedTimer()
        defer {
            phase = .idle
            stopElapsedTimer()
        }

        do {
            phase = .extracting
            let extracted = try await extractor.extract(archiveURL: sourceURL)
            defer { try? FileManager.default.removeItem(at: extracted.scratchRoot) }

            phase = .copyingToDrive
            try await service.installApp(extracted: extracted, appFolderName: folderName, on: disk) { [weak self] index, total, _ in
                Task { @MainActor in
                    self?.currentFileIndex = index
                    self?.totalFileCount = total
                }
            }

            await completion()
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    private func onSourceURLChanged() {
        guard let sourceURL, appFolderName.isEmpty else { return }
        appFolderName = sourceURL.deletingPathExtension().lastPathComponent
    }

    private func startElapsedTimer() {
        startedAt = Date()
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        startedAt = nil
    }
}
