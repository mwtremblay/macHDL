import Foundation

/// Maps hdl_dump's process exit code (see retcodes.h + handle_result_and_exit in hdl_dump.c)
/// to a typed, human-readable error. 0=OK is not represented here (success).
enum HDLDumpError: Error, LocalizedError {
    case ioError(message: String)          // exit 1, RET_ERR
    case outOfMemory                       // exit 2, RET_NO_MEM
    case notAPA                            // 101
    case notHDLPartition(partition: String?) // 102
    case partitionNotFound(partition: String?) // 103
    case badFormat                         // 104
    case badDevice                         // 105
    case noSpace                           // 106
    case badAPA                            // 107
    case interrupted                       // 109 -- also what a user-cancelled install produces
    case partitionAlreadyExists(name: String?) // 110
    case badISOFilesystem                  // 111
    case notPlayStationDisc                // 112
    case badSystemConfig                   // 113
    case notCompatible                     // 114
    /// 115 -- a daemon-side refusal (e.g. attempting to touch the boot disk,
    /// or an invalid PFS partition name). Carries the actual reason string --
    /// either the daemon's own reply text (e.g. "refused: invalid PFS
    /// partition name '...'") for daemon-relayed refusals, or
    /// `Self.bootDiskRefusalMessage` for the client-side-only throw sites
    /// (see FreeHDBootService/HDLDumpService/PS1GameService's
    /// guardNotBootDisk, which never round-trip through the daemon at all).
    /// An earlier version of this case had no associated value, which meant
    /// every refusal surfaced identically as a bare "This operation is not
    /// allowed." with no way to tell which guard fired without reading
    /// server logs.
    case operationNotAllowed(message: String)
    case fileNotFound                      // 120
    case multitrackNotSupported            // 133 -- multi-track (audio) CUE/BIN, single-track only
    case unknown(exitCode: Int32, stderr: String)

    /// A destructive whole-disk operation (FreeHDBoot's `initializeAPA`/
    /// `injectBootloader`, see FreeHDBootService) failed partway through --
    /// unlike an ordinary file-write failure, this can leave the disk's APA
    /// partition table in a half-rebuilt, inconsistent state (see
    /// HDLDumpHelperService.initializeBlankAPADisk's post-`initialize`
    /// verification step for why this can't just be trusted to have fully
    /// succeeded or fully failed). FreeHDBootService wraps failures from
    /// those two specific steps into this case rather than letting them
    /// surface as an ordinary `.ioError`/`.unknown`, since the user needs a
    /// categorically different warning than "a file copy failed." Typed as
    /// `HDLDumpError`, not a bare `Error` -- the only construction site
    /// (FreeHDBootService.throwPossiblyDiskCorrupting) always has a
    /// concrete `HDLDumpError` in hand, and keeping it typed lets callers
    /// (e.g. `isLikelyMissingFullDiskAccess` below) inspect the underlying
    /// case without an unenforced `as?` downcast. Deliberately never wraps
    /// `.operationNotAllowed` or `.daemonLaunchFailed` (see
    /// throwPossiblyDiskCorrupting) -- both mean nothing was actually
    /// written, so they stay as themselves rather than getting this
    /// disk-may-be-corrupted treatment.
    indirect case partitionTableMayBeInconsistent(underlying: HDLDumpError)

    /// Shared by every client-side-only `guardNotBootDisk` throw site (see
    /// FreeHDBootService/HDLDumpService/PS1GameService) so the message never
    /// silently drifts from what those call sites actually pass.
    static let bootDiskRefusalMessage = "target is the boot disk"

    /// hdl_dump itself failed to launch inside the daemon (not found, not
    /// executable, spawn error) -- relayed as exit code -1 by
    /// HDLDumpHelperService, not a real hdl_dump exit code.
    case daemonLaunchFailed(message: String)

    /// The XPC connection to the privileged helper failed or was invalidated.
    case helperConnectionFailed(underlying: Error?)

    /// Writing to the raw disk device requires the daemon binary to have
    /// Full Disk Access, in addition to running as root (a macOS TCC
    /// protection against raw-disk wipers) -- this is a distinct grant from
    /// root privilege, and root alone is not sufficient. hdl_dump surfaces
    /// this as a plain "Operation not permitted" (EPERM) I/O error with no
    /// distinguishing exit code, so detect it by message content.
    var isLikelyMissingFullDiskAccess: Bool {
        switch self {
        case .ioError(let message):
            return message.localizedCaseInsensitiveContains("Operation not permitted")
        // Recurses into the wrapped error -- throwPossiblyDiskCorrupting
        // already excludes FDA failures from being wrapped in the first
        // place, but checking here too means this stays correct even if
        // that exclusion is ever incomplete, without every caller having
        // to know to unwrap partitionTableMayBeInconsistent first.
        case .partitionTableMayBeInconsistent(let underlying):
            return underlying.isLikelyMissingFullDiskAccess
        default:
            return false
        }
    }

    /// pfsutil/pfsshell (unlike hdl_dump) only ever return exit code 0 or 1
    /// -- a full PFS partition surfaces as exit 1 (`.ioError`), not a
    /// distinguishing exit code. Detected by message content instead:
    /// confirmed empirically (per project practice, not assumed) against a
    /// real scratch PFS partition filled to capacity -- pfsutil's `put`
    /// prints "write failed: No space left on device" (via strerror() on the
    /// negative errno-style return from iomanX_write) once this project's
    /// own Scripts/pfsutil-src/pfsutil.c was fixed to report it clearly
    /// instead of a bare negative number.
    var isLikelyOutOfSpace: Bool {
        switch self {
        case .ioError(let message):
            return message.localizedCaseInsensitiveContains("No space left on device")
        case .partitionTableMayBeInconsistent(let underlying):
            return underlying.isLikelyOutOfSpace
        default:
            return false
        }
    }

    init(exitCode: Int32, stderr: String) {
        switch exitCode {
        case -1: self = .daemonLaunchFailed(message: stderr)
        case 1: self = .ioError(message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        case 2: self = .outOfMemory
        case 101: self = .notAPA
        case 102: self = .notHDLPartition(partition: nil)
        case 103: self = .partitionNotFound(partition: nil)
        case 104: self = .badFormat
        case 105: self = .badDevice
        case 106: self = .noSpace
        case 107: self = .badAPA
        case 109: self = .interrupted
        case 110: self = .partitionAlreadyExists(name: nil)
        case 111: self = .badISOFilesystem
        case 112: self = .notPlayStationDisc
        case 113: self = .badSystemConfig
        case 114: self = .notCompatible
        case 115: self = .operationNotAllowed(message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        case 120: self = .fileNotFound
        case 133: self = .multitrackNotSupported
        default: self = .unknown(exitCode: exitCode, stderr: stderr)
        }
    }

    var errorDescription: String? {
        switch self {
        case .ioError(let message):
            return message.isEmpty ? "An I/O error occurred." : message
        case .outOfMemory:
            return "hdl_dump ran out of memory."
        case .notAPA:
            return "This disk does not have a PlayStation 2 (APA) partition table. It may need to be formatted on the PS2 first."
        case .notHDLPartition:
            return "That partition is not a HD Loader partition."
        case .partitionNotFound:
            return "That game/partition could not be found on the drive."
        case .badFormat:
            return "Bad device name format."
        case .badDevice:
            return "Unrecognized device."
        case .noSpace:
            return "Not enough free space on the drive."
        case .badAPA:
            return "The drive's partition table is broken. Aborting to avoid further damage."
        case .interrupted:
            return "The operation was interrupted."
        case .partitionAlreadyExists:
            return "A game with that name already exists on the drive."
        case .badISOFilesystem:
            return "The selected file is not a valid ISO filesystem."
        case .notPlayStationDisc:
            return "The selected file is not a PlayStation CD/DVD image."
        case .badSystemConfig:
            return "SYSTEM.CNF is not in the expected format."
        case .notCompatible:
            return "This input is not supported."
        case .operationNotAllowed(let message):
            return message.isEmpty ? "This operation is not allowed." : "This operation is not allowed: \(message)"
        case .fileNotFound:
            return "File not found."
        case .multitrackNotSupported:
            return "This CUE/BIN has multiple tracks (e.g. a game with audio tracks). Only single-track cue sheets are supported — convert it to a single-track cue/bin first (e.g. using CDMage), then try again."
        case .unknown(let exitCode, let stderr):
            return "hdl_dump failed (exit \(exitCode)): \(stderr.isEmpty ? "Unknown error." : stderr)"
        case .daemonLaunchFailed(let message):
            return "The privileged helper could not launch hdl_dump: \(message)"
        case .helperConnectionFailed(let underlying):
            if let underlying {
                return "Lost connection to the macHDL privileged helper: \(underlying.localizedDescription)"
            }
            return "Lost connection to the macHDL privileged helper."
        case .partitionTableMayBeInconsistent(let underlying):
            let underlyingMessage = underlying.errorDescription ?? "\(underlying)"
            return "FreeHDBoot setup failed while rebuilding the drive's partition table: \(underlyingMessage)\n\nThe drive's partition table may now be left in an inconsistent, half-rebuilt state — this is not a routine failure. Do not use the drive until you re-run FreeHDBoot setup from the start (it will detect the drive is no longer blank and warn you) or re-initialize it."
        }
    }
}
