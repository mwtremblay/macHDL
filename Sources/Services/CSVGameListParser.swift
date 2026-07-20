import Foundation

/// Parses the output of `hdl_dump hdl_toc <device> --csv`.
///
/// Despite the --csv flag, hdl_dump always prints a header row and a trailing
/// "total ...MB, used ...MB, available ...MB" summary line unconditionally --
/// only the per-game rows in between are semicolon-delimited. See show_hdl_toc()
/// in hdl_dump.c: `"%3s;%7luKB;%*s;%-3s;%-12s;%s\n"` (type;size;flags;dma;startup;name).
enum CSVGameListParser {
    static func parse(stdout: String) -> [HDLGame] {
        let lines = stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var games: [HDLGame] = []
        for line in lines {
            guard line.contains(";") else { continue } // skips header row and summary line
            // Cap at 6 fields: an unexpected ';' inside a game name (rare, but not
            // impossible) folds into the trailing `name` field instead of corrupting
            // the row or silently dropping it.
            let fields = line.split(separator: ";", maxSplits: 5, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count == 6 else { continue }

            let type = fields[0].trimmingCharacters(in: .whitespaces)
            let sizeField = fields[1].trimmingCharacters(in: .whitespaces)
            let flags = fields[2].trimmingCharacters(in: .whitespaces)
            let dma = fields[3].trimmingCharacters(in: .whitespaces)
            let startup = fields[4].trimmingCharacters(in: .whitespaces)
            let name = fields[5].trimmingCharacters(in: .whitespaces)

            let sizeKB = Int(sizeField.replacingOccurrences(of: "KB", with: "")
                .trimmingCharacters(in: .whitespaces)) ?? 0

            games.append(HDLGame(
                isDVD: type == "DVD",
                sizeKB: sizeKB,
                compatFlags: flags,
                dma: dma,
                startup: startup,
                name: name
            ))
        }
        return games
    }
}
