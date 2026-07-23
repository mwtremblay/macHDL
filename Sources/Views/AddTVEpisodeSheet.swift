import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddTVEpisodeSheet: View {
    @ObservedObject var viewModel: AddTVEpisodeViewModel
    @Environment(\.dismiss) private var dismiss
    let disk: Disk
    let onInstalled: () async -> Void

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add TV Episode to \(disk.displayName)")
                    .font(.title2)

                HStack {
                    Text(viewModel.sourceURL?.lastPathComponent ?? "No video selected")
                        .foregroundStyle(viewModel.sourceURL == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose Video…") { chooseFile() }
                }

                TextField("Show Name", text: $viewModel.showName)

                HStack {
                    Stepper(value: $viewModel.seasonNumber, in: 1...999) {
                        HStack {
                            Text("Season Number")
                            Spacer()
                            Text("\(viewModel.seasonNumber)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $viewModel.episodeNumber, in: 1...999) {
                        HStack {
                            Text("Episode Number")
                            Spacer()
                            Text("\(viewModel.episodeNumber)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                TextField("Episode Name", text: $viewModel.episodeName)

                HStack {
                    Button("Look Up Online") {
                        Task { await viewModel.lookUpEpisodeMetadata() }
                    }
                    .disabled(viewModel.showName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLookingUpMetadata)
                    if viewModel.isLookingUpMetadata {
                        ProgressView().controlSize(.small)
                    }
                    if let metadataLookupHint = viewModel.metadataLookupHint {
                        Text(metadataLookupHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

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

                Text("The episode is installed to \"Shows/\(viewModel.showName.isEmpty ? "Show Name" : viewModel.showName)/Season \(viewModel.seasonNumber)/\" and converted to a format Simple Media System (SMS) can play (MPEG-4/Xvid in an AVI container, MP3 audio) at the resolution tuned for the display you pick above. SMS's own decoder has a hard resolution ceiling, so the two widescreen options are the highest quality actually achievable -- not literal 720p/1080p pixel counts.")
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
            get: { !viewModel.showCandidates.isEmpty },
            set: { isPresented in
                if !isPresented { viewModel.showCandidates = [] }
            }
        )) {
            TMDBDisambiguationSheet(
                title: "Which show did you mean?",
                candidates: viewModel.showCandidates,
                onSelect: { candidate in
                    Task { await viewModel.selectShow(candidate) }
                }
            )
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
        // Common source video extensions -- ffmpeg's decoders are built
        // wide open, but the picker itself still needs an explicit
        // allowlist. UTType(filenameExtension:) synthesizes a dynamic type
        // for any extension without requiring prior registration, same
        // idiom AddVideoSheet/AddAppSheet/AddPS1GameSheet already rely on.
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
