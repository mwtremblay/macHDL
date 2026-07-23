import SwiftUI
import AppKit

/// Simpler than every other Add sheet in this app -- User Files takes any
/// file(s) as-is, no conversion, no destination-name field (each source
/// file's own name is used directly). Installs into `viewModel.currentPath`.
/// Supports adding multiple files at once (a single file is just a
/// 1-element batch) -- see UserFilesViewModel.addFiles' doc comment for the
/// batch progress/cancel/summary shape, matching BatchAddPS1GameSheet's
/// established convention.
struct AddUserFileSheet: View {
    @ObservedObject var viewModel: UserFilesViewModel
    @Environment(\.dismiss) private var dismiss
    let disk: Disk
    let onInstalled: () async -> Void

    @State private var sourceURLs: [URL] = []

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Files to \(disk.displayName)")
                    .font(.title2)

                HStack {
                    Text(sourceURLsSummaryText)
                        .foregroundStyle(sourceURLs.isEmpty ? .secondary : .primary)
                    Spacer()
                    Button("Choose Files…") { chooseFiles() }
                }

                if sourceURLs.count > 1 {
                    List(sourceURLs, id: \.self) { url in
                        Text(url.lastPathComponent)
                    }
                    .frame(height: 120)
                }

                Text("Any file type is supported. Files are copied to the drive as-is, using their own names -- no conversion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let summary = viewModel.addFilesSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button(viewModel.addFilesSummary == nil ? "Cancel" : "Close") { dismiss() }
                    Button("Add") {
                        guard !sourceURLs.isEmpty else { return }
                        Task {
                            await viewModel.addFiles(urls: sourceURLs, on: disk)
                            await onInstalled()
                            if viewModel.lastError == nil && viewModel.pendingPartitionSizePrompt == nil && viewModel.addFilesSummary == nil {
                                dismiss()
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sourceURLs.isEmpty || viewModel.isAddingFiles)
                }
            }
            .padding()
            .frame(width: 420)
            .disabled(viewModel.isAddingFiles)

            if viewModel.isAddingFiles {
                ProgressSheet(
                    elapsedSeconds: 0,
                    progressFraction: viewModel.addFilesTotalCount > 0 ? Double(viewModel.addFilesCurrentIndex) / Double(viewModel.addFilesTotalCount) : nil,
                    progressText: "Adding \(viewModel.addFilesCurrentIndex) of \(viewModel.addFilesTotalCount): \(viewModel.addFilesCurrentName)",
                    onCancel: { viewModel.cancelAddFiles() }
                )
            }
        }
        // Presented from here, not from ContentView, because this sheet
        // deliberately stays open across its async addFiles call (to keep
        // showing batch progress/summary) -- if pendingPartitionSizePrompt
        // were instead presented as a sibling .sheet on ContentView (like
        // NewFolderSheet's trigger is), it would try to appear while this
        // sheet is still active, which SwiftUI does not support. Nesting it
        // here means it presents on top of this sheet instead, which is
        // fine. See ContentView.installSheets' comment for the other half
        // of this split.
        .sheet(item: Binding(
            get: { viewModel.pendingPartitionSizePrompt },
            set: { viewModel.pendingPartitionSizePrompt = $0 }
        )) { request in
            PartitionSizePromptSheet(request: request) { sizeBytes in
                Task { await viewModel.confirmPartitionSize(sizeBytes, on: disk) }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.lastError?.isLikelyMissingFullDiskAccess ?? false },
            set: { isPresented in
                if !isPresented { viewModel.lastError = nil }
            }
        )) {
            FullDiskAccessSheet(onDismiss: { viewModel.lastError = nil })
        }
        .alert(item: Binding(
            get: { viewModel.lastError?.isLikelyMissingFullDiskAccess == true ? nil : viewModel.lastError },
            set: { viewModel.lastError = $0 }
        )) { error in
            Alert(title: Text("Add Failed"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }

    private var sourceURLsSummaryText: String {
        switch sourceURLs.count {
        case 0: return "No files selected"
        case 1: return sourceURLs[0].lastPathComponent
        default: return "\(sourceURLs.count) files selected"
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            sourceURLs = panel.urls
        }
    }
}
