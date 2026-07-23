import Foundation

/// Modeled directly on AppsListViewModel, trimmed to this feature's scope --
/// no artwork/bulk-fetch logic, since videos don't have cover art (out of
/// scope per requirements).
@MainActor
final class VideoListViewModel: ObservableObject {
    @Published private(set) var videos: [VideoFile] = []
    @Published private(set) var isLoading = false
    @Published var lastError: IdentifiableError?
    @Published var selectedVideoID: VideoFile.ID?

    @Published var pendingDeleteVideo: VideoFile?
    @Published private(set) var isDeleting = false

    private let service: SMSMediaService

    init(service: SMSMediaService) {
        self.service = service
    }

    var selectedVideo: VideoFile? {
        videos.first { $0.id == selectedVideoID }
    }

    func refresh(disk: Disk?) async {
        guard let disk else {
            videos = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            videos = try await service.listVideos(on: disk)
            if let selectedVideoID, !videos.contains(where: { $0.id == selectedVideoID }) {
                self.selectedVideoID = nil
            }
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }

    func confirmDelete(video: VideoFile, disk: Disk) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteVideo(video, on: disk)
            await refresh(disk: disk)
        } catch {
            lastError = IdentifiableError(underlying: error)
        }
    }
}
