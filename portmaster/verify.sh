#!/usr/bin/env bash
# Post-build verification for the 3sx PortMaster bundle.
# Run from inside the 3sx-portmaster Docker image OR after `build.sh`
# (assumes aarch64-linux-gnu-* binutils + qemu-aarch64-static available).
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/src}"
STAGE_DIR="$ROOT_DIR/dist/staging"
REL_DIR="$STAGE_DIR/3sx"   # outer release/wrapper dir (top level of the zip)
PORT_DIR="$REL_DIR/3sx"    # inner data dir
BIN="$PORT_DIR/3sx"
LIBDIR="$PORT_DIR/libs.aarch64"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

[ -f "$BIN" ] || fail "Binary not found at $BIN"

# 1. ELF type + arch
file_out=$(file -L "$BIN")
case "$file_out" in
    *"ELF 64-bit LSB"*"ARM aarch64"*"dynamically linked"*)
        pass "binary is aarch64 ELF dynamic" ;;
    *)
        fail "binary file-type wrong: $file_out" ;;
esac

# 2. RUNPATH/RPATH
rpath_out=$(aarch64-linux-gnu-readelf -d "$BIN" | grep -E "RUNPATH|RPATH" || true)
case "$rpath_out" in
    *'$ORIGIN/libs.aarch64'*) pass "RUNPATH contains \$ORIGIN/libs.aarch64" ;;
    *) fail "RUNPATH missing or wrong: $rpath_out" ;;
esac

# 3. JSON metadata validates
python3 -m json.tool "$REL_DIR/port.json" > /dev/null
pass "port.json is valid JSON"

# 4. Required files present. PortMaster "new port structure": catalog
# metadata + launcher live in the outer release dir; runtime port files
# live in the inner data dir.
for f in \
    "$PORT_DIR/3sx" \
    "$PORT_DIR/3sx.gptk" \
    "$PORT_DIR/conf-defaults/config" \
    "$REL_DIR/port.json" \
    "$REL_DIR/gameinfo.xml" \
    "$REL_DIR/README.md" \
    "$REL_DIR/screenshot.png" \
    "$REL_DIR/3sx.sh" ; do
    [ -e "$f" ] || fail "missing required file: $f"
done
pass "all required bundle files present"

# 5. Bundled libs include SDL3 and FFmpeg shared libs
for lib in libSDL3.so libavcodec.so libavformat.so libavutil.so libswresample.so; do
    ls "$LIBDIR/$lib"* > /dev/null || fail "missing bundled lib: $lib*"
done
pass "all bundled .so files present"

# 6. SDL3 has KMSDRM and Wayland support compiled in.
# We check both symbols (-D) and strings since KMSDRM may be a dynamically
# loaded driver whose entry points aren't in the dynamic-symbol table.
# NOTE: We capture to a variable before grepping to avoid set -o pipefail
# triggering on SIGPIPE when grep -q exits early after its first match.
sdl_lib=$(ls "$LIBDIR"/libSDL3.so.0.* 2>/dev/null | head -1)
[ -n "$sdl_lib" ] || sdl_lib=$(ls "$LIBDIR"/libSDL3.so* | head -1)

sdl_nm_dynamic=$(aarch64-linux-gnu-nm -D "$sdl_lib" 2>/dev/null || true)
sdl_nm_full=$(aarch64-linux-gnu-nm    "$sdl_lib" 2>/dev/null || true)
sdl_strings=$(strings                  "$sdl_lib" 2>/dev/null || true)

kmsdrm_hits=$(printf '%s\n%s\n%s' "$sdl_nm_dynamic" "$sdl_nm_full" "$sdl_strings" \
    | grep -ciE "kmsdrm" || true)
if [ "${kmsdrm_hits:-0}" -gt 0 ]; then
    pass "SDL3 has KMSDRM support"
else
    fail "SDL3 missing KMSDRM (needed for X11-less handhelds)"
fi

wayland_hits=$(printf '%s\n%s\n%s' "$sdl_nm_dynamic" "$sdl_nm_full" "$sdl_strings" \
    | grep -ciE "wayland" || true)
if [ "${wayland_hits:-0}" -gt 0 ]; then
    pass "SDL3 has Wayland support"
else
    fail "SDL3 missing Wayland support"
fi

# 7. ldd-style dependency check via qemu-aarch64-static.
# Add libs.aarch64 to LD_LIBRARY_PATH so bundled libs resolve.
# Anything else should be a core system library.
deps=$(qemu-aarch64-static -L /usr/aarch64-linux-gnu \
    -E LD_LIBRARY_PATH="$LIBDIR" \
    /usr/aarch64-linux-gnu/lib/ld-linux-aarch64.so.1 --list "$BIN" 2>&1 || true)

# Allowlist: core glibc + zlib (always present on device), C++ runtime, dynamic linker.
# libz.so.1 is a direct dep of 3sx (used by SDL3/FFmpeg at build time) and is
# a standard OS library on every Linux distro including PortMaster-supported devices.
allowed_re='libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libgcc_s\.so|ld-linux-aarch64\.so|libstdc\+\+\.so|libz\.so'

unexpected=$(echo "$deps" | awk '/=>/' | grep -v "$LIBDIR" | grep -vE "$allowed_re" || true)
if [ -n "$unexpected" ]; then
    echo "FAIL: unexpected library deps:" >&2
    echo "$unexpected" >&2
    exit 1
fi
pass "no unexpected library dependencies"

# 8. Binary loads cleanly under qemu (any runtime errors after load are
# out of scope here; we just want to confirm the dynamic loader is happy).
mkdir -p "$STAGE_DIR/qemu-conf"
qemu_out=$(qemu-aarch64-static -L /usr/aarch64-linux-gnu \
    -E LD_LIBRARY_PATH="$LIBDIR" \
    -E XDG_DATA_HOME="$STAGE_DIR/qemu-conf" \
    "$BIN" 2>&1 < /dev/null || true)
case "$qemu_out" in
    *"error while loading shared libraries"*|*"undefined symbol"*|*"cannot open shared object"*)
        echo "FAIL: qemu loader rejected the binary:" >&2
        echo "$qemu_out" | head -10 >&2
        exit 1 ;;
    *)
        pass "binary loads cleanly under qemu (any runtime errors after load are out of scope here)"
        ;;
esac

echo "All verification checks passed."
