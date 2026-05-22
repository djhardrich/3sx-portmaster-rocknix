#!/usr/bin/env bash
# Cross-compile third-party deps for the H700 PortMaster build.
# Run inside the 3sx-portmaster Docker image; the source repo is mounted at /src.
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/src}"
THIRD_PARTY="$ROOT_DIR/third_party/aarch64"
JOBS="${JOBS:-$(nproc)}"

mkdir -p "$THIRD_PARTY"

HOST_TRIPLET=aarch64-linux-gnu
export CC=${HOST_TRIPLET}-gcc
export CXX=${HOST_TRIPLET}-g++
export AR=${HOST_TRIPLET}-ar
export RANLIB=${HOST_TRIPLET}-ranlib
export STRIP=${HOST_TRIPLET}-strip
TOOLCHAIN_FILE="$ROOT_DIR/portmaster/cmake/aarch64-linux-gnu.cmake"

# -----------------------------
# FFmpeg 8.0 (only adpcm_adx)
# -----------------------------
FFMPEG_VER="ffmpeg-8.0"
FFMPEG_DIR="$THIRD_PARTY/ffmpeg"
FFMPEG_BUILD="$FFMPEG_DIR/build"

if [ -d "$FFMPEG_BUILD" ]; then
    echo "FFmpeg already built at $FFMPEG_BUILD"
else
    echo "Building FFmpeg (cross)..."
    mkdir -p "$FFMPEG_DIR"
    cd "$FFMPEG_DIR"

    if [ ! -d "$FFMPEG_VER" ]; then
        curl -L -O "https://ffmpeg.org/releases/$FFMPEG_VER.tar.xz"
        tar xf "$FFMPEG_VER.tar.xz"
    fi

    cd "$FFMPEG_VER"
    mkdir -p build && cd build

    ../configure \
        --prefix="$FFMPEG_BUILD" \
        --enable-cross-compile \
        --cross-prefix=${HOST_TRIPLET}- \
        --target-os=linux \
        --arch=aarch64 \
        --cc=${CC} \
        --disable-all --disable-autodetect \
        --disable-static --enable-shared \
        --enable-avcodec --enable-avformat --enable-avutil --enable-swresample \
        --enable-decoder=adpcm_adx --enable-parser=adx --enable-muxer=adx \
        --enable-pic \
        --extra-cflags="-fPIC" \
        --extra-ldflags="-Wl,-rpath,\$ORIGIN"

    make -j"$JOBS"
    make install

    cd "$FFMPEG_DIR"
    rm -rf "$FFMPEG_VER" "$FFMPEG_VER.tar.xz"
    echo "FFmpeg installed to $FFMPEG_BUILD"
fi

# -----------------------------
# SDL3 3.4.4 (KMSDRM + Wayland + ALSA)
# -----------------------------
SDL_TAG="release-3.4.4"
SDL_DIR="$THIRD_PARTY/sdl3"
SDL_BUILD="$SDL_DIR/build"

if [ -f "$SDL_BUILD/lib/libSDL3.so" ]; then
    echo "SDL3 already built at $SDL_BUILD"
else
    echo "Building SDL3 (cross) at $SDL_BUILD..."
    rm -rf "$SDL_BUILD"
    mkdir -p "$SDL_BUILD"
    SDL_SRC=$(mktemp -d)

    git clone --depth 1 --branch "$SDL_TAG" --single-branch \
        https://github.com/libsdl-org/SDL "$SDL_SRC"

    cmake -S "$SDL_SRC" -B "$SDL_SRC/cmake-build" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DCMAKE_INSTALL_PREFIX="$SDL_BUILD" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DSDL_STATIC=OFF \
        -DSDL_SHARED=ON \
        -DSDL_TEST_LIBRARY=OFF \
        -DSDL_X11=OFF \
        -DSDL_WAYLAND=ON \
        -DSDL_KMSDRM=ON \
        -DSDL_KMSDRM_SHARED=ON \
        -DDRM_LIB=/usr/lib/aarch64-linux-gnu/libdrm.so \
        -DGBM_LIB=/usr/lib/aarch64-linux-gnu/libgbm.so \
        -DSDL_OPENGL=OFF \
        -DSDL_OPENGLES=ON \
        -DSDL_VULKAN=OFF \
        -DSDL_RENDER_VULKAN=OFF \
        -DSDL_RENDER_GPU=OFF \
        -DSDL_PIPEWIRE=OFF \
        -DSDL_ALSA=ON \
        -DSDL_PULSEAUDIO=ON

    cmake --build "$SDL_SRC/cmake-build" -j"$JOBS"
    cmake --install "$SDL_SRC/cmake-build"

    rm -rf "$SDL_SRC"
    echo "SDL3 installed to $SDL_BUILD"
fi

# -----------------------------
# GekkoNet @ 7be848c (static)
# -----------------------------
GEKKONET_REF="7be848c"
GEKKONET_DIR="$THIRD_PARTY/GekkoNet"
GEKKONET_BUILD="$GEKKONET_DIR/build"

if [ -d "$GEKKONET_BUILD" ]; then
    echo "GekkoNet already built at $GEKKONET_BUILD"
else
    echo "Building GekkoNet (cross) @ $GEKKONET_REF..."
    GEKKONET_SRC=$(mktemp -d)
    git clone https://github.com/HeatXD/GekkoNet.git "$GEKKONET_SRC"
    git -C "$GEKKONET_SRC" -c advice.detachedHead=false checkout "$GEKKONET_REF"

    cmake -S "$GEKKONET_SRC" -B "$GEKKONET_SRC/cmake-build" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DCMAKE_BUILD_TYPE=Release \
        -DNO_ASIO_BUILD=ON \
        -DBUILD_SHARED_LIBS=OFF

    cmake --build "$GEKKONET_SRC/cmake-build" -j"$JOBS"

    mkdir -p "$GEKKONET_BUILD/include" "$GEKKONET_BUILD/lib"
    cp -r "$GEKKONET_SRC/GekkoLib/include/." "$GEKKONET_BUILD/include/"
    find "$GEKKONET_SRC" -name "*.a" -exec cp {} "$GEKKONET_BUILD/lib/libGekkoNet.a" \;

    rm -rf "$GEKKONET_SRC"
    echo "GekkoNet installed to $GEKKONET_BUILD"
fi

# -----------------------------
# SDL3_net @ 92022dc (static)
# -----------------------------
SDL3_NET_REF="92022dc"
SDL3_NET_DIR="$THIRD_PARTY/SDL_net"
SDL3_NET_BUILD="$SDL3_NET_DIR/build"

if [ -d "$SDL3_NET_BUILD" ]; then
    echo "SDL3_net already built at $SDL3_NET_BUILD"
else
    echo "Building SDL3_net (cross) @ $SDL3_NET_REF..."
    SDL3_NET_SRC=$(mktemp -d)
    git clone https://github.com/libsdl-org/SDL_net.git "$SDL3_NET_SRC"
    git -C "$SDL3_NET_SRC" -c advice.detachedHead=false checkout "$SDL3_NET_REF"

    cmake -S "$SDL3_NET_SRC" -B "$SDL3_NET_SRC/cmake-build" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DCMAKE_INSTALL_PREFIX="$SDL3_NET_BUILD" \
        -DSDL3_DIR="$SDL_BUILD/lib/cmake/SDL3" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DSDLNET_INSTALL=ON

    cmake --build "$SDL3_NET_SRC/cmake-build" -j"$JOBS"
    cmake --install "$SDL3_NET_SRC/cmake-build"

    rm -rf "$SDL3_NET_SRC"
    echo "SDL3_net installed to $SDL3_NET_BUILD"
fi

# -----------------------------
# minizip-ng 4.1.0 (static, decompress-only)
# -----------------------------
MINIZIP_NG_TAG="4.1.0"
MINIZIP_NG_DIR="$THIRD_PARTY/minizip-ng"
MINIZIP_NG_BUILD="$MINIZIP_NG_DIR/build"

if [ -d "$MINIZIP_NG_BUILD" ]; then
    echo "minizip-ng already built at $MINIZIP_NG_BUILD"
else
    echo "Building minizip-ng (cross)..."
    mkdir -p "$MINIZIP_NG_BUILD"
    MINIZIP_NG_SRC=$(mktemp -d)

    git clone --depth 1 --branch "$MINIZIP_NG_TAG" --single-branch \
        https://github.com/zlib-ng/minizip-ng "$MINIZIP_NG_SRC"

    cmake -S "$MINIZIP_NG_SRC" -B "$MINIZIP_NG_SRC/cmake-build" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DCMAKE_INSTALL_PREFIX="$MINIZIP_NG_BUILD" \
        -DCMAKE_BUILD_TYPE=Release \
        -DMZ_COMPAT=OFF \
        -DMZ_ZLIB_FLAVOR=zlib \
        -DMZ_BZIP2=OFF \
        -DMZ_LZMA=OFF \
        -DMZ_PPMD=OFF \
        -DMZ_ZSTD=OFF \
        -DMZ_LIBCOMP=OFF \
        -DMZ_PKCRYPT=OFF \
        -DMZ_WZAES=OFF \
        -DMZ_OPENSSL=OFF \
        -DMZ_LIBBSD=OFF \
        -DMZ_DECOMPRESS_ONLY=ON

    cmake --build "$MINIZIP_NG_SRC/cmake-build" -j"$JOBS"
    cmake --install "$MINIZIP_NG_SRC/cmake-build"

    rm -rf "$MINIZIP_NG_SRC"
    echo "minizip-ng installed to $MINIZIP_NG_BUILD"
fi

# -----------------------------
# tf-psa-crypto 1.0.0 (static)
# -----------------------------
TF_PSA_CRYPTO_VERSION="1.0.0"
TF_PSA_CRYPTO_URL="https://github.com/Mbed-TLS/TF-PSA-Crypto/releases/download/tf-psa-crypto-$TF_PSA_CRYPTO_VERSION/tf-psa-crypto-$TF_PSA_CRYPTO_VERSION.tar.bz2"
TF_PSA_CRYPTO_DIR="$THIRD_PARTY/tf-psa-crypto"
TF_PSA_CRYPTO_BUILD="$TF_PSA_CRYPTO_DIR/build"

if [ -d "$TF_PSA_CRYPTO_BUILD" ]; then
    echo "tf-psa-crypto already built at $TF_PSA_CRYPTO_BUILD"
else
    echo "Building tf-psa-crypto (cross)..."
    mkdir -p "$TF_PSA_CRYPTO_BUILD"
    TF_PSA_CRYPTO_SRC=$(mktemp -d)

    curl -L -o "$TF_PSA_CRYPTO_SRC/tf-psa-crypto.tar.bz2" "$TF_PSA_CRYPTO_URL"
    tar xf "$TF_PSA_CRYPTO_SRC/tf-psa-crypto.tar.bz2" -C "$TF_PSA_CRYPTO_SRC"

    cmake -S "$TF_PSA_CRYPTO_SRC/tf-psa-crypto-$TF_PSA_CRYPTO_VERSION" \
          -B "$TF_PSA_CRYPTO_SRC/cmake-build" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$TF_PSA_CRYPTO_BUILD" \
        -DENABLE_PROGRAMS=OFF \
        -DENABLE_TESTING=OFF \
        -DUSE_SHARED_TF_PSA_CRYPTO_LIBRARY=OFF \
        -DUSE_STATIC_TF_PSA_CRYPTO_LIBRARY=ON \
        -DTF_PSA_CRYPTO_CONFIG_FILE="$ROOT_DIR/configs/crypto-config-ccm-aes-sha256.h"

    cmake --build "$TF_PSA_CRYPTO_SRC/cmake-build" -j"$JOBS"
    cmake --install "$TF_PSA_CRYPTO_SRC/cmake-build"

    rm -rf "$TF_PSA_CRYPTO_SRC"
    echo "tf-psa-crypto installed to $TF_PSA_CRYPTO_BUILD"
fi

echo "All aarch64 dependencies installed under $THIRD_PARTY"
