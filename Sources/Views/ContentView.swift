import SwiftUI

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
    @State private var showingAddPS1GameSheet = false
    @State private var showingPopStarterSetupSheet = false
    @State private var infoSheetItem: InfoSheetItem?
    @State private var infoError: IdentifiableError?
    @State private var binaryMissingError: IdentifiableError?

    private let service: HDLDumpService
    private let ps1Service: PS1GameService

    init() {
        let helperClient = HDLDumpHelperClient()
        let service = HDLDumpService(helper: helperClient)
        let ps1Service = PS1GameService(helper: helperClient)
        self.service = service
        self.ps1Service = ps1Service
        _gameListViewModel = StateObject(wrappedValue: GameListViewModel(service: service))
        _ps1GameListViewModel = StateObject(wrappedValue: PS1GameListViewModel(service: ps1Service))
        _helperRegistrationViewModel = StateObject(wrappedValue: HelperRegistrationViewModel(helper: helperClient))
    }

    var body: some View {
        NavigationSplitView {
            DriveSidebarView(viewModel: driveListViewModel)
        } detail: {
            detailContent
        }
        .toolbar { toolbarContent }
        .installSheets(
            showingAddGameSheet: $showingAddGameSheet,
            showingAddPS1GameSheet: $showingAddPS1GameSheet,
            showingPopStarterSetupSheet: $showingPopStarterSetupSheet,
            infoSheetItem: $infoSheetItem,
            service: service,
            ps1Service: ps1Service,
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
                _ = try HDLDumpBinaryLocator.resolve()
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
        .onChange(of: selectedGameKind) {
            if selectedGameKind == .ps1 {
                Task { await ps1GameListViewModel.refresh(disk: driveListViewModel.selectedDisk) }
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
        showingAddPS1GameSheet: Binding<Bool>,
        showingPopStarterSetupSheet: Binding<Bool>,
        infoSheetItem: Binding<InfoSheetItem?>,
        service: HDLDumpService,
        ps1Service: PS1GameService,
        gameListViewModel: GameListViewModel,
        ps1GameListViewModel: PS1GameListViewModel,
        helperRegistrationViewModel: HelperRegistrationViewModel,
        selectedDisk: Disk?
    ) -> some View {
        self
            .sheet(isPresented: showingAddGameSheet) {
                if let selectedDisk {
                    AddGameSheet(
                        viewModel: InstallGameViewModel(service: service),
                        disk: selectedDisk,
                        onInstalled: { await gameListViewModel.refresh(disk: selectedDisk) }
                    )
                }
            }
            .sheet(isPresented: showingAddPS1GameSheet) {
                if let selectedDisk {
                    AddPS1GameSheet(
                        viewModel: InstallPS1GameViewModel(service: ps1Service),
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
