import Foundation

/// A single installed HDL partition, as reported by `hdl_dump hdl_toc <device> --csv`.
struct HDLGame: Identifiable, Hashable {
    /// hdl_toc never exposes the internal partition_name, only this display name.
    /// It is the only stable identifier we get from the CSV listing.
    static let maxNameLength = 64 // HDL_GAME_NAME_MAX

    let isDVD: Bool
    let sizeKB: Int
    let compatFlags: String
    let dma: String
    let startup: String
    let name: String

    var id: String { name }

    var displaySizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeKB) * 1024, countStyle: .binary)
    }

    var mediaTypeLabel: String {
        isDVD ? "DVD" : "CD"
    }
}
