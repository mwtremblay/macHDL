import SwiftUI

/// Shown when SMAppService.Status == .requiresApproval. Polling via the
/// "Check Again" button is the baseline (and only) mechanism for v1 --
/// SMAppService notification-based auto-detection isn't a stable enough
/// public API surface to design around.
struct HelperApprovalSheet: View {
    let onOpenSettings: () -> Void
    let onCheckAgain: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("One-Time Setup Required")
                .font(.title2)

            Text("macHDL needs your approval to install its privileged helper, which performs disk operations on your PS2 hard drive. Click below to open System Settings, enable macHDL under Login Items & Extensions, then come back and click Check Again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            HStack {
                Button("Open System Settings", action: onOpenSettings)
                Button("Check Again", action: onCheckAgain)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 440)
    }
}
