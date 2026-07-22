import Foundation

/// Thread-safe accumulator for a spawned `Process`'s stdout/stderr, appended
/// to from `Pipe.fileHandleForReading.readabilityHandler` (fires on a
/// background dispatch source) and read back from `terminationHandler` (a
/// different callback context) -- both can run concurrently with each
/// other, so every access is serialized through a single lock.
///
/// `@unchecked Sendable` because the lock is exactly what makes that safe;
/// every call site this replaces was already correct (each access was
/// manually wrapped in matching `NSLock` lock/unlock calls), but a plain
/// captured `var Data()` mutated from multiple escaping closures can't be
/// verified safe by Swift 6's strict concurrency checker no matter how
/// carefully it's locked by hand -- hence "mutation of captured var in
/// concurrently-executing code; this is an error in the Swift 6 language
/// mode" at every one of those call sites. Wrapping the same lock/data pair
/// in a dedicated type lets the compiler trust the `Sendable` annotation
/// instead of trying (and failing) to prove safety of the raw pattern.
final class SynchronizedDataBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    /// Everything appended so far, decoded as UTF-8 (empty string if
    /// decoding fails) -- every call site here only ever wants text output.
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
