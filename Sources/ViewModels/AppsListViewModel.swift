import Foundation

/// Modeled directly on PS1GameListViewModel, trimmed to this feature's scope
/// -- no artwork/bulk-fetch logic at all, since installed apps don't have
/// cover art (explicitly out of scope per requirements).
@MainActor
final class AppsListViewModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoading = false
    @Published var lastError: IdentifiableError?
    @Published var selectedAppID: InstalledApp.ID?

    @Published var pendingDeleteApp: InstalledApp?
    @Published private(set) var isDeleting = false

    private let service: AppsService

    init(service: AppsService) {
        self.service = service
    }

    var selectedApp: InstalledApp? {
        apps.first { $0.id == selectedAppID }
    }

    func refresh(disk: Disk?) async {
        guard let disk else {
            apps = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            apps = try await service.listInstalledApps(on: disk)
            if let selectedAppID, !apps.contains(where: { $0.id == selectedAppID }) {
                self.selectedAppID = nil
            }
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    func confirmDelete(app: InstalledApp, disk: Disk) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteApp(folderName: app.folderName, on: disk)
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
