import Foundation

/// Best-effort extraction of Title/Year from a source video's filename, so
/// AddVideoViewModel can prefill AddVideoSheet's fields instead of the user
/// typing them by hand for every movie. Mirrors TVFilenameParser, but
/// simpler: movie filenames put a release year where TV puts `SxxExx` (e.g.
/// "Movie.Name.2019.1080p.BluRay.x264-GROUP.mkv", "Movie Name (2019).mkv"),
/// and unlike TV's episode title there's no title-shaped text *after* the
/// marker worth keeping -- whatever follows the year is quality/group tags,
/// discarded outright rather than needing TVFilenameParser's separate
/// release-tag-stripping step.
enum MovieFilenameParser {
    struct ParsedMovie: Equatable {
        var title: String?
        var year: Int?
    }

    /// A 4-digit year starting with 19 or 20, optionally wrapped in
    /// parentheses, preceded by a `.`/`-`/`_`/space/`(` separator so it
    /// can't false-positive mid-word. Everything before it is the title;
    /// everything after (resolution, codec, release group, extension) is
    /// discarded.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?x) ^(?<title>.*?) [\.\-_\s\(]+ (?<year>(?:19|20)\d{2}) \)? (?:[\.\-_\s].*)? $"#,
        options: [.allowCommentsAndWhitespace]
    )

    static func parse(filename: String) -> ParsedMovie {
        let base = (filename as NSString).deletingPathExtension
        let fullRange = NSRange(base.startIndex..., in: base)
        guard let match = pattern.firstMatch(in: base, range: fullRange) else {
            return ParsedMovie()
        }

        func group(_ name: String) -> String? {
            let range = match.range(withName: name)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: base) else { return nil }
            return String(base[swiftRange])
        }

        return ParsedMovie(
            title: FilenameCleaning.cleaned(group("title")),
            year: group("year").flatMap(Int.init)
        )
    }
}
