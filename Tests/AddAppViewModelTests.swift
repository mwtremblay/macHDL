import XCTest
@testable import macHDL

/// Regression tests for the path-traversal fix: `appFolderName` becomes a
/// PFS path component under `+OPL/APPS/`, so `/` and `.`/`..` must be
/// rejected before install/delete ever reaches the privileged helper.
final class AddAppViewModelTests: XCTestCase {
    func testRejectsEmptyName() {
        XCTAssertFalse(AddAppViewModel.isValidFolderName(""))
        XCTAssertFalse(AddAppViewModel.isValidFolderName("   "))
    }

    func testRejectsTraversalSegments() {
        XCTAssertFalse(AddAppViewModel.isValidFolderName(".."))
        XCTAssertFalse(AddAppViewModel.isValidFolderName("."))
        XCTAssertFalse(AddAppViewModel.isValidFolderName("../__system"))
        XCTAssertFalse(AddAppViewModel.isValidFolderName("../../__.POPS"))
    }

    func testRejectsEmbeddedSlash() {
        XCTAssertFalse(AddAppViewModel.isValidFolderName("foo/bar"))
        XCTAssertFalse(AddAppViewModel.isValidFolderName("/etc"))
    }

    func testAcceptsOrdinaryNames() {
        XCTAssertTrue(AddAppViewModel.isValidFolderName("wLaunchELF"))
        XCTAssertTrue(AddAppViewModel.isValidFolderName("Neutrino 2.5"))
        XCTAssertTrue(AddAppViewModel.isValidFolderName("  OPL110  "))
    }
}
