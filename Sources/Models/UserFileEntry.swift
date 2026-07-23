import Foundation

/// A single file or folder entry within the `USERFILES` partition, at
/// whatever path `UserFilesViewModel.currentPath` currently points to.
/// Unlike every other content model in this app, entries here can be either
/// a file or a directory -- User Files is a real, arbitrary-content file
/// browser, not a fixed-shape content type.
struct UserFileEntry: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool

    var id: String { name }
}
