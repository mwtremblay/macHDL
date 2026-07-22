#!/bin/bash
# Builds a Release configuration of macHDL and zips it into dist/ for
# publishing as a GitHub release asset (see RELEASING.md). Not an Xcode Run
# Script build phase (unlike every other Scripts/*.sh here) -- this is
# invoked directly from the command line as part of the release process.
#
# IMPORTANT: uses an out-of-repo -derivedDataPath (never something under
# this repo, e.g. never ./build). The vendored pfsshell/pfsutil build
# (Scripts/build-pfsshell.sh) patches a scratch copy of meson.build via
# `git apply`, and git apply silently no-ops ("Skipped patch") when that
# scratch copy sits inside a path this repo's own .gitignore excludes
# (e.g. a derived-data dir nested under ./build) -- discovered directly
# during this project's first-ever CLI Release build. hdl_dump/pfsutil never
# actually get built in that case, and the *first* symptom is a confusing
# "Can't invoke target `pfsutil`: target not found" meson error deep in the
# build log, not anything that points back to derivedDataPath. Building
# outside the repo entirely sidesteps this.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    VERSION="$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([0-9.]+)".*/\1/')"
fi
if [ -z "${VERSION}" ]; then
    echo "error: could not determine version (pass one explicitly: package-release.sh 1.2.3)" >&2
    exit 1
fi

DERIVED_DATA_PATH="$(mktemp -d /tmp/macHDL-release-build.XXXXXX)"
DIST_DIR="${REPO_ROOT}/dist"
ZIP_PATH="${DIST_DIR}/macHDL-${VERSION}.zip"

echo "Building macHDL ${VERSION} (Release) into ${DERIVED_DATA_PATH}..."
xcodebuild -project mac-hdl-gui.xcodeproj -scheme mac-hdl-gui -configuration Release \
    -derivedDataPath "${DERIVED_DATA_PATH}" build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/macHDL.app"
if [ ! -d "${APP_PATH}" ]; then
    echo "error: expected build output not found at ${APP_PATH}" >&2
    exit 1
fi

BUILT_VERSION="$(defaults read "${APP_PATH}/Contents/Info.plist" CFBundleShortVersionString)"
if [ "${BUILT_VERSION}" != "${VERSION}" ]; then
    echo "error: built app reports version ${BUILT_VERSION}, expected ${VERSION} -- is project.yml out of sync?" >&2
    exit 1
fi

mkdir -p "${DIST_DIR}"
rm -f "${ZIP_PATH}"

# ditto, not zip -- preserves the resource forks/extended attributes/code
# signature a plain `zip` of a signed .app bundle would otherwise mangle.
echo "Packaging ${APP_PATH} -> ${ZIP_PATH}..."
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

rm -rf "${DERIVED_DATA_PATH}"

echo "Done: ${ZIP_PATH}"
