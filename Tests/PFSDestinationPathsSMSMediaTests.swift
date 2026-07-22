import XCTest
@testable import macHDL

/// Path-building tests for the SMS video feature's additions to
/// PFSDestinationPaths -- pure functions, no HDD/XPC dependency.
final class PFSDestinationPathsSMSMediaTests: XCTestCase {
    func testSmsMediaVideoPFSPathIsFlatAtPartitionRoot() {
        XCTAssertEqual(
            PFSDestinationPaths.smsMediaVideoPFSPath(filename: "Movie.avi"),
            "Movie.avi"
        )
    }

    func testSmsMediaPartitionSizeIsAligned128MBMultiple() {
        XCTAssertEqual(PFSDestinationPaths.smsMediaPartitionSizeBytes % PFSPartitionSizing.bytesPer128MB, 0)
    }
}
