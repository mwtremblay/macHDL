import XCTest
@testable import macHDL

/// Pure-function tests for VideoConverter -- no real ffmpeg invocation, no
/// HDD/XPC dependency. The argv mapping is the single most valuable thing to
/// pin down here: it's easy to silently regress, and a wrong fourcc/container
/// choice would fail on real hardware in a way this app can't detect on its
/// own (see VideoConverter's doc comment re: the msmpeg4v2/MP42 example that
/// looked plausible but was confirmed wrong against SMS's own source).
final class VideoConverterTests: XCTestCase {
    private let inputURL = URL(fileURLWithPath: "/tmp/input.mp4")
    private let outputURL = URL(fileURLWithPath: "/tmp/output.avi")

    func testArgumentsUseXvidTaggedMpeg4AndLibmp3lame() {
        let args = VideoConverter.arguments(inputURL: inputURL, outputURL: outputURL, profile: .sdNTSC)
        XCTAssertEqual(args[0], "-i")
        XCTAssertEqual(args[1], inputURL.path)
        XCTAssertTrue(args.contains("mpeg4"))
        XCTAssertTrue(args.contains("xvid"))
        XCTAssertTrue(args.contains("libmp3lame"))
        XCTAssertTrue(args.contains("avi"))
        XCTAssertEqual(args.last, outputURL.path)
    }

    func testSDNTSCProfileIs640x480At2997() {
        let args = VideoConverter.arguments(inputURL: inputURL, outputURL: outputURL, profile: .sdNTSC)
        XCTAssertTrue(args.contains("scale=640:480:force_original_aspect_ratio=decrease,pad=640:480:(ow-iw)/2:(oh-ih)/2,setsar=1"))
        XCTAssertTrue(args.contains("29.97"))
    }

    func testSDPALProfileIs720x576At25() {
        let args = VideoConverter.arguments(inputURL: inputURL, outputURL: outputURL, profile: .sdPAL)
        XCTAssertTrue(args.contains("scale=720:576:force_original_aspect_ratio=decrease,pad=720:576:(ow-iw)/2:(oh-ih)/2,setsar=1"))
        XCTAssertTrue(args.contains("25"))
    }

    func testWidescreen720pProfileIs1024x576() {
        let args = VideoConverter.arguments(inputURL: inputURL, outputURL: outputURL, profile: .widescreen720p)
        XCTAssertTrue(args.contains("scale=1024:576:force_original_aspect_ratio=decrease,pad=1024:576:(ow-iw)/2:(oh-ih)/2,setsar=1"))
    }

    func testWidescreenFullHDProfileIs1024x920() {
        let args = VideoConverter.arguments(inputURL: inputURL, outputURL: outputURL, profile: .widescreenFullHD)
        XCTAssertTrue(args.contains("scale=1024:920:force_original_aspect_ratio=decrease,pad=1024:920:(ow-iw)/2:(oh-ih)/2,setsar=1"))
    }

    func testParseProgressSecondsFromTypicalFfmpegLine() {
        let line = "frame=  120 fps= 30 q=5.0 size=    256kB time=00:00:04.00 bitrate= 524.3kbits/s speed=1.2x"
        XCTAssertEqual(VideoConverter.parseProgressSeconds(fromLine: line), 4.0)
    }

    func testParseProgressSecondsReturnsNilWithoutTimeField() {
        XCTAssertNil(VideoConverter.parseProgressSeconds(fromLine: "ffmpeg version 8.1.2 Copyright (c) 2000-2025"))
    }

    func testParseDurationSecondsFromBannerLine() throws {
        let line = "  Duration: 00:03:24.51, start: 0.000000, bitrate: 1234 kb/s"
        let seconds = try XCTUnwrap(VideoConverter.parseDurationSeconds(fromLine: line))
        XCTAssertEqual(seconds, 204.51, accuracy: 0.001)
    }

    func testParseDurationSecondsReturnsNilWithoutDurationField() {
        XCTAssertNil(VideoConverter.parseDurationSeconds(fromLine: "time=00:00:04.00"))
    }

    func testArgumentsOmitMapWithoutAudioTrackIndex() {
        let args = VideoConverter.arguments(inputURL: inputURL, outputURL: outputURL, profile: .sdNTSC)
        XCTAssertFalse(args.contains("-map"))
    }

    /// Regression test: without an explicit `-map`, ffmpeg's own default
    /// audio-stream heuristic picked a French track over an available
    /// English one for a real user's file -- audioTrackIndex must force a
    /// specific stream via `-map 0:a:N`, and never drop the video stream
    /// (`-map 0:v:0`) while doing so.
    func testArgumentsMapSpecificAudioTrackWhenIndexProvided() {
        let args = VideoConverter.arguments(inputURL: inputURL, outputURL: outputURL, profile: .sdNTSC, audioTrackIndex: 1)
        XCTAssertEqual(args[0], "-i")
        XCTAssertEqual(args[1], inputURL.path)
        XCTAssertEqual(args[2], "-map")
        XCTAssertEqual(args[3], "0:v:0")
        XCTAssertEqual(args[4], "-map")
        XCTAssertEqual(args[5], "0:a:1")
    }

    func testParseAudioTracksFindsLanguageTagsInOrder() {
        let output = """
        Input #0, matroska,webm, from 'movie.mkv':
          Duration: 00:03:24.51, start: 0.000000, bitrate: 1234 kb/s
            Stream #0:0: Video: h264 (High), yuv420p, 1920x1080, 24 fps
            Stream #0:1(eng): Audio: aac (LC), 48000 Hz, stereo, fltp, 128 kb/s (default)
            Stream #0:2(fre): Audio: ac3, 48000 Hz, 5.1(side), fltp, 384 kb/s
        """
        let tracks = VideoConverter.parseAudioTracks(fromFFmpegOutput: output)
        XCTAssertEqual(tracks, [
            VideoConverter.AudioTrack(streamIndex: 0, language: "eng"),
            VideoConverter.AudioTrack(streamIndex: 1, language: "fre"),
        ])
    }

    func testParseAudioTracksHandlesMissingLanguageTag() {
        let output = "    Stream #0:1: Audio: mp3, 44100 Hz, stereo, fltp, 128 kb/s"
        let tracks = VideoConverter.parseAudioTracks(fromFFmpegOutput: output)
        XCTAssertEqual(tracks, [VideoConverter.AudioTrack(streamIndex: 0, language: nil)])
    }

    func testParseAudioTracksReturnsEmptyWithNoAudioStreams() {
        let output = "    Stream #0:0: Video: h264 (High), yuv420p, 1920x1080, 24 fps"
        XCTAssertTrue(VideoConverter.parseAudioTracks(fromFFmpegOutput: output).isEmpty)
    }

    func testAudioTrackDisplayNameFallsBackToOrdinalWithoutLanguage() {
        let track = VideoConverter.AudioTrack(streamIndex: 2, language: nil)
        XCTAssertEqual(track.displayName, "Track 3")
    }
}
