import Foundation

@MainActor
final class PopStarterSetupViewModel: ObservableObject {
    @Published var popsElfURL: URL?
    @Published var ioprpImageURL: URL?
    /// Optional -- see PS1GameService.installPopStarterSystemFiles.
    @Published var popsPakURL: URL?
    @Published var popsIoxPakURL: URL?
    @Published private(set) var isInstalling = false
    @Published var lastError: IdentifiableError?
    @Published private(set) var didSucceed = false

    private let service: PS1GameService

    init(service: PS1GameService) {
        self.service = service
    }

    var canSubmit: Bool {
        popsElfURL != nil && ioprpImageURL != nil && !isInstalling
    }

    func install(on disk: Disk) async {
        guard let popsElfURL, let ioprpImageURL else { return }
        isInstalling = true
        didSucceed = false
        defer { isInstalling = false }

        do {
            try await service.createCommonPartitionIfNeeded(sizeBytes: PFSDestinationPaths.commonPartitionSizeBytes, on: disk)
            try await service.installPopStarterSystemFiles(
                popsElfURL: popsElfURL,
                ioprpImageURL: ioprpImageURL,
                popsPakURL: popsPakURL,
                popsIoxPakURL: popsIoxPakURL,
                on: disk
            )
            didSucceed = true
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
