#!/bin/bash
# Embeds the built mac-hdl-gui-helper privileged daemon (and its launchd
# plist) into the app bundle at the exact paths SMAppService.daemon expects,
# and codesigns the daemon binary independently. Sibling script to
# build-hdl-dump.sh -- same copy+codesign pattern, applied to a different
# artifact (an Xcode target's own build product, rather than an externally
# vendored C project). Invoked as an Xcode "Run Script" build phase
# (postCompileScripts in project.yml) on the mac-hdl-gui target, ordered
# after the mac-hdl-gui-helper target via an explicit target dependency.
set -euo pipefail

: "${SRCROOT:?must run inside an Xcode build}"
: "${BUILT_PRODUCTS_DIR:?must run inside an Xcode build}"
: "${CODESIGNING_FOLDER_PATH:?must run inside an Xcode build}"

HELPER_PRODUCT_NAME="com.michaeltremblay.machdl.helper"
HELPER_BUILT_PATH="${BUILT_PRODUCTS_DIR}/${HELPER_PRODUCT_NAME}"
PLIST_SRC="${SRCROOT}/HelperTool/${HELPER_PRODUCT_NAME}.plist"

HELPER_TOOLS_DIR="${CODESIGNING_FOLDER_PATH}/Contents/Library/HelperTools"
LAUNCH_DAEMONS_DIR="${CODESIGNING_FOLDER_PATH}/Contents/Library/LaunchDaemons"

if [ ! -f "${HELPER_BUILT_PATH}" ]; then
    echo "error: helper tool product not found at ${HELPER_BUILT_PATH} -- is mac-hdl-gui-helper a target dependency?" >&2
    exit 1
fi
if [ ! -f "${PLIST_SRC}" ]; then
    echo "error: launchd plist not found at ${PLIST_SRC}" >&2
    exit 1
fi

mkdir -p "${HELPER_TOOLS_DIR}" "${LAUNCH_DAEMONS_DIR}"
cp "${HELPER_BUILT_PATH}" "${HELPER_TOOLS_DIR}/${HELPER_PRODUCT_NAME}"
chmod +x "${HELPER_TOOLS_DIR}/${HELPER_PRODUCT_NAME}"
cp "${PLIST_SRC}" "${LAUNCH_DAEMONS_DIR}/${HELPER_PRODUCT_NAME}.plist"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ] || [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "No real code signing identity configured; ad-hoc signing the helper."
    codesign --force --options runtime --sign - "${HELPER_TOOLS_DIR}/${HELPER_PRODUCT_NAME}"
else
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${HELPER_TOOLS_DIR}/${HELPER_PRODUCT_NAME}"
fi

echo "Embedded privileged helper at ${HELPER_TOOLS_DIR}/${HELPER_PRODUCT_NAME}"
echo "Embedded launchd plist at ${LAUNCH_DAEMONS_DIR}/${HELPER_PRODUCT_NAME}.plist"
