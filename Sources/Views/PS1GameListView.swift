import SwiftUI

struct PS1GameListView: View {
    @ObservedObject var viewModel: PS1GameListViewModel
    let disk: Disk?
    @State private var sortOrder = [KeyPathComparator(\PS1Game.displayName)]

    var body: some View {
        Group {
            if disk == nil {
                ContentUnavailableFallback(text: "Select a drive to view its PS1 games.")
            } else if viewModel.games.isEmpty && !viewModel.isLoading {
                ContentUnavailableFallback(text: "No PS1 games installed on this drive.")
            } else {
                Table(viewModel.games.sorted(using: sortOrder), selection: $viewModel.selectedGameID, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.displayName)
                }
            }
        }
        .navigationTitle(disk.map { "\($0.displayName) — PS1 Games" } ?? "PS1 Games")
        .overlay {
            if viewModel.isDeleting {
                ProgressView("Deleting…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if viewModel.isFetchingAllArtwork {
                VStack(spacing: 6) {
                    ProgressView(viewModel.bulkArtworkProgressText.isEmpty ? "Fetching Artwork…" : viewModel.bulkArtworkProgressText)
                    Button("Cancel") { viewModel.cancelBulkArtworkFetch() }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if viewModel.isLoading {
                ProgressView()
            }
        }
        .overlay(alignment: .bottom) {
            if let summary = viewModel.bulkArtworkSummary {
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
