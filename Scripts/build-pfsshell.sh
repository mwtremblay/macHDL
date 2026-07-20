#!/bin/bash
# Builds the vendored pfsshell CLI and pfsutil (PFS partition/file management
# for PS1 game support via PopStarter) and embeds+signs both inside the app
# bundle. Sibling script to build-hdl-dump.sh, adapted for Meson instead of
# Make.
#
# pfsutil is this project's own addition (Scripts/pfsutil-src/pfsutil.c): a
# one-shot, argv-based CLI for file put/list/rm, built on the
# same apa/pfs/iomanX libraries pfsshell itself uses. It replaced driving
# pfsshell's own interactive REPL over a pty for file transfer, which proved
# fragile in production (stdio buffering, argv-tokenizer quoting, prompt
# detection all caused real bugs on real hardware -- see project memory).
# pfsshell itself is still built and used for partition creation (a rare,
# one-time operation that already works correctly via its REPL).
#
# Adding pfsutil requires patching meson.build (Vendor/pfsshell-pfsutil.patch)
# to add its executable() target, so (unlike this script's pfsshell-only
# predecessor) a scratch copy is needed again -- the actual submodule
# checkout must stay pristine, matching build-hdl-dump.sh's discipline.
#
# pfsfuse (the FUSE-mount-based alternative to pfsshell's REPL for file
# transfer, tried before pfsutil) was tried and abandoned: writing files
# above ~1MB through a pfsfuse/FUSE-T mount corrupted data and, on a repeat
# attempt, panicked the kernel (nfs_vinvalbuf2/ubc_msync, errno 22 -- the
# same errno the corrupted writes returned to userspace just before the
# panic). See project memory for the full incident. Do not re-enable
# -Denable_pfsfuse=true or reintroduce a FUSE-T/macFUSE dependency here.
set -euo pipefail

: "${SRCROOT:?must run inside an Xcode build}"
: "${DERIVED_FILE_DIR:?must run inside an Xcode build}"
: "${CODESIGNING_FOLDER_PATH:?must run inside an Xcode build}"

# Xcode Run Script phases run with a minimal PATH that may not include
# Homebrew's meson/ninja/python3 -- prepend common Homebrew locations.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

VENDOR_SRC="${SRCROOT}/Vendor/pfsshell"
PATCH_FILE="${SRCROOT}/Vendor/pfsshell-pfsutil.patch"
PFSUTIL_SRC="${SRCROOT}/Scripts/pfsutil-src/pfsutil.c"
BUILD_SRC="${DERIVED_FILE_DIR}/pfsshell-src"
BUILD_DIR="${DERIVED_FILE_DIR}/pfsshell-build"

command -v meson >/dev/null 2>&1 || { echo "error: meson not found on PATH (try: brew install meson)" >&2; exit 1; }
command -v ninja >/dev/null 2>&1 || { echo "error: ninja not found on PATH (try: brew install ninja)" >&2; exit 1; }

echo "Building vendored pfsshell + pfsutil from ${VENDOR_SRC}"

# Build into a scratch copy, never in-place inside the submodule checkout --
# the meson.build patch below modifies a tracked source file, so this must
# not touch the real checkout.
rm -rf "${BUILD_SRC}"
mkdir -p "$(dirname "${BUILD_SRC}")"
cp -R "${VENDOR_SRC}" "${BUILD_SRC}"
rm -rf "${BUILD_SRC}/.git"

cp "${PFSUTIL_SRC}" "${BUILD_SRC}/src/pfsutil.c"
(cd "${BUILD_SRC}" && git apply -p1 "${PATCH_FILE}" 2>/dev/null || patch -p1 < "${PATCH_FILE}")

# pfsshell needs its own nested submodules for meson_toolchains and ps2sdk.
git -C "${VENDOR_SRC}" submodule update --init external/meson_toolchains external/ps2sdk
cp -R "${VENDOR_SRC}/external/meson_toolchains" "${BUILD_SRC}/external/"
cp -R "${VENDOR_SRC}/external/ps2sdk" "${BUILD_SRC}/external/"

rm -rf "${BUILD_DIR}"
meson setup "${BUILD_DIR}" "${BUILD_SRC}" -Denable_pfs2tar=false -Denable_pfsfuse=false
meson compile -C "${BUILD_DIR}" pfsshell pfsutil

PFSSHELL_DEST_DIR="${CODESIGNING_FOLDER_PATH}/Contents/Resources/pfsshell-bin"
mkdir -p "${PFSSHELL_DEST_DIR}"
cp "${BUILD_DIR}/pfsshell" "${PFSSHELL_DEST_DIR}/pfsshell"
cp "${BUILD_DIR}/pfsutil" "${PFSSHELL_DEST_DIR}/pfsutil"
chmod +x "${PFSSHELL_DEST_DIR}/pfsshell" "${PFSSHELL_DEST_DIR}/pfsutil"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
codesign_binary() {
    local binary="$1"
    shift
    if [ -z "${SIGN_IDENTITY}" ] || [ "${SIGN_IDENTITY}" = "-" ]; then
        echo "No real code signing identity configured; ad-hoc signing ${binary}."
        codesign --force --options runtime "$@" --sign - "${binary}"
    else
        codesign --force --options runtime --timestamp "$@" --sign "${SIGN_IDENTITY}" "${binary}"
    fi
}

codesign_binary "${PFSSHELL_DEST_DIR}/pfsshell"
codesign_binary "${PFSSHELL_DEST_DIR}/pfsutil"

echo "Embedded pfsshell at ${PFSSHELL_DEST_DIR}/pfsshell"
echo "Embedded pfsutil at ${PFSSHELL_DEST_DIR}/pfsutil"
