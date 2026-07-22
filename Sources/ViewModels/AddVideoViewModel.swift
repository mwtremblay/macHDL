import Foundation

/// Modeled on InstallPS1GameViewModel: a `converting` phase (ffmpeg, via
/// VideoConverter) before `copyingToDrive`, single file at a time -- no
/// batch, matching the Apps feature's own scope decision.
@MainActor
final class AddVideoViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case converting
        case copyingToDrive
    }

    @Published var sourceURL: URL? {
        didSet { onSourceURLChanged() }
    }
    @Published var videoName: String = ""
    @Published var profile: VideoConverter.Profile = .sdNTSC
    @Published private(set) var audioTracks: [VideoConverter.AudioTrack] = []
    @Published var selectedAudioTrackIndex: Int = 0
    @Published private(set) var phase: Phase = .idle
    @Published var lastError: IdentifiableError?
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var progressFraction: Double?

    private let service: SMSMediaService
    private let converter: VideoConverter
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var durationSeconds: Double?

    init(service: SMSMediaService, converter: VideoConverter = VideoConverter()) {
        self.service = service
        self.converter = converter
    }

    var isVideoNameValid: Bool {
        Self.isValidVideoName(videoName)
    }

    /// `videoName` becomes the destination filename at the `SMS_Media`
    /// partition root -- see PFSPathComponentValidation for why this must
    /// reject `/`/`.`/`..`. A static, dependency-free function so it's
    /// directly unit-testable without constructing the
    /// SMSMediaService/PS1GameService object graph.
    nonisolated static func isValidVideoName(_ name: String) -> Bool {
        PFSPathComponentValidation.isValid(name)
    }

    var isInstalling: Bool {
        phase != .idle
    }

    var canSubmit: Bool {
        sourceURL != nil && isVideoNameValid && !isInstalling
    }

    var phaseText: String {
        switch phase {
        case .idle:
            return ""
        case .converting:
            if let progressFraction {
                return "Converting… \(Int(progressFraction * 100))%"
            }
            return "Converting…"
        case .copyingToDrive:
            return "Copying to drive…"
        }
    }

    func reset() {
        sourceURL = nil
        videoName = ""
        profile = .sdNTSC
        audioTracks = []
        selectedAudioTrackIndex = 0
        lastError = nil
        elapsedSeconds = 0
        progressFraction = nil
        durationSeconds = nil
    }

    /// The destination filename on the drive always gets a `.avi`
    /// extension -- VideoConverter always produces an AVI container,
    /// regardless of the source file's own extension or whatever the user
    /// typed.
    func install(on disk: Disk, completion: @escaping () async -> Void) async {
        guard let sourceURL, isVideoNameValid else { return }
        let baseName = videoName.trimmingCharacters(in: .whitespaces)
        let filename = baseName.hasSuffix(".avi") ? baseName : baseName + ".avi"
        startElapsedTimer()
        defer {
            phase = .idle
            stopElapsedTimer()
        }

        do {
            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("macHDL-video-convert-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDir) }

            phase = .converting
            durationSeconds = nil
            progressFraction = nil
            let outputURL = workDir.appendingPathComponent(filename)
            let audioTrackIndex = audioTracks.isEmpty ? nil : selectedAudioTrackIndex
            _ = try await converter.convert(inputURL: sourceURL, outputURL: outputURL, profile: profile, audioTrackIndex: audioTrackIndex) { [weak self] line in
                Task { @MainActor in
                    self?.handleConverterOutputLine(line)
                }
            }

            phase = .copyingToDrive
            progressFraction = nil
            try await service.addVideo(localURL: outputURL, filename: filename, on: disk)

            await completion()
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    private func handleConverterOutputLine(_ line: String) {
        if durationSeconds == nil, let duration = VideoConverter.parseDurationSeconds(fromLine: line) {
            durationSeconds = duration
        }
        if let durationSeconds, let current = VideoConverter.parseProgressSeconds(fromLine: line), durationSeconds > 0 {
            progressFraction = min(1, current / durationSeconds)
        }
    }

    /// Re-probes audio tracks every time the source changes -- `[weak self]`
    /// plus re-checking `self.sourceURL == sourceURL` after the `await`
    /// guards against a stale probe overwriting `audioTracks` if the user
    /// picks a different file before the first probe finishes.
    private func onSourceURLChanged() {
        audioTracks = []
        selectedAudioTrackIndex = 0
        guard let sourceURL else { return }
        if videoName.isEmpty {
            videoName = sourceURL.deletingPathExtension().lastPathComponent
        }
        Task { [weak self, converter] in
            let tracks = (try? await converter.detectAudioTracks(inputURL: sourceURL)) ?? []
            await MainActor.run {
                guard let self, self.sourceURL == sourceURL else { return }
                self.audioTracks = tracks
            }
        }
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
