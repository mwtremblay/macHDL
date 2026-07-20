#!/bin/bash
# Builds the vendored hdl-dump CLI (with the mac-hdl-gui delete patch applied)
# and embeds + signs it inside the app bundle. Invoked as an Xcode "Run Script"
# build phase (see project.yml, preBuildScripts).
set -euo pipefail

: "${SRCROOT:?must run inside an Xcode build}"
: "${DERIVED_FILE_DIR:?must run inside an Xcode build}"
: "${CODESIGNING_FOLDER_PATH:?must run inside an Xcode build}"

VENDOR_SRC="${SRCROOT}/Vendor/hdl-dump"
PATCH_FILE="${SRCROOT}/Vendor/hdl-dump-macos.patch"
BUILD_DIR="${DERIVED_FILE_DIR}/hdl-dump-build"
DEST_DIR="${CODESIGNING_FOLDER_PATH}/Contents/Resources/hdl-dump-bin"
DEST_BINARY="${DEST_DIR}/hdl_dump"

echo "Building vendored hdl-dump from ${VENDOR_SRC}"

# Build into a scratch copy, never in-place inside the submodule checkout, so
# the checkout stays pristine and Debug/Release builds don't collide.
rm -rf "${BUILD_DIR}"
mkdir -p "$(dirname "${BUILD_DIR}")"
cp -R "${VENDOR_SRC}" "${BUILD_DIR}"
rm -rf "${BUILD_DIR}/.git" # plain copy, not a git checkout -- keeps `git apply` from getting confused by the submodule's gitlink

(cd "${BUILD_DIR}" && git apply -p1 "${PATCH_FILE}")

MAKE_BIN="$(command -v gmake || command -v make)"
"${MAKE_BIN}" -C "${BUILD_DIR}" RELEASE=yes USE_THREADED_IIN=no IIN_OPTICAL_MMAP=no

mkdir -p "${DEST_DIR}"
cp "${BUILD_DIR}/hdl_dump" "${DEST_BINARY}"
chmod +x "${DEST_BINARY}"

# Sign the embedded binary independently so it carries a valid signature
# inside the app bundle (required groundwork for eventual notarization, even
# though full notarization setup is out of scope for now). Falls back to
# ad-hoc signing for local "Sign to Run Locally" development builds where no
# real identity is configured.
SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ] || [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "No real code signing identity configured; ad-hoc signing hdl_dump."
    codesign --force --options runtime --sign - "${DEST_BINARY}"
else
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${DEST_BINARY}"
fi

echo "Embedded hdl_dump at ${DEST_BINARY}"
