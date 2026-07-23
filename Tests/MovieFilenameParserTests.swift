import XCTest
@testable import macHDL

/// Pure-function tests for MovieFilenameParser -- covers the naming
/// conventions this is meant to recognize plus the "give up cleanly" path,
/// same reasoning as TVFilenameParserTests.
final class MovieFilenameParserTests: XCTestCase {
    func testParsesDotSeparatedTitleAndYear() {
        let parsed = MovieFilenameParser.parse(filename: "The.Italian.Job.2003.1080p.BluRay.x264-GROUP.mkv")
        XCTAssertEqual(parsed.title, "The Italian Job")
        XCTAssertEqual(parsed.year, 2003)
    }

    func testParsesParenthesizedYear() {
        let parsed = MovieFilenameParser.parse(filename: "The Italian Job (2003).mkv")
        XCTAssertEqual(parsed.title, "The Italian Job")
        XCTAssertEqual(parsed.year, 2003)
    }

    func testParsesUnderscoreSeparatedTitle() {
        let parsed = MovieFilenameParser.parse(filename: "A_Star_Is_Born_2018_1080p.mp4")
        XCTAssertEqual(parsed.title, "A Star Is Born")
        XCTAssertEqual(parsed.year, 2018)
    }

    func testDoesNotMistakeResolutionFor1900sOr2000sYear() {
        let parsed = MovieFilenameParser.parse(filename: "Some.Movie.2160p.mkv")
        XCTAssertNil(parsed.year)
    }

    func testReturnsAllNilFieldsWhenNoYearFound() {
        let parsed = MovieFilenameParser.parse(filename: "some_random_home_video.mp4")
        XCTAssertNil(parsed.title)
        XCTAssertNil(parsed.year)
    }
}
