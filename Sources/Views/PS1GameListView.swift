import SwiftUI

struct PS1GameListView: View {
    @ObservedObject var viewModel: PS1GameListViewModel
    let disk: Disk?

    var body: some View {
        Group {
            if disk == nil {
                ContentUnavailableFallback(text: "Select a drive to view its PS1 games.")
            } else if viewModel.games.isEmpty && !viewModel.isLoading {
                ContentUnavailableFallback(text: "No PS1 games installed on this drive.")
            } else {
                Table(viewModel.games, selection: $viewModel.selectedGameID) {
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
