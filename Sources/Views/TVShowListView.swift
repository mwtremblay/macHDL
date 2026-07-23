import SwiftUI

/// A single row in the Show > Season > Episode tree rendered by this view's
/// hierarchical Table. `id` matches `TVEpisode.id` exactly for leaf (episode)
/// rows, so selecting a leaf row and reading `TVShowListViewModel.
/// selectedEpisode` just works with no separate node-kind bookkeping;
/// show/season group rows use their own shorter id shapes ("ShowName",
/// "ShowName/N"), which by construction can never collide with any 3-segment
/// episode id.
private struct TVLibraryNode: Identifiable, Hashable {
    let id: String
    let name: String
    var children: [TVLibraryNode]?
}

struct TVShowListView: View {
    @ObservedObject var viewModel: TVShowListViewModel
    let disk: Disk?
    @State private var sortOrder = [KeyPathComparator(\TVLibraryNode.name)]
    /// Built by `rebuildLibraryTree`, not a computed property -- grouping
    /// and sorting the full episode list is real work (two
    /// Dictionary(grouping:) passes plus per-level sorts) that only needs to
    /// happen when `viewModel.episodes` or `sortOrder` actually change, not
    /// on every SwiftUI body evaluation (e.g. selection changes, the
    /// isDeleting/isLoading overlay toggling).
    @State private var libraryTree: [TVLibraryNode] = []

    var body: some View {
        Group {
            if disk == nil {
                ContentUnavailableFallback(text: "Select a drive to view its installed TV shows.")
            } else if viewModel.episodes.isEmpty && !viewModel.isLoading {
                ContentUnavailableFallback(text: "No TV shows installed on this drive.")
            } else {
                Table(libraryTree, children: \.children, selection: $viewModel.selectedEpisodeID, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name)
                }
            }
        }
        .navigationTitle(disk.map { "\($0.displayName) — TV Shows" } ?? "TV Shows")
        .overlay {
            if viewModel.isDeleting {
                ProgressView("Deleting…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if viewModel.isLoading {
                ProgressView()
            }
        }
        .task { rebuildLibraryTree() }
        .onChange(of: viewModel.episodes) { rebuildLibraryTree() }
        .onChange(of: sortOrder) { rebuildLibraryTree() }
    }

    private func rebuildLibraryTree() {
        libraryTree = Self.buildLibraryTree(episodes: viewModel.episodes, sortOrder: sortOrder)
    }

    /// Groups the flat `[TVEpisode]` array into a Show > Season > Episode
    /// tree -- the model itself stays thin (see TVEpisode's doc comment),
    /// this view is the one place that needs the hierarchy. Sorted by show,
    /// then season, then episode filename, all in the same direction taken
    /// from the "Name" column's sortOrder -- clicking the header still just
    /// reverses sibling order at each level, it doesn't flatten the
    /// hierarchy (episodes stay grouped under their season/show either way).
    private static func buildLibraryTree(episodes: [TVEpisode], sortOrder: [KeyPathComparator<TVLibraryNode>]) -> [TVLibraryNode] {
        let ascending = sortOrder.first?.order == .forward
        let byShow = Dictionary(grouping: episodes, by: \.showName)
        let showNames = ascending ? byShow.keys.sorted() : byShow.keys.sorted(by: >)
        return showNames.map { showName in
            let showEpisodes = byShow[showName] ?? []
            let bySeason = Dictionary(grouping: showEpisodes, by: \.seasonNumber)
            let seasonNumbers = ascending ? bySeason.keys.sorted() : bySeason.keys.sorted(by: >)
            let seasonNodes = seasonNumbers.map { seasonNumber -> TVLibraryNode in
                let episodeNodes = (bySeason[seasonNumber] ?? [])
                    .sorted { ascending ? $0.filename < $1.filename : $0.filename > $1.filename }
                    .map { TVLibraryNode(id: $0.id, name: $0.displayName, children: nil) }
                return TVLibraryNode(
                    id: "\(showName)/\(seasonNumber)",
                    name: "Season \(seasonNumber)",
                    children: episodeNodes
                )
            }
            return TVLibraryNode(id: showName, name: showName, children: seasonNodes)
        }
    }
}

private struct ContentUnavailableFallback: View {
    let text: String

    var body: some View {
        VStack {
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
