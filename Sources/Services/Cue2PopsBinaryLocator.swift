import Foundation

enum Cue2PopsBinaryLocator {
    enum LocatorError: Error, LocalizedError {
        case binaryNotFound

        var errorDescription: String? {
            "The bundled cue2pops tool could not be found. This build is broken -- the Xcode build phase that compiles and copies it may not have run."
        }
    }

    /// Resolves the bundled cue2pops binary at Contents/Resources/cue2pops-bin/cue2pops.
    static func resolve() throws -> URL {
        guard let url = Bundle.main.url(
            forResource: "cue2pops",
            withExtension: nil,
            subdirectory: "cue2pops-bin"
        ) else {
            throw LocatorError.binaryNotFound
        }
        return url
    }
}
