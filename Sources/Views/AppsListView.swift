import SwiftUI

struct AppsListView: View {
    @ObservedObject var viewModel: AppsListViewModel
    let disk: Disk?
    var tabTitle: String = "Apps"

    var body: some View {
        Group {
            if disk == nil {
                ContentUnavailableFallback(text: "Select a drive to view its installed apps.")
            } else if viewModel.apps.isEmpty && !viewModel.isLoading {
                ContentUnavailableFallback(text: "No apps installed on this drive.")
            } else {
                Table(viewModel.apps, selection: $viewModel.selectedAppID) {
                    TableColumn("Name", value: \.displayName)
                }
            }
        }
        .navigationTitle(disk.map { "\($0.displayName) — \(tabTitle)" } ?? tabTitle)
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
