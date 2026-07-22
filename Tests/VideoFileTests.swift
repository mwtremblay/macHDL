import XCTest
@testable import macHDL

final class VideoFileTests: XCTestCase {
    func testDisplayNameStripsExtension() {
        XCTAssertEqual(VideoFile(filename: "Movie.avi").displayName, "Movie")
    }

    func testDisplayNameHandlesNoExtension() {
        XCTAssertEqual(VideoFile(filename: "Movie").displayName, "Movie")
    }

    func testIdMatchesFilename() {
        XCTAssertEqual(VideoFile(filename: "Movie.avi").id, "Movie.avi")
    }
}
