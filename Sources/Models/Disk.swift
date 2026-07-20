import Foundation

struct Disk: Identifiable, Hashable {
    let deviceIdentifier: String   // e.g. "disk4"
    let sizeBytes: Int64
    let protocolDescription: String
    let mediaName: String?

    var id: String { deviceIdentifier }

    /// Raw/character device path, passed to hdl_dump. Deliberately NOT the
    /// buffered block device (/dev/diskN) -- macOS's buffer cache path is
    /// well known to be significantly slower for large sequential transfers
    /// than the raw device (the same reason `dd` guides always recommend
    /// /dev/rdiskN). The vendored hdl_dump is patched (see
    /// Vendor/hdl-dump-macos.patch, osal_map_device_name) to accept this.
    var devicePath: String { "/dev/r\(deviceIdentifier)" }

    var displaySizeText: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .binary)
    }

    var displayName: String {
        let name = mediaName?.trimmingCharacters(in: .whitespaces)
        if let name, !name.isEmpty {
            return name
        }
        return deviceIdentifier
    }
}
