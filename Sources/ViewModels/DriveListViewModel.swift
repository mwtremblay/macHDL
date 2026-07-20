import Foundation

@MainActor
final class DriveListViewModel: ObservableObject {
    @Published private(set) var disks: [Disk] = []
    @Published private(set) var isLoading = false
    @Published var lastError: IdentifiableError?
    @Published var selectedDiskID: Disk.ID?

    private let discovery: DiskDiscoveryService

    init(discovery: DiskDiscoveryService = DiskDiscoveryService()) {
        self.discovery = discovery
    }

    var selectedDisk: Disk? {
        disks.first { $0.id == selectedDiskID }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await discovery.listCandidateDisks()
            disks = found
            if let selectedDiskID, !found.contains(where: { $0.id == selectedDiskID }) {
                self.selectedDiskID = nil
            }
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
