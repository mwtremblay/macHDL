import Foundation

/// A show or movie search result, reduced to just what AddTVEpisodeSheet/
/// AddVideoSheet's disambiguation picker needs to display and act on --
/// shared so TMDBDisambiguationSheet is one view, not a near-duplicate pair.
/// `ShowResult`/`MovieResult` each expose `.asCandidate`; `id` is only
/// meaningful for shows (TVShowService needs it for the per-episode fetch --
/// movie search results carry their own final title already, so a movie
/// candidate's `id` goes unused after selection).
struct TMDBSearchCandidate: Identifiable, Equatable {
    let id: Int
    let name: String
    let year: String?
}

/// Looks up TV show/episode and movie metadata from TMDB (themoviedb.org)
/// on demand, to correct/confirm what TVFilenameParser/MovieFilenameParser
/// guessed from a source file's name. Mirrors GameArtworkFetcher's shape
/// exactly: a pure struct, a FetchError enum with a soft "not found" case,
/// async/await URLSession.data(from:), manual HTTPURLResponse status
/// handling -- see GameArtworkFetcher's own doc comment for why this app
/// needs no special networking configuration (no App Sandbox/ATS
/// restrictions).
///
/// Deliberately knows nothing about where the API key comes from -- it's
/// passed in as a plain string by the caller (AddTVEpisodeViewModel/
/// AddVideoViewModel, which read it from KeychainStore). Keeps this fully
/// unit-testable without touching the Keychain, same separation
/// GameArtworkFetcher has from GameArtworkService's PFS-writing.
struct TMDBMetadataFetcher {
    struct ShowResult: Identifiable, Decodable, Equatable {
        let id: Int
        let name: String
        let firstAirDate: String?

        /// The first 4 characters of `firstAirDate` (e.g. "2005-03-24" ->
        /// "2005"), for display in the disambiguation picker -- nil if TMDB
        /// didn't report an air date for this show.
        var year: String? {
            guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
            return String(firstAirDate.prefix(4))
        }

        var asCandidate: TMDBSearchCandidate { TMDBSearchCandidate(id: id, name: name, year: year) }
    }

    struct EpisodeResult: Decodable, Equatable {
        let name: String
    }

    struct MovieResult: Identifiable, Decodable, Equatable {
        let id: Int
        let title: String
        let releaseDate: String?

        /// Same "first 4 characters" extraction as ShowResult.year.
        var year: String? {
            guard let releaseDate, releaseDate.count >= 4 else { return nil }
            return String(releaseDate.prefix(4))
        }

        var asCandidate: TMDBSearchCandidate { TMDBSearchCandidate(id: id, name: title, year: year) }
    }

    private struct ShowSearchResponse: Decodable {
        let results: [ShowResult]
    }

    private struct MovieSearchResponse: Decodable {
        let results: [MovieResult]
    }

    enum FetchError: Error, LocalizedError {
        /// No results for a search, or no episode at that season/episode
        /// number -- an expected, common outcome (typo'd name, an episode
        /// TMDB hasn't catalogued yet), not a real error. Callers should
        /// treat this as a soft "nothing found" state, same reasoning as
        /// GameArtworkFetcher.FetchError.notFound.
        case notFound
        case serverError(status: Int)
        case transportError(underlying: Error)
        case decodingError(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "No results were found."
            case .serverError(let status):
                return "The TMDB server returned an error (HTTP \(status))."
            case .transportError(let underlying):
                return "Could not reach TMDB: \(underlying.localizedDescription)"
            case .decodingError(let underlying):
                return "Could not read TMDB's response: \(underlying.localizedDescription)"
            }
        }
    }

    private static let baseURL = URL(string: "https://api.themoviedb.org/3")!

    /// Where the TMDB API key lives in the Keychain -- shared by
    /// SettingsView (writes it) and AddTVEpisodeViewModel/AddVideoViewModel
    /// (read it) so they can't drift out of sync, same reasoning as
    /// PFSDestinationPaths' path-builder constants being a single source of
    /// truth.
    static let apiKeyKeychainService = "mac-hdl-gui.tmdb"
    static let apiKeyKeychainAccount = "api-key"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchShows(name: String, apiKey: String) async throws -> [ShowResult] {
        let url = Self.searchShowsURL(name: name, apiKey: apiKey)
        let data = try await fetchData(from: url)
        let response = try Self.decode(ShowSearchResponse.self, from: data)
        return response.results
    }

    func fetchEpisode(showID: Int, seasonNumber: Int, episodeNumber: Int, apiKey: String) async throws -> EpisodeResult {
        let url = Self.episodeURL(showID: showID, seasonNumber: seasonNumber, episodeNumber: episodeNumber, apiKey: apiKey)
        let data = try await fetchData(from: url)
        return try Self.decode(EpisodeResult.self, from: data)
    }

    /// Unlike `searchShows`, there's no follow-up detail fetch -- TMDB's
    /// movie search response already includes the canonical `title`, so the
    /// search result itself is the final answer a caller applies.
    func searchMovies(name: String, year: Int?, apiKey: String) async throws -> [MovieResult] {
        let url = Self.searchMoviesURL(name: name, year: year, apiKey: apiKey)
        let data = try await fetchData(from: url)
        let response = try Self.decode(MovieSearchResponse.self, from: data)
        return response.results
    }

    private func fetchData(from url: URL) async throws -> Data {
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

    /// Split out from `searchShows` so it's directly unit-testable (correct
    /// percent-encoding of a show name containing spaces/punctuation)
    /// without a real network call -- same reasoning as VideoConverter.
    /// arguments() being a standalone testable function.
    static func searchShowsURL(name: String, apiKey: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("search/tv"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: name),
        ]
        return components.url!
    }

    static func episodeURL(showID: Int, seasonNumber: Int, episodeNumber: Int, apiKey: String) -> URL {
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("tv/\(showID)/season/\(seasonNumber)/episode/\(episodeNumber)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        return components.url!
    }

    /// `year` narrows TMDB's results the same way season/episode numbers
    /// narrow the TV lookup -- omitted from the query entirely when nil
    /// (TMDB treats a present-but-empty `year` param as still constraining
    /// results, so it's left off rather than passed empty).
    static func searchMoviesURL(name: String, year: Int?, apiKey: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("search/movie"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: name),
        ]
        if let year {
            queryItems.append(URLQueryItem(name: "year", value: String(year)))
        }
        components.queryItems = queryItems
        return components.url!
    }

    /// TMDB's JSON keys are snake_case ("first_air_date"); this app's model
    /// properties are camelCase -- decoded here rather than per-call so
    /// every response shape gets the same convention consistently.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw FetchError.decodingError(underlying: error)
        }
    }
}
