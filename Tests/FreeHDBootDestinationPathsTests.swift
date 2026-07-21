import XCTest
@testable import macHDL

/// FreeHDBootDestinationPaths.payloadFiles was transcribed by hand from
/// installer/system.c's HDDBaseFiles[]/PS2SysHDDFiles[] tables -- exactly
/// the kind of large, repetitive, hand-typed data table where a copy/paste
/// slip (a duplicated resource name, a wrong destination path) is easy to
/// make and easy to miss in review, and where getting it wrong means
/// silently overwriting one bundled resource or one on-disk file with
/// another. These tests only check internal self-consistency of the table
/// (no duplicates, no partitions outside the four FreeHDBoot creates) --
/// they cannot verify the entries are correct against the real upstream
/// source, only that the table itself isn't self-contradictory.
final class FreeHDBootDestinationPathsTests: XCTestCase {
    func testNoDuplicateBundledResourceReferences() {
        let keys = FreeHDBootDestinationPaths.payloadFiles.map { "\($0.resourceName).\($0.resourceExtension)" }
        XCTAssertEqual(keys.count, Set(keys).count, "each payload file must reference a distinct bundled resource: \(keys)")
    }

    func testNoDuplicateDestinationPaths() {
        let destinations = FreeHDBootDestinationPaths.payloadFiles.map { "\($0.partitionName):\($0.pfsPath)" }
        XCTAssertEqual(destinations.count, Set(destinations).count, "each payload file must have a distinct destination: \(destinations)")
    }

    func testAllDestinationsTargetSystemOrSysconf() {
        let allowedPartitions: Set<String> = [
            FreeHDBootDestinationPaths.systemPartitionName,
            FreeHDBootDestinationPaths.sysconfPartitionName,
        ]
        for file in FreeHDBootDestinationPaths.payloadFiles {
            XCTAssertTrue(
                allowedPartitions.contains(file.partitionName),
                "\(file.resourceName).\(file.resourceExtension) targets unexpected partition \(file.partitionName)"
            )
        }
    }

    /// __mbr is installed separately via hdl_dump inject_mbr (see
    /// FreeHDBootService.injectBootloader) -- it must never also appear as a
    /// plain PFS file copy target, which would be silently wrong (pfsutil
    /// has no partition literally named "__mbr").
    func testMBRIsNeverAPayloadFile() {
        for file in FreeHDBootDestinationPaths.payloadFiles {
            XCTAssertNotEqual(file.resourceName, FreeHDBootDestinationPaths.mbrKelfResourceName)
        }
    }

    func testPayloadFileCountMatchesUpstreamSource() {
        // installer/system.c's HDDBaseFiles[] has 22 entries (4 SYS-CONF
        // files + FSCK.XLF + 17 FSCK/LANG files); PS2SysHDDFiles[] has 3
        // entries (MBR.XLF, FHDB.XLF, ENDVDPL.XRX), of which __mbr (MBR.XLF)
        // is handled separately via inject_mbr, leaving 2. 22 + 2 = 24.
        XCTAssertEqual(FreeHDBootDestinationPaths.payloadFiles.count, 24)
    }
}
