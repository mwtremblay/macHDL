import Foundation

/// Drives the Core Apps tab's "PopStarter System Files" section -- the
/// PopStarterSystemFile-based sibling of AppsListViewModel, but per-row
/// replace/remove rather than a selectable list with one toolbar action,
/// since each row is a fixed known slot rather than a user-named entry.
@MainActor
final class PopStarterSystemFilesViewModel: ObservableObject {
    @Published private(set) var installedFilenames: Set<String> = []
    @Published private(set) var isLoading = false
    /// The filename currently being replaced/removed, if any -- lets the
    /// view disable just that row's buttons rather than the whole section.
    @Published private(set) var busyFilename: String?
    @Published var lastError: IdentifiableError?

    private let service: PopStarterSystemFilesService

    init(service: PopStarterSystemFilesService) {
        self.service = service
    }

    func refresh(disk: Disk?) async {
        guard let disk else {
            installedFilenames = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            installedFilenames = try await service.installedFilenames(on: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    func replace(_ file: PopStarterSystemFile, localURL: URL, disk: Disk) async {
        busyFilename = file.id
        defer { busyFilename = nil }
        do {
            try await service.replace(file, localURL: localURL, on: disk)
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    func remove(_ file: PopStarterSystemFile, disk: Disk) async {
        busyFilename = file.id
        defer { busyFilename = nil }
        do {
            try await service.remove(file, on: disk)
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
