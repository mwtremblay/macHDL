import Foundation

/// Best-effort extraction of Show Name/Season Number/Episode Number/Episode
/// Title from a source video's filename, so AddTVEpisodeViewModel can
/// prefill AddTVEpisodeSheet's fields instead of the user typing them by
/// hand for every episode. Matches the "S01E02"/"1x02" conventions used by
/// virtually every TV rip/release tool (Sonarr, Plex, scene groups). Pure,
/// dependency-free, and directly unit-testable, same reasoning as
/// VideoConverter's own static parse functions.
enum TVFilenameParser {
    struct ParsedEpisode: Equatable {
        var showName: String?
        var seasonNumber: Int?
        var episodeNumber: Int?
        var episodeTitle: String?
    }

    /// Matches "S01E02"/"s1e2" (1-2 digit season, 1-3 digit episode) or the
    /// older "1x02" scene convention -- both require a `.`/`-`/`_`/space
    /// separator on the show-name side so the marker doesn't false-positive
    /// mid-word. Everything before the marker is the show name; everything
    /// after (if any) is the episode title, still carrying whatever release
    /// tags/extension follow it -- stripped separately by
    /// stripReleaseTag/deletingPathExtension.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?ix) ^(?<show>.*?) [\.\-_\s]+ (?: s(?<season1>\d{1,2})e(?<episode1>\d{1,3}) | (?<season2>\d{1,2})x(?<episode2>\d{2,3}) ) (?: [\.\-_\s]+ (?<title>.*) )? $"#,
        options: [.allowCommentsAndWhitespace]
    )

    /// Release-tag tokens scene/rip tools commonly append after the episode
    /// title -- stripped along with everything after the first one, since
    /// none of it is part of the actual title. Matched as a whole word (not
    /// a substring) so a title legitimately containing e.g. "1080p" mid-
    /// sentence isn't mistaken for a quality tag.
    private static let releaseTagPattern = try! NSRegularExpression(
        pattern: #"(?ix) \b(1080p|720p|480p|2160p|4k|web-?dl|webrip|hdtv|bluray|brrip|dvdrip|x264|x265|h264|h265|hevc|aac|ac3|dts) \b .*$"#,
        options: [.allowCommentsAndWhitespace]
    )

    static func parse(filename: String) -> ParsedEpisode {
        let base = (filename as NSString).deletingPathExtension
        let fullRange = NSRange(base.startIndex..., in: base)
        guard let match = pattern.firstMatch(in: base, range: fullRange) else {
            return ParsedEpisode()
        }

        func group(_ name: String) -> String? {
            let range = match.range(withName: name)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: base) else { return nil }
            return String(base[swiftRange])
        }

        let seasonNumber = group("season1").flatMap(Int.init) ?? group("season2").flatMap(Int.init)
        let episodeNumber = group("episode1").flatMap(Int.init) ?? group("episode2").flatMap(Int.init)

        return ParsedEpisode(
            showName: FilenameCleaning.cleaned(group("show")),
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: FilenameCleaning.cleaned(stripReleaseTag(from: group("title")))
        )
    }

    private static func stripReleaseTag(from title: String?) -> String? {
        guard let title else { return nil }
        let range = NSRange(title.startIndex..., in: title)
        guard let match = releaseTagPattern.firstMatch(in: title, range: range), let swiftRange = Range(match.range, in: title) else {
            return title
        }
        return String(title[title.startIndex..<swiftRange.lowerBound])
    }
}
