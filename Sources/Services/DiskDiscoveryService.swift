import Foundation

/// Enumerates candidate external physical disks via `diskutil`, and structurally
/// excludes the Mac's own boot disk -- this is the primary safety guard against
/// ever targeting the internal disk, enforced here so it can't even appear as a
/// selectable option in the UI (not just a runtime confirmation dialog).
struct DiskDiscoveryService {
    enum DiscoveryError: Error, LocalizedError {
        case diskutilFailed(String)
        case malformedPlist

        var errorDescription: String? {
            switch self {
            case .diskutilFailed(let message): return "diskutil failed: \(message)"
            case .malformedPlist: return "diskutil returned output that couldn't be parsed."
            }
        }
    }

    private let diskutilPath = "/usr/sbin/diskutil"

    func listCandidateDisks() async throws -> [Disk] {
        let bootDiskParent = try? await bootWholeDiskIdentifier()

        let listPlist = try await runDiskutil(["list", "-plist", "external", "physical"])
        guard let listDict = try PropertyListSerialization.propertyList(
            from: listPlist, options: [], format: nil
        ) as? [String: Any] else {
            throw DiscoveryError.malformedPlist
        }

        let allDisksAndPartitions = listDict["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        var disks: [Disk] = []

        for entry in allDisksAndPartitions {
            guard let deviceIdentifier = entry["DeviceIdentifier"] as? String else { continue }
            if deviceIdentifier == bootDiskParent { continue }

            guard let info = try? await diskInfo(for: deviceIdentifier) else { continue }
            guard (info["Internal"] as? Bool) != true else { continue }
            guard (info["WholeDisk"] as? Bool) == true else { continue }

            let sizeBytes = (info["TotalSize"] as? Int) ?? (entry["Size"] as? Int) ?? 0
            let protocolDescription = (info["BusProtocol"] as? String) ?? "Unknown"
            let mediaName = info["MediaName"] as? String

            disks.append(Disk(
                deviceIdentifier: deviceIdentifier,
                sizeBytes: Int64(sizeBytes),
                protocolDescription: protocolDescription,
                mediaName: mediaName
            ))
        }

        return disks
    }

    /// Unmounts every volume on the whole disk before any raw device access.
    /// Idempotent -- safe to call even if nothing is currently mounted, which is
    /// the expected common case for an APA/HDL-formatted disk (macOS doesn't
    /// recognize the filesystem and won't have mounted anything).
    func unmountWholeDisk(deviceIdentifier: String) async throws {
        _ = try await runDiskutil(["unmountDisk", "/dev/\(deviceIdentifier)"])
    }

    /// Re-checked immediately before any write operation, in addition to the
    /// exclusion already applied in `listCandidateDisks()`, in case the boot
    /// disk's identity changed mid-session (e.g. the user swapped drives without
    /// hitting Refresh).
    func isBootDisk(deviceIdentifier: String) async -> Bool {
        (try? await bootWholeDiskIdentifier()) == deviceIdentifier
    }

    private func bootWholeDiskIdentifier() async throws -> String {
        let plist = try await runDiskutil(["info", "-plist", "/"])
        guard let dict = try PropertyListSerialization.propertyList(
            from: plist, options: [], format: nil
        ) as? [String: Any], let parent = dict["ParentWholeDisk"] as? String else {
            throw DiscoveryError.malformedPlist
        }
        return parent
    }

    private func diskInfo(for deviceIdentifier: String) async throws -> [String: Any] {
        let plist = try await runDiskutil(["info", "-plist", "/dev/\(deviceIdentifier)"])
        guard let dict = try PropertyListSerialization.propertyList(
            from: plist, options: [], format: nil
        ) as? [String: Any] else {
            throw DiscoveryError.malformedPlist
        }
        return dict
    }

    private func runDiskutil(_ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: diskutilPath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let out = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    let err = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: err, encoding: .utf8) ?? "unknown error"
                    continuation.resume(throwing: DiscoveryError.diskutilFailed(message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
