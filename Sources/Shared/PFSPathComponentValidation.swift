import Foundation

/// A single PFS path *component* (an app folder name, a video filename --
/// not a multi-segment path) must reject `/` (which would nest into an
/// unintended subdirectory) and `.`/`..` (traversal out of the destination
/// directory). This is the client-side mirror of the check the privileged
/// helper enforces server-side per-path-segment (see
/// HDLDumpHelperService.isValidPFSDestinationPath) -- shared here so the
/// app's several client-side name validators (AddAppViewModel,
/// AddVideoViewModel) can't drift out of sync with each other.
enum PFSPathComponentValidation {
    static func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return false }
        return trimmed != "." && trimmed != ".."
    }
}
