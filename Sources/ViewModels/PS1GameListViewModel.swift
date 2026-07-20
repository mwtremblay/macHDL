import Foundation

@MainActor
final class PS1GameListViewModel: ObservableObject {
    @Published private(set) var games: [PS1Game] = []
    @Published private(set) var isLoading = false
    @Published var lastError: IdentifiableError?
    @Published var selectedGameID: PS1Game.ID?

    @Published var pendingDeleteGame: PS1Game?
    @Published private(set) var isDeleting = false

    @Published private(set) var isFetchingAllArtwork = false
    @Published private(set) var bulkArtworkProgressText: String = ""
    @Published var bulkArtworkSummary: String?
    private var bulkArtworkTask: Task<Void, Never>?

    private let service: PS1GameService
    private let artworkService: GameArtworkService
    private let artworkFetcher: GameArtworkFetcher

    init(service: PS1GameService, artworkService: GameArtworkService, artworkFetcher: GameArtworkFetcher = GameArtworkFetcher()) {
        self.service = service
        self.artworkService = artworkService
        self.artworkFetcher = artworkFetcher
    }

    var selectedGame: PS1Game? {
        games.first { $0.id == selectedGameID }
    }

    func refresh(disk: Disk?) async {
        guard let disk else {
            games = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            games = try await service.listGames(on: disk)
            if let selectedGameID, !games.contains(where: { $0.id == selectedGameID }) {
                self.selectedGameID = nil
            }
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    func confirmDelete(game: PS1Game, disk: Disk) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteGame(vcdFilename: game.vcdFilename, partitionName: game.partitionName, on: disk)
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    /// Fetches artwork for every PS1 game that already has a stored Game ID
    /// sidecar (see GameArtworkService.storeGameID/fetchStoredGameID) --
    /// deliberately does NOT run PS1GameIDDetector or prompt for a source
    /// disc image for games that don't have one yet, per explicit user
    /// request: re-selecting a file per game during a bulk run defeats the
    /// point of "bulk". Games with no stored ID are just skipped/counted,
    /// not treated as failures. Mirrors GameListViewModel's PS2 bulk fetch
    /// (self-owned cancellable Task, skip-if-already-has-art, inter-request
    /// delay, dismissible summary banner).
    func fetchArtworkForAllGames(on disk: Disk) {
        guard !isFetchingAllArtwork, !games.isEmpty else { return }
        bulkArtworkTask = Task { await runBulkArtworkFetch(on: disk) }
    }

    func cancelBulkArtworkFetch() {
        bulkArtworkTask?.cancel()
    }

    private func runBulkArtworkFetch(on disk: Disk) async {
        isFetchingAllArtwork = true
        bulkArtworkSummary = nil
        defer {
            isFetchingAllArtwork = false
            bulkArtworkProgressText = ""
            bulkArtworkTask = nil
        }

        let allGames = games
        var installedCount = 0
        var alreadyHadArtCount = 0
        var notFoundCount = 0
        var noStoredIDCount = 0
        var failedCount = 0

        for (index, game) in allGames.enumerated() {
            if Task.isCancelled { break }
            bulkArtworkProgressText = "Fetching artwork (\(index + 1) of \(allGames.count)): \(game.displayName)"

            guard let gameID = try? await artworkService.fetchStoredGameID(forVCDFilename: game.vcdFilename, on: disk) else {
                noStoredIDCount += 1
                continue
            }

            if (try? await artworkService.fetchInstalledPS1CoverArt(vcdFilename: game.vcdFilename, on: disk)) != nil {
                alreadyHadArtCount += 1
                continue
            }

            do {
                let data = try await artworkFetcher.fetchCoverArt(platform: .ps1, gameID: gameID)
                try await artworkService.installPS1CoverArt(vcdFilename: game.vcdFilename, imageData: data, on: disk)
                installedCount += 1
            } catch GameArtworkFetcher.FetchError.notFound {
                notFoundCount += 1
            } catch {
                failedCount += 1
            }

            // Same rate-limiting courtesy as the PS2 bulk fetch.
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        var summary = "Installed \(installedCount), already had art \(alreadyHadArtCount), no artwork found \(notFoundCount)"
        if noStoredIDCount > 0 {
            summary += ", \(noStoredIDCount) skipped (no Game ID yet)"
        }
        if failedCount > 0 {
            summary += ", \(failedCount) failed"
        }
        if Task.isCancelled {
            summary += " (cancelled)"
        }
        bulkArtworkSummary = summary
    }
}
