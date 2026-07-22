#!/bin/bash
# Builds a minimal, vendored `ffmpeg` (used to convert arbitrary source video
# into the MPEG-4/Xvid-tagged AVI + MP3 format Simple Media System (SMS, a
# PS2 homebrew video player) can actually decode -- see VideoConverter) and
# embeds + signs it inside the app bundle. Never touches the PS2 HDD -- pure
# local-filesystem conversion, same reasoning as build-cue2pops.sh/build-unar.sh.
#
# Unlike every other vendored tool here (all live in actively-tagged git
# repos, hence .gitmodules submodules), ffmpeg's and LAME's canonical
# distribution is numbered release tarballs -- vendored here as plain,
# committed source tarballs under Vendor/ instead (Vendor/ffmpeg-src,
# Vendor/lame-src), matching this project's existing "bundle every CLI
# tool's source, no network needed to build" philosophy for every other
# Vendor/ entry. Sources/checksums confirmed against Homebrew's own
# ffmpeg.rb/lame.rb formulas, and the exact URLs explicitly confirmed with
# the user before first downloading:
#   - ffmpeg 8.1.2:  https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz
#   - LAME 4.0:      https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz
#     (needed for MP3 -- ffmpeg has no LGPL-clean built-in MP3 encoder,
#     libmp3lame requires vendoring LAME itself as a third dependency)
set -euo pipefail

: "${SRCROOT:?must run inside an Xcode build}"
: "${DERIVED_FILE_DIR:?must run inside an Xcode build}"
: "${CODESIGNING_FOLDER_PATH:?must run inside an Xcode build}"

FFMPEG_VERSION="8.1.2"
FFMPEG_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
FFMPEG_TARBALL="${SRCROOT}/Vendor/ffmpeg-src/ffmpeg-${FFMPEG_VERSION}.tar.xz"

LAME_VERSION="4.0"
LAME_SHA256="3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb"
LAME_TARBALL="${SRCROOT}/Vendor/lame-src/lame-${LAME_VERSION}.tar.gz"

NATIVE_ARCH="$(uname -m)"

# Persistent (not DERIVED_FILE_DIR-scoped) cache under the repo's own
# gitignored build/ directory -- ffmpeg's own configure+make is by far the
# slowest build in this project (a full decoder/demuxer set, even with a
# minimal encoder/muxer list), and re-running it on every single Xcode build
# -- or every time DerivedData is wiped -- would make iterating on anything
# else in this app painfully slow. Keyed by version+arch+BUILD_SCRIPT_REVISION:
# a newer FFMPEG_VERSION/LAME_VERSION, or bumping the revision below whenever
# the configure flags change, automatically invalidates stale cached binaries
# (bumped once already: v1 linked against Homebrew's libX11.6.dylib, since
# ffmpeg's vaapi hwaccel auto-detects xlib via whatever X11 dev headers
# happen to be on the build machine, regardless of --disable-devices/
# --disable-indevs/--disable-outdevs -- fixed with --disable-xlib
# --disable-vaapi below).
BUILD_SCRIPT_REVISION="2"
CACHE_ROOT="${SRCROOT}/build/ffmpeg-vendor-cache"
CACHED_BINARY="${CACHE_ROOT}/ffmpeg-${FFMPEG_VERSION}-lame${LAME_VERSION}-${NATIVE_ARCH}-r${BUILD_SCRIPT_REVISION}"

DEST_DIR="${CODESIGNING_FOLDER_PATH}/Contents/Resources/ffmpeg-bin"
DEST_BINARY="${DEST_DIR}/ffmpeg"

# Runs configure/make with a sanitized environment: this script runs as a Run
# Script build phase inside the OUTER mac-hdl-gui build, which sets a large
# number of its own env vars (SDKROOT, ARCHS, CFLAGS-like settings, etc.).
# autoconf configure scripts read several of these directly (CC, CFLAGS,
# LDFLAGS) -- left inherited, they can silently corrupt the probed compiler
# flags. `env -i` with an explicit minimal passthrough avoids that, same
# fix (and same reasoning) as build-unar.sh's nested-xcodebuild wrapper.
run_sandboxed() {
    env -i PATH="${PATH}" HOME="${HOME}" "$@"
}

verify_sha256() {
    local dest="$1" expected_sha256="$2"
    local actual_sha256
    actual_sha256="$(shasum -a 256 "${dest}" | awk '{print $1}')"
    if [ "${actual_sha256}" != "${expected_sha256}" ]; then
        echo "error: $(basename "${dest}") sha256 mismatch (expected ${expected_sha256}, got ${actual_sha256}) -- committed Vendor/ tarball may be corrupt or tampered with" >&2
        exit 1
    fi
}

verify_sha256 "${FFMPEG_TARBALL}" "${FFMPEG_SHA256}"
verify_sha256 "${LAME_TARBALL}" "${LAME_SHA256}"

if [ ! -f "${CACHED_BINARY}" ]; then
    echo "No cached ffmpeg binary for ${FFMPEG_VERSION}/lame${LAME_VERSION}/${NATIVE_ARCH} -- building from source (this can take a while)."

    BUILD_ROOT="${DERIVED_FILE_DIR}/ffmpeg-build"
    rm -rf "${BUILD_ROOT}"
    mkdir -p "${BUILD_ROOT}"
    tar xf "${LAME_TARBALL}" -C "${BUILD_ROOT}"
    tar xf "${FFMPEG_TARBALL}" -C "${BUILD_ROOT}"

    LAME_SRC="${BUILD_ROOT}/lame-${LAME_VERSION}"
    LAME_INSTALL="${BUILD_ROOT}/lame-install"
    FFMPEG_SRC="${BUILD_ROOT}/ffmpeg-${FFMPEG_VERSION}"

    NPROC="$(sysctl -n hw.ncpu)"

    echo "Building vendored LAME (libmp3lame only, no frontend/decoder)..."
    (
        cd "${LAME_SRC}"
        run_sandboxed ./configure --prefix="${LAME_INSTALL}" \
            --enable-static --disable-shared --disable-frontend --disable-decoder
        run_sandboxed make -j"${NPROC}"
        run_sandboxed make install
    )

    # Encoders/muxers/filters are locked down to exactly what SMS-targeted
    # AVI output needs (see VideoConverter.arguments -- mpeg4/xvid video,
    # libmp3lame audio, AVI container); decoders/demuxers/protocols are left
    # at their configure default (everything) since accepting "all commonly
    # used video formats" as input is the whole point of this feature.
    # --disable-gpl fails this configure step outright if anything enabled
    # here secretly required GPL -- confirmed clean (License: LGPL version
    # 2.1 or later) with exactly this flag set during development.
    echo "Configuring vendored ffmpeg..."
    (
        cd "${FFMPEG_SRC}"
        run_sandboxed ./configure \
            --disable-shared --enable-static \
            --disable-programs --enable-ffmpeg \
            --disable-doc --disable-debug \
            --disable-gpl --disable-nonfree --disable-version3 \
            --disable-encoders --enable-encoder=mpeg4,libmp3lame,pcm_s16le \
            --disable-muxers --enable-muxer=avi \
            --disable-filters --enable-filter=scale,pad,fps,aresample,aformat,format,anull,null,setsar,setpts \
            --disable-devices --disable-indevs --disable-outdevs \
            --disable-xlib --disable-vaapi \
            --enable-libmp3lame \
            --extra-cflags="-I${LAME_INSTALL}/include" \
            --extra-ldflags="-L${LAME_INSTALL}/lib"

        echo "Building vendored ffmpeg (slow -- full decoder/demuxer set)..."
        run_sandboxed make -j"${NPROC}"
    )

    mkdir -p "${CACHE_ROOT}"
    cp "${FFMPEG_SRC}/ffmpeg" "${CACHED_BINARY}"
else
    echo "Using cached ffmpeg binary at ${CACHED_BINARY}"
fi

mkdir -p "${DEST_DIR}"
cp "${CACHED_BINARY}" "${DEST_BINARY}"
chmod +x "${DEST_BINARY}"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ] || [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "No real code signing identity configured; ad-hoc signing ffmpeg."
    codesign --force --options runtime --sign - "${DEST_BINARY}"
else
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${DEST_BINARY}"
fi

echo "Embedded ffmpeg at ${DEST_BINARY}"
