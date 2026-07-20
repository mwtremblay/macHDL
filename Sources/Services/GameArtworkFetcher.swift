import Foundation

/// Fetches PS1/PS2 cover art on demand for the user's own personal
/// collection -- never bundled/vendored into this app's repo (same posture
/// already taken toward Sony's copyrighted BIOS files elsewhere in this
/// project). Source: github.com/Luden02/psx-ps2-opl-art-database, a static
/// (unmaintained, "as-is... for archival purposes") mirror of the OPL
/// Manager art database, confirmed via its GitHub tree API to be organized
/// exactly as `PS1/<gameID>/<gameID>_COV.png` / `PS2/<gameID>/<gameID>_COV.png`
/// -- directly fetchable per-game, no bulk download or API key needed.
///
/// This app has no App Sandbox entitlement and no ATS overrides in
/// project.yml, so plain HTTPS via URLSession works with zero configuration
/// changes -- this is the app's first-ever networking code.
struct GameArtworkFetcher {
    enum Platform: String {
        case ps1 = "PS1"
        case ps2 = "PS2"
    }

    enum FetchError: Error, LocalizedError {
        /// HTTP 404 -- confirmed via a real curl check against both a known
        /// real Game ID (200) and a deliberately-wrong one (404) before
        /// writing this. An expected, common outcome (this is a partial,
        /// unmaintained archive), not a real error -- callers should treat
        /// this as a soft "no artwork available" state, not surface an alert.
        case notFound
        case serverError(status: Int)
        case transportError(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "No cover art was found for this game."
            case .serverError(let status):
                return "The artwork server returned an error (HTTP \(status))."
            case .transportError(let underlying):
                return "Could not reach the artwork server: \(underlying.localizedDescription)"
            }
        }
    }

    private static let baseURL = URL(string: "https://raw.githubusercontent.com/Luden02/psx-ps2-opl-art-database/main")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCoverArt(platform: Platform, gameID: String) async throws -> Data {
        let url = Self.baseURL
            .appendingPathComponent(platform.rawValue)
            .appendingPathComponent(gameID)
            .appendingPathComponent("\(gameID)_COV.png")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw FetchError.transportError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FetchError.transportError(underlying: URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200:
            return data
        case 404:
            throw FetchError.notFound
        default:
            throw FetchError.serverError(status: http.statusCode)
        }
    }
}
