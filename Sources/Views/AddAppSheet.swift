import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddAppSheet: View {
    @ObservedObject var viewModel: AddAppViewModel
    @Environment(\.dismiss) private var dismiss
    let disk: Disk
    var sheetTitle: String = "Add App"
    var helpText: String = "FreeMcBoot/FreeHDBoot homebrew apps (e.g. wLaunchELF, Neutrino), distributed as .zip/.7z/.rar archives. The folder name above is where the app will live under APPS on the drive, regardless of the archive's own internal folder name."
    let onInstalled: () async -> Void

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(sheetTitle) to \(disk.displayName)")
                    .font(.title2)

                HStack {
                    Text(viewModel.sourceURL?.lastPathComponent ?? "No archive selected")
                        .foregroundStyle(viewModel.sourceURL == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose Archive…") { chooseFile() }
                }

                TextField("App Folder Name", text: $viewModel.appFolderName)

                Text(helpText)
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
            .disabled(viewModel.isInstalling)

            if viewModel.isInstalling {
                ProgressSheet(
                    elapsedSeconds: viewModel.elapsedSeconds,
                    progressFraction: viewModel.progressFraction,
                    progressText: viewModel.phaseText,
                    onCancel: nil
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
            Alert(title: Text("Install Failed"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        // .zip/.7z/.rar have no reliably Apple-registered UTType the way
        // .cue/.iso do -- UTType(filenameExtension:) synthesizes a dynamic
        // one for any extension without requiring prior registration, same
        // idiom AddPS1GameSheet already relies on for .cue.
        panel.allowedContentTypes = [
            UTType(filenameExtension: "zip"),
            UTType(filenameExtension: "7z"),
            UTType(filenameExtension: "rar"),
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            viewModel.sourceURL = panel.url
        }
    }
}
