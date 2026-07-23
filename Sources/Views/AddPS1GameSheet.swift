import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddPS1GameSheet: View {
    @ObservedObject var viewModel: InstallPS1GameViewModel
    @Environment(\.dismiss) private var dismiss
    let disk: Disk
    let onInstalled: () async -> Void

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add PS1 Game to \(disk.displayName)")
                    .font(.title2)

                HStack {
                    Text(viewModel.sourceURL?.lastPathComponent ?? "No file selected")
                        .foregroundStyle(viewModel.sourceURL == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose Disc Image…") { chooseFile() }
                }

                TextField("Game Name", text: $viewModel.name)

                if viewModel.willTruncateFilename {
                    Text("Name is too long for POPStarter's 73-character limit and will be truncated on the drive.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("PS1 games are always CD-based -- multi-track cue sheets (with CD-DA audio tracks) are supported, including \"split\" dumps with a separate .bin file per track.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Install") {
                        Task {
                            await viewModel.install(on: disk) {
                                await onInstalled()
                            }
                            // Don't dismiss if install() returned early to
                            // show PartitionSizePromptSheet -- see
                            // AddVideoSheet's identical reasoning.
                            if viewModel.lastError == nil && viewModel.pendingPartitionSizePrompt == nil {
                                dismiss()
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canSubmit)
                }
            }
            .padding()
            .frame(width: 420)
            .disabled(viewModel.isInstalling)

            if viewModel.isInstalling {
                ProgressSheet(
                    elapsedSeconds: viewModel.elapsedSeconds,
                    progressFraction: nil,
                    progressText: viewModel.phaseText,
                    onCancel: nil
                )
            }
        }
        .sheet(item: Binding(
            get: { viewModel.pendingPartitionSizePrompt },
            set: { viewModel.pendingPartitionSizePrompt = $0 }
        )) { request in
            PartitionSizePromptSheet(request: request) { sizeBytes in
                Task {
                    await viewModel.confirmPartitionSize(sizeBytes, on: disk) {
                        await onInstalled()
                    }
                    if viewModel.lastError == nil {
                        dismiss()
                    }
                }
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
            Alert(title: Text("Install Failed"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cue")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            viewModel.sourceURL = panel.url
        }
    }
}
