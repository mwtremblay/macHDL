import Foundation

/// Drives `PartitionSizePromptSheet` -- set on a ViewModel's
/// `@Published var pendingPartitionSizePrompt` whenever an "Add"-style flow
/// is about to create a partition that doesn't exist yet (`__.POPS`,
/// `SMS_Media`, `USERFILES` -- the three partitions whose usefulness
/// genuinely scales with drive size, see `PartitionSizeSuggestions`). Every
/// such flow follows the same shape: check existence, if missing surface
/// this request and pause, resume once the user confirms a size.
struct PartitionSizePromptRequest: Identifiable {
    let id = UUID()
    /// Shown in the sheet, e.g. "Movies/TV" or "User Files" -- not
    /// necessarily the literal PFS partition name.
    let partitionDisplayName: String
    let suggestedSizeBytes: Int64
}
