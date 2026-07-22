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

    /// `__system`/`__sysconf` for everything transcribed from upstream's
    /// installer/system.c, plus `PP.FHDB.APPS` for the 3 "core" apps
    /// (uLaunchELF, OPL, SMS) this app's forked FREEHDB.CNF menu expects --
    /// see fhdbAppsPartitionName's doc comment for why those three targets
    /// were chosen.
    func testAllDestinationsTargetKnownPartitions() {
        let allowedPartitions: Set<String> = [
            FreeHDBootDestinationPaths.systemPartitionName,
            FreeHDBootDestinationPaths.sysconfPartitionName,
            FreeHDBootDestinationPaths.fhdbAppsPartitionName,
        ]
        for file in FreeHDBootDestinationPaths.payloadFiles {
            XCTAssertTrue(
                allowedPartitions.contains(file.partitionName),
                "\(file.resourceName).\(file.resourceExtension) targets unexpected partition \(file.partitionName)"
            )
        }
    }

    /// Regression test for the FreeHDBoot "core apps" addition: uLaunchELF's
    /// stock menu paths (FREEHDB.CNF items 1/2) already point at
    /// `__sysconf/FMCB/`, the same partition/subdirectory FreeHDBoot's own
    /// files use -- it must NOT go into the new PP.FHDB.APPS partition.
    /// OPL and SMS (items 2 and 4 in the forked menu) do need the new
    /// partition, matching what that fork's `path3_OSDSYS_ITEM_*` lines say.
    func testCoreAppDestinationsMatchForkedMenuPaths() {
        let files = FreeHDBootDestinationPaths.payloadFiles
        func destination(forResourceName name: String) -> (partitionName: String, pfsPath: String)? {
            files.first { $0.resourceName == name }.map { ($0.partitionName, $0.pfsPath) }
        }

        let uLaunchELF = destination(forResourceName: "ULE_ISR")
        XCTAssertEqual(uLaunchELF?.partitionName, FreeHDBootDestinationPaths.sysconfPartitionName)
        XCTAssertEqual(uLaunchELF?.pfsPath, "FMCB/BOOT.ELF")

        let opl = destination(forResourceName: "OPL110")
        XCTAssertEqual(opl?.partitionName, FreeHDBootDestinationPaths.fhdbAppsPartitionName)
        XCTAssertEqual(opl?.pfsPath, "OPL/OPNPS2LD.ELF")

        let sms = destination(forResourceName: "SMS")
        XCTAssertEqual(sms?.partitionName, FreeHDBootDestinationPaths.fhdbAppsPartitionName)
        XCTAssertEqual(sms?.pfsPath, "SMS/SMS.ELF")
    }

    func testFHDBAppsPartitionNameMatchesForkedCNFConvention() {
        XCTAssertEqual(FreeHDBootDestinationPaths.fhdbAppsPartitionName, "PP.FHDB.APPS")
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

    func testPayloadFileCountMatchesUpstreamSourcePlusCoreApps() {
        // installer/system.c's HDDBaseFiles[] has 22 entries (4 SYS-CONF
        // files + FSCK.XLF + 17 FSCK/LANG files); PS2SysHDDFiles[] has 3
        // entries (MBR.XLF, FHDB.XLF, ENDVDPL.XRX), of which __mbr (MBR.XLF)
        // is handled separately via inject_mbr, leaving 2. 22 + 2 = 24,
        // plus the 3 "core" apps (uLaunchELF, OPL, SMS) added on top -- see
        // testCoreAppDestinationsMatchForkedMenuPaths. 24 + 3 = 27.
        XCTAssertEqual(FreeHDBootDestinationPaths.payloadFiles.count, 27)
    }
}
