import Foundation

/// Drives FreeHDBootSetupSheet. This does NOT block the user from wiping a
/// drive that already has data on it -- it's their drive and their call.
/// What it does do: always shows what's actually on the drive first (the
/// same information `diskutil list` would give), and makes the destructive
/// confirmation impossible to misread. Informed consent, not a gate --
/// matching the boot-disk check (still an unconditional refusal, never a
/// matter of user choice) as the one thing this flow won't let through
/// regardless of what the user confirms.
@MainActor
final class FreeHDBootSetupViewModel: ObservableObject {
    @Published private(set) var isCheckingDrive = false
    /// nil until `checkDrive` completes at least once.
    @Published private(set) var driveAppearsBlank: Bool?
    @Published private(set) var existingPartitionNames: [String] = []
    @Published var pendingWipeConfirmation = false
    @Published private(set) var isInstalling = false
    /// Only the most recent progress line -- the UI (FreeHDBootSetupSheet)
    /// only ever shows a single status line, and this operation can emit a
    /// large number of lines (every `\r`-delimited progress-bar redraw from
    /// `hdl_dump inject_mbr`, plus one per payload file), so keeping the
    /// full history in an ever-growing @Published array would mean a lot of
    /// wasted SwiftUI diffing for state nothing reads beyond the latest
    /// value.
    @Published private(set) var latestProgressLine: String?
    @Published var lastError: IdentifiableError?
    @Published private(set) var didSucceed = false

    private let service: FreeHDBootService

    init(service: FreeHDBootService) {
        self.service = service
    }

    var canRequestWipe: Bool {
        !isInstalling && !isCheckingDrive
    }

    /// Reads what's actually on the drive right now -- shown in the sheet
    /// before any destructive action, purely to inform the decision (see
    /// this type's doc comment -- it no longer gates anything).
    func checkDrive(_ disk: Disk) async {
        isCheckingDrive = true
        didSucceed = false
        defer { isCheckingDrive = false }
        do {
            existingPartitionNames = try await service.existingPartitionNames(on: disk)
            driveAppearsBlank = existingPartitionNames.isEmpty
        } catch {
            driveAppearsBlank = nil
            lastError = IdentifiableError(underlying: error)
        }
    }

    func requestWipeConfirmation() {
        pendingWipeConfirmation = true
    }

    func cancelWipeConfirmation() {
        pendingWipeConfirmation = false
    }

    func confirmAndInstall(on disk: Disk) async {
        pendingWipeConfirmation = false
        isInstalling = true
        didSucceed = false
        latestProgressLine = nil
        defer { isInstalling = false }
        do {
            try await service.setUpFreeHDBoot(on: disk) { [weak self] line in
                self?.latestProgressLine = line
            }
            didSucceed = true
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
