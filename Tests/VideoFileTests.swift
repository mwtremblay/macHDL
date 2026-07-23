import XCTest
@testable import macHDL

final class VideoFileTests: XCTestCase {
    func testDisplayNameStripsExtension() {
        XCTAssertEqual(VideoFile(filename: "Movie.avi", location: .moviesSubdirectory).displayName, "Movie")
    }

    func testDisplayNameHandlesNoExtension() {
        XCTAssertEqual(VideoFile(filename: "Movie", location: .moviesSubdirectory).displayName, "Movie")
    }

    func testIdIncludesLocation() {
        XCTAssertEqual(VideoFile(filename: "Movie.avi", location: .moviesSubdirectory).id, "movies/Movie.avi")
        XCTAssertEqual(VideoFile(filename: "Movie.avi", location: .legacyRoot).id, "root/Movie.avi")
    }

    func testSameFilenameAtDifferentLocationsHasDistinctID() {
        let inMovies = VideoFile(filename: "Movie.avi", location: .moviesSubdirectory)
        let atLegacyRoot = VideoFile(filename: "Movie.avi", location: .legacyRoot)
        XCTAssertNotEqual(inMovies.id, atLegacyRoot.id)
    }
}
