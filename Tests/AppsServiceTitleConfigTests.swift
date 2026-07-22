import XCTest
@testable import macHDL

/// Confirms the OPL title.cfg synthesis logic (see AppsService.
/// installOPLTitleConfigIfNeeded's doc comment for why this exists --
/// OPL's Apps menu silently skips any +OPL/APPS/<name>/ folder without a
/// title.cfg, confirmed by reading OPL's own source).
final class AppsServiceTitleConfigTests: XCTestCase {
    func testDetectsExistingTitleConfigCaseInsensitively() {
        XCTAssertTrue(AppsService.hasExistingTitleConfig(relativePaths: ["title.cfg", "App.ELF"]))
        XCTAssertTrue(AppsService.hasExistingTitleConfig(relativePaths: ["TITLE.CFG", "App.ELF"]))
        XCTAssertFalse(AppsService.hasExistingTitleConfig(relativePaths: ["App.ELF", "readme.txt"]))
    }

    func testExistingTitleConfigMustBeAtRootNotNested() {
        // A title.cfg nested inside a subfolder isn't what OPL's scanner
        // looks for (it only checks <appFolder>/title.cfg directly) -- this
        // must NOT be treated as "already has one".
        XCTAssertFalse(AppsService.hasExistingTitleConfig(relativePaths: ["sub/title.cfg", "App.ELF"]))
    }

    func testPrefersELFMatchingAppFolderName() {
        let candidate = AppsService.bestBootELFCandidate(
            relativePaths: ["readme.txt", "tools/other.ELF", "wLaunchELF.ELF"],
            appFolderName: "wLaunchELF"
        )
        XCTAssertEqual(candidate, "wLaunchELF.ELF")
    }

    func testFallsBackToShallowestELFWhenNoNameMatch() {
        let candidate = AppsService.bestBootELFCandidate(
            relativePaths: ["bin/deep/Other.elf", "Main.elf"],
            appFolderName: "SomeApp"
        )
        XCTAssertEqual(candidate, "Main.elf")
    }

    func testReturnsNilWhenNoELFPresent() {
        XCTAssertNil(AppsService.bestBootELFCandidate(relativePaths: ["readme.txt", "theme.cfg"], appFolderName: "SomeApp"))
    }

    /// Regression test: an earlier version stripped every occurrence of the
    /// substring ".elf" (via replacingOccurrences) rather than just the
    /// trailing extension, so a filename with ".elf" appearing more than
    /// once corrupted the comparison. deletingPathExtension only removes
    /// the final extension.
    func testFilenameWithRepeatedELFSubstringDoesNotCorruptNameMatch() {
        let candidate = AppsService.bestBootELFCandidate(
            relativePaths: ["tools/other.elf", "game.elf.v2.elf"],
            appFolderName: "game.elf.v2"
        )
        XCTAssertEqual(candidate, "game.elf.v2.elf")
    }

    func testTitleConfigContentsMatchesOPLConfigWriteFormat() {
        let contents = AppsService.titleConfigContents(appFolderName: "wLaunchELF", bootRelativePath: "wLaunchELF.ELF")
        XCTAssertEqual(contents, "title=wLaunchELF\r\nboot=wLaunchELF.ELF\r\n")
    }
}
