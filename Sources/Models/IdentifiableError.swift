import Foundation

/// Wraps any Error so it can drive a SwiftUI `.alert(item:)`.
struct IdentifiableError: Identifiable {
    let id = UUID()
    let underlying: Error
    var message: String { underlying.localizedDescription }

    /// Raw exit code / stderr detail for a "Show Details" disclosure, when available.
    var debugDetail: String? {
        guard case let HDLDumpError.unknown(exitCode, stderr) = underlying else { return nil }
        return "exit code \(exitCode): \(stderr)"
    }

    var isLikelyMissingFullDiskAccess: Bool {
        (underlying as? HDLDumpError)?.isLikelyMissingFullDiskAccess ?? false
    }
}
