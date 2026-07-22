import XCTest
@testable import macHDL

/// PopStarterSystemFile.all is a hand-transcribed manifest of exact
/// filenames/paths -- same "self-consistency, not upstream-correctness"
/// testing rationale as FreeHDBootDestinationPathsTests.
final class PopStarterSystemFileTests: XCTestCase {
    func testNoDuplicateFilenames() {
        let ids = PopStarterSystemFile.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "each system file must have a distinct filename: \(ids)")
    }

    func testOnlyThePAKFilesAreOptional() {
        let optionalIDs = Set(PopStarterSystemFile.all.filter(\.isOptional).map(\.id))
        XCTAssertEqual(optionalIDs, ["POPS.PAK", "POPS_IOX.PAK"])
    }

    func testExpectedFilenameExtensionMatchesFileType() {
        XCTAssertEqual(PopStarterSystemFile.popsElf.expectedFilenameExtension, "ELF")
        XCTAssertEqual(PopStarterSystemFile.ioprpImage.expectedFilenameExtension, "IMG")
        XCTAssertEqual(PopStarterSystemFile.patch5Bin.expectedFilenameExtension, "BIN")
        XCTAssertEqual(PopStarterSystemFile.popsPak.expectedFilenameExtension, "PAK")
    }

    func testAllFilesTargetTheCommonPOPSSubdirectory() {
        for file in PopStarterSystemFile.all {
            XCTAssertTrue(
                file.pfsPath.hasPrefix("\(PFSDestinationPaths.popsSubdirectory)/"),
                "\(file.id) must live under \(PFSDestinationPaths.popsSubdirectory)/, got \(file.pfsPath)"
            )
        }
    }
}
