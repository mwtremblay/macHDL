import Foundation

/// Computes *suggested* partition sizes from a drive's total capacity --
/// sibling to `PFSPartitionSizing` (which rounds a size someone has already
/// chosen up to a valid 128MB-aligned APA value; that rounding still happens
/// downstream in `HDLDumpHelperService.createPOPSPartition`, this file
/// doesn't need to duplicate it). PS2 HDDs used with this app range from
/// small to 2TB+, and PFS partitions can't be resized in place once
/// created, so a single hardcoded default (this app's old behavior) is
/// either wasteful on a huge drive or a hard ceiling on a small one.
///
/// First-pass heuristic, not a precisely-tuned algorithm -- the weights/cap
/// below are a reasonable starting point, freely tunable, and every
/// suggestion is always just a prefilled, user-editable default (see the
/// setup wizard / PartitionSizePromptSheet), never silently applied.
enum PartitionSizeSuggestions {
    /// Fixed sizes for infra partitions that never benefit from more room on
    /// a bigger drive -- homebrew ELFs/system files don't get bigger just
    /// because the drive did. Matches this app's existing historical
    /// defaults (PS1GameService.oplPartitionSizeBytes, PFSDestinationPaths.
    /// commonPartitionSizeBytes).
    static let commonPartitionSizeBytes: Int64 = 64_000_000
    static let oplPartitionSizeBytes: Int64 = 128_000_000
    static let fhdbAppsPartitionSizeBytes: Int64 = 128_000_000

    /// The smallest size ever suggested for a scaling bucket -- one APA
    /// chunk (128MB). Below this a partition isn't meaningfully useful.
    static let minimumScalingPartitionSizeBytes: Int64 = 128_000_000

    /// Suggested sizes for the three partitions whose usefulness genuinely
    /// scales with drive capacity: PS1 games, Movies/TV (`SMS_Media`), and
    /// User Files.
    struct ScalingSuggestions: Equatable {
        let ps1Games: Int64
        let movies: Int64
        let userFiles: Int64
        /// Non-nil only when the drive is too small to fit even the
        /// minimum-floor allocation for all three buckets alongside the
        /// fixed infra partitions -- the UI should surface this rather than
        /// silently suggesting sizes that don't actually leave room for
        /// everything.
        let warning: String?
    }

    /// Relative weights splitting the scaling pool between the three
    /// buckets -- Movies/TV gets the largest share since video is the
    /// single largest-per-item content type this app handles (PS1 games are
    /// individually small but numerous; User Files defaults smallest since
    /// its actual usage is the most unpredictable of the three).
    private static let ps1GamesWeight: Double = 2
    private static let moviesWeight: Double = 3
    private static let userFilesWeight: Double = 1

    /// The scaling pool is capped at this fraction of the drive so the
    /// majority stays free for PS2 games -- each an individually-sized HDL
    /// partition, created per-game outside this fixed-bucket scheme
    /// entirely -- plus general headroom.
    private static let scalingPoolFraction: Double = 0.4

    static func suggestions(forDriveSizeBytes driveSizeBytes: Int64) -> ScalingSuggestions {
        let fixedInfraTotal = commonPartitionSizeBytes + oplPartitionSizeBytes + fhdbAppsPartitionSizeBytes
        let remaining = driveSizeBytes - fixedInfraTotal
        let floorTotal = minimumScalingPartitionSizeBytes * 3

        guard remaining >= floorTotal else {
            let each = max(0, remaining / 3)
            return ScalingSuggestions(
                ps1Games: each,
                movies: each,
                userFiles: each,
                warning: "This drive is too small to comfortably fit every partition at its minimum useful size. Consider leaving one or more of these at 0 for now, or using a larger drive."
            )
        }

        let pool = min(remaining, Int64(Double(driveSizeBytes) * scalingPoolFraction))
        let totalWeight = ps1GamesWeight + moviesWeight + userFilesWeight

        func weighted(_ weight: Double) -> Int64 {
            max(minimumScalingPartitionSizeBytes, Int64(Double(pool) * (weight / totalWeight)))
        }

        return ScalingSuggestions(
            ps1Games: weighted(ps1GamesWeight),
            movies: weighted(moviesWeight),
            userFiles: weighted(userFilesWeight),
            warning: nil
        )
    }
}

/// Shared GB<->bytes conversion for the size fields every partition-sizing
/// UI edits (PartitionSizePromptSheet, FreeHDBootSetupSheet) -- one place so
/// the two don't drift out of sync on rounding/precision.
enum GigabyteConversion {
    static func gigabytes(fromBytes bytes: Int64) -> Double {
        Double(bytes) / 1_000_000_000
    }

    static func bytes(fromGigabytes gigabytes: Double) -> Int64 {
        Int64(gigabytes * 1_000_000_000)
    }
}

/// The one decision every "Add"-style flow that can trigger first-time
/// creation of a scaling partition (`__.POPS`, `SMS_Media`, `USERFILES`)
/// needs to make, in one place -- see PartitionSizePromptRequest's doc
/// comment ("every such flow follows the same shape"). Each view model
/// still owns its own `@Published var pendingPartitionSizePrompt`/confirmed-
/// size storage (SwiftUI observation has to live on the ObservableObject
/// itself) and constructs its own PartitionSizePromptRequest from
/// `.awaitingPrompt`'s suggested size -- this type deliberately doesn't
/// reference PartitionSizePromptRequest (a Sources/Models type) itself,
/// since Sources/Shared is also compiled into the privileged helper target
/// (mac-hdl-gui-helper, see project.yml), which doesn't include
/// Sources/Models at all.
enum PartitionSizeGate {
    enum Decision {
        case proceed(sizeBytes: Int64)
        case awaitingPrompt(suggestedSizeBytes: Int64)
    }

    /// - Parameters:
    ///   - confirmedSizeBytes: Already-resolved size for this partition, if
    ///     any (e.g. from a prior call to this same gate this sheet
    ///     presentation/disk). When set, always proceeds with it directly --
    ///     `partitionExists` isn't even called.
    ///   - partitionExists: Checked only when `confirmedSizeBytes` is nil.
    ///     Callers should already fold a failed existence-check into "assume
    ///     it exists" (matching every call site's prior `(try? ...) ?? true`)
    ///     so a broken check doesn't block the flow -- the downstream
    ///     `create*IfNeeded` call re-checks existence anyway.
    static func decide(
        confirmedSizeBytes: Int64?,
        suggestedSizeBytes: Int64,
        partitionExists: () async -> Bool
    ) async -> Decision {
        if let confirmedSizeBytes {
            return .proceed(sizeBytes: confirmedSizeBytes)
        }
        if await partitionExists() {
            return .proceed(sizeBytes: suggestedSizeBytes)
        }
        return .awaitingPrompt(suggestedSizeBytes: suggestedSizeBytes)
    }
}
