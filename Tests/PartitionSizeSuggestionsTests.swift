import XCTest
@testable import macHDL

final class PartitionSizeSuggestionsTests: XCTestCase {
    func testFixedInfraSizesDoNotScaleWithDriveSize() {
        // Fixed sizes are plain constants, not derived from drive size --
        // this just pins them so a future edit can't accidentally make them
        // scale without a conscious decision.
        XCTAssertEqual(PartitionSizeSuggestions.commonPartitionSizeBytes, 64_000_000)
        XCTAssertEqual(PartitionSizeSuggestions.oplPartitionSizeBytes, 128_000_000)
        XCTAssertEqual(PartitionSizeSuggestions.fhdbAppsPartitionSizeBytes, 128_000_000)
    }

    func testMoviesGetsTheLargestShareOnA1TBDrive() {
        let suggestions = PartitionSizeSuggestions.suggestions(forDriveSizeBytes: 1_000_000_000_000)
        XCTAssertNil(suggestions.warning)
        XCTAssertGreaterThan(suggestions.movies, suggestions.ps1Games)
        XCTAssertGreaterThan(suggestions.ps1Games, suggestions.userFiles)
    }

    func testScalingBucketsStayWithinAFractionOfA2TBDriveLeavingRoomForPS2Games() {
        let driveSize: Int64 = 2_000_000_000_000
        let suggestions = PartitionSizeSuggestions.suggestions(forDriveSizeBytes: driveSize)
        let total = suggestions.ps1Games + suggestions.movies + suggestions.userFiles
        XCTAssertLessThan(total, driveSize / 2, "the fixed-bucket partitions should leave the majority of a large drive free for PS2 games")
    }

    func testEveryScalingBucketMeetsTheMinimumFloorOnA500GBDrive() {
        let suggestions = PartitionSizeSuggestions.suggestions(forDriveSizeBytes: 500_000_000_000)
        XCTAssertNil(suggestions.warning)
        XCTAssertGreaterThanOrEqual(suggestions.ps1Games, PartitionSizeSuggestions.minimumScalingPartitionSizeBytes)
        XCTAssertGreaterThanOrEqual(suggestions.movies, PartitionSizeSuggestions.minimumScalingPartitionSizeBytes)
        XCTAssertGreaterThanOrEqual(suggestions.userFiles, PartitionSizeSuggestions.minimumScalingPartitionSizeBytes)
    }

    func testWarnsAndDegradesGracefullyOnAVeryTinyDrive() {
        // Smaller than the fixed infra partitions plus the minimum floor for
        // all three scaling buckets combined.
        let suggestions = PartitionSizeSuggestions.suggestions(forDriveSizeBytes: 200_000_000)
        XCTAssertNotNil(suggestions.warning)
        XCTAssertGreaterThanOrEqual(suggestions.ps1Games, 0)
        XCTAssertGreaterThanOrEqual(suggestions.movies, 0)
        XCTAssertGreaterThanOrEqual(suggestions.userFiles, 0)
    }

    func testNeverSuggestsNegativeSizesOnAnExtremelyTinyDrive() {
        let suggestions = PartitionSizeSuggestions.suggestions(forDriveSizeBytes: 1_000_000)
        XCTAssertNotNil(suggestions.warning)
        XCTAssertGreaterThanOrEqual(suggestions.ps1Games, 0)
        XCTAssertGreaterThanOrEqual(suggestions.movies, 0)
        XCTAssertGreaterThanOrEqual(suggestions.userFiles, 0)
    }
}
