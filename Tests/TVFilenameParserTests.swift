import XCTest
@testable import macHDL

/// Pure-function tests for TVFilenameParser -- covers the naming
/// conventions this is meant to recognize plus the "give up cleanly" path,
/// since a wrong guess here silently mis-files an episode on the drive
/// rather than failing loudly.
final class TVFilenameParserTests: XCTestCase {
    func testParsesDotSeparatedSxxExxWithTitle() {
        let parsed = TVFilenameParser.parse(filename: "Firefly.S01E02.The.Train.Job.1080p.WEB-DL.x264.mkv")
        XCTAssertEqual(parsed.showName, "Firefly")
        XCTAssertEqual(parsed.seasonNumber, 1)
        XCTAssertEqual(parsed.episodeNumber, 2)
        XCTAssertEqual(parsed.episodeTitle, "The Train Job")
    }

    func testParsesDashSeparatedWithSpaces() {
        let parsed = TVFilenameParser.parse(filename: "Firefly - S01E02 - The Train Job.mkv")
        XCTAssertEqual(parsed.showName, "Firefly")
        XCTAssertEqual(parsed.seasonNumber, 1)
        XCTAssertEqual(parsed.episodeNumber, 2)
        XCTAssertEqual(parsed.episodeTitle, "The Train Job")
    }

    func testParsesLegacyNxNNFormat() {
        let parsed = TVFilenameParser.parse(filename: "Firefly.1x02.The.Train.Job.avi")
        XCTAssertEqual(parsed.showName, "Firefly")
        XCTAssertEqual(parsed.seasonNumber, 1)
        XCTAssertEqual(parsed.episodeNumber, 2)
        XCTAssertEqual(parsed.episodeTitle, "The Train Job")
    }

    func testParsesUnderscoreSeparatedShowName() {
        let parsed = TVFilenameParser.parse(filename: "Deep_Space_Nine_S02E14_Whispers.mkv")
        XCTAssertEqual(parsed.showName, "Deep Space Nine")
        XCTAssertEqual(parsed.seasonNumber, 2)
        XCTAssertEqual(parsed.episodeNumber, 14)
        XCTAssertEqual(parsed.episodeTitle, "Whispers")
    }

    func testHandlesNoTitleAfterMarker() {
        let parsed = TVFilenameParser.parse(filename: "Firefly.S01E02.mkv")
        XCTAssertEqual(parsed.showName, "Firefly")
        XCTAssertEqual(parsed.seasonNumber, 1)
        XCTAssertEqual(parsed.episodeNumber, 2)
        XCTAssertNil(parsed.episodeTitle)
    }

    func testStripsReleaseTagFromTitleButKeepsGenuineWordsBeforeIt() {
        let parsed = TVFilenameParser.parse(filename: "Firefly.S01E01.Serenity.720p.HDTV.x264-GROUP.mkv")
        XCTAssertEqual(parsed.episodeTitle, "Serenity")
    }

    func testReturnsAllNilFieldsWhenNoMarkerFound() {
        let parsed = TVFilenameParser.parse(filename: "some_random_movie_file.mp4")
        XCTAssertNil(parsed.showName)
        XCTAssertNil(parsed.seasonNumber)
        XCTAssertNil(parsed.episodeNumber)
        XCTAssertNil(parsed.episodeTitle)
    }

    func testSuggestedEpisodeNamePadsAndCombinesNumberWithTitle() {
        let parsed = TVFilenameParser.ParsedEpisode(showName: "Firefly", seasonNumber: 1, episodeNumber: 2, episodeTitle: "The Train Job")
        XCTAssertEqual(AddTVEpisodeViewModel.suggestedEpisodeName(parsed: parsed, fallback: "fallback"), "02 - The Train Job")
    }

    func testSuggestedEpisodeNameFallsBackWhenNothingParsed() {
        let parsed = TVFilenameParser.ParsedEpisode()
        XCTAssertEqual(AddTVEpisodeViewModel.suggestedEpisodeName(parsed: parsed, fallback: "fallback"), "fallback")
    }
}
