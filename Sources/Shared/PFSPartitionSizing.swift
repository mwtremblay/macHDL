import Foundation

/// The PS2 APA format requires every partition's size to be an exact
/// multiple of 128MB -- confirmed directly in hdl_dump's own
/// `apa_check_slice` (apa.c). pfsshell's `mkpart` does NOT enforce or round
/// this itself; it honors whatever size it's given. Requesting a
/// non-aligned size produces a partition that makes hdl_dump's strict
/// reader abort on reading the ENTIRE partition table -- not just the one
/// bad partition -- which on real hardware made every other partition
/// (including pre-existing, correctly-created PS2 games) look unreadable,
/// even though they were untouched. This was hit and recovered from on real
/// hardware; see project memory for the full incident writeup. Shared
/// between the app and the daemon so the app-side default size constants
/// and the daemon's authoritative enforcement can't drift out of sync.
enum PFSPartitionSizing {
    static let bytesPer128MB: Int64 = 128 * 1024 * 1024

    /// Rounds up to the nearest 128MB multiple, expressed in MiB (the unit
    /// pfsshell's `mkpart` command accepts, e.g. "3840M").
    static func roundedSizeInMiB(requestedBytes: Int64) -> Int {
        let roundedBytes = ((requestedBytes + bytesPer128MB - 1) / bytesPer128MB) * bytesPer128MB
        return max(128, Int(roundedBytes / (1024 * 1024)))
    }
}
