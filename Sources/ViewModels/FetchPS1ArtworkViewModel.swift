import Foundation

/// Retroactive/manual PS1 artwork fetch -- for an already-installed game (or
/// a retry). If a Game ID was already detected and stored for this game
/// before (at install time, or a previous manual fetch -- see
/// GameArtworkService.storeGameID/fetchStoredGameID), that's reused
/// directly with no file picker needed at all. Only falls back to asking
/// the user to re-select the original disc image when no stored ID exists
/// yet -- re-selecting a file every single time this was used turned out to
/// be real, reported friction.
@MainActor
final class FetchPS1ArtworkViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checkingStoredGameID
        case detectingGameID
        case fetchingArtwork
        case installingArtwork
    }

    @Published var sourceURL: URL?
    @Published private(set) var storedGameID: String?
    @Published private(set) var phase: Phase = .idle
    @Published var lastError: IdentifiableError?
    @Published private(set) var didSucceed = false
    @Published private(set) var elapsedSeconds: Int = 0

    private let artworkService: GameArtworkService
    private let artworkFetcher: GameArtworkFetcher
    private let gameIDDetector: PS1GameIDDetector
    private var elapsedTimer: Timer?
    private var startedAt: Date?

    init(
        artworkService: GameArtworkService,
        artworkFetcher: GameArtworkFetcher = GameArtworkFetcher(),
        gameIDDetector: PS1GameIDDetector = PS1GameIDDetector()
    ) {
        self.artworkService = artworkService
        self.artworkFetcher = artworkFetcher
        self.gameIDDetector = gameIDDetector
    }

    var isFetching: Bool { phase != .idle }
    var canSubmit: Bool { (sourceURL != nil || storedGameID != nil) && !isFetching }

    var phaseText: String {
        switch phase {
        case .idle: return ""
        case .checkingStoredGameID: return "Checking for a previously-detected Game ID…"
        case .detectingGameID: return "Detecting Game ID…"
        case .fetchingArtwork: return "Fetching artwork…"
        case .installingArtwork: return "Installing artwork…"
        }
    }

    func reset() {
        sourceURL = nil
        storedGameID = nil
        lastError = nil
        didSucceed = false
        elapsedSeconds = 0
    }

    /// Call once when the sheet appears -- if this returns a stored ID, the
    /// UI can skip straight to a "Fetch" button with no file picker shown.
    func checkForStoredGameID(game: PS1Game, on disk: Disk) async {
        phase = .checkingStoredGameID
        defer { phase = .idle }
        storedGameID = try? await artworkService.fetchStoredGameID(forVCDFilename: game.vcdFilename, on: disk)
    }

    func fetch(game: PS1Game, on disk: Disk) async {
        didSucceed = false
        startElapsedTimer()
        defer {
            phase = .idle
            stopElapsedTimer()
        }

        do {
            let gameID: String
            if let sourceURL {
                phase = .detectingGameID
                gameID = try await gameIDDetector.detectGameID(cueOrBinURL: sourceURL)
                // Best-effort -- a failure to persist shouldn't block using
                // the ID we just successfully detected for this one fetch.
                try? await artworkService.storeGameID(gameID, forVCDFilename: game.vcdFilename, on: disk)
            } else if let storedGameID {
                gameID = storedGameID
            } else {
                return
            }

            phase = .fetchingArtwork
            let data = try await artworkFetcher.fetchCoverArt(platform: .ps1, gameID: gameID)

            phase = .installingArtwork
            try await artworkService.installPS1CoverArt(vcdFilename: game.vcdFilename, imageData: data, on: disk)

            didSucceed = true
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
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
