import Foundation

/// Modeled directly on AddVideoViewModel, plus Show Name/Season Number
/// fields that become PFS path components (see PFSPathComponentValidation)
/// rather than the destination filename itself.
@MainActor
final class AddTVEpisodeViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case converting
        case copyingToDrive
    }

    @Published var sourceURL: URL? {
        didSet { onSourceURLChanged() }
    }
    @Published var episodeName: String = ""
    @Published var showName: String = ""
    @Published var seasonNumber: Int = 1
    /// First-class (not just baked into `episodeName`) so
    /// `lookUpEpisodeMetadata` has something to query TMDB's per-episode
    /// endpoint with -- see that method's doc comment.
    @Published var episodeNumber: Int = 1
    @Published var profile: VideoConverter.Profile = .sdNTSC
    @Published private(set) var audioTracks: [VideoConverter.AudioTrack] = []
    @Published var selectedAudioTrackIndex: Int = 0
    @Published private(set) var phase: Phase = .idle
    @Published var lastError: IdentifiableError?
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var progressFraction: Double?

    @Published private(set) var isLookingUpMetadata = false
    /// Populated when a show-name search returns more than one plausible
    /// match (e.g. "The Office" US/UK) -- AddTVEpisodeSheet presents this as
    /// a picker; empty otherwise.
    @Published var showCandidates: [TMDBSearchCandidate] = []
    /// Soft-state guidance text for lookUpEpisodeMetadata ("Set an API key
    /// in Settings," "No shows found…") -- deliberately separate from
    /// `lastError`, which is reserved for genuine network/server failures.
    /// Same soft/hard split GameArtworkFetcher.FetchError.notFound already
    /// established for this app's other online lookup.
    @Published var metadataLookupHint: String?

    /// Set by `install` when `SMS_Media` doesn't exist yet -- same shape as
    /// AddVideoViewModel's identical property (Shows and Movies share the
    /// same underlying partition, see TVShowService.smsMediaPartitionExists'
    /// doc comment).
    @Published var pendingPartitionSizePrompt: PartitionSizePromptRequest?
    private var confirmedPartitionSizeBytes: Int64?

    private let service: TVShowService
    private let converter: VideoConverter
    private let metadataFetcher: TMDBMetadataFetcher
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var durationSeconds: Double?

    init(service: TVShowService, converter: VideoConverter = VideoConverter(), metadataFetcher: TMDBMetadataFetcher = TMDBMetadataFetcher()) {
        self.service = service
        self.converter = converter
        self.metadataFetcher = metadataFetcher
    }

    var isEpisodeNameValid: Bool {
        PFSPathComponentValidation.isValid(episodeName)
    }

    /// `showName` becomes a PFS directory name (`Shows/<showName>/...`) --
    /// same reason this must reject `/`/`.`/`..` as AddVideoViewModel's
    /// videoName, see PFSPathComponentValidation's doc comment.
    var isShowNameValid: Bool {
        PFSPathComponentValidation.isValid(showName)
    }

    var isSeasonNumberValid: Bool {
        seasonNumber >= 1
    }

    var isInstalling: Bool {
        phase != .idle
    }

    var canSubmit: Bool {
        sourceURL != nil && isEpisodeNameValid && isShowNameValid && isSeasonNumberValid && !isInstalling
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
        episodeName = ""
        showName = ""
        seasonNumber = 1
        episodeNumber = 1
        profile = .sdNTSC
        audioTracks = []
        selectedAudioTrackIndex = 0
        lastError = nil
        elapsedSeconds = 0
        progressFraction = nil
        durationSeconds = nil
        isLookingUpMetadata = false
        showCandidates = []
        metadataLookupHint = nil
        pendingPartitionSizePrompt = nil
        confirmedPartitionSizeBytes = nil
    }

    /// Called by AddTVEpisodeSheet's PartitionSizePromptSheet once the user
    /// confirms a size -- see AddVideoViewModel.confirmPartitionSize's
    /// identical reasoning.
    func confirmPartitionSize(_ sizeBytes: Int64, on disk: Disk, completion: @escaping () async -> Void) async {
        confirmedPartitionSizeBytes = sizeBytes
        pendingPartitionSizePrompt = nil
        await install(on: disk, completion: completion)
    }

    /// The destination filename on the drive always gets a `.avi`
    /// extension -- VideoConverter always produces an AVI container,
    /// regardless of the source file's own extension or whatever the user
    /// typed. See AddVideoViewModel.install's identical reasoning.
    func install(on disk: Disk, completion: @escaping () async -> Void) async {
        guard let sourceURL, isEpisodeNameValid, isShowNameValid, isSeasonNumberValid else { return }

        // See AddVideoViewModel.install's identical SMS_Media sizing check
        // -- Shows and Movies share the same underlying partition.
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

        let baseName = episodeName.trimmingCharacters(in: .whitespaces)
        let filename = baseName.hasSuffix(".avi") ? baseName : baseName + ".avi"
        let trimmedShowName = showName.trimmingCharacters(in: .whitespaces)
        startElapsedTimer()
        defer {
            phase = .idle
            stopElapsedTimer()
        }

        do {
            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("macHDL-tv-convert-\(UUID().uuidString)", isDirectory: true)
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
            try await service.addEpisode(localURL: outputURL, showName: trimmedShowName, seasonNumber: seasonNumber, filename: filename, partitionSizeBytesIfCreating: sizeBytesIfCreating, on: disk)

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

    /// Re-probes audio tracks every time the source changes -- see
    /// AddVideoViewModel.onSourceURLChanged's identical `[weak self]`/
    /// stale-probe-guard reasoning. Also prefills Show Name/Season Number/
    /// Episode Name from the source filename via TVFilenameParser, same
    /// "only if not already set" guard as episodeName's own prior
    /// unconditional prefill -- never overwrites something the user already
    /// typed. seasonNumber has no "unset" sentinel (the Stepper always
    /// starts at 1), so a detected season always wins; low-risk since this
    /// only ever runs immediately after picking a file, before the user has
    /// had a chance to adjust it themselves.
    private func onSourceURLChanged() {
        audioTracks = []
        selectedAudioTrackIndex = 0
        guard let sourceURL else { return }

        let parsed = TVFilenameParser.parse(filename: sourceURL.lastPathComponent)
        if showName.isEmpty, let detectedShowName = parsed.showName {
            showName = detectedShowName
        }
        if let detectedSeasonNumber = parsed.seasonNumber {
            seasonNumber = detectedSeasonNumber
        }
        if let detectedEpisodeNumber = parsed.episodeNumber {
            episodeNumber = detectedEpisodeNumber
        }
        if episodeName.isEmpty {
            episodeName = Self.suggestedEpisodeName(parsed: parsed, fallback: sourceURL.deletingPathExtension().lastPathComponent)
        }

        Task { [weak self, converter] in
            let tracks = (try? await converter.detectAudioTracks(inputURL: sourceURL)) ?? []
            await MainActor.run {
                guard let self, self.sourceURL == sourceURL else { return }
                self.audioTracks = tracks
            }
        }
    }

    /// Combines a parsed episode number/title into the destination
    /// filename's base name, e.g. episode 2 titled "Serenity" -> "02 -
    /// Serenity". The zero-padded number prefix isn't just cosmetic:
    /// TVShowListView sorts episodes alphabetically by filename, so without
    /// it "Episode 10" would sort before "Episode 2". Falls back to the
    /// source file's own name, unchanged, when nothing could be parsed --
    /// matches this method's previous unconditional behavior.
    nonisolated static func suggestedEpisodeName(parsed: TVFilenameParser.ParsedEpisode, fallback: String) -> String {
        guard let episodeNumber = parsed.episodeNumber else {
            return parsed.episodeTitle ?? fallback
        }
        let paddedNumber = String(format: "%02d", episodeNumber)
        guard let episodeTitle = parsed.episodeTitle, !episodeTitle.isEmpty else {
            return paddedNumber
        }
        return "\(paddedNumber) - \(episodeTitle)"
    }

    /// Looks up the episode title on TMDB using the current
    /// showName/seasonNumber/episodeNumber fields (whether they got there
    /// via TVFilenameParser or the user typing them directly -- this method
    /// doesn't care which). Reads the API key straight from KeychainStore
    /// rather than through TVEpisodeMetadataFetcher (which deliberately
    /// knows nothing about Keychain, see its own doc comment) -- a missing
    /// key is a soft "can't do this yet" state, not a network error, so it's
    /// checked before ever calling the fetcher.
    func lookUpEpisodeMetadata() async {
        metadataLookupHint = nil
        showCandidates = []
        let trimmedShowName = showName.trimmingCharacters(in: .whitespaces)
        guard !trimmedShowName.isEmpty else { return }

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
            let shows = try await metadataFetcher.searchShows(name: trimmedShowName, apiKey: apiKey)
            switch shows.count {
            case 0:
                metadataLookupHint = "No shows found matching \"\(trimmedShowName)\"."
            case 1:
                try await fetchEpisodeTitle(showID: shows[0].id, showName: shows[0].name, apiKey: apiKey)
            default:
                // Already relevance-ordered by TMDB -- capped so the picker
                // stays short and digestible.
                showCandidates = shows.prefix(5).map(\.asCandidate)
            }
        } catch let error as TMDBMetadataFetcher.FetchError {
            if case .notFound = error {
                metadataLookupHint = "No shows found matching \"\(trimmedShowName)\"."
            } else {
                lastError = IdentifiableError(underlying: error)
            }
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    /// Called by AddTVEpisodeSheet's disambiguation picker once the user
    /// taps a candidate from `showCandidates`.
    func selectShow(_ candidate: TMDBSearchCandidate) async {
        showCandidates = []
        guard let apiKey = KeychainStore.get(
            service: TMDBMetadataFetcher.apiKeyKeychainService,
            account: TMDBMetadataFetcher.apiKeyKeychainAccount
        ) else { return }

        isLookingUpMetadata = true
        defer { isLookingUpMetadata = false }
        do {
            try await fetchEpisodeTitle(showID: candidate.id, showName: candidate.name, apiKey: apiKey)
        } catch let error as TMDBMetadataFetcher.FetchError {
            if case .notFound = error {
                metadataLookupHint = "TMDB has no episode \(episodeNumber) for Season \(seasonNumber) of \"\(candidate.name)\"."
            } else {
                lastError = IdentifiableError(underlying: error)
            }
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    /// Fetches the specific season/episode's title and applies it -- sets
    /// `showName` to TMDB's canonical name (fixes capitalization/naming
    /// consistency across a show's episodes, since a later episode's
    /// filename might spell the show differently than an earlier one) and
    /// rebuilds `episodeName` through the same suggestedEpisodeName
    /// formatter the filename-parse path already uses, so the "NN - Title"
    /// convention is identical regardless of source. Still just a normal
    /// editable text field afterward -- the user can override it, same
    /// philosophy as the filename-parse prefill.
    private func fetchEpisodeTitle(showID: Int, showName resolvedShowName: String, apiKey: String) async throws {
        let episode = try await metadataFetcher.fetchEpisode(showID: showID, seasonNumber: seasonNumber, episodeNumber: episodeNumber, apiKey: apiKey)
        showName = resolvedShowName
        episodeName = Self.suggestedEpisodeName(
            parsed: TVFilenameParser.ParsedEpisode(episodeNumber: episodeNumber, episodeTitle: episode.name),
            fallback: episodeName
        )
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
