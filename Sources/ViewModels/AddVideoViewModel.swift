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
    /// Prefilled by MovieFilenameParser, or typed directly -- purely a
    /// disambiguation aid for lookUpMovieMetadata (narrows TMDB's search the
    /// same way season/episode numbers narrow the TV lookup) and isn't
    /// required for install, so nil genuinely means "not detected/entered"
    /// rather than needing a Stepper-style non-optional default.
    @Published var releaseYear: Int?
    @Published var profile: VideoConverter.Profile = .sdNTSC
    @Published private(set) var audioTracks: [VideoConverter.AudioTrack] = []
    @Published var selectedAudioTrackIndex: Int = 0
    @Published private(set) var phase: Phase = .idle
    @Published var lastError: IdentifiableError?
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var progressFraction: Double?

    @Published private(set) var isLookingUpMetadata = false
    /// Populated when a title search returns more than one plausible match
    /// (e.g. "The Italian Job" 1969/2003) -- AddVideoSheet presents this as
    /// a picker; empty otherwise. Same shape/reasoning as
    /// AddTVEpisodeViewModel.showCandidates.
    @Published var movieCandidates: [TMDBSearchCandidate] = []
    /// Soft-state guidance text for lookUpMovieMetadata -- see
    /// AddTVEpisodeViewModel.metadataLookupHint's identical reasoning.
    @Published var metadataLookupHint: String?

    /// Set by `install` when `SMS_Media` doesn't exist yet -- AddVideoSheet
    /// presents PartitionSizePromptSheet bound to this; confirming calls
    /// `confirmPartitionSize`, which resumes `install` with a size resolved.
    /// See PartitionSizePromptRequest's doc comment.
    @Published var pendingPartitionSizePrompt: PartitionSizePromptRequest?
    private var confirmedPartitionSizeBytes: Int64?

    private let service: SMSMediaService
    private let converter: VideoConverter
    private let metadataFetcher: TMDBMetadataFetcher
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var durationSeconds: Double?

    init(service: SMSMediaService, converter: VideoConverter = VideoConverter(), metadataFetcher: TMDBMetadataFetcher = TMDBMetadataFetcher()) {
        self.service = service
        self.converter = converter
        self.metadataFetcher = metadataFetcher
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
        releaseYear = nil
        profile = .sdNTSC
        audioTracks = []
        selectedAudioTrackIndex = 0
        lastError = nil
        elapsedSeconds = 0
        progressFraction = nil
        durationSeconds = nil
        isLookingUpMetadata = false
        movieCandidates = []
        metadataLookupHint = nil
        pendingPartitionSizePrompt = nil
        confirmedPartitionSizeBytes = nil
    }

    /// Called by AddVideoSheet's PartitionSizePromptSheet once the user
    /// confirms a size -- stores it and resumes `install`, which this time
    /// finds `confirmedPartitionSizeBytes` already set and proceeds straight
    /// through instead of prompting again.
    func confirmPartitionSize(_ sizeBytes: Int64, on disk: Disk, completion: @escaping () async -> Void) async {
        confirmedPartitionSizeBytes = sizeBytes
        pendingPartitionSizePrompt = nil
        await install(on: disk, completion: completion)
    }

    /// The destination filename on the drive always gets a `.avi`
    /// extension -- VideoConverter always produces an AVI container,
    /// regardless of the source file's own extension or whatever the user
    /// typed.
    func install(on disk: Disk, completion: @escaping () async -> Void) async {
        guard let sourceURL, isVideoNameValid else { return }

        // SMS_Media genuinely scales with drive size (video is large) --
        // unlike +OPL/PP.FHDB.APPS, there's a real sizing decision to make
        // the first time it's created. Resolved once per sheet presentation
        // (confirmedPartitionSizeBytes), not re-checked on every call.
        let sizeBytesIfCreating: Int64
        switch await PartitionSizeGate.decide(
            confirmedSizeBytes: confirmedPartitionSizeBytes,
            suggestedSizeBytes: PartitionSizeSuggestions.suggestions(forDriveSizeBytes: disk.sizeBytes).movies,
            partitionExists: { (try? await self.service.smsMediaPartitionExists(on: disk)) ?? true }
        ) {
        case .proceed(let sizeBytes):
            sizeBytesIfCreating = sizeBytes
        case .awaitingPrompt(let suggestedSizeBytes):
            pendingPartitionSizePrompt = PartitionSizePromptRequest(partitionDisplayName: "Movies/TV", suggestedSizeBytes: suggestedSizeBytes)
            return
        }

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
            try await service.addVideo(localURL: outputURL, filename: filename, partitionSizeBytesIfCreating: sizeBytesIfCreating, on: disk)

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

        let parsed = MovieFilenameParser.parse(filename: sourceURL.lastPathComponent)
        if videoName.isEmpty {
            videoName = parsed.title ?? sourceURL.deletingPathExtension().lastPathComponent
        }
        if let detectedYear = parsed.year {
            releaseYear = detectedYear
        }

        Task { [weak self, converter] in
            let tracks = (try? await converter.detectAudioTracks(inputURL: sourceURL)) ?? []
            await MainActor.run {
                guard let self, self.sourceURL == sourceURL else { return }
                self.audioTracks = tracks
            }
        }
    }

    /// Looks up the movie's canonical title on TMDB using the current
    /// videoName/releaseYear fields (whether they got there via
    /// MovieFilenameParser or the user typing them directly). Reads the API
    /// key straight from KeychainStore rather than through
    /// TMDBMetadataFetcher -- see AddTVEpisodeViewModel.lookUpEpisodeMetadata's
    /// identical reasoning.
    func lookUpMovieMetadata() async {
        metadataLookupHint = nil
        movieCandidates = []
        let trimmedName = videoName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        guard let apiKey = KeychainStore.get(
            service: TMDBMetadataFetcher.apiKeyKeychainService,
            account: TMDBMetadataFetcher.apiKeyKeychainAccount
        ), !apiKey.isEmpty else {
            metadataLookupHint = "Set a TMDB API key in Settings (⌘,) to enable this."
            return
        }

        isLookingUpMetadata = true
        defer { isLookingUpMetadata = false }

        do {
            let movies = try await metadataFetcher.searchMovies(name: trimmedName, year: releaseYear, apiKey: apiKey)
            switch movies.count {
            case 0:
                metadataLookupHint = "No movies found matching \"\(trimmedName)\"."
            case 1:
                apply(movies[0].asCandidate)
            default:
                // Already relevance-ordered by TMDB -- capped so the picker
                // stays short and digestible.
                movieCandidates = movies.prefix(5).map(\.asCandidate)
            }
        } catch let error as TMDBMetadataFetcher.FetchError {
            if case .notFound = error {
                metadataLookupHint = "No movies found matching \"\(trimmedName)\"."
            } else {
                lastError = IdentifiableError(underlying: error)
            }
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    /// Called by AddVideoSheet's disambiguation picker once the user taps a
    /// candidate from `movieCandidates`. Unlike AddTVEpisodeViewModel.
    /// selectShow, no further network call is needed -- the search result
    /// already carried the final title (see TMDBMetadataFetcher.searchMovies'
    /// doc comment).
    func selectMovie(_ candidate: TMDBSearchCandidate) {
        movieCandidates = []
        apply(candidate)
    }

    private func apply(_ candidate: TMDBSearchCandidate) {
        videoName = candidate.name
        releaseYear = candidate.year.flatMap(Int.init)
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
