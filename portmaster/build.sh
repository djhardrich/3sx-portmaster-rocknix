#!/usr/bin/env bash
# Top-level cross-build entrypoint for the 3sx PortMaster zip.
# Run inside the 3sx-portmaster Docker image:
#   docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/build.sh [--verify]
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/src}"
PM_DIR="$ROOT_DIR/portmaster"
THIRD_PARTY="$ROOT_DIR/third_party/aarch64"
BUILD_DIR="$ROOT_DIR/build-aarch64"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/staging"
PORT_DIR="$STAGE_DIR/3sx"
JOBS="${JOBS:-$(nproc)}"
DO_VERIFY=0

for arg in "$@"; do
    case "$arg" in
        --verify) DO_VERIFY=1 ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# 1. Build third-party deps (no-op if already built).
echo "==> Cross-building third-party deps"
"$PM_DIR/build-deps-aarch64.sh"

# 2. Configure + build 3sx.
echo "==> Configuring 3sx for aarch64"
cmake -S "$ROOT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$PM_DIR/cmake/aarch64-linux-gnu.cmake" \
    -DTHIRD_PARTY_DIR="$THIRD_PARTY" \
    -DPORTMASTER=ON \
    -DCMAKE_BUILD_TYPE=Release

echo "==> Building 3sx"
cmake --build "$BUILD_DIR" --target 3sx -j"$JOBS"

# 3. Stage the bundle.
echo "==> Staging bundle"
rm -rf "$STAGE_DIR"
mkdir -p "$PORT_DIR/libs.aarch64" "$PORT_DIR/licenses"

# Binary
cp "$BUILD_DIR/3sx" "$PORT_DIR/3sx"
aarch64-linux-gnu-strip --strip-unneeded "$PORT_DIR/3sx"

# Bundled .so files
SDL_LIB_DIR="$THIRD_PARTY/sdl3/build/lib"
FFMPEG_LIB_DIR="$THIRD_PARTY/ffmpeg/build/lib"

cp -P "$SDL_LIB_DIR"/libSDL3.so* "$PORT_DIR/libs.aarch64/"
cp -P "$FFMPEG_LIB_DIR"/libavcodec.so*    "$PORT_DIR/libs.aarch64/"
cp -P "$FFMPEG_LIB_DIR"/libavformat.so*   "$PORT_DIR/libs.aarch64/"
cp -P "$FFMPEG_LIB_DIR"/libavutil.so*     "$PORT_DIR/libs.aarch64/"
cp -P "$FFMPEG_LIB_DIR"/libswresample.so* "$PORT_DIR/libs.aarch64/"

# Bundle libdrm.so.2 and libgbm.so.1 as fallback. SDL3 was built with
# KMSDRM_SHARED so it dlopens these at runtime, and devices vary widely
# in where they store them (Knulli: /usr/lib64, Rocknix:
# /usr/lib/aarch64-linux-gnu, others: nowhere standard). The launcher
# adds both common paths to LD_LIBRARY_PATH; if neither has them, our
# bundled copies in libs.aarch64/ are the last-resort fallback.
SYS_LIB_DIR=/usr/lib/aarch64-linux-gnu
for sys_lib in libdrm.so.2 libgbm.so.1; do
    if [ -e "$SYS_LIB_DIR/$sys_lib" ]; then
        cp -P "$SYS_LIB_DIR"/$sys_lib* "$PORT_DIR/libs.aarch64/"
    fi
done

# Strip bundled shared libs
for f in "$PORT_DIR/libs.aarch64/"*.so*; do
    if [ -f "$f" ] && [ ! -L "$f" ]; then
        aarch64-linux-gnu-strip --strip-unneeded "$f" || true
    fi
done

# Bundle template (port.json, gameinfo.xml, README, gptk, screenshot,
# cover, conf-defaults).
cp -r "$PM_DIR/bundle/3sx/." "$PORT_DIR/"
cp "$PM_DIR/bundle/3sx.sh" "$STAGE_DIR/"
chmod +x "$STAGE_DIR/3sx.sh"

# Licenses
cp "$ROOT_DIR/LICENSE" "$PORT_DIR/licenses/LICENSE-3sx"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.txt" "$PORT_DIR/licenses/" 2>/dev/null || true

# Drop the .gitkeep marker that was needed to keep the dir in git.
rm -f "$PORT_DIR/licenses/.gitkeep"

# 4. Build the zip (overwrite any previous build to avoid stale entries).
echo "==> Building dist/3sx.zip"
rm -f "$DIST_DIR/3sx.zip"
( cd "$STAGE_DIR" && zip -r "$DIST_DIR/3sx.zip" "3sx.sh" "3sx" )
ls -la "$DIST_DIR/3sx.zip"

if [ "$DO_VERIFY" = "1" ]; then
    if [ -x "$PM_DIR/verify.sh" ]; then
        "$PM_DIR/verify.sh"
    else
        echo "==> Skipping verify (verify.sh not present yet)"
    fi
fi

echo "==> Done. Output: $DIST_DIR/3sx.zip"
