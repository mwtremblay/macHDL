import SwiftUI

struct GameListView: View {
    @ObservedObject var viewModel: GameListViewModel
    let disk: Disk?
    @State private var sortOrder = [KeyPathComparator(\HDLGame.name)]

    var body: some View {
        Group {
            if disk == nil {
                ContentUnavailableFallback(text: "Select a drive to view its games.")
            } else if viewModel.games.isEmpty && !viewModel.isLoading {
                ContentUnavailableFallback(text: "No HDL games installed on this drive.")
            } else {
                Table(viewModel.games.sorted(using: sortOrder), selection: $viewModel.selectedGameID, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name)
                    // Sorts by the raw isDVD-derived label text ("CD"/"DVD"),
                    // matching what's displayed -- fine since there are only
                    // two possible values.
                    TableColumn("Type", value: \.mediaTypeLabel) { game in
                        Text(game.mediaTypeLabel)
                    }
                    .width(50)
                    // Sorts by the raw sizeKB Int, not the formatted
                    // displaySizeText string -- sorting the formatted text
                    // would put "1.2 GB" before "900 MB" lexicographically.
                    TableColumn("Size", value: \.sizeKB) { game in
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
            } else if viewModel.isFetchingAllArtwork {
                VStack(spacing: 6) {
                    ProgressView(viewModel.bulkArtworkProgressText.isEmpty ? "Fetching Artwork…" : viewModel.bulkArtworkProgressText)
                    Button("Cancel") { viewModel.cancelBulkArtworkFetch() }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if viewModel.isFetchingArtwork {
                ProgressView("Fetching Artwork…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if viewModel.isLoading {
                ProgressView()
            }
        }
        // Soft, non-modal, dismissible -- a missing entry in an unmaintained
        // archival art database is an expected, common outcome, not an
        // error, so this deliberately isn't an .alert(). Success also gets a
        // banner here (not just silence-on-success) -- a fetch that spins
        // and vanishes looked identical to a silent no-op without this.
        .overlay(alignment: .bottom) {
            if let notFoundGame = viewModel.artworkNotFoundGame {
                Text("No cover art found for \"\(notFoundGame.name)\".")
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
                    .onTapGesture { viewModel.artworkNotFoundGame = nil }
            } else if let installedGame = viewModel.artworkInstalledGame {
                Text("Cover art installed for \"\(installedGame.name)\".")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
                    .onTapGesture { viewModel.artworkInstalledGame = nil }
            } else if let summary = viewModel.bulkArtworkSummary {
                Text(summary)
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
                    .onTapGesture { viewModel.bulkArtworkSummary = nil }
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
