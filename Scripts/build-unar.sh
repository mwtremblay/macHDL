#!/bin/bash
# Builds the vendored `unar` CLI (archive extraction for FreeMcBoot/FreeHDBoot
# homebrew "apps" installs -- .zip/.7z/.rar) and embeds + signs it inside the
# app bundle. Sibling script to build-cue2pops.sh: unar never touches the PS2
# HDD either -- it's pure local-filesystem extraction on the Mac, so it's
# embedded in the app target's own Resources, not the helper's.
#
# Source: MacPaw/XADMaster (LGPL-2.1-or-later), pinned to tag v1.10.8, plus
# its MacPaw/universal-detector dependency (tag 1.1) -- the exact source/tags
# Homebrew's own "unar" formula builds from (Formula/u/unar.rb). Unlike
# cue2pops-mac's bare Makefile, this is an Xcode-project build with a
# secondary dependency, mirroring that formula's `install` recipe as closely
# as possible for a local, unprivileged, subprocess-invoked binary (never
# statically linked into this app -- see AppArchiveExtractor's doc comment
# for why that keeps LGPL compliance simple).
set -euo pipefail

: "${SRCROOT:?must run inside an Xcode build}"
: "${DERIVED_FILE_DIR:?must run inside an Xcode build}"
: "${CODESIGNING_FOLDER_PATH:?must run inside an Xcode build}"

XADMASTER_SRC="${SRCROOT}/Vendor/XADMaster"
UNIVERSAL_DETECTOR_SRC="${SRCROOT}/Vendor/universal-detector"
BUILD_ROOT="${DERIVED_FILE_DIR}/unar-build"
XADMASTER_BUILD="${BUILD_ROOT}/XADMaster"
DEST_DIR="${CODESIGNING_FOLDER_PATH}/Contents/Resources/unar-bin"
DEST_BINARY="${DEST_DIR}/unar"

echo "Building vendored unar from ${XADMASTER_SRC}"

# Build into a scratch copy, never in-place inside the submodule checkouts --
# same reasoning as build-cue2pops.sh/build-hdl-dump.sh. universal-detector
# must land as a sibling directory literally named "UniversalDetector" (not
# "universal-detector") -- XADMaster's project file expects it there, matching
# how Homebrew's own formula stages it (`resource("universal-detector").stage
# buildpath/"../UniversalDetector"`).
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}"
cp -R "${XADMASTER_SRC}" "${XADMASTER_BUILD}"
rm -rf "${XADMASTER_BUILD}/.git"
cp -R "${UNIVERSAL_DETECTOR_SRC}" "${BUILD_ROOT}/UniversalDetector"
rm -rf "${BUILD_ROOT}/UniversalDetector/.git"

# Same two patches Homebrew's formula applies for a clean Release build:
# link against libc++ instead of the removed libstdc++, and avoid a
# __DATE__ macro (non-reproducible, and not meaningful for a local build).
sed -i '' 's/libstdc++\.6\.dylib/libc++.1.dylib/g' "${XADMASTER_BUILD}/XADMaster.xcodeproj/project.pbxproj"
BUILD_DATE="$(date '+%b %d %Y')"
sed -i '' "s/@__DATE__/@\"${BUILD_DATE}\"/g" "${XADMASTER_BUILD}/lsar.m" "${XADMASTER_BUILD}/unar.m"

SYMROOT="${XADMASTER_BUILD}/build"
NATIVE_ARCH="$(uname -m)"

# Run the nested xcodebuild with a sanitized environment: this script itself
# runs as a Run Script build phase inside the OUTER mac-hdl-gui build, which
# sets a large number of its own build-setting env vars (PRODUCT_NAME,
# WRAPPER_NAME, EXECUTABLE_NAME, etc.). Left inherited, those leak into and
# corrupt XADMaster's own (unrelated) product naming -- confirmed by an
# initial run of this script producing a bogus "macHDL.app" inside
# XADMaster's own build output. `env -i` with an explicit minimal
# passthrough avoids that entirely.
run_xcodebuild() {
    env -i PATH="${PATH}" HOME="${HOME}" ${DEVELOPER_DIR:+DEVELOPER_DIR="${DEVELOPER_DIR}"} \
        xcodebuild "$@"
}

run_xcodebuild -target XADMaster -project "${XADMASTER_BUILD}/XADMaster.xcodeproj" \
    SYMROOT="${SYMROOT}" -configuration Release ARCHS="${NATIVE_ARCH}" ONLY_ACTIVE_ARCH=YES
run_xcodebuild -target unar -project "${XADMASTER_BUILD}/XADMaster.xcodeproj" \
    SYMROOT="${SYMROOT}" -configuration Release ARCHS="${NATIVE_ARCH}" ONLY_ACTIVE_ARCH=YES

mkdir -p "${DEST_DIR}"
cp "${SYMROOT}/Release/unar" "${DEST_BINARY}"
chmod +x "${DEST_BINARY}"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ] || [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "No real code signing identity configured; ad-hoc signing unar."
    codesign --force --options runtime --sign - "${DEST_BINARY}"
else
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${DEST_BINARY}"
fi

echo "Embedded unar at ${DEST_BINARY}"
