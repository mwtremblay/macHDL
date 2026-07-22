import Foundation

/// Converts an arbitrary source video file into an AVI that Simple Media
/// System (SMS) can actually decode, via the vendored ffmpeg. Runs
/// unprivileged, directly from the app (never through the daemon) -- pure
/// local-filesystem conversion, same reasoning as PS1GameConverter/cue2pops.
struct VideoConverter {
    enum ConversionError: Error, LocalizedError {
        case launchFailed(String)
        case conversionFailed(output: String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let message):
                return "Could not launch ffmpeg: \(message)"
            case .conversionFailed(let output):
                // ffmpeg's own log is verbose (codec/muxer banners on every
                // run) -- surface only the last few lines, which is where
                // the actual fatal error always ends up.
                let lines = output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "\n")
                let tail = lines.suffix(5).joined(separator: "\n")
                return tail.isEmpty ? "ffmpeg failed to convert this video." : tail
            }
        }
    }

    /// The four PS2 display targets this app supports converting for. SMS's
    /// own decoder/texture ceiling is roughly 1024x1024 (confirmed against
    /// its real source and community hardware testing -- the highest stable
    /// resolution is about 1024x920), so the two widescreen tiers are
    /// labeled by the display they're tuned for, not a literal 720p/1080p
    /// pixel count SMS cannot actually decode.
    enum Profile: String, CaseIterable, Identifiable {
        case sdNTSC
        case sdPAL
        case widescreen720p
        case widescreenFullHD

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .sdNTSC: return "Standard Definition (NTSC)"
            case .sdPAL: return "Standard Definition (PAL)"
            case .widescreen720p: return "Widescreen — tuned for 720p displays"
            case .widescreenFullHD: return "Widescreen — tuned for Full HD displays"
            }
        }

        var width: Int {
            switch self {
            case .sdNTSC: return 640
            case .sdPAL: return 720
            case .widescreen720p, .widescreenFullHD: return 1024
            }
        }

        var height: Int {
            switch self {
            case .sdNTSC: return 480
            case .sdPAL: return 576
            case .widescreen720p: return 576
            case .widescreenFullHD: return 920
            }
        }

        var frameRate: String {
            self == .sdPAL ? "25" : "29.97"
        }
    }

    /// One decoded audio stream from a source file, as reported by ffmpeg's
    /// own `-i`-only stream analysis. `streamIndex` is the audio-RELATIVE
    /// index (0 = first audio stream, 1 = second, ...), matching what
    /// ffmpeg's own `-map 0:a:N` syntax expects -- not the raw `#0:N`
    /// container-relative index ffmpeg prints, which also counts video/
    /// subtitle streams.
    struct AudioTrack: Identifiable, Equatable {
        let streamIndex: Int
        /// The raw language tag ffmpeg reports (e.g. "eng", "fre") -- an
        /// ISO 639-2 code, not always present (many containers have no
        /// per-track language metadata at all).
        let language: String?

        var id: Int { streamIndex }

        /// Falls back to the raw tag if `Locale` can't resolve it (rare --
        /// mainly obscure ISO 639-2 bibliographic codes), and to a plain
        /// ordinal if the source has no language metadata at all. Always
        /// includes the ordinal so multiple tracks in the same language
        /// (e.g. stereo + 5.1 commentary) stay distinguishable in a picker.
        var displayName: String {
            let ordinal = "Track \(streamIndex + 1)"
            guard let language else { return ordinal }
            let localized = Locale.current.localizedString(forLanguageCode: language) ?? language.uppercased()
            return "\(localized) (\(ordinal))"
        }
    }

    /// Pure function, separated from process-launching so the exact argv per
    /// profile is unit-testable without invoking the real ffmpeg binary.
    /// Codec/container choices (mpeg4/xvid, AVI, libmp3lame) are confirmed
    /// directly against SMS's own source (SMS_Codec.c's fourcc table) -- a
    /// commonly-cited msmpeg4v2/MP42 example elsewhere is WRONG, that fourcc
    /// isn't in SMS's table at all. scale+pad (not a bare scale) letterboxes/
    /// pillarboxes arbitrary source aspect ratios rather than distorting them.
    ///
    /// `audioTrackIndex` (audio-relative, matching AudioTrack.streamIndex)
    /// picks a specific audio track via explicit `-map` -- without it,
    /// ffmpeg's own default stream-selection heuristic picks one, which is
    /// NOT simply "the first" and surprised a user by picking a French track
    /// over an available English one. `nil` preserves that old default
    /// behavior (e.g. for single-audio-track sources, where there's nothing
    /// to pick between).
    static func arguments(inputURL: URL, outputURL: URL, profile: Profile, audioTrackIndex: Int? = nil) -> [String] {
        let w = profile.width
        let h = profile.height
        var args = ["-i", inputURL.path]
        if let audioTrackIndex {
            args += ["-map", "0:v:0", "-map", "0:a:\(audioTrackIndex)"]
        }
        args += [
            "-c:v", "mpeg4",
            "-vtag", "xvid",
            "-q:v", "5",
            "-vf", "scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1",
            "-r", profile.frameRate,
            "-c:a", "libmp3lame",
            "-b:a", "128k",
            "-ar", "44100",
            "-ac", "2",
            "-f", "avi",
            "-y",
            outputURL.path,
        ]
        return args
    }

    /// Finds every audio stream in `inputURL` by parsing ffmpeg's own
    /// `-i`-only stream-analysis banner (printed to stderr before it exits
    /// complaining "At least one output file must be specified", which is
    /// expected here and ignored). There's no bundled ffprobe -- see
    /// Scripts/build-ffmpeg.sh's `--disable-programs --enable-ffmpeg`, which
    /// builds only the `ffmpeg` binary -- so this is the same probe any
    /// one-shot ffmpeg wrapper without ffprobe falls back to.
    func detectAudioTracks(inputURL: URL) async throws -> [AudioTrack] {
        let binary = try BundledBinaryLocator.resolve(name: "ffmpeg", subdirectory: "ffmpeg-bin")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = ["-i", inputURL.path]

            let stderrPipe = Pipe()
            process.standardOutput = Pipe()
            process.standardError = stderrPipe

            let stderrData = SynchronizedDataBuffer()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stderrData.append(chunk)
            }

            process.terminationHandler = { _ in
                // Same "drain synchronously, terminationHandler isn't
                // guaranteed to fire last" reasoning as convert() below.
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let remaining = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty { stderrData.append(remaining) }
                let output = stderrData.text
                // A nonzero exit here is expected (no output file was given
                // to this probe-only invocation) -- the stream list is
                // already fully printed to stderr by the time ffmpeg gets to
                // that error, regardless of exit code.
                continuation.resume(returning: Self.parseAudioTracks(fromFFmpegOutput: output))
            }

            do {
                try process.run()
            } catch {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: ConversionError.launchFailed("\(error)"))
            }
        }
    }

    /// Parses lines like `    Stream #0:2(fre): Audio: ac3, 48000 Hz, ...`
    /// (language tag) or `    Stream #0:1: Audio: mp3, ...` (no tag, common
    /// for containers without per-track metadata). `streamIndex` is assigned
    /// by counting audio lines in the order ffmpeg prints them, which
    /// matches `-map 0:a:N`'s own audio-relative indexing -- not parsed from
    /// the `#0:N` text, which is container-relative and also counts video/
    /// subtitle streams.
    static func parseAudioTracks(fromFFmpegOutput output: String) -> [AudioTrack] {
        var tracks: [AudioTrack] = []
        for line in output.split(separator: "\n") {
            guard let streamRange = line.range(of: "Stream #"),
                  let audioRange = line.range(of: ": Audio:", range: streamRange.upperBound..<line.endIndex)
            else { continue }
            let header = line[streamRange.upperBound..<audioRange.lowerBound]
            var language: String?
            if let openParen = header.firstIndex(of: "("),
               let closeParen = header.firstIndex(of: ")"),
               openParen < closeParen {
                language = String(header[header.index(after: openParen)..<closeParen])
            }
            tracks.append(AudioTrack(streamIndex: tracks.count, language: language))
        }
        return tracks
    }

    /// Converts `inputURL` to `outputURL` at `profile`. Unlike cue2pops,
    /// ffmpeg uses NORMAL exit-code semantics (0 = success). All of ffmpeg's
    /// own progress/log output goes to stderr, not stdout (confirmed by
    /// direct testing), and it redraws its progress line with `\r`, not
    /// `\n` -- `onOutputLine` fires once per complete `\r`/`\n`-delimited
    /// segment, mirroring HelperProcessRunner's LineRedrawBuffer (which
    /// can't be reused directly since it lives in the privileged-helper
    /// target; this is a sibling copy, same as PS1GameConverter's own
    /// private LineBuffer). Callers parse progress out of these raw lines
    /// via parseDurationSeconds/parseProgressSeconds below.
    func convert(
        inputURL: URL,
        outputURL: URL,
        profile: Profile,
        audioTrackIndex: Int? = nil,
        onOutputLine: ((String) -> Void)? = nil
    ) async throws -> URL {
        let binary = try BundledBinaryLocator.resolve(name: "ffmpeg", subdirectory: "ffmpeg-bin")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = Self.arguments(inputURL: inputURL, outputURL: outputURL, profile: profile, audioTrackIndex: audioTrackIndex)

            let stderrPipe = Pipe()
            process.standardOutput = Pipe() // discarded -- ffmpeg's real output goes to stderr
            process.standardError = stderrPipe

            let lineBuffer = LineRedrawBuffer(onLine: onOutputLine)
            let stderrData = SynchronizedDataBuffer()

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stderrData.append(chunk)
                lineBuffer.append(chunk)
            }

            process.terminationHandler = { proc in
                // See HelperProcessRunner's identical fix -- terminationHandler
                // isn't guaranteed to fire after the last readabilityHandler
                // callback, so drain synchronously before reading the buffer.
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let remaining = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty {
                    stderrData.append(remaining)
                    lineBuffer.append(remaining)
                }
                let output = stderrData.text

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: outputURL)
                } else {
                    continuation.resume(throwing: ConversionError.conversionFailed(output: output))
                }
            }

            do {
                try process.run()
            } catch {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: ConversionError.launchFailed("\(error)"))
            }
        }
    }

    /// Parses ffmpeg's own progress line, e.g. `frame=  120 fps= 30 q=5.0
    /// size=    256kB time=00:00:04.00 bitrate=...` -> 4.0 seconds. Returns
    /// nil for any line without a `time=` field.
    static func parseProgressSeconds(fromLine line: String) -> Double? {
        guard let range = line.range(of: "time=") else { return nil }
        let token = line[range.upperBound...].prefix { !$0.isWhitespace }
        return parseTimecode(String(token))
    }

    /// Parses ffmpeg's total-duration banner line, e.g. `  Duration:
    /// 00:03:24.51, start: 0.000000, bitrate: 1234 kb/s` -> 204.51. Returns
    /// nil for any line without a `Duration:` field.
    static func parseDurationSeconds(fromLine line: String) -> Double? {
        guard let range = line.range(of: "Duration: ") else { return nil }
        let token = line[range.upperBound...].prefix { $0 != "," }
        return parseTimecode(String(token))
    }

    /// `HH:MM:SS.ss` -> total seconds.
    private static func parseTimecode(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}

/// Splits raw process output on `\r` or `\n` and forwards each complete
/// segment. A sibling copy of HelperProcessRunner.LineRedrawBuffer -- that
/// type lives in the privileged-helper target and isn't reusable here, since
/// this converter runs as a direct, unprivileged app-side subprocess.
private final class LineRedrawBuffer {
    /// Undecoded trailing bytes -- a pipe read can end mid-way through a
    /// multi-byte UTF-8 character; buffering raw Data first means a split
    /// character just waits for its remaining bytes on the next call.
    private var pendingBytes = Data()
    private var pendingText = ""
    private let onLine: ((String) -> Void)?
    private let lock = NSLock()

    init(onLine: ((String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard let onLine else { return }

        lock.lock()
        pendingBytes.append(data)
        guard let (text, consumedByteCount) = Self.decodeLongestValidPrefix(of: pendingBytes) else {
            lock.unlock()
            return
        }
        pendingBytes.removeFirst(consumedByteCount)
        pendingText += text
        let segments = pendingText.split(omittingEmptySubsequences: false) { $0 == "\r" || $0 == "\n" }
        pendingText = segments.last.map(String.init) ?? ""
        let complete = segments.dropLast().map(String.init)
        lock.unlock()

        for segment in complete where !segment.isEmpty {
            onLine(segment)
        }
    }

    private static func decodeLongestValidPrefix(of data: Data) -> (text: String, consumedByteCount: Int)? {
        var candidate = data
        while !candidate.isEmpty {
            if let text = String(data: candidate, encoding: .utf8) {
                return (text, candidate.count)
            }
            candidate.removeLast()
        }
        return nil
    }
}
