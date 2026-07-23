import SwiftUI

struct UserFilesView: View {
    @ObservedObject var viewModel: UserFilesViewModel
    let disk: Disk?

    var body: some View {
        Group {
            if disk == nil {
                ContentUnavailableFallback(text: "Select a drive to view its User Files.")
            } else if viewModel.entries.isEmpty && !viewModel.isLoading {
                VStack(spacing: 8) {
                    breadcrumbBar
                    ContentUnavailableFallback(text: "Nothing here yet.")
                }
            } else {
                VStack(spacing: 0) {
                    breadcrumbBar
                    Table(viewModel.entries, selection: $viewModel.selectedEntryID) {
                        TableColumn("Name") { entry in
                            HStack {
                                Image(systemName: entry.isDirectory ? "folder" : "doc")
                                    .foregroundStyle(.secondary)
                                Text(entry.name)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if entry.isDirectory {
                                    Task { await viewModel.navigate(into: entry, disk: disk) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(disk.map { "\($0.displayName) — User Files" } ?? "User Files")
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

    @ViewBuilder
    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button {
                Task { await viewModel.navigateToRoot(disk: disk) }
            } label: {
                Image(systemName: "house")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.currentPath.isEmpty)

            ForEach(Array(viewModel.breadcrumbComponents.enumerated()), id: \.offset) { index, component in
                Text("›")
                    .foregroundStyle(.secondary)
                Button(component) {
                    Task { await viewModel.navigateToBreadcrumb(index: index, disk: disk) }
                }
                .buttonStyle(.borderless)
                .disabled(index == viewModel.breadcrumbComponents.count - 1)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
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
