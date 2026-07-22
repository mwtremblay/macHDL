import XCTest
@testable import macHDL

/// Path-building tests for the Apps feature's additions to
/// PFSDestinationPaths -- pure functions, no HDD/XPC dependency.
final class PFSDestinationPathsAppsTests: XCTestCase {
    func testOplAppPFSPathBuildsNestedPath() {
        XCTAssertEqual(
            PFSDestinationPaths.oplAppPFSPath(appFolderName: "wLaunchELF", relativePath: "CFG/theme.cfg"),
            "APPS/wLaunchELF/CFG/theme.cfg"
        )
    }

    func testOplAppPFSPathBuildsTopLevelPath() {
        XCTAssertEqual(
            PFSDestinationPaths.oplAppPFSPath(appFolderName: "wLaunchELF", relativePath: "wLaunchELF.ELF"),
            "APPS/wLaunchELF/wLaunchELF.ELF"
        )
    }

    func testOplAppFolderPFSPath() {
        XCTAssertEqual(
            PFSDestinationPaths.oplAppFolderPFSPath(appFolderName: "Neutrino"),
            "APPS/Neutrino"
        )
    }
}
