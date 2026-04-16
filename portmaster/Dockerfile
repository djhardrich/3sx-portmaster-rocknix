# Cross-compile environment for the Anbernic H700 (aarch64 glibc).
# Pinned to debian:bookworm for compatibility with current
# Knulli/Rocknix images (glibc ~2.36).
#
# The arm64 sysroot (libc, libdrm, etc.) comes from bookworm (glibc 2.36).
# The cross-compiler binaries (GCC 13, host-side x86-64) are pulled from
# debian:trixie so we get C23 typed-enum support without bumping the
# target glibc.
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

# Add trixie as a low-priority secondary source (host-arch packages only).
# We pin it to 100 so it never auto-upgrades bookworm packages, and we only
# use it to install the GCC 13 cross-compiler tools.
RUN echo "deb http://deb.debian.org/debian trixie main" > /etc/apt/sources.list.d/trixie.list && \
    printf 'Package: *\nPin: release n=trixie\nPin-Priority: 100\n' \
        > /etc/apt/preferences.d/pin-trixie

RUN dpkg --add-architecture arm64 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        build-essential \
        crossbuild-essential-arm64 \
        cmake \
        ninja-build \
        pkg-config \
        autoconf \
        automake \
        libtool \
        nasm \
        yasm \
        python3 \
        python3-pip \
        zip \
        unzip \
        xz-utils \
        libarchive-tools \
        file \
        binutils-aarch64-linux-gnu \
        qemu-user-static \
        libdrm-dev:arm64 \
        libgbm-dev:arm64 \
        libgles2-mesa-dev:arm64 \
        libegl1-mesa-dev:arm64 \
        libwayland-dev:arm64 \
        wayland-protocols \
        libdecor-0-dev:arm64 \
        libxkbcommon-dev:arm64 \
        libasound2-dev:arm64 \
        libudev-dev:arm64 \
        libpulse-dev:arm64 \
        zlib1g-dev:arm64 \
    && apt-get install -y --no-install-recommends \
           -t trixie \
           gcc-13-aarch64-linux-gnu \
           g++-13-aarch64-linux-gnu \
    && update-alternatives --install \
           /usr/bin/aarch64-linux-gnu-gcc aarch64-linux-gnu-gcc \
           /usr/bin/aarch64-linux-gnu-gcc-13 130 \
    && update-alternatives --install \
           /usr/bin/aarch64-linux-gnu-g++ aarch64-linux-gnu-g++ \
           /usr/bin/aarch64-linux-gnu-g++-13 130 \
    && rm -rf /var/lib/apt/lists/*

# pkg-config wrapper that knows about the arm64 multiarch sysroot.
ENV PKG_CONFIG=aarch64-linux-gnu-pkg-config
ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
ENV PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
ENV PKG_CONFIG_SYSROOT_DIR=/

WORKDIR /src
