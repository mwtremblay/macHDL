import Foundation

@MainActor
final class GameListViewModel: ObservableObject {
    @Published private(set) var games: [HDLGame] = []
    @Published private(set) var isLoading = false
    @Published var lastError: IdentifiableError?
    @Published var selectedGameID: HDLGame.ID?

    @Published var pendingDeleteGame: HDLGame?
    @Published private(set) var isDeleting = false
    @Published private(set) var deleteProgressText: String = ""

    @Published private(set) var isFetchingArtwork = false
    /// Soft "no artwork available" state -- deliberately NOT surfaced via
    /// `lastError`/an alert, since a missing entry in an unmaintained
    /// archival art database is an expected, common outcome, not a failure.
    @Published var artworkNotFoundGame: HDLGame?
    /// Soft "installed successfully" state -- a manual fetch that just spins
    /// and vanishes with no feedback either way is a real UX gap (real
    /// installs looked identical to silent no-ops without this).
    @Published var artworkInstalledGame: HDLGame?

    @Published private(set) var isFetchingAllArtwork = false
    @Published private(set) var bulkArtworkProgressText: String = ""
    @Published var bulkArtworkSummary: String?
    private var bulkArtworkTask: Task<Void, Never>?

    private let service: HDLDumpService
    private let artworkService: GameArtworkService
    private let artworkFetcher: GameArtworkFetcher

    init(service: HDLDumpService, artworkService: GameArtworkService, artworkFetcher: GameArtworkFetcher = GameArtworkFetcher()) {
        self.service = service
        self.artworkService = artworkService
        self.artworkFetcher = artworkFetcher
    }

    var selectedGame: HDLGame? {
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

    func confirmDelete(game: HDLGame, disk: Disk) async {
        isDeleting = true
        deleteProgressText = ""
        defer { isDeleting = false }
        do {
            try await service.deleteGame(game, on: disk, onProgress: { [weak self] line in
                Task { @MainActor in
                    self?.deleteProgressText = line.trimmingCharacters(in: .whitespaces)
                }
            })
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    /// Explicit, user-triggered fetch -- covers retries and any PS2 game
    /// installed before this feature existed (install-time auto-fetch in
    /// InstallGameViewModel handles the happy path for new installs).
    func fetchArtwork(for game: HDLGame, on disk: Disk) async {
        isFetchingArtwork = true
        artworkNotFoundGame = nil
        artworkInstalledGame = nil
        defer { isFetchingArtwork = false }
        do {
            let data = try await artworkFetcher.fetchCoverArt(platform: .ps2, gameID: game.startup)
            try await artworkService.installPS2CoverArt(gameID: game.startup, imageData: data, on: disk)
            artworkInstalledGame = game
        } catch GameArtworkFetcher.FetchError.notFound {
            artworkNotFoundGame = game
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    /// Fetches artwork for every game in the library in one action -- for
    /// large libraries where clicking "Fetch Artwork" per game isn't
    /// practical. Not `async` itself (unlike the single-game fetch above) --
    /// it owns its own `Task` so `cancelBulkArtworkFetch()` has something to
    /// cancel, since this can realistically run for minutes across a big
    /// library.
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

        do {
            try await artworkService.createOPLPartitionIfNeeded(on: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
            return
        }

        let allGames = games
        var installedCount = 0
        var alreadyHadArtCount = 0
        var notFoundCount = 0
        var failedCount = 0

        for (index, game) in allGames.enumerated() {
            if Task.isCancelled { break }
            bulkArtworkProgressText = "Fetching artwork (\(index + 1) of \(allGames.count)): \(game.name)"

            // Skip games that already have art installed -- avoids redundant
            // network fetches and drive writes, especially valuable when
            // re-running this on a library that's mostly already covered.
            if (try? await artworkService.fetchInstalledPS2CoverArt(gameID: game.startup, on: disk)) != nil {
                alreadyHadArtCount += 1
                continue
            }

            do {
                let data = try await artworkFetcher.fetchCoverArt(platform: .ps2, gameID: game.startup)
                try await artworkService.installPS2CoverArt(gameID: game.startup, imageData: data, on: disk)
                installedCount += 1
            } catch GameArtworkFetcher.FetchError.notFound {
                notFoundCount += 1
            } catch {
                failedCount += 1
            }

            // Be a good citizen toward the free, unauthenticated,
            // anonymous archival art source -- don't hammer it in a tight
            // loop across a large library.
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        var summary = "Installed \(installedCount), already had art \(alreadyHadArtCount), no artwork found \(notFoundCount)"
        if failedCount > 0 {
            summary += ", \(failedCount) failed"
        }
        if Task.isCancelled {
            summary += " (cancelled)"
        }
        bulkArtworkSummary = summary
    }
}
