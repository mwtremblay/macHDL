import XCTest
@testable import macHDL

/// AppArchiveExtractor has zero XPC/privileged-helper dependency (pure
/// Process shell-out to the vendored unar + local filesystem walk), so it's
/// the one new piece from the Apps feature that's fully unit-testable.
/// Fixtures are built at test time via the system `/usr/bin/zip` (always
/// present on macOS) -- .7z/.rar format coverage is intentionally scoped out
/// here (unar itself is a well-tested upstream tool; these tests verify this
/// app's own single-folder/flat-archive/junk-filtering logic, not unar's
/// format support).
final class AppArchiveExtractorTests: XCTestCase {
    private func makeZip(named zipName: String, contents: (URL) throws -> Void) throws -> URL {
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: workDir) }

        let srcDir = workDir.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try contents(srcDir)

        let zipURL = workDir.appendingPathComponent(zipName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = srcDir
        process.arguments = ["-r", zipURL.path, "."]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "test fixture zip creation failed")

        return zipURL
    }

    func testSingleWrappingFolderIsDetected() async throws {
        let zipURL = try makeZip(named: "MyApp.zip") { srcDir in
            let appDir = srcDir.appendingPathComponent("MyApp", isDirectory: true)
            let cfgDir = appDir.appendingPathComponent("CFG", isDirectory: true)
            try FileManager.default.createDirectory(at: cfgDir, withIntermediateDirectories: true)
            try "readme".write(to: appDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
            try "cfg".write(to: cfgDir.appendingPathComponent("theme.cfg"), atomically: true, encoding: .utf8)
        }

        let extracted = try await AppArchiveExtractor().extract(archiveURL: zipURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: extracted.scratchRoot) }

        XCTAssertEqual(extracted.rootDirectory.lastPathComponent, "MyApp")
        XCTAssertEqual(extracted.suggestedAppFolderName, "MyApp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.rootDirectory.appendingPathComponent("readme.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.rootDirectory.appendingPathComponent("CFG/theme.cfg").path))
    }

    func testFlatArchiveFallsBackToArchiveFilename() async throws {
        let zipURL = try makeZip(named: "FlatTool.zip") { srcDir in
            try "elf-contents".write(to: srcDir.appendingPathComponent("FlatTool.elf"), atomically: true, encoding: .utf8)
            try "readme".write(to: srcDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        }

        let extracted = try await AppArchiveExtractor().extract(archiveURL: zipURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: extracted.scratchRoot) }

        // Confirmed by direct experimentation: unar itself always wraps its
        // output in exactly one top-level folder, synthesizing one named
        // after the archive when the archive has no single top-level folder
        // of its own -- so rootDirectory is scratchRoot/FlatTool, not
        // scratchRoot itself. resolvingSymlinksInPath() on both sides avoids
        // a spurious failure from /var vs /private/var (temporaryDirectory
        // and appendingPathComponent don't always agree on which form to use).
        XCTAssertEqual(
            extracted.rootDirectory.resolvingSymlinksInPath(),
            extracted.scratchRoot.appendingPathComponent("FlatTool").resolvingSymlinksInPath()
        )
        XCTAssertEqual(extracted.suggestedAppFolderName, "FlatTool")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.rootDirectory.appendingPathComponent("FlatTool.elf").path))
    }

    /// Real-world .zip archives built on a Mac often contain a spurious
    /// __MACOSX sibling folder alongside the real wrapping folder -- this
    /// must not defeat single-folder detection.
    func testMACOSXSiblingIsIgnored() async throws {
        let zipURL = try makeZip(named: "WithJunk.zip") { srcDir in
            let appDir = srcDir.appendingPathComponent("RealApp", isDirectory: true)
            try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            try "contents".write(to: appDir.appendingPathComponent("app.elf"), atomically: true, encoding: .utf8)

            let macosxDir = srcDir.appendingPathComponent("__MACOSX", isDirectory: true)
            try FileManager.default.createDirectory(at: macosxDir, withIntermediateDirectories: true)
            try "junk".write(to: macosxDir.appendingPathComponent("._RealApp"), atomically: true, encoding: .utf8)
        }

        let extracted = try await AppArchiveExtractor().extract(archiveURL: zipURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: extracted.scratchRoot) }

        XCTAssertEqual(extracted.rootDirectory.lastPathComponent, "RealApp")
        XCTAssertEqual(extracted.suggestedAppFolderName, "RealApp")
    }

    func testNonexistentArchiveThrowsCleanly() async throws {
        let bogusURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        do {
            _ = try await AppArchiveExtractor().extract(archiveURL: bogusURL)
            XCTFail("expected extraction of a nonexistent archive to throw")
        } catch is AppArchiveExtractor.ExtractionError {
            // expected
        }
    }
}
