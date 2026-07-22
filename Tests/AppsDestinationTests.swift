import XCTest
@testable import macHDL

/// Confirms the two AppsDestination presets build the exact PFS paths the
/// "Apps" and "Core Apps" tabs depend on -- in particular that `.fhdbApps`'s
/// empty `appsSubdirectory` doesn't introduce a stray leading/double slash,
/// since `+OPL`'s apps live one level deeper (`APPS/<name>`) than
/// `PP.FHDB.APPS`'s (`<name>`, directly at the partition root).
final class AppsDestinationTests: XCTestCase {
    func testOPLAppsDestinationBuildsPathsUnderAPPSSubdirectory() {
        XCTAssertEqual(AppsDestination.oplApps.partitionName, "+OPL")
        XCTAssertEqual(AppsDestination.oplApps.appFolderPFSPath(appFolderName: "wLaunchELF"), "APPS/wLaunchELF")
        XCTAssertEqual(
            AppsDestination.oplApps.appPFSPath(appFolderName: "wLaunchELF", relativePath: "CFG/theme.cfg"),
            "APPS/wLaunchELF/CFG/theme.cfg"
        )
    }

    func testFHDBAppsDestinationBuildsPathsDirectlyAtPartitionRoot() {
        XCTAssertEqual(AppsDestination.fhdbApps.partitionName, "PP.FHDB.APPS")
        XCTAssertEqual(AppsDestination.fhdbApps.appFolderPFSPath(appFolderName: "OPL"), "OPL")
        XCTAssertEqual(
            AppsDestination.fhdbApps.appPFSPath(appFolderName: "OPL", relativePath: "OPNPS2LD.ELF"),
            "OPL/OPNPS2LD.ELF"
        )
    }
}
