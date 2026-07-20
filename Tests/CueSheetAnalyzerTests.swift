import XCTest
@testable import macHDL

final class CueSheetAnalyzerTests: XCTestCase {
    private func writeCue(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("cue")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testSingleFileCueIsNotSplitDump() throws {
        let cue = try writeCue("""
        FILE "game.bin" BINARY
          TRACK 01 MODE2/2352
            INDEX 01 00:00:00
        """)
        XCTAssertFalse(try CueSheetAnalyzer.isSplitDump(cueURL: cue))
    }

    func testMultiFileCueIsSplitDump() throws {
        let cue = try writeCue("""
        FILE "track1.bin" BINARY
          TRACK 01 MODE2/2352
            INDEX 01 00:00:00
        FILE "track2.bin" BINARY
          TRACK 02 MODE2/2352
            INDEX 00 00:00:00
            INDEX 01 00:02:00
        """)
        XCTAssertTrue(try CueSheetAnalyzer.isSplitDump(cueURL: cue))
    }

    /// Matches cue2pops.c's own occurrence-based counting (not distinct
    /// filename counting) -- two FILE/BINARY lines referencing the same
    /// filename still count as 2, still a split dump.
    func testRepeatedIdenticalFilenameStillCountsAsSplitDump() throws {
        let cue = try writeCue("""
        FILE "game.bin" BINARY
          TRACK 01 MODE2/2352
            INDEX 01 00:00:00
        FILE "game.bin" BINARY
          TRACK 02 MODE2/2352
            INDEX 01 00:02:00
        """)
        XCTAssertTrue(try CueSheetAnalyzer.isSplitDump(cueURL: cue))
    }
}
