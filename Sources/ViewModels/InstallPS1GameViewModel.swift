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

    /// New `__.POPS` partitions are created at this size the first time a
    /// PS1 game is installed on a drive that doesn't have one yet. Sized to
    /// comfortably hold a handful of PS1 games (VCDs are typically
    /// 600-750MB, matching their CD-ROM origin).
    static let defaultGamesPartitionSizeBytes: Int64 = 4_000_000_000

    private let service: PS1GameService
    private let converter: PS1GameConverter
    private let combiner: SplitDumpCombiner
    private var elapsedTimer: Timer?
    private var startedAt: Date?

    init(
        service: PS1GameService,
        converter: PS1GameConverter = PS1GameConverter(),
        combiner: SplitDumpCombiner = SplitDumpCombiner()
    ) {
        self.service = service
        self.converter = converter
        self.combiner = combiner
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
            try await service.createGamesPartitionIfNeeded(sizeBytes: Self.defaultGamesPartitionSizeBytes, on: disk)
            try await service.installGame(vcdURL: vcdURL, vcdFilename: vcdFilename, on: disk)

            await completion()
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
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
