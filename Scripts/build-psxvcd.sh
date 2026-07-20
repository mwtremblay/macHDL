#!/bin/bash
# Builds the vendored psx-vcd CLI (split/multi-file BIN+CUE dump merging for
# PS1 game support) and embeds + signs it inside the app bundle. Sibling
# script to build-cue2pops.sh, adapted for Cargo instead of Make.
#
# psx-vcd is used for exactly one narrow purpose in this app: merging a
# split dump's multiple .bin files into a single combined .bin/.cue pair
# (its `combine` subcommand only). The resulting combined .cue is then fed
# into the existing, hardware-verified cue2pops-mac path for the actual
# .VCD conversion -- psx-vcd's own `auto`/`convert` VCD-writing behavior is
# never invoked by this app. This is a deliberate trust-boundary decision:
# psx-vcd is a low-maturity, single-author tool (v0.1.1, 5 commits total in
# a single 2-day burst, no releases) compared to every other tool vendored
# in this project, so its blast radius is kept to the one thing cue2pops
# fundamentally cannot do (cue2pops rejects split dumps outright -- see
# Vendor/cue2pops-mac/cue2pops.c's binary_count check).
#
# Confirmed via hands-on standalone testing before this script was written
# (not just README-reading, per project practice): `combine` exits 0 on
# success / 1 on failure (standard Rust/anyhow convention -- NOT cue2pops's
# inverted 1=success), writes all output to stdout on success and error
# text to stderr on failure, and `-f <name>` produces a BIN file named
# exactly `<name>` (no extension appended) plus `<name>.cue`.
set -euo pipefail

: "${SRCROOT:?must run inside an Xcode build}"
: "${DERIVED_FILE_DIR:?must run inside an Xcode build}"
: "${CODESIGNING_FOLDER_PATH:?must run inside an Xcode build}"

# Xcode Run Script phases run with a minimal PATH -- prepend common Homebrew
# and rustup install locations for cargo (same reasoning as
# build-pfsshell.sh's meson/ninja PATH prepend).
export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.cargo/bin:${PATH}"

command -v cargo >/dev/null 2>&1 || { echo "error: cargo not found on PATH (try: brew install rust, or https://rustup.rs)" >&2; exit 1; }

VENDOR_SRC="${SRCROOT}/Vendor/psx-vcd"
BUILD_DIR="${DERIVED_FILE_DIR}/psxvcd-build"
DEST_DIR="${CODESIGNING_FOLDER_PATH}/Contents/Resources/psxvcd-bin"
DEST_BINARY="${DEST_DIR}/psx-vcd"

echo "Building vendored psx-vcd from ${VENDOR_SRC}"

# Build into a scratch copy, never in-place inside the submodule checkout --
# Cargo's target/ build output would otherwise land in the tracked checkout
# (same reasoning as build-hdl-dump.sh/build-cue2pops.sh).
rm -rf "${BUILD_DIR}"
mkdir -p "$(dirname "${BUILD_DIR}")"
cp -R "${VENDOR_SRC}" "${BUILD_DIR}"
rm -rf "${BUILD_DIR}/.git"

(cd "${BUILD_DIR}" && cargo build --release)

mkdir -p "${DEST_DIR}"
cp "${BUILD_DIR}/target/release/psx-vcd" "${DEST_BINARY}"
chmod +x "${DEST_BINARY}"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ] || [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "No real code signing identity configured; ad-hoc signing psx-vcd."
    codesign --force --options runtime --sign - "${DEST_BINARY}"
else
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${DEST_BINARY}"
fi

echo "Embedded psx-vcd at ${DEST_BINARY}"
