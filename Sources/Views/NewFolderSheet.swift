import SwiftUI

/// The User Files tab's explicit "New Folder" action -- creates a
/// genuinely empty folder (see UserFilesViewModel.createFolder / the new
/// PS1GameService.makeDirectory primitive), unlike every other folder in
/// this app, which only ever comes into existence as a side effect of
/// adding a file.
struct NewFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String) -> Void

    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Folder")
                .font(.title2)

            TextField("Folder Name", text: $name)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(name.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!PFSPathComponentValidation.isValid(name))
            }
        }
        .padding()
        .frame(width: 360)
    }
}
