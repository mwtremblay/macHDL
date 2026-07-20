import Foundation

/// Detects "split" PS1 dumps -- CUE sheets referencing more than one BIN
/// file (one per track), which cue2pops-mac cannot convert.
///
/// Mirrors cue2pops-mac's own detection exactly rather than a more
/// "proper" line-based CUE parse, so this stays perfectly predictive of
/// what cue2pops will actually reject: Vendor/cue2pops-mac/cue2pops.c's
/// `binary_count` (line ~696) is a crude, case-sensitive scan for the
/// literal substring "BINARY" anywhere in the file -- not per-line, not
/// restricted to `FILE` directives -- and it rejects (`binary_count != 1`,
/// cue2pops.c:732) whenever that count isn't exactly 1. A single-BIN cue
/// has exactly one `FILE "..." BINARY` line; a split dump has one per
/// track.
enum CueSheetAnalyzer {
    /// True if cue2pops would reject this cue sheet specifically because it
    /// references more than one BIN file (a split dump). Does NOT flag
    /// cue2pops's other, unrelated rejection reason (WAVE/audio-track
    /// entries) -- that failure mode isn't a split dump and isn't handled
    /// by psx-vcd's `combine` step either, so it's left to surface via
    /// cue2pops's own existing error path, unchanged.
    static func isSplitDump(cueURL: URL) throws -> Bool {
        let contents = try String(contentsOf: cueURL, encoding: .utf8)
        return countOccurrences(of: "BINARY", in: contents) > 1
    }

    private static func countOccurrences(of substring: String, in text: String) -> Int {
        var count = 0
        var searchStart = text.startIndex
        while let range = text.range(of: substring, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}
