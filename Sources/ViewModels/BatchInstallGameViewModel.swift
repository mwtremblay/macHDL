import Foundation

/// Installs multiple PS2 disc images in one action -- picks up several
/// files from a single multi-select file picker, derives each one's name/
/// media-type the same way the single-game `InstallGameViewModel` does, and
/// skips any file whose derived name matches a game already on the drive
/// (or already installed earlier in this same batch). No per-file name
/// editing or DVD/CD override, unlike the single-game flow -- that's the
/// deliberate simplicity tradeoff of a "batch" action; use Add Game
/// individually for fine control over a specific file.
///
/// Deliberately does NOT auto-fetch cover art per installed game (unlike
/// InstallGameViewModel, which does) -- doing that inline here would mean
/// up to N extra network round-trips stacked on top of what can already be
/// a long-running batch of large ISO installs. "Fetch All Artwork" already
/// covers backfilling art for anything installed here, on the next run.
@MainActor
final class BatchInstallGameViewModel: ObservableObject {
    @Published var pendingSourceURLs: [URL] = []
    @Published private(set) var isInstalling = false
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentItemName: String = ""
    @Published private(set) var progressFraction: Double?
    @Published private(set) var progressText: String = ""
    @Published private(set) var elapsedSeconds: Int = 0
    @Published var summary: String?
    @Published var lastError: IdentifiableError?

    /// Matches InstallGameViewModel's own threshold -- kept in sync
    /// deliberately, not re-derived independently.
    private static let dvdSizeThresholdBytes: Int64 = 700_000_000

    private let service: HDLDumpService
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var cancelRequested = false

    init(service: HDLDumpService) {
        self.service = service
    }

    var totalCount: Int { pendingSourceURLs.count }
    var canSubmit: Bool { !pendingSourceURLs.isEmpty && !isInstalling }

    var progressSummaryText: String {
        guard totalCount > 0 else { return "" }
        return "Installing \(currentIndex) of \(totalCount): \(currentItemName)"
    }

    func reset() {
        pendingSourceURLs = []
        summary = nil
        lastError = nil
        currentIndex = 0
        currentItemName = ""
        progressFraction = nil
        progressText = ""
        elapsedSeconds = 0
    }

    func cancel() {
        cancelRequested = true
        Task { _ = await service.cancelInstall() }
    }

    /// `existingGameNames` should be the current drive's game list at the
    /// time this is called (`gameListViewModel.games.map(\.name)`) --
    /// caller's responsibility, since this view model has no reference to
    /// the game list itself.
    func installAll(existingGameNames: Set<String>, on disk: Disk, completion: @escaping () async -> Void) async {
        guard canSubmit else { return }
        isInstalling = true
        summary = nil
        cancelRequested = false
        startElapsedTimer()
        defer {
            isInstalling = false
            stopElapsedTimer()
            progressText = ""
            progressFraction = nil
            currentItemName = ""
        }

        var knownNames = existingGameNames
        var installedCount = 0
        var skippedCount = 0
        var failedCount = 0

        for (index, url) in pendingSourceURLs.enumerated() {
            if cancelRequested { break }
            currentIndex = index + 1
            let name = Self.deriveName(from: url)
            currentItemName = name
            progressFraction = nil
            progressText = ""

            guard !knownNames.contains(name) else {
                skippedCount += 1
                continue
            }

            let isDVD = Self.deriveIsDVD(from: url)
            do {
                try await service.installGame(
                    sourceISO: url,
                    name: name,
                    isDVD: isDVD,
                    on: disk,
                    onProgress: { [weak self] line in
                        Task { @MainActor in
                            self?.handleProgressLine(line)
                        }
                    }
                )
                installedCount += 1
                // Guards against two selected files deriving the same name
                // within this same batch (e.g. accidental duplicate picks).
                knownNames.insert(name)
            } catch HDLDumpError.interrupted {
                break // user-initiated cancel mid-install
            } catch {
                failedCount += 1
            }
        }

        await completion()

        var summaryText = "Installed \(installedCount), skipped \(skippedCount) (already installed)"
        if failedCount > 0 {
            summaryText += ", \(failedCount) failed"
        }
        if cancelRequested {
            summaryText += " (cancelled)"
        }
        summary = summaryText
    }

    /// Mirrors InstallGameViewModel.onSourceURLChanged's name derivation
    /// exactly -- same truncation to HDLGame.maxNameLength.
    private static func deriveName(from url: URL) -> String {
        String(url.deletingPathExtension().lastPathComponent.prefix(HDLGame.maxNameLength))
    }

    /// Mirrors InstallGameViewModel.onSourceURLChanged's DVD/CD heuristic
    /// exactly: a .cue file is never DVD-sized in any real PS1/PS2-CD
    /// scenario, otherwise fall back to a file-size threshold.
    private static func deriveIsDVD(from url: URL) -> Bool {
        if url.pathExtension.lowercased() == "cue" {
            return false
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            return size > dvdSizeThresholdBytes
        }
        return true
    }

    private func handleProgressLine(_ line: String) {
        if let progress = HDLDumpProgressParser.parse(line) {
            progressFraction = progress.fraction
            progressText = progress.detailText ?? line.trimmingCharacters(in: .whitespaces)
        } else {
            progressText = line.trimmingCharacters(in: .whitespaces)
        }
    }

    private func startElapsedTimer() {
        startedAt = Date()
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            Task { @MainActor in
                self.elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        startedAt = nil
    }
}
