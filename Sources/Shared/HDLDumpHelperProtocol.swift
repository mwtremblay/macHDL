import Foundation

/// Identifiers shared between the app and the privileged helper daemon.
/// Must match the `Label`/`MachServices` keys in the launchd plist
/// (HelperTool/com.michaeltremblay.machdl.helper.plist) verbatim.
enum HDLDumpHelperConstants {
    static let machServiceName = "com.michaeltremblay.machdl.helper"
    static let daemonLabel = "com.michaeltremblay.machdl.helper"
    static let daemonPlistName = "com.michaeltremblay.machdl.helper.plist"
    static let appBundleIdentifier = "com.michaeltremblay.machdl"
}

/// Closed, parameterized operation set exposed by the privileged daemon --
/// deliberately never a raw-argv passthrough (see HDLDumpHelperListenerDelegate
/// and HDLDumpHelperService for the security reasoning). Mirrors HDLDumpService's
/// four disk operations one-to-one, plus install cancellation.
@objc protocol HDLDumpHelperProtocol {
    /// stdout (raw hdl_toc --csv output as UTF-8 Data), exit code, stderr.
    func listGames(devicePath: String, with reply: @escaping (Data?, Int32, String) -> Void)

    /// raw `info` stdout, exit code, stderr.
    func gameInfo(devicePath: String, gameName: String, with reply: @escaping (String?, Int32, String) -> Void)

    /// exit code, stderr. Progress is delivered separately via HDLDumpHelperProgressProtocol.
    func installGame(
        devicePath: String,
        gameName: String,
        isDVD: Bool,
        sourcePath: String,
        workingDirectory: String,
        with reply: @escaping (Int32, String) -> Void
    )

    /// Sends SIGINT to the hdl_dump child process currently running an install
    /// on this connection, if any. reply(true) if something was signaled,
    /// reply(false) if there was nothing in flight to cancel.
    func cancelCurrentInstall(with reply: @escaping (Bool) -> Void)

    func deleteGame(devicePath: String, gameName: String, with reply: @escaping (Int32, String) -> Void)

    /// Raw `hdl_dump toc <device>` output (every partition on the drive,
    /// any type -- HDL games, PFS partitions like `__.POPS`/`__common`,
    /// anything else -- one name per line), exit code, stderr. Used to check
    /// for a PFS partition's existence by substring search on the name.
    ///
    /// Deliberately NOT `pfsshell`'s own unmounted `ls`/`lspart` (an earlier
    /// version of this used that) -- `apa_toc_read` reads the whole
    /// partition table in one pass, the same fast path `hdl_dump`'s other
    /// commands already use, while `pfsshell`'s `lspart` issues one raw
    /// device read per partition and was never given the same optimization.
    /// Confirmed via a real hang on real hardware (a drive with 46+
    /// partitions took long enough to make `lspart` genuinely take minutes,
    /// not seconds) -- see project memory for the full incident.
    func listAllPartitions(devicePath: String, with reply: @escaping (String?, Int32, String) -> Void)

    /// Allocates and formats a new PFS partition for PS1 games via pfsshell's
    /// `mkpart <name> <size> PFS` -- never via `initialize`, which reformats
    /// the entire disk's APA scheme (see initializeBlankAPADisk below for the
    /// one, narrowly-gated exception to that).
    /// partitionName is independently validated server-side against
    /// "__.POPS"/"__.POPS1"-"__.POPS10" -- never trusted as-is from the client.
    func createPOPSPartition(devicePath: String, partitionName: String, sizeBytes: Int64, with reply: @escaping (Int32, String) -> Void)

    /// Wraps pfsshell's `initialize yes` -- the single most dangerous
    /// operation this app exposes. Rebuilds the disk's entire APA scheme
    /// from scratch (`__mbr` + `__net`/`__system`/`__sysconf`/`__common`,
    /// each auto-formatted as PFS -- see hddFormat/do_initialize in the
    /// vendored pfsshell submodule), destroying whatever was on the disk
    /// before. Does not itself require the disk to be blank -- like every
    /// other destructive operation in this protocol, that's an informed
    /// choice surfaced to the user in the UI (FreeHDBootSetupSheet), not a
    /// server-side precondition. Only the boot-disk check is unconditional.
    ///
    /// Success is not just "pfsshell's REPL didn't print an error" -- see
    /// HDLDumpHelperService's implementation for why that alone can't be
    /// trusted (pfsshell's own `do_initialize` silently discards the format
    /// result for three of the four partitions it builds), and for the
    /// independent `hdl_dump toc` verification this runs before ever
    /// reporting success back to the caller.
    func initializeBlankAPADisk(devicePath: String, with reply: @escaping (Int32, String) -> Void)

    /// Wraps hdl-dump's `inject_mbr <device> <mbr_kelf_path>` -- writes a
    /// bootstrap KELF into the `__mbr` partition's OSD slot (see
    /// apa_initialize_ex in Vendor/hdl-dump/apa.c). Requires a valid `__mbr`
    /// header to already exist at sector 0, so this is only ever meaningful
    /// immediately after initializeBlankAPADisk, never standalone -- it does
    /// not itself build a partition table.
    func injectMBR(devicePath: String, mbrKelfPath: String, with reply: @escaping (Int32, String) -> Void)

    /// Directory entry names at the given path within the partition, via
    /// `pfsutil` (a one-shot argv-based CLI, see
    /// Scripts/pfsutil-src/pfsutil.c) -- not pfsshell's REPL over a pty
    /// (fragile: buffering/quoting/prompt-detection bugs) nor a pfsfuse/
    /// FUSE-T mount (corrupted large writes and panicked the kernel). See
    /// project memory for the full incident history. exit code, stderr.
    func listPFSFiles(devicePath: String, partitionName: String, pfsPath: String, with reply: @escaping ([String]?, Int32, String) -> Void)

    func putPFSFile(devicePath: String, partitionName: String, localSourcePath: String, pfsDestPath: String, with reply: @escaping (Int32, String) -> Void)

    /// Reads a single file's contents back from a PFS partition into memory
    /// via `pfsutil get`, e.g. to display previously-installed cover art.
    /// Only intended for small files (cover art PNGs, tens-hundreds of KB) --
    /// unlike putPFSFile (which takes a local path, since VCDs can be
    /// hundreds of MB), this returns the bytes directly over XPC. A read,
    /// like listPFSFiles/gameInfo -- no partition-name allowlist or
    /// boot-disk check, matching that existing precedent.
    func getPFSFile(devicePath: String, partitionName: String, pfsPath: String, with reply: @escaping (Data?, Int32, String) -> Void)

    /// Removes a single file at the given path (not a directory -- a PS1
    /// game's VCD sits directly at the partition root, see
    /// PFSDestinationPaths).
    func removePFSFile(devicePath: String, partitionName: String, pfsPath: String, with reply: @escaping (Int32, String) -> Void)
}

/// Exported by the client so the daemon's remoteObjectProxy can call back with
/// live progress during installGame/deleteGame.
@objc protocol HDLDumpHelperProgressProtocol {
    /// One `\r`/`\n`-delimited output segment.
    func didReceiveOutputLine(_ line: String)
}
