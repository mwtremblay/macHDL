import Foundation

@MainActor
final class InstallPS1GameViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case combiningSplitDump
        case converting
        case copyingToDrive
    }

    @Published var sourceURL: URL? {
        didSet { onSourceURLChanged() }
    }
    @Published var name: String = ""
    @Published private(set) var phase: Phase = .idle
    @Published var lastError: IdentifiableError?
    @Published private(set) var elapsedSeconds: Int = 0

    /// New PS1 games partitions (`__.POPS`, or an overflow `__.POPS1`-
    /// `__.POPS10` once a previous one fills up -- see
    /// `PS1GameService.installGameWithOverflow`) are created at this size.
    /// Originally 4GB ("a handful of games"), which in real use only fit 4
    /// games before filling up (VCDs are typically 600MB-1GB) -- bumped
    /// significantly for real libraries, now that filling a partition is a
    /// transparent, automatic overflow instead of a hard install failure.
    static let defaultGamesPartitionSizeBytes: Int64 = 32_000_000_000

    private let service: PS1GameService
    private let converter: PS1GameConverter
    private let combiner: SplitDumpCombiner
    private let artworkService: GameArtworkService
    private let artworkFetcher: GameArtworkFetcher
    private let gameIDDetector: PS1GameIDDetector
    private var elapsedTimer: Timer?
    private var startedAt: Date?

    init(
        service: PS1GameService,
        artworkService: GameArtworkService,
        converter: PS1GameConverter = PS1GameConverter(),
        combiner: SplitDumpCombiner = SplitDumpCombiner(),
        artworkFetcher: GameArtworkFetcher = GameArtworkFetcher(),
        gameIDDetector: PS1GameIDDetector = PS1GameIDDetector()
    ) {
        self.service = service
        self.converter = converter
        self.combiner = combiner
        self.artworkService = artworkService
        self.artworkFetcher = artworkFetcher
        self.gameIDDetector = gameIDDetector
    }

    var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty
    }

    /// POPStarter enforces a hard 73-character limit on the VCD filename
    /// (see PFSDestinationPaths) -- surfaced here so the UI can warn before
    /// installing a game whose name would get silently truncated.
    var willTruncateFilename: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.count + ".VCD".count > PFSDestinationPaths.maxGameFilenameLength
    }

    var isInstalling: Bool {
        phase != .idle
    }

    var canSubmit: Bool {
        sourceURL != nil && isNameValid && !isInstalling
    }

    var phaseText: String {
        switch phase {
        case .idle: return ""
        case .combiningSplitDump: return "Combining split disc image…"
        case .converting: return "Converting to POPStarter format…"
        case .copyingToDrive: return "Copying to drive…"
        }
    }

    func reset() {
        sourceURL = nil
        name = ""
        lastError = nil
        elapsedSeconds = 0
    }

    func install(on disk: Disk, completion: @escaping () async -> Void) async {
        guard let sourceURL else { return }
        let vcdFilename = PFSDestinationPaths.gameVCDFilename(forGameNamed: name.trimmingCharacters(in: .whitespaces))
        startElapsedTimer()
        defer {
            phase = .idle
            stopElapsedTimer()
        }

        do {
            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("macHDL-ps1-convert-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDir) }

            // Split dumps (multiple .bin files per .cue) can't be converted
            // directly by cue2pops -- merge them into a single .bin/.cue
            // first via psx-vcd, then feed the merged .cue into the same,
            // unchanged cue2pops conversion path below. Non-split dumps
            // (the common case) skip this entirely.
            var cueToConvert = sourceURL
            if try CueSheetAnalyzer.isSplitDump(cueURL: sourceURL) {
                phase = .combiningSplitDump
                let combineScratchDir = workDir.appendingPathComponent("combined", isDirectory: true)
                cueToConvert = try await combiner.combine(cueURL: sourceURL, into: combineScratchDir)
            }

            phase = .converting
            // The local temp filename doesn't matter (deleted after upload)
            // -- only the destination filename (vcdFilename) does.
            let vcdURL = workDir.appendingPathComponent(vcdFilename)
            _ = try await converter.convert(cueURL: cueToConvert, outputVCDURL: vcdURL)

            phase = .copyingToDrive
            try await service.installGameWithOverflow(
                vcdURL: vcdURL,
                vcdFilename: vcdFilename,
                defaultPartitionSizeBytes: Self.defaultGamesPartitionSizeBytes,
                on: disk
            )

            await completion()
            await autoFetchArtworkBestEffort(cueURL: sourceURL, vcdFilename: vcdFilename, on: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    /// Best-effort, silent -- the game install already succeeded and
    /// reported success by this point. Reuses the original source .cue
    /// still in scope here (via `sourceURL`, the parameter passed in) to
    /// detect a Game ID for art lookup -- this is the one point in this
    /// app's lifecycle where that source file is guaranteed available
    /// without asking the user to re-select it (see FetchPS1ArtworkSheet
    /// for the retroactive/re-select path used for already-installed games).
    private func autoFetchArtworkBestEffort(cueURL: URL, vcdFilename: String, on disk: Disk) async {
        guard let gameID = try? await gameIDDetector.detectGameID(cueOrBinURL: cueURL) else { return }
        // Store the detected ID regardless of whether the art fetch below
        // succeeds -- e.g. a transient network failure shouldn't force the
        // user to re-select the disc image again later just to retry.
        try? await artworkService.storeGameID(gameID, forVCDFilename: vcdFilename, on: disk)
        guard let data = try? await artworkFetcher.fetchCoverArt(platform: .ps1, gameID: gameID) else { return }
        try? await artworkService.installPS1CoverArt(vcdFilename: vcdFilename, imageData: data, on: disk)
    }

    private func onSourceURLChanged() {
        guard let sourceURL, name.isEmpty else { return }
        name = sourceURL.deletingPathExtension().lastPathComponent
    }

    private func startElapsedTimer() {
        startedAt = Date()
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            Task { @MainActor in
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
