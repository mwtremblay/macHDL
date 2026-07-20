import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddGameSheet: View {
    @ObservedObject var viewModel: InstallGameViewModel
    @Environment(\.dismiss) private var dismiss
    let disk: Disk
    let onInstalled: () async -> Void

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Game to \(disk.displayName)")
                    .font(.title2)

                HStack {
                    Text(viewModel.sourceURL?.lastPathComponent ?? "No file selected")
                        .foregroundStyle(viewModel.sourceURL == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose Disc Image…") { chooseFile() }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Game Name", text: $viewModel.name)
                    if !viewModel.name.isEmpty && !viewModel.isNameValid {
                        Text("Name must be 1–\(HDLGame.maxNameLength) characters.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Picker("Media Type", selection: $viewModel.isDVD) {
                    Text("DVD").tag(true)
                    Text("CD").tag(false)
                }
                .pickerStyle(.segmented)

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Install") {
                        Task {
                            await viewModel.install(on: disk) {
                                await onInstalled()
                            }
                            if viewModel.lastError == nil {
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
            // Only the form controls are disabled during an install -- the
            // ProgressSheet overlay below is a ZStack sibling, not a
            // descendant, so its Cancel button stays interactive.
            .disabled(viewModel.isInstalling)

            if viewModel.isInstalling {
                ProgressSheet(
                    elapsedSeconds: viewModel.elapsedSeconds,
                    progressFraction: viewModel.progressFraction,
                    progressText: viewModel.progressText,
                    onCancel: { Task { await viewModel.cancel() } }
                )
            }
        }
        // Same split as ContentView's delete-error handling: a dedicated
        // actionable sheet for the "missing Full Disk Access" signature,
        // a plain alert for everything else.
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
        // .cue is picked (not .bin directly) -- hdl_dump resolves the
        // referenced .bin file itself from the cue's FILE line, including a
        // fallback that joins the cue's own directory with the bin's
        // basename (verified in Vendor/hdl-dump/common.c's lookup_file).
        panel.allowedContentTypes = [
            UTType(filenameExtension: "iso"),
            UTType(filenameExtension: "cue"),
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            viewModel.sourceURL = panel.url
        }
    }
}
