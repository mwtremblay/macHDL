import SwiftUI

/// The "Core Apps" tab: the bundled OPL/SMS folder-apps at `PP.FHDB.APPS`
/// (reusing the generic AppsListView, same as the "Apps" tab) on top, and
/// the fixed `__common/POPS/` system files below -- two structurally
/// different destinations, so two separate sections/viewmodels rather than
/// one generic list. See AppsDestination/PopStarterSystemFile's doc comments
/// for why they're never merged into a single model.
struct CoreAppsView: View {
    @ObservedObject var appsViewModel: AppsListViewModel
    @ObservedObject var systemFilesViewModel: PopStarterSystemFilesViewModel
    let disk: Disk?

    var body: some View {
        VStack(spacing: 0) {
            AppsListView(viewModel: appsViewModel, disk: disk, tabTitle: "Core Apps")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ScrollView {
                PopStarterSystemFilesSection(viewModel: systemFilesViewModel, disk: disk)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
