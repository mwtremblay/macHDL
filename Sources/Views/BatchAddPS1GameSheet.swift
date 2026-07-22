import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// PS1 sibling of BatchAddGameSheet -- see BatchInstallPS1GameViewModel's
/// doc comment for the scope/tradeoffs versus the single-game
/// AddPS1GameSheet.
struct BatchAddPS1GameSheet: View {
    @ObservedObject var viewModel: BatchInstallPS1GameViewModel
    @Environment(\.dismiss) private var dismiss
    let disk: Disk
    let existingGameNames: Set<String>
    let onInstalled: () async -> Void

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Batch Add PS1 Games to \(disk.displayName)")
                    .font(.title2)

                Text("Games already installed on this drive are skipped automatically. Each file's name is detected automatically -- use Add PS1 Game individually if you need to adjust it. Split dumps (multiple .bin files per .cue) are supported, same as the single-game flow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.pendingSourceURLs.isEmpty {
                    Button("Choose Disc Images…") { chooseFiles() }
                } else {
                    List {
                        ForEach(viewModel.pendingSourceURLs, id: \.self) { url in
                            HStack {
                                Text(url.lastPathComponent)
                                if existingGameNames.contains(BatchInstallPS1GameViewModel.effectiveDisplayName(forSourceURL: url)) {
                                    Spacer()
                                    Text("already installed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 220)

                    HStack {
                        Button("Choose Disc Images…") { chooseFiles() }
                        Spacer()
                        Text("\(viewModel.pendingSourceURLs.count) file(s) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let summary = viewModel.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.green)
                }

                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                    Button("Install All") {
                        Task {
                            await viewModel.installAll(existingGameNames: existingGameNames, on: disk) {
                                await onInstalled()
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canSubmit)
                }
            }
            .padding()
            .frame(width: 480)
            .disabled(viewModel.isInstalling)

            if viewModel.isInstalling {
                ProgressSheet(
                    elapsedSeconds: viewModel.elapsedSeconds,
                    progressFraction: nil,
                    progressText: [viewModel.progressSummaryText, viewModel.currentItemPhase.text]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n"),
                    onCancel: { viewModel.cancel() }
                )
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
            Alert(title: Text("Batch Install Failed"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cue")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            viewModel.pendingSourceURLs = panel.urls
        }
    }
}
