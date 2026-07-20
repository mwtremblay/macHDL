import Foundation

/// Parses hdl_dump's progress-bar redraw lines (see progress_cb in
/// hdl_dump.c) into a percentage + optional detail text. Two formats
/// depending on whether a time estimate is available:
///   "[===>   ] 15%, 2 min remaining, 12.34 MB/sec         "
///   "15%"
/// Falls back to nil (caller shows the raw line text) if a clean percentage
/// can't be extracted -- never regress to showing less than before.
enum HDLDumpProgressParser {
    struct Progress {
        let fraction: Double     // 0...1
        let detailText: String?  // e.g. "2 min remaining, 12.34 MB/sec"
    }

    static func parse(_ line: String) -> Progress? {
        guard let percentRange = line.range(of: #"\d+%"#, options: .regularExpression) else {
            return nil
        }
        let percentDigits = line[percentRange].dropLast() // strip trailing '%'
        guard let percentValue = Int(percentDigits), (0...100).contains(percentValue) else {
            return nil
        }

        var detail: String?
        if let commaIndex = line[percentRange.upperBound...].firstIndex(of: ",") {
            let trimmed = line[line.index(after: commaIndex)...].trimmingCharacters(in: .whitespaces)
            detail = trimmed.isEmpty ? nil : trimmed
        }

        return Progress(fraction: Double(percentValue) / 100.0, detailText: detail)
    }
}
