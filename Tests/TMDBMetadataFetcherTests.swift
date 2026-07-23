import XCTest
@testable import macHDL

/// Pure-function tests for TMDBMetadataFetcher -- no real network call, same
/// "no real ffmpeg invocation" precedent as VideoConverterTests. Covers the
/// things most likely to silently regress: correct query-string percent-
/// encoding of a show/movie name, the movie search's optional `year` query
/// param, and decoding TMDB's actual (snake_case) JSON shapes.
final class TMDBMetadataFetcherTests: XCTestCase {
    func testSearchShowsURLPercentEncodesShowNameWithSpacesAndPunctuation() {
        let url = TMDBMetadataFetcher.searchShowsURL(name: "Marvel's Agents of S.H.I.E.L.D.", apiKey: "KEY123")
        XCTAssertEqual(url.host, "api.themoviedb.org")
        XCTAssertEqual(url.path, "/3/search/tv")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let queryItems = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        XCTAssertEqual(queryItems["api_key"], "KEY123")
        XCTAssertEqual(queryItems["query"], "Marvel's Agents of S.H.I.E.L.D.")
    }

    func testEpisodeURLIncludesShowSeasonAndEpisodeNumbers() {
        let url = TMDBMetadataFetcher.episodeURL(showID: 1399, seasonNumber: 1, episodeNumber: 2, apiKey: "KEY123")
        XCTAssertEqual(url.path, "/3/tv/1399/season/1/episode/2")
    }

    func testDecodesSearchResponseFromTypicalTMDBShape() throws {
        let json = """
        {
          "page": 1,
          "results": [
            {"id": 1399, "name": "Game of Thrones", "first_air_date": "2011-04-17"},
            {"id": 79501, "name": "Game of Thrones (2019)", "first_air_date": null}
          ],
          "total_results": 2
        }
        """.data(using: .utf8)!

        struct SearchResponse: Decodable { let results: [TMDBMetadataFetcher.ShowResult] }
        let response = try TMDBMetadataFetcher.decode(SearchResponse.self, from: json)

        XCTAssertEqual(response.results.count, 2)
        XCTAssertEqual(response.results[0].id, 1399)
        XCTAssertEqual(response.results[0].name, "Game of Thrones")
        XCTAssertEqual(response.results[0].year, "2011")
        XCTAssertNil(response.results[1].firstAirDate)
        XCTAssertNil(response.results[1].year)
    }

    func testDecodesEpisodeResponseFromTypicalTMDBShape() throws {
        let json = """
        {"name": "Winter Is Coming", "season_number": 1, "episode_number": 1, "overview": "..."}
        """.data(using: .utf8)!

        let episode = try TMDBMetadataFetcher.decode(TMDBMetadataFetcher.EpisodeResult.self, from: json)
        XCTAssertEqual(episode.name, "Winter Is Coming")
    }

    func testDecodeThrowsDecodingErrorOnMalformedJSON() {
        let json = "{ not valid json".data(using: .utf8)!
        XCTAssertThrowsError(try TMDBMetadataFetcher.decode(TMDBMetadataFetcher.EpisodeResult.self, from: json)) { error in
            guard case TMDBMetadataFetcher.FetchError.decodingError = error else {
                return XCTFail("expected .decodingError, got \(error)")
            }
        }
    }

    func testSearchMoviesURLOmitsYearQueryItemWhenNil() {
        let url = TMDBMetadataFetcher.searchMoviesURL(name: "The Italian Job", year: nil, apiKey: "KEY123")
        XCTAssertEqual(url.path, "/3/search/movie")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let names = Set(components.queryItems!.map(\.name))
        XCTAssertFalse(names.contains("year"))
    }

    func testSearchMoviesURLIncludesYearQueryItemWhenProvided() {
        let url = TMDBMetadataFetcher.searchMoviesURL(name: "The Italian Job", year: 2003, apiKey: "KEY123")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let queryItems = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        XCTAssertEqual(queryItems["year"], "2003")
        XCTAssertEqual(queryItems["query"], "The Italian Job")
    }

    func testDecodesMovieSearchResponseFromTypicalTMDBShape() throws {
        let json = """
        {
          "page": 1,
          "results": [
            {"id": 33, "title": "The Italian Job", "release_date": "1969-05-28"},
            {"id": 8536, "title": "The Italian Job", "release_date": "2003-05-30"}
          ],
          "total_results": 2
        }
        """.data(using: .utf8)!

        struct SearchResponse: Decodable { let results: [TMDBMetadataFetcher.MovieResult] }
        let response = try TMDBMetadataFetcher.decode(SearchResponse.self, from: json)

        XCTAssertEqual(response.results.count, 2)
        XCTAssertEqual(response.results[0].title, "The Italian Job")
        XCTAssertEqual(response.results[0].year, "1969")
        XCTAssertEqual(response.results[1].year, "2003")
    }

    func testShowResultAndMovieResultConvertToEquivalentCandidateShape() {
        let show = TMDBMetadataFetcher.ShowResult(id: 1399, name: "Game of Thrones", firstAirDate: "2011-04-17")
        XCTAssertEqual(show.asCandidate, TMDBSearchCandidate(id: 1399, name: "Game of Thrones", year: "2011"))

        let movie = TMDBMetadataFetcher.MovieResult(id: 8536, title: "The Italian Job", releaseDate: "2003-05-30")
        XCTAssertEqual(movie.asCandidate, TMDBSearchCandidate(id: 8536, name: "The Italian Job", year: "2003"))
    }
}
