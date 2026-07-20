import SwiftUI

struct DriveSidebarView: View {
    @ObservedObject var viewModel: DriveListViewModel

    var body: some View {
        List(selection: $viewModel.selectedDiskID) {
            Section("External Drives") {
                if viewModel.disks.isEmpty && !viewModel.isLoading {
                    Text("No external physical drives found.\nConnect the PS2 HDD via USB and press Refresh.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.disks) { disk in
                    VStack(alignment: .leading) {
                        Text(disk.displayName)
                            .font(.headline)
                        Text("\(disk.displaySizeText) · \(disk.protocolDescription) · \(disk.devicePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(disk.id)
                }
            }
        }
        .navigationTitle("Drives")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }
}
