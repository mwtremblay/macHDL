import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddVideoSheet: View {
    @ObservedObject var viewModel: AddVideoViewModel
    @Environment(\.dismiss) private var dismiss
    let disk: Disk
    let onInstalled: () async -> Void

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Video to \(disk.displayName)")
                    .font(.title2)

                HStack {
                    Text(viewModel.sourceURL?.lastPathComponent ?? "No video selected")
                        .foregroundStyle(viewModel.sourceURL == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose Video…") { chooseFile() }
                }

                TextField("Video Name", text: $viewModel.videoName)

                Picker("Target Display", selection: $viewModel.profile) {
                    ForEach(VideoConverter.Profile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }

                // Only shown when the source actually has more than one
                // audio track -- nothing to pick between otherwise, and
                // ffmpeg's own default is fine for a single-track source.
                if viewModel.audioTracks.count > 1 {
                    Picker("Audio Track", selection: $viewModel.selectedAudioTrackIndex) {
                        ForEach(viewModel.audioTracks) { track in
                            Text(track.displayName).tag(track.streamIndex)
                        }
                    }
                }

                Text("The video is converted to a format Simple Media System (SMS) can play (MPEG-4/Xvid in an AVI container, MP3 audio) at the resolution tuned for the display you pick above. SMS's own decoder has a hard resolution ceiling, so the two widescreen options are the highest quality actually achievable -- not literal 720p/1080p pixel counts.")
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
            .frame(width: 460)
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
        // Common source video extensions -- ffmpeg's decoders are built
        // wide open, but the picker itself still needs an explicit
        // allowlist. UTType(filenameExtension:) synthesizes a dynamic type
        // for any extension without requiring prior registration, same
        // idiom AddAppSheet/AddPS1GameSheet already rely on.
        panel.allowedContentTypes = [
            "mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv", "flv",
        ].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            viewModel.sourceURL = panel.url
        }
    }
}
