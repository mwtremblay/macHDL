import SwiftUI

/// Shows real incremental progress (percentage + detail text) when available,
/// falling back to an indeterminate spinner before the first progress line
/// arrives or if a line doesn't parse cleanly. Now possible because the
/// privileged helper daemon runs hdl_dump as its own child process and can
/// stream progress back over XPC -- unlike the old AppleScript elevation
/// mechanism, which buffered all output until the subprocess exited.
struct ProgressSheet: View {
    let elapsedSeconds: Int
    let progressFraction: Double?
    let progressText: String
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            if let progressFraction {
                ProgressView(value: progressFraction)
                    .frame(maxWidth: 260)
            } else {
                ProgressView()
                    .controlSize(.large)
            }

            Text("Working… \(elapsedTimeText)")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !progressText.isEmpty {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if let onCancel {
                Button("Cancel", action: onCancel)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var elapsedTimeText: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
