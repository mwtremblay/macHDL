import XCTest
@testable import macHDL

final class CSVGameListParserTests: XCTestCase {
    func testParsesTypicalOutput() {
        let stdout = """
        type      size flags     dma startup      name
        DVD;4700000KB;     ;u4 ;SLUS_123.45 ;Some Game
        CD ;700000KB;   +1;u2 ;SLUS_999.99 ;Another Game
        total 40000MB, used 5000MB, available 35000MB
        """
        let games = CSVGameListParser.parse(stdout: stdout)
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games[0].name, "Some Game")
        XCTAssertTrue(games[0].isDVD)
        XCTAssertEqual(games[0].sizeKB, 4_700_000)
        XCTAssertEqual(games[1].name, "Another Game")
        XCTAssertFalse(games[1].isDVD)
    }

    func testNameContainingSemicolonDoesNotCorruptRow() {
        // Real printf output captured from hdl_dump's show_hdl_toc format string.
        let stdout = """
        type      size flags dma startup      name
        DVD;4700000KB;     ;u4 ;SLUS_123.45 ;Some Game; With Semicolon
        total 40000MB, used 5000MB, available 35000MB
        """
        let games = CSVGameListParser.parse(stdout: stdout)
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games[0].name, "Some Game; With Semicolon")
    }

    func testEmptyListReturnsNoGames() {
        let stdout = """
        type      size flags dma startup      name
        total 0MB, used 0MB, available 0MB
        """
        XCTAssertTrue(CSVGameListParser.parse(stdout: stdout).isEmpty)
    }
}
