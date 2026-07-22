import XCTest
@testable import macHDL

/// Regression tests for the path-traversal fix: `videoName` becomes the
/// destination filename at the `SMS_Media` partition root, so `/` and
/// `.`/`..` must be rejected before the write ever reaches the privileged
/// helper.
final class AddVideoViewModelTests: XCTestCase {
    func testRejectsEmptyName() {
        XCTAssertFalse(AddVideoViewModel.isValidVideoName(""))
        XCTAssertFalse(AddVideoViewModel.isValidVideoName("   "))
    }

    func testRejectsTraversalSegments() {
        XCTAssertFalse(AddVideoViewModel.isValidVideoName(".."))
        XCTAssertFalse(AddVideoViewModel.isValidVideoName("."))
        XCTAssertFalse(AddVideoViewModel.isValidVideoName("../__system/foo"))
    }

    func testRejectsEmbeddedSlash() {
        XCTAssertFalse(AddVideoViewModel.isValidVideoName("foo/bar"))
        XCTAssertFalse(AddVideoViewModel.isValidVideoName("/etc/passwd"))
    }

    func testAcceptsOrdinaryNames() {
        XCTAssertTrue(AddVideoViewModel.isValidVideoName("My Movie"))
        XCTAssertTrue(AddVideoViewModel.isValidVideoName("  Trip 2024  "))
    }
}
