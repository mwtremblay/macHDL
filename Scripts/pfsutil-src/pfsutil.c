/* pfsutil -- a one-shot, argv-based CLI for PFS partition file operations,
 * built on top of the same apa/pfs/iomanX libraries pfsshell itself uses
 * (see meson.build). Written for mac-hdl-gui specifically to replace
 * driving pfsshell's interactive REPL over a pty, which proved fragile in
 * production (stdio buffering, argv-tokenizer quoting, prompt detection --
 * see project notes). Modeled directly on pfs2tar.c's proven pattern in
 * this same source tree: call _init_apa/_init_pfs/_init_hdlfs and check
 * their return codes explicitly (they return negative errno-style codes on
 * failure, they do not call exit() themselves -- only shell.c's own
 * do_device() REPL wrapper chooses to exit(1) on failure, which pfs2tar.c
 * does not do and neither does this file).
 *
 * Every subcommand does its own device-init + mount + operation + umount in
 * one process invocation and returns a real exit code (0 = success, nonzero
 * = failure) with a human-readable message on stderr -- no REPL, no prompt
 * text to parse.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "iomanX_port.h"

#define IOMANX_MOUNT_POINT "pfs0:"

/* where (image of) PS2 HDD is; in fakeps2sdk/atad.c */
extern void set_atad_device_path(const char *path);
extern void atad_close(void);

static int init_device(const char *device_path)
{
    set_atad_device_path(device_path);

    /* Mirrors shell.c's do_device() exactly -- these args are already
     * proven correct throughout this project against real hardware. */
    static const char *apa_args[] = {"ps2hdd.irx", NULL};
    int result = _init_apa(1, (char **)apa_args);
    if (result < 0) {
        fprintf(stderr, "(!) init_apa: failed with %d (%s)\n", result, strerror(-result));
        return -1;
    }

    static const char *pfs_args[] = {"pfs.irx", "-m", "1", "-o", "1", "-n", "10", NULL};
    result = _init_pfs(7, (char **)pfs_args);
    if (result < 0) {
        fprintf(stderr, "(!) init_pfs: failed with %d (%s)\n", result, strerror(-result));
        return -1;
    }

    result = _init_hdlfs(0, NULL);
    if (result < 0) {
        fprintf(stderr, "(!) init_hdlfs: failed with %d (%s)\n", result, strerror(-result));
        return -1;
    }
    return 0;
}

static int mount_partition(const char *partition_name)
{
    char mount_point[256];
    snprintf(mount_point, sizeof(mount_point), "hdd0:%s", partition_name);
    int result = iomanX_mount(IOMANX_MOUNT_POINT, mount_point, 0, NULL, 0);
    if (result < 0) {
        fprintf(stderr, "(!) mount of \"%s\" failed with %d (%s)\n", mount_point, result, strerror(-result));
        return -1;
    }
    return 0;
}

static void unmount_partition(void)
{
    iomanX_umount(IOMANX_MOUNT_POINT);
}

/* Builds "pfs0:/<subpath>", tolerating subpath being empty (root) or
 * already having a leading slash, so callers never have to think about
 * double slashes. */
static void build_pfs_path(char *out, size_t out_size, const char *subpath)
{
    while (subpath[0] == '/')
        subpath++;
    if (subpath[0] == '\0')
        snprintf(out, out_size, "%s/", IOMANX_MOUNT_POINT);
    else
        snprintf(out, out_size, "%s/%s", IOMANX_MOUNT_POINT, subpath);
}

/* Creates every path component of `dir_path` in order (e.g. "pfs0:/POPS/ART"
 * creates "pfs0:/POPS" then "pfs0:/POPS/ART"), not just the final component.
 * iomanX_mkdir (like POSIX mkdir) only creates one directory level and
 * requires its immediate parent to already exist -- a single
 * mkdir("pfs0:/POPS/ART") call silently fails when "POPS" doesn't already
 * exist yet (e.g. installing PS1 cover art before anything else has ever
 * written into __common on a freshly-initialized drive), and the open()
 * below then fails with ENOENT. Confirmed as the real cause of exactly that
 * failure on real hardware, not guessed. Best-effort per level, matching
 * this function's existing "already exists is the expected steady-state
 * outcome" semantics -- modifies dir_path in place but always restores it
 * before returning. */
static void mkdir_recursive(char *dir_path)
{
    char *p = dir_path + strlen(IOMANX_MOUNT_POINT) + 1;
    for (; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            iomanX_mkdir(dir_path, 0777);
            *p = '/';
        }
    }
    iomanX_mkdir(dir_path, 0777);
}

static int cmd_put(const char *partition_name, const char *pfs_dest_dir, const char *pfs_dest_filename, const char *local_source_path)
{
    /* O_NOFOLLOW: this runs as the privileged helper, and local_source_path
     * ultimately traces back to app-archive contents the app extracted from
     * a user-downloaded .zip/.rar (see AppsService.installApp's own
     * symlink rejection during enumeration). Refusing to follow a symlink
     * here too, at the one choke point every `put` call (apps, videos, PS1
     * game files, cover art) goes through, means a symlink slipping past
     * any future/other caller still can't make this privileged process
     * read an arbitrary local file (e.g. ~/.ssh/id_rsa) and copy its
     * contents onto the PS2 drive. */
    int in_file = open(local_source_path, O_RDONLY | O_NOFOLLOW);
    if (in_file == -1) {
        fprintf(stderr, "(!) %s: %s\n", local_source_path, strerror(errno));
        return 1;
    }

    if (mount_partition(partition_name) != 0) {
        close(in_file);
        return 1;
    }

    int retval = 0;
    char dest_path[768];

    if (pfs_dest_dir[0] != '\0') {
        char dir_path[512];
        build_pfs_path(dir_path, sizeof(dir_path), pfs_dest_dir);
        /* Best-effort: "already exists" is the expected outcome on every
         * call after the first for a given directory. Only a subsequent
         * open() failure below is treated as a real error. */
        mkdir_recursive(dir_path);
        snprintf(dest_path, sizeof(dest_path), "%s/%s", dir_path, pfs_dest_filename);
    } else {
        build_pfs_path(dest_path, sizeof(dest_path), pfs_dest_filename);
    }

    int out_file = iomanX_open(dest_path, FIO_O_WRONLY | FIO_O_CREAT, 0666);
    if (out_file >= 0) {
        char buf[4096 * 16];
        long len;
        while ((len = read(in_file, buf, sizeof(buf))) > 0) {
            int written = iomanX_write(out_file, buf, (int)len);
            if (written < 0) {
                /* A negative return is an errno-style code (e.g. -ENOSPC
                 * when the partition is full), not a partial-write byte
                 * count -- confirmed empirically against a real filled-up
                 * scratch PFS partition ("wrote -28 of 65536 bytes" before
                 * this fix). strerror() gives a stable, portable message
                 * ("No space left on device") the app can match on, instead
                 * of a raw negative number tied to a specific errno value. */
                fprintf(stderr, "(!) %s: write failed: %s\n", dest_path, strerror(-written));
                retval = 1;
                break;
            } else if (written != (int)len) {
                fprintf(stderr, "(!) %s: write failed (wrote %d of %ld bytes)\n", dest_path, written, len);
                retval = 1;
                break;
            }
        }
        if (len < 0) {
            fprintf(stderr, "(!) %s: %s\n", local_source_path, strerror(errno));
            retval = 1;
        }
        int close_result = iomanX_close(out_file);
        if (close_result < 0) {
            fprintf(stderr, "(!) %s: close failed with %d\n", dest_path, close_result);
            retval = 1;
        }
    } else {
        fprintf(stderr, "(!) %s: create failed with %d (%s)\n", dest_path, out_file, strerror(-out_file));
        retval = 1;
    }

    close(in_file);
    unmount_partition();
    return retval;
}

/* Reverse of cmd_put -- reads a single file out of the PFS partition and
 * writes it to a local path. Added for the game-artwork-display feature:
 * showing a previously-fetched cover in the app needs to read it back off
 * the drive, since nothing before this kept a local copy around. */
static int cmd_get(const char *partition_name, const char *pfs_path, const char *local_dest_path)
{
    if (mount_partition(partition_name) != 0)
        return 1;

    char src_path[512];
    build_pfs_path(src_path, sizeof(src_path), pfs_path);

    int retval = 0;
    int in_file = iomanX_open(src_path, FIO_O_RDONLY, 0);
    if (in_file >= 0) {
        int out_file = open(local_dest_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (out_file >= 0) {
            char buf[4096 * 16];
            int len;
            while ((len = iomanX_read(in_file, buf, sizeof(buf))) > 0) {
                ssize_t written = write(out_file, buf, (size_t)len);
                if (written != len) {
                    fprintf(stderr, "(!) %s: write failed (wrote %zd of %d bytes)\n", local_dest_path, written, len);
                    retval = 1;
                    break;
                }
            }
            if (len < 0) {
                fprintf(stderr, "(!) %s: read failed with %d (%s)\n", src_path, len, strerror(-len));
                retval = 1;
            }
            close(out_file);
        } else {
            fprintf(stderr, "(!) %s: %s\n", local_dest_path, strerror(errno));
            retval = 1;
        }
        iomanX_close(in_file);
    } else {
        fprintf(stderr, "(!) %s: %s\n", src_path, strerror(-in_file));
        retval = 1;
    }

    unmount_partition();
    return retval;
}

/* Prints one name per line, matching pfsshell's own plain (non -l) `ls`
 * format exactly: directories suffixed '/', symlinks suffixed '@' -- so the
 * app's existing Swift-side parser for that format keeps working unchanged. */
static int cmd_list(const char *partition_name, const char *pfs_path)
{
    if (mount_partition(partition_name) != 0)
        return 1;

    char dir_path[512];
    build_pfs_path(dir_path, sizeof(dir_path), pfs_path);

    int retval = 0;
    int dh = iomanX_dopen(dir_path);
    if (dh >= 0) {
        iox_dirent_t dirent;
        int result;
        while ((result = iomanX_dread(dh, &dirent)) && result != -1) {
            const char *suffix = "";
            if (FIO_S_ISDIR(dirent.stat.mode))
                suffix = "/";
            else if (FIO_S_ISLNK(dirent.stat.mode))
                suffix = "@";
            printf("%s%s\n", dirent.name, suffix);
        }
        iomanX_close(dh);
    } else {
        fprintf(stderr, "(!) %s: %s\n", dir_path, strerror(-dh));
        retval = 1;
    }

    unmount_partition();
    return retval;
}

/* Removes a single file. Refuses to touch the partition root (an empty or
 * "/" pfs_path) as a defensive guard against a caller-side bug ever turning
 * into a wildcard-style deletion. */
static int cmd_rm(const char *partition_name, const char *pfs_path)
{
    while (pfs_path[0] == '/')
        pfs_path++;
    if (pfs_path[0] == '\0') {
        fprintf(stderr, "(!) refusing to remove the partition root\n");
        return 1;
    }

    if (mount_partition(partition_name) != 0)
        return 1;

    char file_path[512];
    build_pfs_path(file_path, sizeof(file_path), pfs_path);

    int retval = 0;
    int remove_result = iomanX_remove(file_path);
    if (remove_result < 0) {
        fprintf(stderr, "(!) %s: remove failed with %d (%s)\n", file_path, remove_result, strerror(-remove_result));
        retval = 1;
    }

    unmount_partition();
    return retval;
}

/* Recursively removes every file and subdirectory under dir_path, then
 * dir_path itself. iomanX_rmdir (unlike iomanX_remove) requires its target to
 * already be an empty directory, so a naive top-down rm-then-rmdir would fail
 * with ENOTEMPTY at the first non-empty directory -- this empties bottom-up
 * instead: for the current directory, every entry is either removed directly
 * (files) or recursed into first (subdirectories, post-order) so their
 * contents/directory are gone before this function rmdir's the current
 * directory on the way back up. */
static int rmtree_recursive(const char *dir_path)
{
    int dh = iomanX_dopen(dir_path);
    if (dh < 0) {
        fprintf(stderr, "(!) %s: %s\n", dir_path, strerror(-dh));
        return -1;
    }

    int retval = 0;
    iox_dirent_t dirent;
    int result;
    while ((result = iomanX_dread(dh, &dirent)) && result != -1) {
        if (strcmp(dirent.name, ".") == 0 || strcmp(dirent.name, "..") == 0)
            continue;

        char child_path[768];
        snprintf(child_path, sizeof(child_path), "%s/%s", dir_path, dirent.name);

        if (FIO_S_ISDIR(dirent.stat.mode)) {
            if (rmtree_recursive(child_path) != 0)
                retval = -1;
        } else {
            int remove_result = iomanX_remove(child_path);
            if (remove_result < 0) {
                fprintf(stderr, "(!) %s: remove failed with %d (%s)\n", child_path, remove_result, strerror(-remove_result));
                retval = -1;
            }
        }
    }
    iomanX_close(dh);

    int rmdir_result = iomanX_rmdir(dir_path);
    if (rmdir_result < 0) {
        fprintf(stderr, "(!) %s: rmdir failed with %d (%s)\n", dir_path, rmdir_result, strerror(-rmdir_result));
        retval = -1;
    }
    return retval;
}

/* Removes an entire directory tree. Refuses to touch the partition root,
 * matching cmd_rm's identical existing guard. */
static int cmd_rmtree(const char *partition_name, const char *pfs_path)
{
    while (pfs_path[0] == '/')
        pfs_path++;
    if (pfs_path[0] == '\0') {
        fprintf(stderr, "(!) refusing to remove the partition root\n");
        return 1;
    }

    if (mount_partition(partition_name) != 0)
        return 1;

    char dir_path[512];
    build_pfs_path(dir_path, sizeof(dir_path), pfs_path);

    int retval = rmtree_recursive(dir_path) == 0 ? 0 : 1;

    unmount_partition();
    return retval;
}

static void show_usage(const char *prog)
{
    fprintf(stderr,
            "Usage:\n"
            "  %s put <device> <partition> <destDir> <destFilename> <localSourcePath>\n"
            "  %s get <device> <partition> <pfsPath> <localDestPath>\n"
            "  %s list <device> <partition> <path>\n"
            "  %s rm <device> <partition> <path>\n"
            "  %s rmtree <device> <partition> <path>\n"
            "(destDir may be empty (\"\") for the partition root)\n",
            prog, prog, prog, prog, prog);
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        show_usage(argv[0]);
        return 1;
    }

    const char *command = argv[1];
    int result;

    if (strcmp(command, "put") == 0) {
        if (argc != 7) {
            show_usage(argv[0]);
            return 1;
        }
        if (init_device(argv[2]) != 0)
            return 1;
        result = cmd_put(argv[3], argv[4], argv[5], argv[6]);
    } else if (strcmp(command, "get") == 0) {
        if (argc != 6) {
            show_usage(argv[0]);
            return 1;
        }
        if (init_device(argv[2]) != 0)
            return 1;
        result = cmd_get(argv[3], argv[4], argv[5]);
    } else if (strcmp(command, "list") == 0) {
        if (argc != 5) {
            show_usage(argv[0]);
            return 1;
        }
        if (init_device(argv[2]) != 0)
            return 1;
        result = cmd_list(argv[3], argv[4]);
    } else if (strcmp(command, "rm") == 0) {
        if (argc != 5) {
            show_usage(argv[0]);
            return 1;
        }
        if (init_device(argv[2]) != 0)
            return 1;
        result = cmd_rm(argv[3], argv[4]);
    } else if (strcmp(command, "rmtree") == 0) {
        if (argc != 5) {
            show_usage(argv[0]);
            return 1;
        }
        if (init_device(argv[2]) != 0)
            return 1;
        result = cmd_rmtree(argv[3], argv[4]);
    } else {
        show_usage(argv[0]);
        return 1;
    }

    atad_close();
    return result;
}
