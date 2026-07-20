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

    private let service: HDLDumpService

    init(service: HDLDumpService) {
        self.service = service
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
}
