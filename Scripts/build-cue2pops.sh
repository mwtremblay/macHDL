#!/bin/bash
# Builds the vendored cue2pops-mac CLI (BIN/CUE -> IMAGE0.VCD conversion for
# PS1 games via PopStarter) and embeds + signs it inside the app bundle.
# Sibling script to build-hdl-dump.sh. Unlike hdl_dump/pfsshell, this tool
# never touches the PS2 HDD -- it's pure local-filesystem conversion on the
# Mac, so it's embedded in the app target's own Resources, not the helper's.
set -euo pipefail

: "${SRCROOT:?must run inside an Xcode build}"
: "${DERIVED_FILE_DIR:?must run inside an Xcode build}"
: "${CODESIGNING_FOLDER_PATH:?must run inside an Xcode build}"

VENDOR_SRC="${SRCROOT}/Vendor/cue2pops-mac"
BUILD_DIR="${DERIVED_FILE_DIR}/cue2pops-build"
DEST_DIR="${CODESIGNING_FOLDER_PATH}/Contents/Resources/cue2pops-bin"
DEST_BINARY="${DEST_DIR}/cue2pops"

echo "Building vendored cue2pops-mac from ${VENDOR_SRC}"

# Build into a scratch copy, never in-place inside the submodule checkout --
# its Makefile compiles+links directly into the source directory, so without
# this the checkout would get a build artifact left in it (same reasoning as
# build-hdl-dump.sh, no patch needed here though -- this tool builds as-is).
rm -rf "${BUILD_DIR}"
mkdir -p "$(dirname "${BUILD_DIR}")"
cp -R "${VENDOR_SRC}" "${BUILD_DIR}"
rm -rf "${BUILD_DIR}/.git"

MAKE_BIN="$(command -v gmake || command -v make)"
"${MAKE_BIN}" -C "${BUILD_DIR}"

mkdir -p "${DEST_DIR}"
cp "${BUILD_DIR}/cue2pops" "${DEST_BINARY}"
chmod +x "${DEST_BINARY}"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ] || [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "No real code signing identity configured; ad-hoc signing cue2pops."
    codesign --force --options runtime --sign - "${DEST_BINARY}"
else
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${DEST_BINARY}"
fi

echo "Embedded cue2pops at ${DEST_BINARY}"
