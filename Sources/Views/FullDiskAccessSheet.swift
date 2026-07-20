import SwiftUI
import AppKit

/// Shown when an operation fails with the specific "Operation not permitted"
/// signature that indicates the privileged helper is missing Full Disk
/// Access -- a separate macOS TCC grant from running as root, required for
/// writes to a raw disk device. Unlike the one-time SMAppService approval
/// flow, there's no programmatic way to detect this ahead of time or poll
/// for it, so this is a reactive recovery sheet shown after a failure,
/// rather than a proactive launch-time check.
struct FullDiskAccessSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Full Disk Access Required")
                .font(.title2)

            Text("Writing to the PS2 hard drive needs Full Disk Access for macHDL's privileged helper -- this is a separate permission from the one you already approved, required by macOS to protect against raw-disk wipers.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Click \"Open System Settings\" below.")
                Text("2. Click the + button.")
                Text("3. Click \"Reveal Helper in Finder\" below, then drag it into the list (or press Cmd+Shift+G and paste its path).")
                Text("4. Make sure the toggle is on, then try the action again.")
            }
            .font(.callout)
            .frame(maxWidth: 400, alignment: .leading)

            HStack {
                Button("Reveal Helper in Finder", action: revealHelperInFinder)
                Button("Open System Settings", action: openSystemSettings)
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 460)
    }

    private var helperBinaryURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HelperTools", isDirectory: true)
            .appendingPathComponent(HDLDumpHelperConstants.machServiceName)
    }

    private func revealHelperInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([helperBinaryURL])
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
