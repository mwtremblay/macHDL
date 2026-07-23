import Foundation

/// Shared by TVFilenameParser and MovieFilenameParser -- both extract a
/// title from a piece of a scene/rip filename and need the same normalizing
/// step before it's fit to prefill a text field.
enum FilenameCleaning {
    /// "Show.Name_Here" -> "Show Name Here" -- dots/underscores are the two
    /// most common word separators in scene/rip filenames, standing in for
    /// spaces most filesystems/tools historically avoided. Also collapses
    /// runs of whitespace left behind by stripping a release tag/marker, and
    /// trims a leftover leading/trailing separator (e.g. a trailing "-" when
    /// the title was empty after tag-stripping).
    static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var value = raw.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " -").union(.whitespaces))
        return value.isEmpty ? nil : value
    }
}
