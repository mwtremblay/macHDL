import Foundation

enum HDLDumpBinaryLocator {
    enum LocatorError: Error, LocalizedError {
        case binaryNotFound

        var errorDescription: String? {
            "The bundled hdl_dump tool could not be found. This build is broken -- the Xcode build phase that compiles and copies it may not have run."
        }
    }

    /// Resolves the bundled hdl_dump binary at Contents/Resources/hdl-dump-bin/hdl_dump.
    /// Fails fast rather than silently falling back to a PATH lookup, since a missing
    /// binary here always means the app was built incorrectly.
    static func resolve() throws -> URL {
        guard let url = Bundle.main.url(
            forResource: "hdl_dump",
            withExtension: nil,
            subdirectory: "hdl-dump-bin"
        ) else {
            throw LocatorError.binaryNotFound
        }
        return url
    }
}
