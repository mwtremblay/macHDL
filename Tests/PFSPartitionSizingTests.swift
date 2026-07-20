import XCTest
@testable import macHDL

/// Regression coverage for a real incident: an earlier version rounded PFS
/// partition sizes to the nearest MiB instead of the nearest 128MB multiple,
/// which corrupted a real PS2 HDD's partition table on real hardware (see
/// project memory for the full writeup). This must never regress silently.
final class PFSPartitionSizingTests: XCTestCase {
    func testRoundsUpNonAlignedSizeToNearest128MBMultiple() {
        // The exact incident case: 4,000,000,000 bytes rounded (incorrectly)
        // to 3815 MiB previously -- 3815 is not a multiple of 128.
        XCTAssertEqual(PFSPartitionSizing.roundedSizeInMiB(requestedBytes: 4_000_000_000), 3840)
    }

    func testRoundsUpSmallSizeToMinimumOneChunk() {
        // The PopStarter system-files partition incident case: 64,000,000
        // bytes rounded (incorrectly) to 62 MiB previously.
        XCTAssertEqual(PFSPartitionSizing.roundedSizeInMiB(requestedBytes: 64_000_000), 128)
    }

    func testExactMultipleIsUnchanged() {
        let exact256MiB: Int64 = 256 * 1024 * 1024
        XCTAssertEqual(PFSPartitionSizing.roundedSizeInMiB(requestedBytes: exact256MiB), 256)
    }

    func testResultIsAlwaysAMultipleOf128() {
        for bytes: Int64 in [1, 1_000, 128 * 1024 * 1024 + 1, 3_726_000_000, 10_000_000_000] {
            let mib = PFSPartitionSizing.roundedSizeInMiB(requestedBytes: bytes)
            XCTAssertEqual(mib % 128, 0, "\(mib) MiB (from \(bytes) bytes) is not a multiple of 128")
        }
    }
}
