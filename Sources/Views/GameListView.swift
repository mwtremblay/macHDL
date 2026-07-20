import SwiftUI

struct GameListView: View {
    @ObservedObject var viewModel: GameListViewModel
    let disk: Disk?

    var body: some View {
        Group {
            if disk == nil {
                ContentUnavailableFallback(text: "Select a drive to view its games.")
            } else if viewModel.games.isEmpty && !viewModel.isLoading {
                ContentUnavailableFallback(text: "No HDL games installed on this drive.")
            } else {
                Table(viewModel.games, selection: $viewModel.selectedGameID) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Type") { game in
                        Text(game.mediaTypeLabel)
                    }
                    .width(50)
                    TableColumn("Size") { game in
                        Text(game.displaySizeText)
                    }
                    .width(90)
                    TableColumn("Flags", value: \.compatFlags)
                        .width(70)
                    TableColumn("DMA", value: \.dma)
                        .width(60)
                }
            }
        }
        .navigationTitle(disk?.displayName ?? "Games")
        .overlay {
            if viewModel.isDeleting {
                VStack(spacing: 6) {
                    ProgressView("Deleting…")
                    if !viewModel.deleteProgressText.isEmpty {
                        Text(viewModel.deleteProgressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if viewModel.isLoading {
                ProgressView()
            }
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
