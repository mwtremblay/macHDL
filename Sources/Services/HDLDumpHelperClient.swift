import Foundation
import ServiceManagement

/// Manages the NSXPCConnection to the privileged helper daemon: SMAppService
/// registration/approval status, connection lifecycle, and async wrapping of
/// the completion-handler-based XPC protocol -- the replacement for
/// AdminPromptExecutor's role in the app.
final class HDLDumpHelperClient {
    private var connection: NSXPCConnection?
    private let progressExportedObject = ProgressReceiver()
    private let daemonService = SMAppService.daemon(plistName: HDLDumpHelperConstants.daemonPlistName)

    // MARK: - Registration & approval

    var registrationStatus: SMAppService.Status {
        daemonService.status
    }

    /// Always calls through to `SMAppService.register()`, even when
    /// `status` already reports `.enabled` -- Apple's API is documented as
    /// safe/idempotent to call repeatedly. An earlier version of this
    /// skipped the call when already `.enabled` as an optimization, but that
    /// masked a real inconsistency: `launchctl bootout`-ing the daemon's
    /// launchd job (done manually once during development, recovering from
    /// a stale DerivedData-path registration) removes the loaded job but
    /// does NOT change `SMAppService`'s own persisted `.enabled` status --
    /// so the guarded version silently never re-registered/reloaded the job
    /// at all, leaving the daemon permanently gone until this was diagnosed.
    /// Does not itself resolve `.requiresApproval` -- the caller
    /// (HelperRegistrationViewModel) surfaces that status to the user via a
    /// dedicated approval sheet, not an error.
    func register() throws {
        try daemonService.register()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Operations

    func listGames(devicePath: String) async throws -> (data: Data?, exitCode: Int32, stderr: String) {
        try await performCall { helper, complete in
            helper.listGames(devicePath: devicePath) { data, exitCode, stderr in
                complete(.success((data, exitCode, stderr)))
            }
        }
    }

    func gameInfo(devicePath: String, gameName: String) async throws -> (stdout: String?, exitCode: Int32, stderr: String) {
        try await performCall { helper, complete in
            helper.gameInfo(devicePath: devicePath, gameName: gameName) { stdout, exitCode, stderr in
                complete(.success((stdout, exitCode, stderr)))
            }
        }
    }

    func installGame(
        devicePath: String,
        gameName: String,
        isDVD: Bool,
        sourcePath: String,
        workingDirectory: String,
        onProgress: ((String) -> Void)?
    ) async throws -> (exitCode: Int32, stderr: String) {
        progressExportedObject.handler = onProgress
        defer { progressExportedObject.handler = nil }
        return try await performCall { helper, complete in
            helper.installGame(
                devicePath: devicePath,
                gameName: gameName,
                isDVD: isDVD,
                sourcePath: sourcePath,
                workingDirectory: workingDirectory
            ) { exitCode, stderr in
                complete(.success((exitCode, stderr)))
            }
        }
    }

    /// Best-effort: returns false (rather than throwing) if the daemon can't
    /// be reached, since "nothing to cancel" and "couldn't ask" have the same
    /// practical UI treatment here.
    func cancelCurrentInstall() async -> Bool {
        (try? await performCall { helper, complete in
            helper.cancelCurrentInstall { wasRunning in
                complete(.success(wasRunning))
            }
        }) ?? false
    }

    func deleteGame(devicePath: String, gameName: String, onProgress: ((String) -> Void)?) async throws -> (exitCode: Int32, stderr: String) {
        progressExportedObject.handler = onProgress
        defer { progressExportedObject.handler = nil }
        return try await performCall { helper, complete in
            helper.deleteGame(devicePath: devicePath, gameName: gameName) { exitCode, stderr in
                complete(.success((exitCode, stderr)))
            }
        }
    }

    // MARK: - PFS / PopStarter operations

    func listAllPartitions(devicePath: String) async throws -> (output: String?, exitCode: Int32, stderr: String) {
        try await performCall { helper, complete in
            helper.listAllPartitions(devicePath: devicePath) { output, exitCode, stderr in
                complete(.success((output, exitCode, stderr)))
            }
        }
    }

    func createPOPSPartition(devicePath: String, partitionName: String, sizeBytes: Int64) async throws -> (exitCode: Int32, stderr: String) {
        try await performCall { helper, complete in
            helper.createPOPSPartition(devicePath: devicePath, partitionName: partitionName, sizeBytes: sizeBytes) { exitCode, stderr in
                complete(.success((exitCode, stderr)))
            }
        }
    }

    /// SAFETY-CRITICAL: see HDLDumpHelperProtocol.initializeBlankAPADisk --
    /// wipes the entire disk's APA scheme. The daemon does NOT re-check
    /// blankness before running (that gate was deliberately removed in
    /// favor of an informed client-side confirmation -- see
    /// FreeHDBootSetupSheet); it only re-checks that the target isn't the
    /// boot disk, and independently verifies afterward that all four base
    /// partitions actually got built (pfsshell's own `initialize` can report
    /// success without having formatted all of them -- see
    /// HDLDumpHelperService.initializeBlankAPADisk for why). This call is
    /// just the transport for both of those; it is not itself a safety
    /// check.
    func initializeBlankAPADisk(devicePath: String) async throws -> (exitCode: Int32, stderr: String) {
        try await performCall { helper, complete in
            helper.initializeBlankAPADisk(devicePath: devicePath) { exitCode, stderr in
                complete(.success((exitCode, stderr)))
            }
        }
    }

    func injectMBR(devicePath: String, mbrKelfPath: String, onProgress: ((String) -> Void)?) async throws -> (exitCode: Int32, stderr: String) {
        progressExportedObject.handler = onProgress
        defer { progressExportedObject.handler = nil }
        return try await performCall { helper, complete in
            helper.injectMBR(devicePath: devicePath, mbrKelfPath: mbrKelfPath) { exitCode, stderr in
                complete(.success((exitCode, stderr)))
            }
        }
    }

    func listPFSFiles(devicePath: String, partitionName: String, pfsPath: String) async throws -> (names: [String]?, exitCode: Int32, stderr: String) {
        try await performCall { helper, complete in
            helper.listPFSFiles(devicePath: devicePath, partitionName: partitionName, pfsPath: pfsPath) { names, exitCode, stderr in
                complete(.success((names, exitCode, stderr)))
            }
        }
    }

    func putPFSFile(devicePath: String, partitionName: String, localSourcePath: String, pfsDestPath: String) async throws -> (exitCode: Int32, stderr: String) {
        try await performCall { helper, complete in
            helper.putPFSFile(devicePath: devicePath, partitionName: partitionName, localSourcePath: localSourcePath, pfsDestPath: pfsDestPath) { exitCode, stderr in
                complete(.success((exitCode, stderr)))
            }
        }
    }

    func getPFSFile(devicePath: String, partitionName: String, pfsPath: String) async throws -> (data: Data?, exitCode: Int32, stderr: String) {
        try await performCall { helper, complete in
            helper.getPFSFile(devicePath: devicePath, partitionName: partitionName, pfsPath: pfsPath) { data, exitCode, stderr in
                complete(.success((data, exitCode, stderr)))
            }
        }
    }

    func removePFSFile(devicePath: String, partitionName: String, pfsPath: String) async throws -> (exitCode: Int32, stderr: String) {
        try await performCall { helper, complete in
            helper.removePFSFile(devicePath: devicePath, partitionName: partitionName, pfsPath: pfsPath) { exitCode, stderr in
                complete(.success((exitCode, stderr)))
            }
        }
    }

    // MARK: - Connection management

    private func activeConnection() -> NSXPCConnection? {
        if let connection { return connection }

        let newConnection = NSXPCConnection(machServiceName: HDLDumpHelperConstants.machServiceName)
        newConnection.remoteObjectInterface = NSXPCInterface(with: HDLDumpHelperProtocol.self)
        newConnection.exportedInterface = NSXPCInterface(with: HDLDumpHelperProgressProtocol.self)
        newConnection.exportedObject = progressExportedObject
        newConnection.invalidationHandler = { [weak self] in self?.connection = nil }
        newConnection.interruptionHandler = { [weak self] in self?.connection = nil }
        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    /// Wraps a completion-handler-based XPC call in `async`/`await`, guarding
    /// against a double-resume if both the error handler and a reply fire
    /// (shouldn't happen per NSXPCConnection's contract, but XPC failure
    /// modes are exactly the kind of thing worth not trusting blindly).
    private func performCall<T>(
        _ body: @escaping (HDLDumpHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let resumeOnce = SingleFireGuard()

            guard let conn = activeConnection() else {
                resumeOnce.fire { continuation.resume(throwing: HDLDumpError.helperConnectionFailed(underlying: nil)) }
                return
            }

            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                resumeOnce.fire { continuation.resume(throwing: HDLDumpError.helperConnectionFailed(underlying: error)) }
            }
            guard let helper = proxy as? HDLDumpHelperProtocol else {
                resumeOnce.fire { continuation.resume(throwing: HDLDumpError.helperConnectionFailed(underlying: nil)) }
                return
            }

            body(helper) { result in
                resumeOnce.fire {
                    switch result {
                    case .success(let value):
                        continuation.resume(returning: value)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

/// Exported to the daemon so its remoteObjectProxy can call back with live
/// progress lines during installGame/deleteGame.
private final class ProgressReceiver: NSObject, HDLDumpHelperProgressProtocol {
    var handler: ((String) -> Void)?

    func didReceiveOutputLine(_ line: String) {
        handler?(line)
    }
}

/// Ensures a completion closure fires at most once, guarding against the
/// (should-be-impossible-but-XPC-is-XPC) case of both a reply and the
/// connection's error handler firing for the same outstanding call.
private final class SingleFireGuard {
    private var fired = false
    private let lock = NSLock()

    func fire(_ body: () -> Void) {
        lock.lock()
        let alreadyFired = fired
        fired = true
        lock.unlock()
        guard !alreadyFired else { return }
        body()
    }
}
