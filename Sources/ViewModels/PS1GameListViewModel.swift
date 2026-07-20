import Foundation

@MainActor
final class PS1GameListViewModel: ObservableObject {
    @Published private(set) var games: [PS1Game] = []
    @Published private(set) var isLoading = false
    @Published var lastError: IdentifiableError?
    @Published var selectedGameID: PS1Game.ID?

    @Published var pendingDeleteGame: PS1Game?
    @Published private(set) var isDeleting = false

    private let service: PS1GameService

    init(service: PS1GameService) {
        self.service = service
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
            try await service.deleteGame(vcdFilename: game.vcdFilename, on: disk)
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
