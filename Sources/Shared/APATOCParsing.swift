import Foundation

/// Parses `hdl_dump toc`'s output -- lives in Sources/Shared (not
/// Sources/Services) specifically so both the main app target and the
/// privileged helper daemon target (mac-hdl-gui-helper, which does not
/// compile Sources/Services -- see project.yml) can use the exact same
/// parsing logic, rather than each maintaining their own copy that could
/// silently drift out of sync. The daemon's own post-`initialize`
/// verification (HDLDumpHelperService.initializeBlankAPADisk) specifically
/// gates whether a whole-disk destructive operation is allowed to report
/// success, so this logic being correct in both places matters.
enum APATOCParsing {
    /// Extracts exact partition names from `hdl_dump toc`'s output. Confirmed
    /// directly from source (`hdl_dump.c`'s `show_apa_slice2`): every real
    /// partition line matches `"0x%04x %06lx00%c%c %2lu %5luMB %s\n"` --
    /// always starts with `0x` (the hex type field), always ends with the
    /// name (`part->id`) as the last, space-preceded field with nothing
    /// after it. Filtering to `0x`-prefixed lines (skipping the header row
    /// and the trailing "Total slice size: ..." summary line) before taking
    /// each line's last token means a blind substring search
    /// (`output.contains(name)`, used before this fix) is no longer needed
    /// -- which mattered because `__.POPS1` and `__.POPS10` share a prefix,
    /// so `output.contains("__.POPS1")` would wrongly also match a line
    /// that's actually `__.POPS10`. Taking each partition line's own last
    /// token doesn't have that problem.
    static func partitionNames(inTOCOutput output: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("0x") else { return nil }
            return line.split(separator: " ").last.map(String.init)
        })
    }

    static func output(_ output: String, containsPartitionNamed name: String) -> Bool {
        partitionNames(inTOCOutput: output).contains(name)
    }
}
