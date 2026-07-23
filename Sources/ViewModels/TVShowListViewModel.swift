import Foundation

/// Modeled directly on VideoListViewModel, trimmed to this feature's scope --
/// no artwork/bulk-fetch logic, since TV episodes don't have cover art (out
/// of scope per requirements, same as movies).
@MainActor
final class TVShowListViewModel: ObservableObject {
    @Published private(set) var episodes: [TVEpisode] = []
    @Published private(set) var isLoading = false
    @Published var lastError: IdentifiableError?
    @Published var selectedEpisodeID: TVEpisode.ID?

    @Published var pendingDeleteEpisode: TVEpisode?
    @Published private(set) var isDeleting = false

    private let service: TVShowService

    init(service: TVShowService) {
        self.service = service
    }

    /// nil both when nothing is selected and when the current selection is a
    /// Show/Season group node rather than a leaf episode -- TVShowListView's
    /// tree uses the same `TVEpisode.id` shape only for actual episode rows,
    /// so a group-node ID never matches any entry here. That's what keeps
    /// the toolbar's Delete button disabled for group-node selections without
    /// TVShowListView needing to distinguish node kinds itself.
    var selectedEpisode: TVEpisode? {
        episodes.first { $0.id == selectedEpisodeID }
    }

    func refresh(disk: Disk?) async {
        guard let disk else {
            episodes = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            episodes = try await service.listEpisodes(on: disk)
            if let selectedEpisodeID, !episodes.contains(where: { $0.id == selectedEpisodeID }) {
                self.selectedEpisodeID = nil
            }
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    func confirmDelete(episode: TVEpisode, disk: Disk) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteEpisode(showName: episode.showName, seasonNumber: episode.seasonNumber, filename: episode.filename, on: disk)
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
