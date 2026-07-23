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

    /// Suggested sizes for the three partitions whose usefulness genuinely
    /// scales with drive capacity (PS1 games, Movies/TV, User Files) --
    /// prefilled from PartitionSizeSuggestions as soon as `checkDrive` knows
    /// the drive's capacity (no need to wait for the wipe to succeed first,
    /// since these only depend on disk.sizeBytes), freely editable by the
    /// user before confirming. `+OPL`/`PP.FHDB.APPS`/`__common` never scale
    /// (see PartitionSizeSuggestions' doc comment), so they're not part of
    /// this step -- `PP.FHDB.APPS` is already created unconditionally as
    /// part of setUpFreeHDBoot itself, and `+OPL` is created lazily/silently
    /// whenever it's first needed.
    ///
    /// Created as one atomic step inside `confirmAndInstall`, not a separate
    /// button/step after success -- an earlier version made this a distinct
    /// "Create Partitions" action shown only after the wipe succeeded, and a
    /// real user closed the sheet at that point without noticing/clicking
    /// it, leaving USERFILES/SMS_Media/__.POPS never actually created
    /// despite having reviewed and accepted the suggested sizes. Folding
    /// creation into the one primary action removes that whole class of
    /// "reviewed the defaults but nothing happened" bug.
    @Published var ps1GamesSizeBytes: Int64 = 0
    @Published var moviesSizeBytes: Int64 = 0
    @Published var userFilesSizeBytes: Int64 = 0
    /// Set when the drive is too small to comfortably fit every scaling
    /// partition at its minimum useful size -- see
    /// PartitionSizeSuggestions.ScalingSuggestions.warning's doc comment.
    @Published private(set) var partitionSizeWarning: String?

    private let service: FreeHDBootService
    private let ps1Service: PS1GameService

    init(service: FreeHDBootService, ps1Service: PS1GameService) {
        self.service = service
        self.ps1Service = ps1Service
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
        let suggestions = PartitionSizeSuggestions.suggestions(forDriveSizeBytes: disk.sizeBytes)
        ps1GamesSizeBytes = suggestions.ps1Games
        moviesSizeBytes = suggestions.movies
        userFilesSizeBytes = suggestions.userFiles
        partitionSizeWarning = suggestions.warning
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
            // Created as part of the same primary action, at whatever sizes
            // are currently in ps1GamesSizeBytes/moviesSizeBytes/
            // userFilesSizeBytes (prefilled by checkDrive, editable in the
            // sheet before this ever runs) -- see those properties' doc
            // comment for why this must not be a separate, skippable step.
            latestProgressLine = "Creating PS1 Games/Movies/User Files partitions…"
            try await ps1Service.createGamesPartitionIfNeeded(sizeBytes: ps1GamesSizeBytes, on: disk)
            try await ps1Service.createSMSMediaPartitionIfNeeded(sizeBytes: moviesSizeBytes, on: disk)
            try await ps1Service.createUserFilesPartitionIfNeeded(sizeBytes: userFilesSizeBytes, on: disk)
            didSucceed = true
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
