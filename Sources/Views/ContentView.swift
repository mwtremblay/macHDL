import SwiftUI
import AppKit

enum GameKind: String, CaseIterable {
    case ps2 = "PS2 Games"
    case ps1 = "PS1 Games"
    case coreApps = "Core Apps"
    case videos = "Movies"
    case tvShows = "TV Shows"
    case userFiles = "User Files"

    /// Core Apps/Movies/TV Shows/User Files have no cover art concept --
    /// always show the "No Artwork" placeholder for those kinds.
    var hasArtwork: Bool {
        switch self {
        case .ps2, .ps1: return true
        case .coreApps, .videos, .tvShows, .userFiles: return false
        }
    }
}

struct ContentView: View {
    @StateObject private var driveListViewModel = DriveListViewModel()
    @StateObject private var gameListViewModel: GameListViewModel
    @StateObject private var ps1GameListViewModel: PS1GameListViewModel
    @StateObject private var coreAppsListViewModel: AppsListViewModel
    @StateObject private var popStarterSystemFilesViewModel: PopStarterSystemFilesViewModel
    @StateObject private var appsListViewModel: AppsListViewModel
    @StateObject private var videoListViewModel: VideoListViewModel
    @StateObject private var tvShowListViewModel: TVShowListViewModel
    @StateObject private var userFilesViewModel: UserFilesViewModel
    @StateObject private var helperRegistrationViewModel: HelperRegistrationViewModel

    @State private var selectedGameKind: GameKind = .ps2
    @State private var showingAddGameSheet = false
    @State private var showingBatchAddGameSheet = false
    @State private var showingAddPS1GameSheet = false
    @State private var showingBatchAddPS1GameSheet = false
    @State private var showingAddCoreAppSheet = false
    @State private var showingAddVideoSheet = false
    @State private var showingAddTVEpisodeSheet = false
    @State private var showingAddUserFileSheet = false
    @State private var showingNewFolderSheet = false
    @State private var showingPopStarterSetupSheet = false
    @State private var showingFreeHDBootSetupSheet = false
    @State private var showingOPLAppsManagerSheet = false
    @State private var infoSheetItem: InfoSheetItem?
    @State private var infoError: IdentifiableError?
    @State private var binaryMissingError: IdentifiableError?
    @State private var fetchPS1ArtworkGame: PS1Game?
    @State private var artworkPreviewImage: NSImage?
    @State private var isLoadingArtworkPreview = false
    @State private var artworkPreviewRefreshNonce = 0

    private let service: HDLDumpService
    private let ps1Service: PS1GameService
    private let freeHDBootService: FreeHDBootService
    private let artworkService: GameArtworkService
    private let artworkFetcher: GameArtworkFetcher
    private let appsService: AppsService
    private let coreAppsService: AppsService
    private let popStarterSystemFilesService: PopStarterSystemFilesService
    private let smsMediaService: SMSMediaService
    private let tvShowService: TVShowService
    private let userFilesService: UserFilesService

    init() {
        let helperClient = HDLDumpHelperClient()
        let service = HDLDumpService(helper: helperClient)
        let ps1Service = PS1GameService(helper: helperClient)
        let freeHDBootService = FreeHDBootService(helper: helperClient, ps1Service: ps1Service)
        let artworkService = GameArtworkService(ps1Service: ps1Service)
        let artworkFetcher = GameArtworkFetcher()
        let appsService = AppsService(ps1Service: ps1Service)
        let coreAppsService = AppsService(ps1Service: ps1Service, destination: .fhdbApps)
        let popStarterSystemFilesService = PopStarterSystemFilesService(ps1Service: ps1Service)
        let smsMediaService = SMSMediaService(ps1Service: ps1Service)
        let tvShowService = TVShowService(ps1Service: ps1Service)
        let userFilesService = UserFilesService(ps1Service: ps1Service)
        self.service = service
        self.ps1Service = ps1Service
        self.freeHDBootService = freeHDBootService
        self.artworkService = artworkService
        self.artworkFetcher = artworkFetcher
        self.appsService = appsService
        self.coreAppsService = coreAppsService
        self.popStarterSystemFilesService = popStarterSystemFilesService
        self.smsMediaService = smsMediaService
        self.tvShowService = tvShowService
        self.userFilesService = userFilesService
        _gameListViewModel = StateObject(wrappedValue: GameListViewModel(service: service, artworkService: artworkService, artworkFetcher: artworkFetcher))
        _ps1GameListViewModel = StateObject(wrappedValue: PS1GameListViewModel(service: ps1Service, artworkService: artworkService, artworkFetcher: artworkFetcher))
        _coreAppsListViewModel = StateObject(wrappedValue: AppsListViewModel(service: coreAppsService))
        _popStarterSystemFilesViewModel = StateObject(wrappedValue: PopStarterSystemFilesViewModel(service: popStarterSystemFilesService))
        _appsListViewModel = StateObject(wrappedValue: AppsListViewModel(service: appsService))
        _videoListViewModel = StateObject(wrappedValue: VideoListViewModel(service: smsMediaService))
        _tvShowListViewModel = StateObject(wrappedValue: TVShowListViewModel(service: tvShowService))
        _userFilesViewModel = StateObject(wrappedValue: UserFilesViewModel(service: userFilesService))
        _helperRegistrationViewModel = StateObject(wrappedValue: HelperRegistrationViewModel(helper: helperClient))
    }

    var body: some View {
        NavigationSplitView {
            DriveSidebarView(viewModel: driveListViewModel)
        } content: {
            detailContent
        } detail: {
            artworkPreviewPane
        }
        .toolbar { toolbarContent }
        // Not threaded through installSheets (unlike every other sheet) --
        // it's reached from the Utilities menu, not a per-GameKind Add
        // button, and appsListViewModel/appsService are already directly
        // available here without growing installSheets' already-long
        // parameter list for a sheet that isn't part of that per-tab
        // pattern. See OPLAppsManagerSheet's own doc comment for why this
        // exists instead of an "Apps" tab.
        .sheet(isPresented: $showingOPLAppsManagerSheet) {
            if let selectedDisk = driveListViewModel.selectedDisk {
                OPLAppsManagerSheet(appsListViewModel: appsListViewModel, appsService: appsService, disk: selectedDisk)
            }
        }
        .installSheets(
            showingAddGameSheet: $showingAddGameSheet,
            showingBatchAddGameSheet: $showingBatchAddGameSheet,
            showingAddPS1GameSheet: $showingAddPS1GameSheet,
            showingBatchAddPS1GameSheet: $showingBatchAddPS1GameSheet,
            showingAddCoreAppSheet: $showingAddCoreAppSheet,
            showingAddVideoSheet: $showingAddVideoSheet,
            showingAddTVEpisodeSheet: $showingAddTVEpisodeSheet,
            showingAddUserFileSheet: $showingAddUserFileSheet,
            showingNewFolderSheet: $showingNewFolderSheet,
            showingPopStarterSetupSheet: $showingPopStarterSetupSheet,
            showingFreeHDBootSetupSheet: $showingFreeHDBootSetupSheet,
            infoSheetItem: $infoSheetItem,
            fetchPS1ArtworkGame: $fetchPS1ArtworkGame,
            service: service,
            ps1Service: ps1Service,
            freeHDBootService: freeHDBootService,
            artworkService: artworkService,
            artworkFetcher: artworkFetcher,
            coreAppsService: coreAppsService,
            smsMediaService: smsMediaService,
            tvShowService: tvShowService,
            gameListViewModel: gameListViewModel,
            ps1GameListViewModel: ps1GameListViewModel,
            coreAppsListViewModel: coreAppsListViewModel,
            videoListViewModel: videoListViewModel,
            tvShowListViewModel: tvShowListViewModel,
            userFilesViewModel: userFilesViewModel,
            helperRegistrationViewModel: helperRegistrationViewModel,
            selectedDisk: driveListViewModel.selectedDisk
        )
        .deleteAlerts(
            gameListViewModel: gameListViewModel,
            ps1GameListViewModel: ps1GameListViewModel,
            coreAppsListViewModel: coreAppsListViewModel,
            videoListViewModel: videoListViewModel,
            tvShowListViewModel: tvShowListViewModel,
            userFilesViewModel: userFilesViewModel,
            selectedDisk: driveListViewModel.selectedDisk
        )
        .errorAlerts(
            gameListViewModel: gameListViewModel,
            ps1GameListViewModel: ps1GameListViewModel,
            coreAppsListViewModel: coreAppsListViewModel,
            popStarterSystemFilesViewModel: popStarterSystemFilesViewModel,
            videoListViewModel: videoListViewModel,
            tvShowListViewModel: tvShowListViewModel,
            userFilesViewModel: userFilesViewModel,
            driveListViewModel: driveListViewModel,
            helperRegistrationViewModel: helperRegistrationViewModel,
            infoError: $infoError,
            binaryMissingError: $binaryMissingError
        )
        .task {
            do {
                _ = try BundledBinaryLocator.resolve(name: "hdl_dump", subdirectory: "hdl-dump-bin")
            } catch {
                binaryMissingError = IdentifiableError(underlying: error)
            }
            helperRegistrationViewModel.registerIfNeeded()
            await driveListViewModel.refresh()
        }
        .onChange(of: driveListViewModel.selectedDiskID) {
            Task {
                let disk = driveListViewModel.selectedDisk
                async let ps2 = gameListViewModel.refresh(disk: disk)
                async let ps1 = ps1GameListViewModel.refresh(disk: disk)
                async let coreApps = coreAppsListViewModel.refresh(disk: disk)
                async let popStarterSystemFiles = popStarterSystemFilesViewModel.refresh(disk: disk)
                async let videos = videoListViewModel.refresh(disk: disk)
                async let tvShows = tvShowListViewModel.refresh(disk: disk)
                async let userFiles = userFilesViewModel.refresh(disk: disk)
                _ = await (ps2, ps1, coreApps, popStarterSystemFiles, videos, tvShows, userFiles)
            }
        }
        .onChange(of: fetchPS1ArtworkGame) { oldValue, newValue in
            // Sheet dismissed (item -> nil) -- refresh the preview
            // regardless of whether the fetch succeeded, same as the PS2
            // button's unconditional bump above.
            if oldValue != nil && newValue == nil {
                artworkPreviewRefreshNonce += 1
            }
        }
        .onChange(of: selectedGameKind) {
            if selectedGameKind == .ps1 {
                Task { await ps1GameListViewModel.refresh(disk: driveListViewModel.selectedDisk) }
            } else if selectedGameKind == .coreApps {
                Task {
                    async let coreApps = coreAppsListViewModel.refresh(disk: driveListViewModel.selectedDisk)
                    async let popStarterSystemFiles = popStarterSystemFilesViewModel.refresh(disk: driveListViewModel.selectedDisk)
                    _ = await (coreApps, popStarterSystemFiles)
                }
            } else if selectedGameKind == .videos {
                Task { await videoListViewModel.refresh(disk: driveListViewModel.selectedDisk) }
            } else if selectedGameKind == .tvShows {
                Task { await tvShowListViewModel.refresh(disk: driveListViewModel.selectedDisk) }
            } else if selectedGameKind == .userFiles {
                Task { await userFilesViewModel.refresh(disk: driveListViewModel.selectedDisk) }
            }
        }
        .onChange(of: gameListViewModel.isFetchingAllArtwork) { wasFetching, isFetching in
            if wasFetching && !isFetching {
                artworkPreviewRefreshNonce += 1
            }
        }
        .onChange(of: ps1GameListViewModel.isFetchingAllArtwork) { wasFetching, isFetching in
            if wasFetching && !isFetching {
                artworkPreviewRefreshNonce += 1
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedGameKind) {
                ForEach(GameKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            switch selectedGameKind {
            case .ps2:
                GameListView(viewModel: gameListViewModel, disk: driveListViewModel.selectedDisk)
            case .ps1:
                PS1GameListView(viewModel: ps1GameListViewModel, disk: driveListViewModel.selectedDisk)
            case .coreApps:
                CoreAppsView(appsViewModel: coreAppsListViewModel, systemFilesViewModel: popStarterSystemFilesViewModel, disk: driveListViewModel.selectedDisk)
            case .videos:
                VideoListView(viewModel: videoListViewModel, disk: driveListViewModel.selectedDisk)
            case .tvShows:
                TVShowListView(viewModel: tvShowListViewModel, disk: driveListViewModel.selectedDisk)
            case .userFiles:
                UserFilesView(viewModel: userFilesViewModel, disk: driveListViewModel.selectedDisk)
            }
        }
    }

    /// Reads previously-installed cover art back off the drive for display
    /// (via GameArtworkService.fetchInstalledPS2/PS1CoverArt, which in turn
    /// uses pfsutil's new `get` command -- added specifically for this,
    /// since nothing before this feature ever needed to read a file's
    /// contents back from a PFS partition). No artwork installed, or any
    /// other failure, is treated as "nothing to show" here, not an alert --
    /// this is a passive preview pane, not a user-initiated action.
    @ViewBuilder
    private var artworkPreviewPane: some View {
        Group {
            if isLoadingArtworkPreview {
                ProgressView()
            } else if let artworkPreviewImage {
                Image(nsImage: artworkPreviewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                ContentUnavailableView("No Artwork", systemImage: "photo", description: Text("No cover art installed for this game."))
            }
        }
        .frame(minWidth: 180)
        .task(id: artworkPreviewSelectionKey) {
            await loadArtworkPreview()
        }
    }

    /// Encodes both the selected game kind and the selected game's identity
    /// so `.task(id:)` reloads exactly when either changes.
    private var artworkPreviewSelectionKey: String {
        switch selectedGameKind {
        case .ps2: return "ps2:\(gameListViewModel.selectedGame?.id ?? ""):\(artworkPreviewRefreshNonce)"
        case .ps1: return "ps1:\(ps1GameListViewModel.selectedGame?.id ?? ""):\(artworkPreviewRefreshNonce)"
        case .coreApps, .videos, .tvShows, .userFiles: return selectedGameKind.rawValue // No cover art -- see GameKind.hasArtwork.
        }
    }

    private func loadArtworkPreview() async {
        artworkPreviewImage = nil
        guard let disk = driveListViewModel.selectedDisk else { return }
        isLoadingArtworkPreview = true
        defer { isLoadingArtworkPreview = false }
        do {
            switch selectedGameKind {
            case .ps2:
                guard let game = gameListViewModel.selectedGame else { return }
                let data = try await artworkService.fetchInstalledPS2CoverArt(gameID: game.startup, on: disk)
                artworkPreviewImage = NSImage(data: data)
            case .ps1:
                guard let game = ps1GameListViewModel.selectedGame else { return }
                let data = try await artworkService.fetchInstalledPS1CoverArt(vcdFilename: game.vcdFilename, on: disk)
                artworkPreviewImage = NSImage(data: data)
            case .coreApps, .videos, .tvShows, .userFiles:
                return // No cover art -- see GameKind.hasArtwork.
            }
        } catch {
            artworkPreviewImage = nil
        }
    }

    private var isDeleteButtonDisabled: Bool {
        switch selectedGameKind {
        case .ps2: return gameListViewModel.selectedGame == nil
        case .ps1: return ps1GameListViewModel.selectedGame == nil
        case .coreApps: return coreAppsListViewModel.selectedApp == nil
        case .videos: return videoListViewModel.selectedVideo == nil
        case .tvShows: return tvShowListViewModel.selectedEpisode == nil
        case .userFiles: return userFilesViewModel.selectedEntry == nil
        }
    }

    private var addButtonLabel: String {
        switch selectedGameKind {
        case .ps2, .ps1: return "Add Game"
        case .coreApps: return "Add Core App"
        case .videos: return "Add Movie"
        case .tvShows: return "Add TV Episode"
        case .userFiles: return "Add File"
        }
    }

    private var deleteButtonLabel: String {
        switch selectedGameKind {
        case .ps2, .ps1: return "Delete Game"
        case .coreApps: return "Delete Core App"
        case .videos: return "Delete Movie"
        case .tvShows: return "Delete Episode"
        case .userFiles: return "Delete"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task {
                    await driveListViewModel.refresh()
                    let disk = driveListViewModel.selectedDisk
                    async let ps2 = gameListViewModel.refresh(disk: disk)
                    async let ps1 = ps1GameListViewModel.refresh(disk: disk)
                    async let coreApps = coreAppsListViewModel.refresh(disk: disk)
                    async let popStarterSystemFiles = popStarterSystemFilesViewModel.refresh(disk: disk)
                    async let videos = videoListViewModel.refresh(disk: disk)
                    async let tvShows = tvShowListViewModel.refresh(disk: disk)
                    async let userFiles = userFilesViewModel.refresh(disk: disk)
                    _ = await (ps2, ps1, coreApps, popStarterSystemFiles, videos, tvShows, userFiles)
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            if selectedGameKind == .ps1 {
                Button {
                    DispatchQueue.main.async {
                        showingPopStarterSetupSheet = true
                    }
                } label: {
                    Label("Set Up PopStarter", systemImage: "gearshape")
                }
                .disabled(driveListViewModel.selectedDisk == nil)
            }

            // Non-game-specific drive operations live here rather than as
            // flat toolbar buttons -- FreeHDBoot setup is the first. Uses
            // the same `.disabled(selectedDisk == nil)` condition as every
            // other button here: that's sufficient on its own because
            // DiskDiscoveryService.listCandidateDisks() doesn't filter by
            // whether a drive is already HDL/APA-formatted, so a brand-new/
            // blank external drive still shows up as a selectable disk.
            Menu {
                Button {
                    DispatchQueue.main.async {
                        showingFreeHDBootSetupSheet = true
                    }
                } label: {
                    Label("Set Up FreeHDBoot…", systemImage: "opticaldiscdrive")
                }
                .disabled(driveListViewModel.selectedDisk == nil)

                // +OPL/APPS/ (homebrew ELFs for OPL's own Apps menu) has no
                // dedicated tab -- unlike Core Apps (PP.FHDB.APPS, its own
                // tab), it's reached here instead. See OPLAppsManagerSheet's
                // doc comment for why.
                Button {
                    DispatchQueue.main.async {
                        showingOPLAppsManagerSheet = true
                    }
                } label: {
                    Label("Manage OPL Apps…", systemImage: "puzzlepiece.extension")
                }
                .disabled(driveListViewModel.selectedDisk == nil)
            } label: {
                Label("Utilities", systemImage: "wrench.and.screwdriver")
            }

            Button {
                // See the Delete Game button's comment: deferred to avoid
                // SwiftUI's "Publishing changes from within view updates"
                // issue with direct state mutation in a toolbar action.
                DispatchQueue.main.async {
                    switch selectedGameKind {
                    case .ps2: showingAddGameSheet = true
                    case .ps1: showingAddPS1GameSheet = true
                    case .coreApps: showingAddCoreAppSheet = true
                    case .videos: showingAddVideoSheet = true
                    case .tvShows: showingAddTVEpisodeSheet = true
                    case .userFiles: showingAddUserFileSheet = true
                    }
                }
            } label: {
                Label(addButtonLabel, systemImage: "plus")
            }
            .disabled(driveListViewModel.selectedDisk == nil)

            if selectedGameKind == .userFiles {
                Button {
                    DispatchQueue.main.async {
                        showingNewFolderSheet = true
                    }
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .disabled(driveListViewModel.selectedDisk == nil)
            }

            if selectedGameKind == .ps2 {
                Button {
                    DispatchQueue.main.async {
                        showingBatchAddGameSheet = true
                    }
                } label: {
                    Label("Batch Add Games", systemImage: "square.stack.3d.up")
                }
                .disabled(driveListViewModel.selectedDisk == nil)
            }

            if selectedGameKind == .ps1 {
                Button {
                    DispatchQueue.main.async {
                        showingBatchAddPS1GameSheet = true
                    }
                } label: {
                    Label("Batch Add Games", systemImage: "square.stack.3d.up")
                }
                .disabled(driveListViewModel.selectedDisk == nil)
            }

            Button(role: .destructive) {
                // Deferred to the next run loop tick: mutating @Published
                // state directly inside a macOS toolbar button's action can
                // trigger SwiftUI's "Publishing changes from within view
                // updates is not allowed" runtime warning (toolbar buttons
                // bridge through AppKit's NSToolbar, unlike regular
                // in-content buttons), which silently breaks the resulting
                // .alert(item:) presentation.
                switch selectedGameKind {
                case .ps2:
                    let game = gameListViewModel.selectedGame
                    DispatchQueue.main.async {
                        gameListViewModel.pendingDeleteGame = game
                    }
                case .ps1:
                    let game = ps1GameListViewModel.selectedGame
                    DispatchQueue.main.async {
                        ps1GameListViewModel.pendingDeleteGame = game
                    }
                case .coreApps:
                    let app = coreAppsListViewModel.selectedApp
                    DispatchQueue.main.async {
                        coreAppsListViewModel.pendingDeleteApp = app
                    }
                case .videos:
                    let video = videoListViewModel.selectedVideo
                    DispatchQueue.main.async {
                        videoListViewModel.pendingDeleteVideo = video
                    }
                case .tvShows:
                    let episode = tvShowListViewModel.selectedEpisode
                    DispatchQueue.main.async {
                        tvShowListViewModel.pendingDeleteEpisode = episode
                    }
                case .userFiles:
                    let entry = userFilesViewModel.selectedEntry
                    DispatchQueue.main.async {
                        userFilesViewModel.pendingDeleteEntry = entry
                    }
                }
            } label: {
                Label(deleteButtonLabel, systemImage: "trash")
            }
            .disabled(isDeleteButtonDisabled)

            if selectedGameKind == .ps2 {
                Button {
                    Task { await showInfo() }
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
                .disabled(gameListViewModel.selectedGame == nil)

                Button {
                    guard let game = gameListViewModel.selectedGame, let disk = driveListViewModel.selectedDisk else { return }
                    Task {
                        await gameListViewModel.fetchArtwork(for: game, on: disk)
                        artworkPreviewRefreshNonce += 1
                    }
                } label: {
                    Label("Fetch Artwork", systemImage: "photo")
                }
                .disabled(gameListViewModel.selectedGame == nil || gameListViewModel.isFetchingArtwork || gameListViewModel.isFetchingAllArtwork)

                Button {
                    guard let disk = driveListViewModel.selectedDisk else { return }
                    gameListViewModel.fetchArtworkForAllGames(on: disk)
                } label: {
                    Label("Fetch All Artwork", systemImage: "photo.stack")
                }
                .disabled(gameListViewModel.games.isEmpty || gameListViewModel.isFetchingArtwork || gameListViewModel.isFetchingAllArtwork)
            }

            if selectedGameKind == .ps1 {
                Button {
                    guard let game = ps1GameListViewModel.selectedGame else { return }
                    DispatchQueue.main.async {
                        fetchPS1ArtworkGame = game
                    }
                } label: {
                    Label("Fetch Artwork", systemImage: "photo")
                }
                .disabled(ps1GameListViewModel.selectedGame == nil)

                Button {
                    guard let disk = driveListViewModel.selectedDisk else { return }
                    ps1GameListViewModel.fetchArtworkForAllGames(on: disk)
                } label: {
                    Label("Fetch All Artwork", systemImage: "photo.stack")
                }
                .disabled(ps1GameListViewModel.games.isEmpty || ps1GameListViewModel.isFetchingAllArtwork)
            }
        }
    }

    private func showInfo() async {
        guard let game = gameListViewModel.selectedGame, let disk = driveListViewModel.selectedDisk else { return }
        do {
            let text = try await service.rawInfo(for: game, on: disk)
            infoSheetItem = InfoSheetItem(text: text)
        } catch {
            infoError = IdentifiableError(underlying: error)
        }
    }
}

private struct InfoSheetItem: Identifiable {
    let id = UUID()
    let text: String
}

private extension View {
    @ViewBuilder
    func installSheets(
        showingAddGameSheet: Binding<Bool>,
        showingBatchAddGameSheet: Binding<Bool>,
        showingAddPS1GameSheet: Binding<Bool>,
        showingBatchAddPS1GameSheet: Binding<Bool>,
        showingAddCoreAppSheet: Binding<Bool>,
        showingAddVideoSheet: Binding<Bool>,
        showingAddTVEpisodeSheet: Binding<Bool>,
        showingAddUserFileSheet: Binding<Bool>,
        showingNewFolderSheet: Binding<Bool>,
        showingPopStarterSetupSheet: Binding<Bool>,
        showingFreeHDBootSetupSheet: Binding<Bool>,
        infoSheetItem: Binding<InfoSheetItem?>,
        fetchPS1ArtworkGame: Binding<PS1Game?>,
        service: HDLDumpService,
        ps1Service: PS1GameService,
        freeHDBootService: FreeHDBootService,
        artworkService: GameArtworkService,
        artworkFetcher: GameArtworkFetcher,
        coreAppsService: AppsService,
        smsMediaService: SMSMediaService,
        tvShowService: TVShowService,
        gameListViewModel: GameListViewModel,
        ps1GameListViewModel: PS1GameListViewModel,
        coreAppsListViewModel: AppsListViewModel,
        videoListViewModel: VideoListViewModel,
        tvShowListViewModel: TVShowListViewModel,
        userFilesViewModel: UserFilesViewModel,
        helperRegistrationViewModel: HelperRegistrationViewModel,
        selectedDisk: Disk?
    ) -> some View {
        self
            .sheet(isPresented: showingAddGameSheet) {
                if let selectedDisk {
                    AddGameSheet(
                        viewModel: InstallGameViewModel(service: service, artworkService: artworkService, artworkFetcher: artworkFetcher),
                        disk: selectedDisk,
                        onInstalled: { await gameListViewModel.refresh(disk: selectedDisk) }
                    )
                }
            }
            .sheet(isPresented: showingBatchAddGameSheet) {
                if let selectedDisk {
                    BatchAddGameSheet(
                        viewModel: BatchInstallGameViewModel(service: service),
                        disk: selectedDisk,
                        existingGameNames: Set(gameListViewModel.games.map(\.name)),
                        onInstalled: { await gameListViewModel.refresh(disk: selectedDisk) }
                    )
                }
            }
            .sheet(isPresented: showingAddPS1GameSheet) {
                if let selectedDisk {
                    AddPS1GameSheet(
                        viewModel: InstallPS1GameViewModel(service: ps1Service, artworkService: artworkService),
                        disk: selectedDisk,
                        onInstalled: { await ps1GameListViewModel.refresh(disk: selectedDisk) }
                    )
                }
            }
            .sheet(isPresented: showingBatchAddPS1GameSheet) {
                if let selectedDisk {
                    BatchAddPS1GameSheet(
                        viewModel: BatchInstallPS1GameViewModel(service: ps1Service, artworkService: artworkService),
                        disk: selectedDisk,
                        existingGameNames: Set(ps1GameListViewModel.games.map(\.displayName)),
                        onInstalled: { await ps1GameListViewModel.refresh(disk: selectedDisk) }
                    )
                }
            }
            .sheet(isPresented: showingAddCoreAppSheet) {
                if let selectedDisk {
                    AddAppSheet(
                        viewModel: AddAppViewModel(service: coreAppsService),
                        disk: selectedDisk,
                        sheetTitle: "Add Core App",
                        helpText: "OPL and SMS are the two \"core\" apps this app bundles and FreeHDBoot's boot menu launches directly. The folder name above is where the app will live directly on the PP.FHDB.APPS partition (e.g. \"OPL\", \"SMS\") -- use the exact existing name to replace one of them, or a new name to add another.",
                        onInstalled: { await coreAppsListViewModel.refresh(disk: selectedDisk) }
                    )
                }
            }
            .sheet(isPresented: showingAddVideoSheet) {
                if let selectedDisk {
                    AddVideoSheet(
                        viewModel: AddVideoViewModel(service: smsMediaService),
                        disk: selectedDisk,
                        onInstalled: { await videoListViewModel.refresh(disk: selectedDisk) }
                    )
                }
            }
            .sheet(isPresented: showingAddTVEpisodeSheet) {
                if let selectedDisk {
                    AddTVEpisodeSheet(
                        viewModel: AddTVEpisodeViewModel(service: tvShowService),
                        disk: selectedDisk,
                        onInstalled: { await tvShowListViewModel.refresh(disk: selectedDisk) }
                    )
                }
            }
            .sheet(isPresented: showingAddUserFileSheet) {
                if let selectedDisk {
                    AddUserFileSheet(
                        viewModel: userFilesViewModel,
                        disk: selectedDisk,
                        onInstalled: { await userFilesViewModel.refresh(disk: selectedDisk) }
                    )
                }
            }
            .sheet(isPresented: showingNewFolderSheet) {
                if let selectedDisk {
                    NewFolderSheet(onCreate: { name in
                        Task {
                            await userFilesViewModel.createFolder(name: name, on: selectedDisk)
                        }
                    })
                }
            }
            // Only handles the NewFolderSheet trigger. NewFolderSheet
            // dismisses itself synchronously before its async createFolder
            // call runs, so by the time pendingPartitionSizePrompt goes
            // non-nil here, no other sheet is active on this view and
            // presenting from here is safe. AddUserFileSheet is the other
            // thing that can set pendingPartitionSizePrompt, but it
            // deliberately stays open across its async addFiles call (to
            // keep showing batch progress/summary) -- presenting the prompt
            // from here at the same time would mean two sibling .sheet
            // modifiers on this same view becoming active simultaneously,
            // which SwiftUI does not support (this used to actually happen:
            // the prompt would fail to appear while a stale AddUserFileSheet
            // sat on screen). So this is suppressed whenever
            // AddUserFileSheet owns the prompt instead -- see its own nested
            // .sheet(item:) for that path. UserFilesViewModel is a
            // persistent @StateObject (unlike AddVideoViewModel etc., which
            // are constructed fresh per sheet presentation and so own this
            // presentation themselves), so observing it from here works the
            // same way.
            .sheet(item: Binding(
                get: { showingAddUserFileSheet.wrappedValue ? nil : userFilesViewModel.pendingPartitionSizePrompt },
                set: { userFilesViewModel.pendingPartitionSizePrompt = $0 }
            )) { request in
                if let selectedDisk {
                    PartitionSizePromptSheet(request: request) { sizeBytes in
                        Task { await userFilesViewModel.confirmPartitionSize(sizeBytes, on: selectedDisk) }
                    }
                }
            }
            .sheet(isPresented: showingPopStarterSetupSheet) {
                if let selectedDisk {
                    PopStarterSetupSheet(viewModel: PopStarterSetupViewModel(service: ps1Service), disk: selectedDisk)
                }
            }
            .sheet(isPresented: showingFreeHDBootSetupSheet) {
                if let selectedDisk {
                    FreeHDBootSetupSheet(viewModel: FreeHDBootSetupViewModel(service: freeHDBootService, ps1Service: ps1Service), disk: selectedDisk)
                }
            }
            .sheet(item: infoSheetItem) { item in
                GameInfoSheet(text: item.text)
            }
            .sheet(item: fetchPS1ArtworkGame) { game in
                if let selectedDisk {
                    FetchPS1ArtworkSheet(
                        viewModel: FetchPS1ArtworkViewModel(artworkService: artworkService, artworkFetcher: artworkFetcher),
                        game: game,
                        disk: selectedDisk
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { helperRegistrationViewModel.needsApproval },
                set: { helperRegistrationViewModel.needsApproval = $0 }
            )) {
                HelperApprovalSheet(
                    onOpenSettings: { helperRegistrationViewModel.openSystemSettings() },
                    onCheckAgain: { helperRegistrationViewModel.refreshStatus() }
                )
            }
    }

    @ViewBuilder
    func deleteAlerts(
        gameListViewModel: GameListViewModel,
        ps1GameListViewModel: PS1GameListViewModel,
        coreAppsListViewModel: AppsListViewModel,
        videoListViewModel: VideoListViewModel,
        tvShowListViewModel: TVShowListViewModel,
        userFilesViewModel: UserFilesViewModel,
        selectedDisk: Disk?
    ) -> some View {
        self
            // Modern presenting-based alert API, not the older item-based
            // Alert(primaryButton:secondaryButton:) initializer -- the
            // latter was observed to silently fail to present on this
            // OS/SwiftUI version (button click had no visible effect at
            // all), while the simpler single-button .alert(item:) alerts
            // elsewhere in this file worked fine. This form is the
            // actively-maintained API.
            .alert(
                "Delete \"\(gameListViewModel.pendingDeleteGame?.name ?? "")\"?",
                isPresented: Binding(
                    get: { gameListViewModel.pendingDeleteGame != nil },
                    set: { isPresented in
                        if !isPresented { gameListViewModel.pendingDeleteGame = nil }
                    }
                ),
                presenting: gameListViewModel.pendingDeleteGame
            ) { game in
                // Use the `game` snapshot SwiftUI hands us here (captured at
                // presentation time), not a live re-read of
                // pendingDeleteGame -- the alert's own dismissal races with
                // clearing that published property (see isPresented's
                // setter above), so re-reading it inside confirmDelete()
                // could observe nil and silently no-op.
                Button("Delete", role: .destructive) {
                    guard let selectedDisk else { return }
                    Task { await gameListViewModel.confirmDelete(game: game, disk: selectedDisk) }
                }
                Button("Cancel", role: .cancel) {
                    gameListViewModel.pendingDeleteGame = nil
                }
            } message: { _ in
                Text("This permanently removes the partition from \(selectedDisk?.displayName ?? "the drive") and frees its space. This cannot be undone.")
            }
            .alert(
                "Delete \"\(ps1GameListViewModel.pendingDeleteGame?.displayName ?? "")\"?",
                isPresented: Binding(
                    get: { ps1GameListViewModel.pendingDeleteGame != nil },
                    set: { isPresented in
                        if !isPresented { ps1GameListViewModel.pendingDeleteGame = nil }
                    }
                ),
                presenting: ps1GameListViewModel.pendingDeleteGame
            ) { game in
                Button("Delete", role: .destructive) {
                    guard let selectedDisk else { return }
                    Task { await ps1GameListViewModel.confirmDelete(game: game, disk: selectedDisk) }
                }
                Button("Cancel", role: .cancel) {
                    ps1GameListViewModel.pendingDeleteGame = nil
                }
            } message: { _ in
                Text("This permanently removes the game's VCD file from \(selectedDisk?.displayName ?? "the drive"). This cannot be undone.")
            }
            .alert(
                "Delete \"\(coreAppsListViewModel.pendingDeleteApp?.displayName ?? "")\"?",
                isPresented: Binding(
                    get: { coreAppsListViewModel.pendingDeleteApp != nil },
                    set: { isPresented in
                        if !isPresented { coreAppsListViewModel.pendingDeleteApp = nil }
                    }
                ),
                presenting: coreAppsListViewModel.pendingDeleteApp
            ) { app in
                Button("Delete", role: .destructive) {
                    guard let selectedDisk else { return }
                    Task { await coreAppsListViewModel.confirmDelete(app: app, disk: selectedDisk) }
                }
                Button("Cancel", role: .cancel) {
                    coreAppsListViewModel.pendingDeleteApp = nil
                }
            } message: { _ in
                Text("This permanently removes the app's whole folder from \(selectedDisk?.displayName ?? "the drive"). If this is \"OPL\" or \"SMS\", your FreeHDBoot menu shortcut for it will stop working until you reinstall it. This cannot be undone.")
            }
            .alert(
                "Delete \"\(videoListViewModel.pendingDeleteVideo?.displayName ?? "")\"?",
                isPresented: Binding(
                    get: { videoListViewModel.pendingDeleteVideo != nil },
                    set: { isPresented in
                        if !isPresented { videoListViewModel.pendingDeleteVideo = nil }
                    }
                ),
                presenting: videoListViewModel.pendingDeleteVideo
            ) { video in
                Button("Delete", role: .destructive) {
                    guard let selectedDisk else { return }
                    Task { await videoListViewModel.confirmDelete(video: video, disk: selectedDisk) }
                }
                Button("Cancel", role: .cancel) {
                    videoListViewModel.pendingDeleteVideo = nil
                }
            } message: { _ in
                Text("This permanently removes the video file from \(selectedDisk?.displayName ?? "the drive"). This cannot be undone.")
            }
            .alert(
                "Delete \"\(tvShowListViewModel.pendingDeleteEpisode?.displayName ?? "")\"?",
                isPresented: Binding(
                    get: { tvShowListViewModel.pendingDeleteEpisode != nil },
                    set: { isPresented in
                        if !isPresented { tvShowListViewModel.pendingDeleteEpisode = nil }
                    }
                ),
                presenting: tvShowListViewModel.pendingDeleteEpisode
            ) { episode in
                Button("Delete", role: .destructive) {
                    guard let selectedDisk else { return }
                    Task { await tvShowListViewModel.confirmDelete(episode: episode, disk: selectedDisk) }
                }
                Button("Cancel", role: .cancel) {
                    tvShowListViewModel.pendingDeleteEpisode = nil
                }
            } message: { _ in
                Text("This permanently removes the episode file from \(selectedDisk?.displayName ?? "the drive"). This cannot be undone.")
            }
            .alert(
                "Delete \"\(userFilesViewModel.pendingDeleteEntry?.name ?? "")\"?",
                isPresented: Binding(
                    get: { userFilesViewModel.pendingDeleteEntry != nil },
                    set: { isPresented in
                        if !isPresented { userFilesViewModel.pendingDeleteEntry = nil }
                    }
                ),
                presenting: userFilesViewModel.pendingDeleteEntry
            ) { entry in
                Button("Delete", role: .destructive) {
                    guard let selectedDisk else { return }
                    Task { await userFilesViewModel.confirmDelete(entry: entry, disk: selectedDisk) }
                }
                Button("Cancel", role: .cancel) {
                    userFilesViewModel.pendingDeleteEntry = nil
                }
            } message: { entry in
                Text(entry.isDirectory
                    ? "This permanently removes the folder and everything in it from \(selectedDisk?.displayName ?? "the drive"). This cannot be undone."
                    : "This permanently removes the file from \(selectedDisk?.displayName ?? "the drive"). This cannot be undone.")
            }
    }

    @ViewBuilder
    func errorAlerts(
        gameListViewModel: GameListViewModel,
        ps1GameListViewModel: PS1GameListViewModel,
        coreAppsListViewModel: AppsListViewModel,
        popStarterSystemFilesViewModel: PopStarterSystemFilesViewModel,
        videoListViewModel: VideoListViewModel,
        tvShowListViewModel: TVShowListViewModel,
        userFilesViewModel: UserFilesViewModel,
        driveListViewModel: DriveListViewModel,
        helperRegistrationViewModel: HelperRegistrationViewModel,
        infoError: Binding<IdentifiableError?>,
        binaryMissingError: Binding<IdentifiableError?>
    ) -> some View {
        self
            .gameErrorAlerts(gameListViewModel: gameListViewModel, ps1GameListViewModel: ps1GameListViewModel)
            .coreAppsErrorAlerts(coreAppsListViewModel: coreAppsListViewModel, popStarterSystemFilesViewModel: popStarterSystemFilesViewModel)
            .videoErrorAlerts(videoListViewModel: videoListViewModel)
            .tvShowsErrorAlerts(tvShowListViewModel: tvShowListViewModel)
            .userFilesErrorAlerts(userFilesViewModel: userFilesViewModel)
            .miscErrorAlerts(
                driveListViewModel: driveListViewModel,
                helperRegistrationViewModel: helperRegistrationViewModel,
                infoError: infoError,
                binaryMissingError: binaryMissingError
            )
    }

    // Split into two presentations by error content: a dedicated, actionable
    // sheet for the specific "missing Full Disk Access" signature (matches
    // the approach already used for HelperApprovalSheet -- a generic error
    // alert can't offer a "reveal in Finder" button or step-by-step
    // instructions), and a plain alert for everything else.
    @ViewBuilder
    private func gameErrorAlerts(
        gameListViewModel: GameListViewModel,
        ps1GameListViewModel: PS1GameListViewModel
    ) -> some View {
        self
            .sheet(isPresented: Binding(
                get: { gameListViewModel.lastError?.isLikelyMissingFullDiskAccess ?? false },
                set: { isPresented in
                    if !isPresented { gameListViewModel.lastError = nil }
                }
            )) {
                FullDiskAccessSheet(onDismiss: { gameListViewModel.lastError = nil })
            }
            .alert(item: Binding(
                get: { gameListViewModel.lastError?.isLikelyMissingFullDiskAccess == true ? nil : gameListViewModel.lastError },
                set: { gameListViewModel.lastError = $0 }
            )) { error in
                Alert(title: Text("hdl_dump Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
            .sheet(isPresented: Binding(
                get: { ps1GameListViewModel.lastError?.isLikelyMissingFullDiskAccess ?? false },
                set: { isPresented in
                    if !isPresented { ps1GameListViewModel.lastError = nil }
                }
            )) {
                FullDiskAccessSheet(onDismiss: { ps1GameListViewModel.lastError = nil })
            }
            .alert(item: Binding(
                get: { ps1GameListViewModel.lastError?.isLikelyMissingFullDiskAccess == true ? nil : ps1GameListViewModel.lastError },
                set: { ps1GameListViewModel.lastError = $0 }
            )) { error in
                Alert(title: Text("pfsshell Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
    }

    // Its own small chained method -- see videoErrorAlerts' doc comment for
    // why each additional GameKind's error-alert pair gets its own method
    // rather than growing an existing one (a documented compiler-timeout
    // risk in this file).
    @ViewBuilder
    private func coreAppsErrorAlerts(
        coreAppsListViewModel: AppsListViewModel,
        popStarterSystemFilesViewModel: PopStarterSystemFilesViewModel
    ) -> some View {
        self
            .sheet(isPresented: Binding(
                get: { coreAppsListViewModel.lastError?.isLikelyMissingFullDiskAccess ?? false },
                set: { isPresented in
                    if !isPresented { coreAppsListViewModel.lastError = nil }
                }
            )) {
                FullDiskAccessSheet(onDismiss: { coreAppsListViewModel.lastError = nil })
            }
            .alert(item: Binding(
                get: { coreAppsListViewModel.lastError?.isLikelyMissingFullDiskAccess == true ? nil : coreAppsListViewModel.lastError },
                set: { coreAppsListViewModel.lastError = $0 }
            )) { error in
                Alert(title: Text("Core Apps Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
            .sheet(isPresented: Binding(
                get: { popStarterSystemFilesViewModel.lastError?.isLikelyMissingFullDiskAccess ?? false },
                set: { isPresented in
                    if !isPresented { popStarterSystemFilesViewModel.lastError = nil }
                }
            )) {
                FullDiskAccessSheet(onDismiss: { popStarterSystemFilesViewModel.lastError = nil })
            }
            .alert(item: Binding(
                get: { popStarterSystemFilesViewModel.lastError?.isLikelyMissingFullDiskAccess == true ? nil : popStarterSystemFilesViewModel.lastError },
                set: { popStarterSystemFilesViewModel.lastError = $0 }
            )) { error in
                Alert(title: Text("PopStarter System Files Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
    }

    // Split from gameErrorAlerts (rather than added to it) -- previously
    // covered Apps + Videos together (both hit "the compiler is unable to
    // type-check this expression in reasonable time" as a single chain), but
    // Apps' half moved into OPLAppsManagerSheet's own self-contained alerts
    // once the Apps tab was removed -- this method now covers Videos alone.
    // Each additional GameKind's error-alert pair should get its own small
    // chained method like this one, not grow an existing one further.
    @ViewBuilder
    private func videoErrorAlerts(
        videoListViewModel: VideoListViewModel
    ) -> some View {
        self
            .sheet(isPresented: Binding(
                get: { videoListViewModel.lastError?.isLikelyMissingFullDiskAccess ?? false },
                set: { isPresented in
                    if !isPresented { videoListViewModel.lastError = nil }
                }
            )) {
                FullDiskAccessSheet(onDismiss: { videoListViewModel.lastError = nil })
            }
            .alert(item: Binding(
                get: { videoListViewModel.lastError?.isLikelyMissingFullDiskAccess == true ? nil : videoListViewModel.lastError },
                set: { videoListViewModel.lastError = $0 }
            )) { error in
                Alert(title: Text("Videos Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
    }

    // Its own chained method -- see videoErrorAlerts' doc comment for why
    // each additional GameKind's error-alert pair gets its own method rather
    // than growing an existing one (a documented compiler-timeout risk in
    // this file).
    @ViewBuilder
    private func tvShowsErrorAlerts(
        tvShowListViewModel: TVShowListViewModel
    ) -> some View {
        self
            .sheet(isPresented: Binding(
                get: { tvShowListViewModel.lastError?.isLikelyMissingFullDiskAccess ?? false },
                set: { isPresented in
                    if !isPresented { tvShowListViewModel.lastError = nil }
                }
            )) {
                FullDiskAccessSheet(onDismiss: { tvShowListViewModel.lastError = nil })
            }
            .alert(item: Binding(
                get: { tvShowListViewModel.lastError?.isLikelyMissingFullDiskAccess == true ? nil : tvShowListViewModel.lastError },
                set: { tvShowListViewModel.lastError = $0 }
            )) { error in
                Alert(title: Text("TV Shows Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
    }

    // Its own chained method, same compiler-timeout-avoidance reasoning as
    // tvShowsErrorAlerts above.
    @ViewBuilder
    private func userFilesErrorAlerts(
        userFilesViewModel: UserFilesViewModel
    ) -> some View {
        self
            .sheet(isPresented: Binding(
                get: { userFilesViewModel.lastError?.isLikelyMissingFullDiskAccess ?? false },
                set: { isPresented in
                    if !isPresented { userFilesViewModel.lastError = nil }
                }
            )) {
                FullDiskAccessSheet(onDismiss: { userFilesViewModel.lastError = nil })
            }
            .alert(item: Binding(
                get: { userFilesViewModel.lastError?.isLikelyMissingFullDiskAccess == true ? nil : userFilesViewModel.lastError },
                set: { userFilesViewModel.lastError = $0 }
            )) { error in
                Alert(title: Text("User Files Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
    }

    @ViewBuilder
    private func miscErrorAlerts(
        driveListViewModel: DriveListViewModel,
        helperRegistrationViewModel: HelperRegistrationViewModel,
        infoError: Binding<IdentifiableError?>,
        binaryMissingError: Binding<IdentifiableError?>
    ) -> some View {
        self
            .alert(item: Binding(
                get: { driveListViewModel.lastError },
                set: { driveListViewModel.lastError = $0 }
            )) { error in
                Alert(title: Text("Drive Discovery Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
            .alert(item: infoError) { error in
                Alert(title: Text("Info Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
            .alert(item: binaryMissingError) { error in
                Alert(title: Text("Setup Problem"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
            .alert(item: Binding(
                get: { helperRegistrationViewModel.registrationFailure },
                set: { helperRegistrationViewModel.registrationFailure = $0 }
            )) { error in
                Alert(title: Text("Setup Problem"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
    }
}
