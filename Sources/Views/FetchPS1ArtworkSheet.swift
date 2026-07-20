import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Manual/retroactive PS1 artwork fetch. If a Game ID was already detected
/// and stored for this game before (see FetchPS1ArtworkViewModel), skips the
/// file picker entirely -- re-selecting the source disc image every single
/// time was real, reported friction. Only shows the picker when no stored
/// ID exists yet, or if the user explicitly wants to use a different disc
/// image.
struct FetchPS1ArtworkSheet: View {
    @ObservedObject var viewModel: FetchPS1ArtworkViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingFilePicker = false
    let game: PS1Game
    let disk: Disk

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Fetch Artwork for \(game.displayName)")
                    .font(.title2)

                if let storedGameID = viewModel.storedGameID, !showingFilePicker {
                    Text("Using previously detected Game ID: \(storedGameID)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Use a Different Disc Image…") { showingFilePicker = true }
                } else {
                    Text("Select the original disc image (.cue) for this game so its Game ID can be detected and used to look up cover art.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text(viewModel.sourceURL?.lastPathComponent ?? "No file selected")
                            .foregroundStyle(viewModel.sourceURL == nil ? .secondary : .primary)
                        Spacer()
                        Button("Choose Disc Image…") { chooseFile() }
                    }
                }

                if viewModel.didSucceed {
                    Text("Artwork installed successfully.")
                        .font(.callout)
                        .foregroundStyle(.green)
                }

                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                    Button("Fetch") {
                        Task { await viewModel.fetch(game: game, on: disk) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canSubmit)
                }
            }
            .padding()
            .frame(width: 420)
            .disabled(viewModel.isFetching)

            if viewModel.isFetching {
                ProgressSheet(
                    elapsedSeconds: viewModel.elapsedSeconds,
                    progressFraction: nil,
                    progressText: viewModel.phaseText,
                    onCancel: nil
                )
            }
        }
        .task {
            await viewModel.checkForStoredGameID(game: game, on: disk)
        }
        .alert(item: Binding(
            get: { viewModel.lastError },
            set: { viewModel.lastError = $0 }
        )) { error in
            Alert(title: Text("Fetch Artwork Failed"), message: Text(error.message), dismissButton: .default(Text("OK")))
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
