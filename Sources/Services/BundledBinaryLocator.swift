import Foundation

/// Resolves a bundled CLI binary embedded under Contents/Resources/<subdirectory>/<name>
/// by one of this app's preBuildScripts (see project.yml). Shared by every
/// bundled-tool locator in the app target (hdl_dump, cue2pops, psx-vcd) --
/// fails fast rather than silently falling back to a PATH lookup, since a
/// missing binary here always means the app was built incorrectly.
enum BundledBinaryLocator {
    struct BinaryNotFoundError: Error, LocalizedError {
        let name: String

        var errorDescription: String? {
            "The bundled \(name) tool could not be found. This build is broken -- the Xcode build phase that compiles and copies it may not have run."
        }
    }

    static func resolve(name: String, subdirectory: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: subdirectory) else {
            throw BinaryNotFoundError(name: name)
        }
        return url
    }
}
