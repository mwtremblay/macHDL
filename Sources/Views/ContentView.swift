import SwiftUI
import AppKit

enum GameKind: String, CaseIterable {
    case ps2 = "PS2 Games"
    case ps1 = "PS1 Games"
}

struct ContentView: View {
    @StateObject private var driveListViewModel = DriveListViewModel()
    @StateObject private var gameListViewModel: GameListViewModel
    @StateObject private var ps1GameListViewModel: PS1GameListViewModel
    @StateObject private var helperRegistrationViewModel: HelperRegistrationViewModel

    @State private var selectedGameKind: GameKind = .ps2
    @State private var showingAddGameSheet = false
    @State private var showingBatchAddGameSheet = false
    @State private var showingAddPS1GameSheet = false
    @State private var showingPopStarterSetupSheet = false
    @State private var infoSheetItem: InfoSheetItem?
    @State private var infoError: IdentifiableError?
    @State private var binaryMissingError: IdentifiableError?
    @State private var fetchPS1ArtworkGame: PS1Game?
    @State private var artworkPreviewImage: NSImage?
    @State private var isLoadingArtworkPreview = false
    @State private var artworkPreviewRefreshNonce = 0

    private let service: HDLDumpService
    private let ps1Service: PS1GameService
    private let artworkService: GameArtworkService
    private let artworkFetcher: GameArtworkFetcher

    init() {
        let helperClient = HDLDumpHelperClient()
        let service = HDLDumpService(helper: helperClient)
        let ps1Service = PS1GameService(helper: helperClient)
        let artworkService = GameArtworkService(ps1Service: ps1Service)
        let artworkFetcher = GameArtworkFetcher()
        self.service = service
        self.ps1Service = ps1Service
        self.artworkService = artworkService
        self.artworkFetcher = artworkFetcher
        _gameListViewModel = StateObject(wrappedValue: GameListViewModel(service: service, artworkService: artworkService, artworkFetcher: artworkFetcher))
        _ps1GameListViewModel = StateObject(wrappedValue: PS1GameListViewModel(service: ps1Service, artworkService: artworkService, artworkFetcher: artworkFetcher))
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
        .installSheets(
            showingAddGameSheet: $showingAddGameSheet,
            showingBatchAddGameSheet: $showingBatchAddGameSheet,
            showingAddPS1GameSheet: $showingAddPS1GameSheet,
            showingPopStarterSetupSheet: $showingPopStarterSetupSheet,
            infoSheetItem: $infoSheetItem,
            fetchPS1ArtworkGame: $fetchPS1ArtworkGame,
            service: service,
            ps1Service: ps1Service,
            artworkService: artworkService,
            artworkFetcher: artworkFetcher,
            gameListViewModel: gameListViewModel,
            ps1GameListViewModel: ps1GameListViewModel,
            helperRegistrationViewModel: helperRegistrationViewModel,
            selectedDisk: driveListViewModel.selectedDisk
        )
        .deleteAlerts(
            gameListViewModel: gameListViewModel,
            ps1GameListViewModel: ps1GameListViewModel,
            selectedDisk: driveListViewModel.selectedDisk
        )
        .errorAlerts(
            gameListViewModel: gameListViewModel,
            ps1GameListViewModel: ps1GameListViewModel,
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
                await gameListViewModel.refresh(disk: driveListViewModel.selectedDisk)
                await ps1GameListViewModel.refresh(disk: driveListViewModel.selectedDisk)
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
            }
        } catch {
            artworkPreviewImage = nil
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task {
                    await driveListViewModel.refresh()
                    await gameListViewModel.refresh(disk: driveListViewModel.selectedDisk)
                    await ps1GameListViewModel.refresh(disk: driveListViewModel.selectedDisk)
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

            Button {
                // See the Delete Game button's comment: deferred to avoid
                // SwiftUI's "Publishing changes from within view updates"
                // issue with direct state mutation in a toolbar action.
                DispatchQueue.main.async {
                    switch selectedGameKind {
                    case .ps2: showingAddGameSheet = true
                    case .ps1: showingAddPS1GameSheet = true
                    }
                }
            } label: {
                Label("Add Game", systemImage: "plus")
            }
            .disabled(driveListViewModel.selectedDisk == nil)

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
                }
            } label: {
                Label("Delete Game", systemImage: "trash")
            }
            .disabled(selectedGameKind == .ps2 ? gameListViewModel.selectedGame == nil : ps1GameListViewModel.selectedGame == nil)

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
        showingPopStarterSetupSheet: Binding<Bool>,
        infoSheetItem: Binding<InfoSheetItem?>,
        fetchPS1ArtworkGame: Binding<PS1Game?>,
        service: HDLDumpService,
        ps1Service: PS1GameService,
        artworkService: GameArtworkService,
        artworkFetcher: GameArtworkFetcher,
        gameListViewModel: GameListViewModel,
        ps1GameListViewModel: PS1GameListViewModel,
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
            .sheet(isPresented: showingPopStarterSetupSheet) {
                if let selectedDisk {
                    PopStarterSetupSheet(viewModel: PopStarterSetupViewModel(service: ps1Service), disk: selectedDisk)
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
    }

    @ViewBuilder
    func errorAlerts(
        gameListViewModel: GameListViewModel,
        ps1GameListViewModel: PS1GameListViewModel,
        driveListViewModel: DriveListViewModel,
        helperRegistrationViewModel: HelperRegistrationViewModel,
        infoError: Binding<IdentifiableError?>,
        binaryMissingError: Binding<IdentifiableError?>
    ) -> some View {
        self
            .gameErrorAlerts(gameListViewModel: gameListViewModel, ps1GameListViewModel: ps1GameListViewModel)
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
