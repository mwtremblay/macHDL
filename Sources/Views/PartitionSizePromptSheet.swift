import SwiftUI

/// One-time sizing prompt shown the first time a scaling partition
/// (`__.POPS`, `SMS_Media`, `USERFILES`) is about to be created outside the
/// setup wizard -- e.g. adding a movie on a drive that was set up before
/// this feature existed, or a content type used for the first time weeks
/// after initial setup. See `PartitionSizePromptRequest`'s doc comment.
struct PartitionSizePromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: PartitionSizePromptRequest
    let onConfirm: (Int64) -> Void

    @State private var sizeGB: Double

    init(request: PartitionSizePromptRequest, onConfirm: @escaping (Int64) -> Void) {
        self.request = request
        self.onConfirm = onConfirm
        _sizeGB = State(initialValue: GigabyteConversion.gigabytes(fromBytes: request.suggestedSizeBytes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Size the \(request.partitionDisplayName) partition")
                .font(.title2)

            Text("This is a one-time choice -- PS2 PFS partitions can't be resized later without recreating them (losing their contents). Pick generously if you're not sure.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Size (GB)", value: $sizeGB, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 100)
                Stepper("", value: $sizeGB, in: 0.13...2000, step: 1)
                    .labelsHidden()
                Text("GB")
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Partition") {
                    onConfirm(GigabyteConversion.bytes(fromGigabytes: sizeGB))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sizeGB <= 0)
            }
        }
        .padding()
        .frame(width: 420)
    }
}
