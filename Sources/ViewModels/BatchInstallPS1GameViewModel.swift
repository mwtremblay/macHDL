import Foundation

/// PS1 sibling of BatchInstallGameViewModel -- see that type's doc comment
/// for the shared scope/tradeoffs (no per-file name editing, skip-if-
/// already-installed). Differs from the PS2 version in one structural way:
/// each PS1 file has to go through the full local convert pipeline (split-
/// dump combine + cue2pops) before it can even be copied to the drive, not
/// just a direct copy -- so per-item progress here tracks *phase*
/// (combining/converting/copying), not a byte-level percentage.
///
/// Game-ID detection (via PS1GameIDDetector) is run and the result stored
/// as a sidecar for every successfully-installed file here, same as the
/// single-game InstallPS1GameViewModel -- this is a local, no-network step
/// (reads the first 150KB of the source .bin) and the source file is only
/// ever in hand at this exact moment, so skipping it here would permanently
/// lose the chance for these games (unlike PS2, whose Game ID always comes
/// back for free from the drive's own TOC). The actual cover-art *fetch*
/// (a network call) is deliberately NOT run per-file here, for the same
/// reason PS2 batch skips it: avoids stacking up to N network round-trips
/// on top of what's already a long batch of local conversions. "Fetch All
/// Artwork" already covers these once a sidecar exists.
///
/// Cancel is cooperative only, checked before each new file starts -- there
/// is no subprocess-cancellation hook wired into PS1GameConverter/
/// SplitDumpCombiner (unlike HDLDumpService.cancelInstall for the PS2 copy
/// itself), so a cancel request will let the file currently converting/
/// copying finish before stopping, rather than interrupting it immediately.
@MainActor
final class BatchInstallPS1GameViewModel: ObservableObject {
    enum ItemPhase: Equatable {
        case idle
        case combiningSplitDump
        case converting
        case copyingToDrive

        var text: String {
            switch self {
            case .idle: return ""
            case .combiningSplitDump: return "Combining split disc image…"
            case .converting: return "Converting to POPStarter format…"
            case .copyingToDrive: return "Copying to drive…"
            }
        }
    }

    @Published var pendingSourceURLs: [URL] = []
    @Published private(set) var isInstalling = false
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentItemName: String = ""
    @Published private(set) var currentItemPhase: ItemPhase = .idle
    @Published private(set) var elapsedSeconds: Int = 0
    @Published var summary: String?
    @Published var lastError: IdentifiableError?

    private let service: PS1GameService
    private let converter: PS1GameConverter
    private let combiner: SplitDumpCombiner
    private let artworkService: GameArtworkService
    private let gameIDDetector: PS1GameIDDetector
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var cancelRequested = false

    init(
        service: PS1GameService,
        artworkService: GameArtworkService,
        converter: PS1GameConverter = PS1GameConverter(),
        combiner: SplitDumpCombiner = SplitDumpCombiner(),
        gameIDDetector: PS1GameIDDetector = PS1GameIDDetector()
    ) {
        self.service = service
        self.artworkService = artworkService
        self.converter = converter
        self.combiner = combiner
        self.gameIDDetector = gameIDDetector
    }

    var totalCount: Int { pendingSourceURLs.count }
    var canSubmit: Bool { !pendingSourceURLs.isEmpty && !isInstalling }

    var progressSummaryText: String {
        guard totalCount > 0 else { return "" }
        return "Installing \(currentIndex) of \(totalCount): \(currentItemName)"
    }

    /// The effective on-drive display name a source file would get, if
    /// installed -- accounts for POPStarter's 73-character filename
    /// truncation so "already installed" checks match what actually landed
    /// on the drive, not just the raw source filename.
    static func effectiveDisplayName(forSourceURL url: URL) -> String {
        let rawName = url.deletingPathExtension().lastPathComponent
        let vcdFilename = PFSDestinationPaths.gameVCDFilename(forGameNamed: rawName)
        return PS1Game(vcdFilename: vcdFilename, partitionName: "").displayName
    }

    func reset() {
        pendingSourceURLs = []
        summary = nil
        lastError = nil
        currentIndex = 0
        currentItemName = ""
        currentItemPhase = .idle
        elapsedSeconds = 0
    }

    func cancel() {
        cancelRequested = true
    }

    /// `existingGameNames` should be every currently-installed PS1 game's
    /// `displayName` (`ps1GameListViewModel.games.map(\.displayName)`) --
    /// caller's responsibility, since this view model has no reference to
    /// the game list itself.
    func installAll(existingGameNames: Set<String>, on disk: Disk, completion: @escaping () async -> Void) async {
        guard canSubmit else { return }
        isInstalling = true
        summary = nil
        cancelRequested = false
        startElapsedTimer()
        defer {
            isInstalling = false
            stopElapsedTimer()
            currentItemPhase = .idle
            currentItemName = ""
        }

        var knownNames = existingGameNames
        var installedCount = 0
        var skippedCount = 0
        var failedCount = 0

        for (index, sourceURL) in pendingSourceURLs.enumerated() {
            if cancelRequested { break }
            currentIndex = index + 1
            let displayName = Self.effectiveDisplayName(forSourceURL: sourceURL)
            currentItemName = displayName
            currentItemPhase = .idle

            guard !knownNames.contains(displayName) else {
                skippedCount += 1
                continue
            }

            do {
                let vcdFilename = try await installOne(sourceURL: sourceURL, on: disk)
                installedCount += 1
                // Guards against two selected files deriving the same name
                // within this same batch.
                knownNames.insert(displayName)
                await detectAndStoreGameIDBestEffort(sourceURL: sourceURL, vcdFilename: vcdFilename, on: disk)
            } catch {
                failedCount += 1
            }
        }

        await completion()

        var summaryText = "Installed \(installedCount), skipped \(skippedCount) (already installed)"
        if failedCount > 0 {
            summaryText += ", \(failedCount) failed"
        }
        if cancelRequested {
            summaryText += " (cancelled)"
        }
        summary = summaryText
    }

    /// Runs the same convert-then-copy pipeline as
    /// InstallPS1GameViewModel.install, for one file. Returns the installed
    /// VCD's filename on success.
    private func installOne(sourceURL: URL, on disk: Disk) async throws -> String {
        let rawName = sourceURL.deletingPathExtension().lastPathComponent
        let vcdFilename = PFSDestinationPaths.gameVCDFilename(forGameNamed: rawName)

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macHDL-ps1-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        var cueToConvert = sourceURL
        if try CueSheetAnalyzer.isSplitDump(cueURL: sourceURL) {
            currentItemPhase = .combiningSplitDump
            let combineScratchDir = workDir.appendingPathComponent("combined", isDirectory: true)
            cueToConvert = try await combiner.combine(cueURL: sourceURL, into: combineScratchDir)
        }

        currentItemPhase = .converting
        let vcdURL = workDir.appendingPathComponent(vcdFilename)
        _ = try await converter.convert(cueURL: cueToConvert, outputVCDURL: vcdURL)

        currentItemPhase = .copyingToDrive
        // Batch install has no per-item interactive prompt (would mean
        // stopping a multi-game batch partway through to ask a question) --
        // uses the drive-capacity-aware suggestion directly, same value
        // InstallPS1GameViewModel's own PartitionSizePromptSheet would have
        // prefilled for a single install.
        try await service.installGameWithOverflow(
            vcdURL: vcdURL,
            vcdFilename: vcdFilename,
            defaultPartitionSizeBytes: PartitionSizeSuggestions.suggestions(forDriveSizeBytes: disk.sizeBytes).ps1Games,
            on: disk
        )

        return vcdFilename
    }

    private func detectAndStoreGameIDBestEffort(sourceURL: URL, vcdFilename: String, on disk: Disk) async {
        guard let gameID = try? await gameIDDetector.detectGameID(cueOrBinURL: sourceURL) else { return }
        try? await artworkService.storeGameID(gameID, forVCDFilename: vcdFilename, on: disk)
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
