import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The Core Apps tab's second section: the fixed `__common/POPS/` system
/// files, each with its own "Replace…" (and, for the two optional files,
/// "Remove") action -- never a generic "type a name" install, since these
/// are a closed set of exact slots (see PopStarterSystemFile's doc comment).
struct PopStarterSystemFilesSection: View {
    @ObservedObject var viewModel: PopStarterSystemFilesViewModel
    let disk: Disk?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PopStarter System Files")
                .font(.headline)
            Text("Shared files PopStarter/OPL need to launch PS1 games, stored at __common/POPS/. POPSTARTER.ELF, POPSLOADER.ELF, and PATCH_5.BIN are bundled with this app; the rest are Sony's own PS2 system software you must supply yourself.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(PopStarterSystemFile.all) { file in
                row(for: file)
                Divider()
            }
        }
        .padding()
        .disabled(disk == nil)
    }

    @ViewBuilder
    private func row(for file: PopStarterSystemFile) -> some View {
        let isInstalled = viewModel.installedFilenames.contains(file.id)
        let isBusy = viewModel.busyFilename == file.id

        HStack {
            Text(file.displayName)
                .frame(width: 140, alignment: .leading)
            Text(isInstalled ? "Installed" : (file.isOptional ? "Not installed (optional)" : "Not installed"))
                .foregroundStyle(isInstalled ? .primary : .secondary)
            Spacer()
            if isBusy {
                ProgressView().controlSize(.small)
            }
            if file.isOptional && isInstalled {
                Button("Remove") {
                    guard let disk else { return }
                    Task { await viewModel.remove(file, disk: disk) }
                }
                .disabled(isBusy)
            }
            Button("Replace…") {
                guard let disk else { return }
                chooseFile(for: file) { url in
                    Task { await viewModel.replace(file, localURL: url, disk: disk) }
                }
            }
            .disabled(isBusy)
        }
    }

    private func chooseFile(for file: PopStarterSystemFile, onPick: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: file.expectedFilenameExtension)].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }
}
