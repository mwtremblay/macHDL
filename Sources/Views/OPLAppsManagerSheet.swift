import SwiftUI

/// Standalone management surface for `+OPL/APPS/` -- homebrew ELFs for
/// OPL's own in-console Apps menu. Not a tab: unlike "Core Apps" (a
/// separate `AppsDestination` on this exact same shared AppsListView/
/// AddAppSheet/AppsService machinery, pointed at `PP.FHDB.APPS` instead --
/// see AppsDestination's doc comment), this used to be its own "Apps" tab
/// but was removed in favor of reaching it from the toolbar's "Utilities"
/// menu, alongside other non-tab-specific drive operations like "Set Up
/// FreeHDBoot…". OPL itself still launches whatever's already installed at
/// `+OPL/APPS/` regardless of this app (its own Apps-menu scanner doesn't
/// go through here) -- this sheet is what lets that content actually be
/// managed (listed/added/deleted) from macHDL.
///
/// Self-contained (owns its own child-sheet state and alerts), matching
/// FreeHDBootSetupSheet's shape, rather than threading through
/// ContentView's tab-switch machinery the way every GameKind case does.
struct OPLAppsManagerSheet: View {
    @ObservedObject var appsListViewModel: AppsListViewModel
    let appsService: AppsService
    let disk: Disk
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddAppSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("OPL Apps on \(disk.displayName)")
                    .font(.title2)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()

            AppsListView(viewModel: appsListViewModel, disk: disk, tabTitle: "OPL Apps")

            HStack {
                Button {
                    showingAddAppSheet = true
                } label: {
                    Label("Add App…", systemImage: "plus")
                }

                Button(role: .destructive) {
                    appsListViewModel.pendingDeleteApp = appsListViewModel.selectedApp
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(appsListViewModel.selectedApp == nil)

                Spacer()
            }
            .padding()
        }
        .frame(width: 480, height: 420)
        .task {
            await appsListViewModel.refresh(disk: disk)
        }
        .sheet(isPresented: $showingAddAppSheet) {
            AddAppSheet(
                viewModel: AddAppViewModel(service: appsService),
                disk: disk,
                onInstalled: { await appsListViewModel.refresh(disk: disk) }
            )
        }
        .alert(
            "Delete \"\(appsListViewModel.pendingDeleteApp?.displayName ?? "")\"?",
            isPresented: Binding(
                get: { appsListViewModel.pendingDeleteApp != nil },
                set: { isPresented in
                    if !isPresented { appsListViewModel.pendingDeleteApp = nil }
                }
            ),
            presenting: appsListViewModel.pendingDeleteApp
        ) { app in
            Button("Delete", role: .destructive) {
                Task { await appsListViewModel.confirmDelete(app: app, disk: disk) }
            }
            Button("Cancel", role: .cancel) {
                appsListViewModel.pendingDeleteApp = nil
            }
        } message: { _ in
            Text("This permanently removes the app's whole folder from \(disk.displayName). This cannot be undone.")
        }
        // Same FDA-sheet/generic-alert split as every other content kind's
        // error handling in this app (see ContentView's gameErrorAlerts) --
        // self-contained here since this sheet owns appsListViewModel's
        // lifecycle for as long as it's presented.
        .sheet(isPresented: Binding(
            get: { appsListViewModel.lastError?.isLikelyMissingFullDiskAccess ?? false },
            set: { isPresented in
                if !isPresented { appsListViewModel.lastError = nil }
            }
        )) {
            FullDiskAccessSheet(onDismiss: { appsListViewModel.lastError = nil })
        }
        .alert(item: Binding(
            get: { appsListViewModel.lastError?.isLikelyMissingFullDiskAccess == true ? nil : appsListViewModel.lastError },
            set: { appsListViewModel.lastError = $0 }
        )) { error in
            Alert(title: Text("Apps Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }
}
