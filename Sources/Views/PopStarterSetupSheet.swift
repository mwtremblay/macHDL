import SwiftUI
import AppKit

/// One-time setup sheet (separate from the per-game Add Game flow) for
/// placing PopStarter's shared PS1 emulator system files onto the drive.
///
/// POPS.ELF, IOPRP252.IMG, POPS.PAK, and POPS_IOX.PAK are Sony-copyrighted
/// PS2 system software -- this app never bundles, fetches, or embeds them.
/// The user must supply their own copies, legally extracted from their own
/// PS2 console. POPS.ELF/IOPRP252.IMG are required; POPS.PAK/POPS_IOX.PAK
/// are optional (real-hardware testing showed a game launches fine without
/// them). POPSTARTER.ELF, POPSLOADER.ELF, and PATCH_5.BIN (GPLv3, freely
/// redistributable) are bundled and installed automatically -- all three
/// are required for OPL to actually launch a game, confirmed via real
/// hardware testing.
struct PopStarterSetupSheet: View {
    @ObservedObject var viewModel: PopStarterSetupViewModel
    @Environment(\.dismiss) private var dismiss
    let disk: Disk

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Up PopStarter (PS1 Support)")
                .font(.title2)

            Text("POPS.ELF and IOPRP252.IMG are Sony's own PS2 system software and are not included with this app. You must supply your own copies, extracted from your own PS2 console. POPSTARTER.ELF, POPSLOADER.ELF, and PATCH_5.BIN (all freely redistributable) are bundled and installed automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            filePickerRow(title: "POPS.ELF", url: viewModel.popsElfURL) {
                choose(filenameExtension: "ELF") { viewModel.popsElfURL = $0 }
            }
            filePickerRow(title: "IOPRP252.IMG", url: viewModel.ioprpImageURL) {
                choose(filenameExtension: "IMG") { viewModel.ioprpImageURL = $0 }
            }

            Divider()

            Text("Optional -- also Sony's own PS2 system software, not required for a game to launch. POPS_IOX.PAK is understood to only matter for PopStarter's network modes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            filePickerRow(title: "POPS.PAK", url: viewModel.popsPakURL, isOptional: true, onClear: { viewModel.popsPakURL = nil }) {
                choose(filenameExtension: "PAK") { viewModel.popsPakURL = $0 }
            }
            filePickerRow(title: "POPS_IOX.PAK", url: viewModel.popsIoxPakURL, isOptional: true, onClear: { viewModel.popsIoxPakURL = nil }) {
                choose(filenameExtension: "PAK") { viewModel.popsIoxPakURL = $0 }
            }

            if viewModel.didSucceed {
                Text("PopStarter system files installed successfully.")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                Button("Install") {
                    Task { await viewModel.install(on: disk) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSubmit)
            }
        }
        .padding()
        .frame(width: 460)
        .disabled(viewModel.isInstalling)
        .alert(item: $viewModel.lastError) { error in
            Alert(title: Text("Setup Failed"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private func filePickerRow(
        title: String,
        url: URL?,
        isOptional: Bool = false,
        onClear: (() -> Void)? = nil,
        onChoose: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Text(url?.lastPathComponent ?? (isOptional ? "Not selected (optional)" : "Not selected"))
                .foregroundStyle(url == nil ? .secondary : .primary)
            Spacer()
            if url != nil, let onClear {
                Button("Clear", action: onClear)
            }
            Button("Choose…", action: onChoose)
        }
    }

    private func choose(filenameExtension: String, onPick: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }
}
