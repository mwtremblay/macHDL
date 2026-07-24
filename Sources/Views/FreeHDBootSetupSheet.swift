import SwiftUI

/// Sets up a brand-new/blank PS2 HDD as a bootable FreeHDBoot (FreeMcBoot)
/// drive, entirely from the Mac -- see FreeHDBootService for the full
/// setup sequence.
///
/// This is the single most destructive action in the app: unlike deleting
/// one game, it wipes the drive's *entire* partition table. It does not
/// block proceeding against a drive that already has data on it -- it
/// shows what's actually there and lets the user decide, the same pattern
/// every other destructive confirmation in this app already uses (see
/// ContentView's per-game delete alert). The boot-disk check is the one
/// thing that's never a matter of user choice, here or anywhere else in
/// this app -- see PS1GameService.guardNotBootDisk, reused by
/// FreeHDBootService via composition.
struct FreeHDBootSetupSheet: View {
    @ObservedObject var viewModel: FreeHDBootSetupViewModel
    @Environment(\.dismiss) private var dismiss
    let disk: Disk

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Up FreeHDBoot")
                .font(.title2)

            Text("Turns \(disk.displayName) (\(disk.displaySizeText)) into a bootable FreeMcBoot (FreeHDBoot) PS2 hard drive -- for a brand-new or blank drive only.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            statusSection

            // Shown before the destructive confirmation, not after --
            // creating these is now part of the same one confirmation
            // (see FreeHDBootSetupViewModel's doc comment for why an
            // earlier, separate-step version of this was a real bug).
            if !viewModel.isInstalling && !viewModel.didSucceed {
                partitionSizingSection
            }

            if viewModel.isInstalling {
                progressSection
            }

            if viewModel.didSucceed {
                Text("FreeHDBoot setup completed, including the PS1 Games/Movies/User Files partitions. Move the drive to your PS2 to confirm it boots -- this cannot be verified from the Mac.")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                Button("Set Up FreeHDBoot…") {
                    viewModel.requestWipeConfirmation()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canRequestWipe)
            }
        }
        .padding()
        .frame(width: 480)
        .disabled(viewModel.isInstalling)
        .task {
            await viewModel.checkDrive(disk)
        }
        // Same split as ContentView's gameErrorAlerts: a dedicated,
        // actionable sheet for "missing Full Disk Access" (a normal,
        // recoverable condition -- a generic alert can't offer step-by-step
        // instructions), and a plain alert for everything else. Without
        // this, an FDA failure during FreeHDBoot setup would show the same
        // generic alert as any other failure with no path to the actual fix.
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
            Alert(title: Text("FreeHDBoot Setup Failed"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
        .alert(
            "Erase \(disk.displayName)?",
            isPresented: $viewModel.pendingWipeConfirmation
        ) {
            Button("Erase and Set Up FreeHDBoot", role: .destructive) {
                Task { await viewModel.confirmAndInstall(on: disk) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelWipeConfirmation()
            }
        } message: {
            Text(wipeConfirmationMessage)
        }
    }

    // Named counts only, never the raw partition-name list: a drive with a
    // large existing game library (each game is its own PFS partition) can
    // easily have 70+ entries, and a system .alert sizes itself to fit its
    // message with no scrolling -- joining all of them in here made the
    // alert balloon to fill (and exceed) the screen, pushing its own
    // buttons out of reach. See statusSection below for the identical fix
    // to the sheet's own inline listing.
    private var wipeConfirmationMessage: String {
        var message = "This will completely erase ALL data on \(disk.displayName) (\(disk.displaySizeText)) and rebuild it from scratch as a FreeHDBoot drive, including PS1 Games/Movies/User Files partitions at the sizes shown. This cannot be undone."
        if viewModel.driveAppearsBlank == false {
            let count = viewModel.existingPartitionNames.count
            message += "\n\nThis drive is NOT blank -- it currently has \(count) existing partition\(count == 1 ? "" : "s"). All of that will be permanently destroyed."
        }
        return message
    }

    @ViewBuilder
    private var statusSection: some View {
        if viewModel.isCheckingDrive {
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking what's currently on the drive…")
                    .foregroundStyle(.secondary)
            }
        } else if let driveAppearsBlank = viewModel.driveAppearsBlank {
            if driveAppearsBlank {
                Label("This drive has no existing partition table.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This drive already has data on it.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    // Count only, not the raw partition-name list -- see
                    // wipeConfirmationMessage's doc comment for why (a large
                    // existing game library can have 70+ entries, which grew
                    // this sheet's own window absurdly tall).
                    Text("Existing partitions: \(viewModel.existingPartitionNames.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Setting up FreeHDBoot will permanently destroy everything on this drive, including the above. This feature is meant for a brand-new or blank drive -- proceed only if you're sure this is the right drive and you don't need what's currently on it.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Sizes PS1 Games/Movies/TV/User Files -- created together with the
    /// rest of FreeHDBoot setup as one action when "Set Up FreeHDBoot…" is
    /// confirmed below, not a separate step (see FreeHDBootSetupViewModel's
    /// doc comment for why that matters). If you'd rather decide later,
    /// just leave these at their suggested defaults or close this sheet
    /// without confirming -- any partition not created here still gets its
    /// own one-time sizing prompt the first time it's actually used.
    @ViewBuilder
    private var partitionSizingSection: some View {
        Divider()
        VStack(alignment: .leading, spacing: 12) {
            Text("These partitions will be created along with FreeHDBoot setup. PS2 PFS partitions can't be resized later without recreating them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sizeRow(title: "PS1 Games", sizeBytes: $viewModel.ps1GamesSizeBytes)
            sizeRow(title: "Movies/TV", sizeBytes: $viewModel.moviesSizeBytes)
            sizeRow(title: "User Files", sizeBytes: $viewModel.userFilesSizeBytes)

            if let partitionSizeWarning = viewModel.partitionSizeWarning {
                Text(partitionSizeWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sizeRow(title: String, sizeBytes: Binding<Int64>) -> some View {
        HStack {
            Text(title)
                .frame(width: 90, alignment: .leading)
            TextField(
                title,
                value: Binding(
                    get: { GigabyteConversion.gigabytes(fromBytes: sizeBytes.wrappedValue) },
                    set: { sizeBytes.wrappedValue = GigabyteConversion.bytes(fromGigabytes: $0) }
                ),
                format: .number.precision(.fractionLength(0...2))
            )
            .labelsHidden()
            .frame(width: 80)
            Text("GB")
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView()
            if let latestProgressLine = viewModel.latestProgressLine {
                Text(latestProgressLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }
}
