import XCTest
@testable import macHDL

final class HDLDumpProgressParserTests: XCTestCase {
    func testParsesFullFormatWithBarAndDetail() throws {
        let line = "[==========>                                                          ] 15%, 2 min remaining, 12.34 MB/sec         "
        let progress = try XCTUnwrap(HDLDumpProgressParser.parse(line))
        XCTAssertEqual(progress.fraction, 0.15, accuracy: 0.0001)
        XCTAssertEqual(progress.detailText, "2 min remaining, 12.34 MB/sec")
    }

    func testParsesBareFormatWithoutDetail() throws {
        let progress = try XCTUnwrap(HDLDumpProgressParser.parse(" 15%"))
        XCTAssertEqual(progress.fraction, 0.15, accuracy: 0.0001)
        XCTAssertNil(progress.detailText)
    }

    func testReturnsNilForUnparseableLine() {
        XCTAssertNil(HDLDumpProgressParser.parse("garbage line with no percent"))
    }
}
