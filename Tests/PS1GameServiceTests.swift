import XCTest
@testable import macHDL

final class PS1GameServiceTests: XCTestCase {
    /// Regression test for the exact bug fixed this session: a naive
    /// `output.contains("__.POPS1")` would wrongly match a line that's
    /// actually `__.POPS10`, since `"__.POPS1"` is a substring of
    /// `"__.POPS10"`. The real fix (exact per-line matching, since each
    /// partition name is the last space-separated field on its own line --
    /// confirmed directly from hdl_dump.c's show_apa_slice2) must
    /// distinguish these correctly.
    func testDistinguishesOverflowPartitionsWithSharedPrefix() {
        let output = """
        type   start     #parts size name
        0x0517 000c0000     1     4MB __net
        0x0517 000c2000     1  4096MB __.POPS
        0x0517 004c2000     1  4096MB __.POPS10
        Total slice size: 1907200MB, used: 8200MB, available: 1899000MB
        """
        let names = PS1GameService.partitionNames(inTOCOutput: output)
        XCTAssertTrue(names.contains("__.POPS"))
        XCTAssertTrue(names.contains("__.POPS10"))
        XCTAssertFalse(names.contains("__.POPS1"), "__.POPS1 was never actually created -- only __.POPS and __.POPS10 exist in this output")
    }

    func testFindsAllExpectedPartitionsAcrossMultipleLines() {
        let output = """
        type   start     #parts size name
        0x0517 000c0000     1  4096MB __common
        0x0517 004c0000     1  4096MB __.POPS
        0x0517 008c0000     1  4096MB __.POPS1
        0x0517 00cc0000     1   128MB +OPL
        Total slice size: 1907200MB, used: 12416MB, available: 1894784MB
        """
        let names = PS1GameService.partitionNames(inTOCOutput: output)
        XCTAssertEqual(names, ["__common", "__.POPS", "__.POPS1", "+OPL"])
    }

    func testEmptyOutputYieldsNoPartitions() {
        XCTAssertTrue(PS1GameService.partitionNames(inTOCOutput: "").isEmpty)
    }
}
