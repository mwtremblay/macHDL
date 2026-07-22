import SwiftUI

struct VideoListView: View {
    @ObservedObject var viewModel: VideoListViewModel
    let disk: Disk?

    var body: some View {
        Group {
            if disk == nil {
                ContentUnavailableFallback(text: "Select a drive to view its installed videos.")
            } else if viewModel.videos.isEmpty && !viewModel.isLoading {
                ContentUnavailableFallback(text: "No videos installed on this drive.")
            } else {
                Table(viewModel.videos, selection: $viewModel.selectedVideoID) {
                    TableColumn("Name", value: \.displayName)
                }
            }
        }
        .navigationTitle(disk.map { "\($0.displayName) — Videos" } ?? "Videos")
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
