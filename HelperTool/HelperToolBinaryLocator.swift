import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum HelperToolBinaryLocator {
    enum LocatorError: Error, CustomStringConvertible {
        case binaryNotFound(String)
        case couldNotDetermineOwnPath

        var description: String {
            switch self {
            case .binaryNotFound(let path):
                return "bundled hdl_dump not found at expected path: \(path)"
            case .couldNotDetermineOwnPath:
                return "could not determine this daemon's own executable path"
            }
        }
    }

    /// Resolves hdl_dump's path relative to this daemon's own executable
    /// location inside the app bundle. Cannot use Bundle.main the way the app
    /// target's BundledBinaryLocator does -- for a bare `tool`-type executable
    /// launched by launchd, Bundle.main does not represent the containing
    /// .app bundle. Also cannot use CommandLine.arguments[0]: for a daemon
    /// launched via a launchd plist's `BundleProgram` key, argv[0] is
    /// literally that relative string ("Contents/Library/HelperTools/...",
    /// not an absolute path), and the daemon's cwd defaults to "/" -- walking
    /// up from that produces garbage. _NSGetExecutablePath is the correct,
    /// reliable way to get this process's actual resolved executable path.
    static func resolve() throws -> URL {
        try resolve(binaryName: "hdl_dump", resourceSubdir: "hdl-dump-bin")
    }

    /// Resolves pfsshell's path the same way, in its own sibling Resources subdirectory.
    static func resolvePFSShell() throws -> URL {
        try resolve(binaryName: "pfsshell", resourceSubdir: "pfsshell-bin")
    }

    /// Resolves pfsutil's path the same way. pfsutil is built alongside
    /// pfsshell (same Meson project, same output directory) -- see
    /// Scripts/build-pfsshell.sh.
    static func resolvePFSUtil() throws -> URL {
        try resolve(binaryName: "pfsutil", resourceSubdir: "pfsshell-bin")
    }

    static func resolve(binaryName: String, resourceSubdir: String) throws -> URL {
        guard let executablePath = currentExecutablePath() else {
            throw LocatorError.couldNotDetermineOwnPath
        }

        // .../macHDL.app/Contents/Library/HelperTools/<daemon>
        //                     -> .../Contents/Resources/<resourceSubdir>/<binaryName>
        let executableURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        let contentsURL = executableURL
            .deletingLastPathComponent() // HelperTools
            .deletingLastPathComponent() // Library
            .deletingLastPathComponent() // Contents
        let binaryURL = contentsURL
            .appendingPathComponent("Resources")
            .appendingPathComponent(resourceSubdir)
            .appendingPathComponent(binaryName)

        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw LocatorError.binaryNotFound(binaryURL.path)
        }
        return binaryURL
    }

    private static func currentExecutablePath() -> String? {
        var bufferSize: UInt32 = 0
        _NSGetExecutablePath(nil, &bufferSize)
        guard bufferSize > 0 else { return nil }

        var buffer = [Int8](repeating: 0, count: Int(bufferSize))
        guard _NSGetExecutablePath(&buffer, &bufferSize) == 0 else { return nil }
        return String(cString: buffer)
    }
}
