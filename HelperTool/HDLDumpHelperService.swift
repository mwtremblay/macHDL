import Foundation

/// Implements the privileged operations exposed to the app over XPC. One
/// instance is created per accepted connection (see
/// HDLDumpHelperListenerDelegate), so `runner`'s tracked install process is
/// naturally scoped per-connection.
final class HDLDumpHelperService: NSObject, HDLDumpHelperProtocol {
    /// Set by the listener delegate right after the connection resumes, to
    /// the client's exported progress-callback object (its remoteObjectProxy).
    var progressDelegate: HDLDumpHelperProgressProtocol?

    private let runner = HelperProcessRunner()

    func listGames(devicePath: String, with reply: @escaping (Data?, Int32, String) -> Void) {
        Task {
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolve(),
                    arguments: ["hdl_toc", devicePath, "--csv"],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: nil,
                    trackForCancellation: false
                )
                reply(result.stdout.data(using: .utf8), result.exitCode, result.stderr)
            } catch {
                reply(nil, -1, "launch failed: \(error)")
            }
        }
    }

    func gameInfo(devicePath: String, gameName: String, with reply: @escaping (String?, Int32, String) -> Void) {
        Task {
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolve(),
                    arguments: ["info", devicePath, gameName],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: nil,
                    trackForCancellation: false
                )
                reply(result.stdout, result.exitCode, result.stderr)
            } catch {
                reply(nil, -1, "launch failed: \(error)")
            }
        }
    }

    func installGame(
        devicePath: String,
        gameName: String,
        isDVD: Bool,
        sourcePath: String,
        workingDirectory: String,
        with reply: @escaping (Int32, String) -> Void
    ) {
        Task {
            let targetsBootDisk = await isBootDisk(devicePath: devicePath)
            guard !targetsBootDisk else {
                reply(115, "refused: target is the boot disk")
                return
            }
            let command = isDVD ? "inject_dvd" : "inject_cd"
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolve(),
                    arguments: [command, devicePath, gameName, sourcePath],
                    workingDirectory: URL(fileURLWithPath: workingDirectory),
                    onOutputLine: { [weak self] line in self?.progressDelegate?.didReceiveOutputLine(line) },
                    trackForCancellation: true
                )
                reply(result.exitCode, result.stderr)
            } catch {
                reply(-1, "launch failed: \(error)")
            }
        }
    }

    func cancelCurrentInstall(with reply: @escaping (Bool) -> Void) {
        reply(runner.cancelCurrentInstall())
    }

    func deleteGame(devicePath: String, gameName: String, with reply: @escaping (Int32, String) -> Void) {
        Task {
            let targetsBootDisk = await isBootDisk(devicePath: devicePath)
            guard !targetsBootDisk else {
                reply(115, "refused: target is the boot disk")
                return
            }
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolve(),
                    arguments: ["delete_game", devicePath, gameName],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: { [weak self] line in self?.progressDelegate?.didReceiveOutputLine(line) },
                    trackForCancellation: false
                )
                reply(result.exitCode, result.stderr)
            } catch {
                reply(-1, "launch failed: \(error)")
            }
        }
    }

    // MARK: - PFS / PopStarter operations

    func listAllPartitions(devicePath: String, with reply: @escaping (String?, Int32, String) -> Void) {
        Task {
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolve(),
                    arguments: ["toc", devicePath],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: nil,
                    trackForCancellation: false
                )
                reply(result.stdout, result.exitCode, result.stderr)
            } catch {
                reply(nil, -1, "launch failed: \(error)")
            }
        }
    }

    /// Allocates and formats a new PFS partition via pfsshell's
    /// `mkpart <name> <size> PFS`. Deliberately never constructs or exposes
    /// `initialize`, which reformats the entire disk's APA scheme and would
    /// destroy the drive's existing PS2/HDL partition table -- confirmed via
    /// pfsshell's own help text ("blank and create APA/PFS on a new PS2 HDD
    /// (destructive)"). See plan for the full safety writeup.
    ///
    /// SAFETY-CRITICAL: sizeBytes must be rounded to a 128MB multiple before
    /// reaching pfsshell -- see PFSPartitionSizing's doc comment for why.
    func createPOPSPartition(devicePath: String, partitionName: String, sizeBytes: Int64, with reply: @escaping (Int32, String) -> Void) {
        Task {
            guard Self.isValidPFSPartitionNameForPartitionOps(partitionName) else {
                reply(115, "refused: invalid PFS partition name '\(partitionName)'")
                return
            }
            let targetsBootDisk = await isBootDisk(devicePath: devicePath)
            guard !targetsBootDisk else {
                reply(115, "refused: target is the boot disk")
                return
            }
            let sizeMiB = PFSPartitionSizing.roundedSizeInMiB(requestedBytes: sizeBytes)
            var session: PFSShellSession?
            do {
                session = try await PFSShellSession.open(devicePath: devicePath)
                let output = try await session!.send("mkpart \(partitionName) \(sizeMiB)M PFS")
                await session!.close()
                reply(Self.succeeded(output) ? 0 : 1, output)
            } catch {
                await session?.forceTerminate()
                reply(-1, "pfsshell failed: \(error)")
            }
        }
    }

    /// This is the one operation in the whole app that wipes an entire
    /// disk's partition table, not one partition -- but it does not itself
    /// require the disk to be blank. Whether the target already has data on
    /// it is surfaced to the user client-side (see
    /// FreeHDBootService.existingPartitionNames/FreeHDBootSetupViewModel) as
    /// an informed decision, not enforced here: this app applies that same
    /// "show what's there, let the user confirm" pattern to every other
    /// destructive action (see deleteGame, removePFSFile above), and this
    /// is deliberately no different. The boot-disk check below is the one
    /// thing that's never negotiable, here or anywhere else in this file.
    func initializeBlankAPADisk(devicePath: String, with reply: @escaping (Int32, String) -> Void) {
        Task {
            let targetsBootDisk = await isBootDisk(devicePath: devicePath)
            guard !targetsBootDisk else {
                reply(115, "refused: target is the boot disk")
                return
            }
            var session: PFSShellSession?
            let initializeOutput: String
            do {
                session = try await PFSShellSession.open(devicePath: devicePath)
                initializeOutput = try await session!.send("initialize yes")
                await session!.close()
            } catch {
                await session?.forceTerminate()
                reply(-1, "pfsshell failed: \(error)")
                return
            }
            guard Self.succeeded(initializeOutput) else {
                reply(1, initializeOutput)
                return
            }
            // SAFETY-CRITICAL: pfsshell's own `do_initialize` (Vendor/
            // pfsshell/src/shell.c) only checks/reports the base APA format
            // result -- the three `mkpfs(...)` calls that build __system/
            // __sysconf/__common are bare statements with their return
            // values discarded, and `mkpfs` itself never prints anything on
            // failure. A "succeeded" REPL response above therefore does NOT
            // guarantee all four partitions actually exist -- confirmed
            // directly from the vendored C source, not assumed. Independently
            // verify via `hdl_dump toc` before ever reporting success.
            do {
                let tocResult = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolve(),
                    arguments: ["toc", devicePath],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: nil,
                    trackForCancellation: false
                )
                // Check toc's own exit code/stderr before ever trusting its
                // stdout -- if `toc` itself failed (e.g. a transient I/O
                // error right after `initialize`, the same flaky-USB-bridge
                // class of issue already documented elsewhere in this file),
                // stdout will be empty/unparseable and every partition would
                // otherwise be misreported as "missing," burying the real
                // diagnostic. listAllPartitions (above) already propagates
                // exitCode/stdout/stderr faithfully for this exact command;
                // this mirrors that instead of discarding them.
                guard tocResult.exitCode == 0 else {
                    reply(1, "pfsshell reported success, but verifying the result failed: hdl_dump toc exited \(tocResult.exitCode): \(tocResult.stderr.isEmpty ? tocResult.stdout : tocResult.stderr). The disk's partition table may now be left in an inconsistent state.")
                    return
                }
                let missing = Self.expectedBaseLayoutPartitionNames.filter { !APATOCParsing.output(tocResult.stdout, containsPartitionNamed: $0) }
                guard missing.isEmpty else {
                    reply(1, "pfsshell reported success, but the following partition(s) are missing afterward: \(missing.joined(separator: ", ")). The disk's partition table may now be left in an inconsistent state.")
                    return
                }
            } catch {
                reply(-1, "post-initialize verification failed: \(error)")
                return
            }
            reply(0, initializeOutput)
        }
    }

    /// The four partitions `pfsshell initialize` is supposed to build (see
    /// hddFormat/do_initialize in the vendored pfsshell submodule). Checked
    /// via APATOCParsing (Sources/Shared) -- the same TOC-parsing logic
    /// PS1GameService.partitionNames uses in the main app target, shared
    /// rather than duplicated since this daemon target (mac-hdl-gui-helper)
    /// already compiles Sources/Shared (see project.yml).
    private static let expectedBaseLayoutPartitionNames = ["__net", "__system", "__sysconf", "__common"]

    /// One-shot argv invocation of hdl-dump's `inject_mbr`. Always follows
    /// initializeBlankAPADisk in FreeHDBootService's orchestration -- this
    /// method does not itself verify a valid `__mbr` header exists first
    /// (hdl_dump's own apa_initialize_ex already fails cleanly if it
    /// doesn't; no need to duplicate that check here).
    func injectMBR(devicePath: String, mbrKelfPath: String, with reply: @escaping (Int32, String) -> Void) {
        Task {
            let targetsBootDisk = await isBootDisk(devicePath: devicePath)
            guard !targetsBootDisk else {
                reply(115, "refused: target is the boot disk")
                return
            }
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolve(),
                    arguments: ["inject_mbr", devicePath, mbrKelfPath],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: { [weak self] line in self?.progressDelegate?.didReceiveOutputLine(line) },
                    trackForCancellation: false
                )
                reply(result.exitCode, result.stderr)
            } catch {
                reply(-1, "launch failed: \(error)")
            }
        }
    }

    /// File transfer (listing/put/remove) drives `pfsutil`, a one-shot
    /// argv-based CLI (see Scripts/pfsutil-src/pfsutil.c) built on the same
    /// apa/pfs/iomanX libraries pfsshell itself uses, instead of driving
    /// pfsshell's own interactive REPL over a pty. Two earlier approaches
    /// were tried and abandoned here:
    /// 1. A pfsfuse/FUSE-T mount -- writing a file above ~1MB through the
    ///    mount corrupted the data (confirmed via MD5 mismatch) and, on a
    ///    repeat attempt, panicked the kernel (nfs_vinvalbuf2/ubc_msync).
    /// 2. Driving pfsshell's REPL over a pty (see the now-deleted
    ///    PFSShellSession) -- fragile in production (stdio buffering,
    ///    argv-tokenizer quoting, prompt detection all caused real bugs on
    ///    real hardware).
    /// pfsutil has none of these failure modes: real argv (no shell/REPL
    /// tokenizing to get wrong), a real process exit code (0 = success),
    /// and no prompt text to parse. See project memory for the full
    /// incident history. Partition creation (createPOPSPartition above)
    /// deliberately stays on pfsshell's REPL -- it already works correctly
    /// and is a rare, one-time operation, not worth the churn of moving.
    func listPFSFiles(devicePath: String, partitionName: String, pfsPath: String, with reply: @escaping ([String]?, Int32, String) -> Void) {
        Task {
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolvePFSUtil(),
                    arguments: ["list", devicePath, partitionName, pfsPath],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: nil,
                    trackForCancellation: false
                )
                let names = result.exitCode == 0 ? Self.plainDirectoryEntries(in: result.stdout) : nil
                reply(names, result.exitCode, result.stderr)
            } catch {
                reply(nil, -1, "launch failed: \(error)")
            }
        }
    }

    func putPFSFile(devicePath: String, partitionName: String, localSourcePath: String, pfsDestPath: String, with reply: @escaping (Int32, String) -> Void) {
        Task {
            guard Self.isValidPFSPartitionNameForFileWrite(partitionName) else {
                reply(115, "refused: invalid PFS partition name '\(partitionName)'")
                return
            }
            let targetsBootDisk = await isBootDisk(devicePath: devicePath)
            guard !targetsBootDisk else {
                reply(115, "refused: target is the boot disk")
                return
            }
            var destComponents = pfsDestPath.split(separator: "/").map(String.init)
            guard let destFilename = destComponents.popLast() else {
                reply(115, "refused: empty destination path")
                return
            }
            let destDir = destComponents.joined(separator: "/")
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolvePFSUtil(),
                    arguments: ["put", devicePath, partitionName, destDir, destFilename, localSourcePath],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: nil,
                    trackForCancellation: false
                )
                reply(result.exitCode, result.stderr)
            } catch {
                reply(-1, "launch failed: \(error)")
            }
        }
    }

    func getPFSFile(devicePath: String, partitionName: String, pfsPath: String, with reply: @escaping (Data?, Int32, String) -> Void) {
        Task {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolvePFSUtil(),
                    arguments: ["get", devicePath, partitionName, pfsPath, tempURL.path],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: nil,
                    trackForCancellation: false
                )
                guard result.exitCode == 0 else {
                    reply(nil, result.exitCode, result.stderr)
                    return
                }
                reply(try? Data(contentsOf: tempURL), result.exitCode, result.stderr)
            } catch {
                reply(nil, -1, "launch failed: \(error)")
            }
        }
    }

    /// Removes a single file at the given path within the partition -- a PS1
    /// game's VCD sits directly at the partition root (never in a
    /// subdirectory; see PFSDestinationPaths for why), so deleting a game is
    /// just removing one file.
    func removePFSFile(devicePath: String, partitionName: String, pfsPath: String, with reply: @escaping (Int32, String) -> Void) {
        Task {
            guard Self.isValidPFSPartitionNameForPartitionOps(partitionName) else {
                reply(115, "refused: invalid PFS partition name '\(partitionName)'")
                return
            }
            let targetsBootDisk = await isBootDisk(devicePath: devicePath)
            guard !targetsBootDisk else {
                reply(115, "refused: target is the boot disk")
                return
            }
            do {
                let result = try await runner.run(
                    binary: try HelperToolBinaryLocator.resolvePFSUtil(),
                    arguments: ["rm", devicePath, partitionName, pfsPath],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutputLine: nil,
                    trackForCancellation: false
                )
                reply(result.exitCode, result.stderr)
            } catch {
                reply(-1, "launch failed: \(error)")
            }
        }
    }

    /// Parses pfsshell's plain (non `-l`) `ls` output: one name per line,
    /// directories suffixed `/` and symlinks suffixed `@` (confirmed by
    /// reading `list_dir_objects` in Vendor/pfsshell/src/hl.c directly, not
    /// guessed). `send`'s return value includes the trailing prompt line
    /// pfsshell prints before reading its next command -- always the last
    /// line, and always ends in "> " or "# ", never a real entry -- so it's
    /// dropped unconditionally rather than pattern-matched. `ls` also always
    /// lists `./` and `../` first -- confirmed by running it against a real
    /// scratch partition, not assumed -- filtered out here so they never
    /// surface as fake games/files.
    private static func rawDirectoryEntries(in output: String) -> [(name: String, isDirectory: Bool)] {
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if !lines.isEmpty { lines.removeLast() }
        return lines.compactMap { line -> (name: String, isDirectory: Bool)? in
            var name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "./", name != "../" else { return nil }
            let isDirectory = name.hasSuffix("/")
            if isDirectory || name.hasSuffix("@") {
                name.removeLast()
            }
            return (name, isDirectory)
        }
    }

    private static func plainDirectoryEntries(in output: String) -> [String] {
        rawDirectoryEntries(in: output).map(\.name)
    }

    /// Never trust a client-supplied partition name for a partition-table-
    /// mutating operation -- restrict to the documented PopStarter
    /// convention: the games partition (`__.POPS`, plus overflow
    /// `__.POPS1`-`__.POPS10`), the shared system-files partition
    /// (`__common`), and OPL's own dedicated partition (`+OPL`, used for
    /// PS2 cover art -- see PFSDestinationPaths.oplPartitionName).
    ///
    /// Used by createPOPSPartition (creates a new partition) and
    /// removePFSFile (deletes a file). Deliberately does NOT include
    /// `__system`/`__sysconf` -- see isValidPFSPartitionNameForFileWrite,
    /// used only by putPFSFile, for those. Widening this shared list to
    /// include them too would let removePFSFile delete a file out of
    /// FreeHDBoot's own boot partitions, and let createPOPSPartition carve a
    /// new partition out of __sysconf's space -- neither operation has any
    /// legitimate reason to touch those partitions, so each gets its own
    /// narrowly-scoped allowlist instead of one list shared across
    /// structurally different operations.
    private static func isValidPFSPartitionNameForPartitionOps(_ name: String) -> Bool {
        if name == "__.POPS" || name == "__common" || name == "+OPL" { return true }
        for suffix in 1...10 where name == "__.POPS\(suffix)" {
            return true
        }
        return false
    }

    /// Used only by putPFSFile. Everything isValidPFSPartitionNameForPartitionOps
    /// allows, plus `__system`/`__sysconf` -- both created by
    /// initializeBlankAPADisk's `pfsshell initialize`, and the only two
    /// partitions FreeHDBoot's payload files (see FreeHDBootDestinationPaths)
    /// ever write into. Never `__net`, which nothing in this app writes to.
    private static func isValidPFSPartitionNameForFileWrite(_ name: String) -> Bool {
        if isValidPFSPartitionNameForPartitionOps(name) { return true }
        return name == "__system" || name == "__sysconf"
    }

    /// pfsshell's REPL has no discrete per-command exit code the way hdl_dump's
    /// argv invocations do. Every observed pfsshell error (bad arguments,
    /// "No such file or directory", non-zero command exit codes) is
    /// consistently prefixed with "(!) " -- confirmed directly from real
    /// output on real hardware (e.g. "(!) mkdir: unknown command or bad
    /// number of arguments.", "(!) pfs0:/...: No such file or directory.").
    /// An earlier version of this checked for the substring "error"
    /// case-insensitively, which does NOT appear in any of pfsshell's real
    /// error text -- that flaw caused the app to report install "success"
    /// on real hardware when nothing had actually been written. Fixed and
    /// confirmed this session; see project memory.
    private static func succeeded(_ output: String) -> Bool {
        !output.contains("(!)")
    }

    // MARK: - Independent safety check

    /// Re-derives the boot disk independently of anything the client claims --
    /// the daemon must never trust a client-supplied "this isn't the boot
    /// disk" answer, since the whole point of the privilege boundary is that
    /// the privileged side can't blindly trust the unprivileged caller.
    /// Fails closed: if this can't be determined, refuse rather than proceed.
    private func isBootDisk(devicePath: String) async -> Bool {
        let deviceIdentifier = devicePath.replacingOccurrences(of: "/dev/", with: "")
        guard let plistData = try? await runDiskutilInfo(path: "/"),
              let dict = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let parent = dict["ParentWholeDisk"] as? String
        else {
            return true
        }
        return parent == deviceIdentifier
    }

    private func runDiskutilInfo(path: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["info", "-plist", path]
            let pipe = Pipe()
            process.standardOutput = pipe

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
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
