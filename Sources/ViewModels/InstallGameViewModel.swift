import Foundation

@MainActor
final class InstallGameViewModel: ObservableObject {
    @Published var sourceURL: URL? {
        didSet { onSourceURLChanged() }
    }
    @Published var name: String = ""
    @Published var isDVD: Bool = true
    @Published private(set) var isInstalling = false
    @Published var lastError: IdentifiableError?
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var progressFraction: Double?
    @Published private(set) var progressText: String = ""

    private let service: HDLDumpService
    private var elapsedTimer: Timer?
    private var startedAt: Date?

    /// Files above this size are assumed to be DVD-sized PS2 images.
    private static let dvdSizeThresholdBytes: Int64 = 700_000_000

    init(service: HDLDumpService) {
        self.service = service
    }

    var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= HDLGame.maxNameLength
    }

    var canSubmit: Bool {
        sourceURL != nil && isNameValid && !isInstalling
    }

    func reset() {
        sourceURL = nil
        name = ""
        isDVD = true
        lastError = nil
        elapsedSeconds = 0
        progressFraction = nil
        progressText = ""
    }

    func install(on disk: Disk, completion: @escaping () async -> Void) async {
        guard let sourceURL else { return }
        isInstalling = true
        progressFraction = nil
        progressText = ""
        startElapsedTimer()
        defer {
            isInstalling = false
            stopElapsedTimer()
        }

        do {
            try await service.installGame(
                sourceISO: sourceURL,
                name: name.trimmingCharacters(in: .whitespaces),
                isDVD: isDVD,
                on: disk,
                onProgress: { [weak self] line in
                    Task { @MainActor in
                        self?.handleProgressLine(line)
                    }
                }
            )
            await completion()
        } catch HDLDumpError.interrupted {
            // User-initiated cancel (in practice the only realistic trigger
            // for RET_INTERRUPTED here) -- quiet, expected dismissal, not an
            // alarming error alert.
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    /// Sends SIGINT to the running install via the daemon. hdl_dump's own
    /// SIGINT handling aborts cleanly without corrupting the drive's
    /// partition table -- see the plan for the verified source references.
    func cancel() async {
        _ = await service.cancelInstall()
    }

    private func handleProgressLine(_ line: String) {
        if let progress = HDLDumpProgressParser.parse(line) {
            progressFraction = progress.fraction
            progressText = progress.detailText ?? line.trimmingCharacters(in: .whitespaces)
        } else {
            progressText = line.trimmingCharacters(in: .whitespaces)
        }
    }

    private func onSourceURLChanged() {
        guard let sourceURL else { return }

        if name.isEmpty {
            name = String(sourceURL.deletingPathExtension().lastPathComponent.prefix(HDLGame.maxNameLength))
        }

        if sourceURL.pathExtension.lowercased() == "cue" {
            // A .cue file's own size (a few hundred bytes of text) isn't
            // representative of the actual image -- but a cue/bin pair is
            // never DVD-sized in any real PS1/PS2-CD scenario, so skip
            // sniffing the referenced .bin's size entirely and just default
            // to CD. The manual override control is still available.
            isDVD = false
        } else if let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
                  let size = attributes[.size] as? Int64 {
            isDVD = size > Self.dvdSizeThresholdBytes
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
