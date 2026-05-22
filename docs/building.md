# Build guide

## PortMaster / aarch64 (Docker cross-compile)

This produces `dist/3sx.zip`, the file submitted to PortMaster.  
**Prerequisite:** Docker (any recent version).

### Quick start

```bash
# 1. Build the cross-compile image (one-time, ~5 min).
docker build -t 3sx-portmaster -f portmaster/Dockerfile .

# 2. Cross-compile deps + game + package into dist/3sx.zip.
docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/build.sh

# 3. Optional: verify the bundle (ELF arch, RUNPATH, bundled libs, qemu load).
docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/build.sh --verify
```

Or use the convenience wrapper (handles the `docker build` automatically):

```bash
bash portmaster/docker-build.sh          # build
bash portmaster/docker-build.sh --verify # build + verify
```

### How it works

| Step | What runs |
|------|-----------|
| `portmaster/Dockerfile` | Debian bookworm + GCC 13 aarch64 cross-toolchain + arm64 sysroot libs |
| `portmaster/build-deps-aarch64.sh` | Cross-compiles FFmpeg, SDL3, GekkoNet, SDL3_net, minizip-ng, tf-psa-crypto into `third_party/aarch64/` (skips any already built) |
| `portmaster/build.sh` | CMake cross-build of `3sx`, strips + stages the bundle, zips to `dist/3sx.zip` |
| `portmaster/verify.sh` | Checks ELF arch, RUNPATH, bundled .so list, SDL3 KMSDRM/Wayland support, and a qemu-aarch64 load test |

### Incremental builds

Dep builds are skipped if their output directories exist, so re-running
`build.sh` after a source change only re-runs CMake and the zip step.
To force a clean dep rebuild, delete `third_party/aarch64/`.

### Output

```
dist/
  3sx.zip         ← submit this to PortMaster
  staging/
    3sx.sh        ← launcher
    3sx/
      3sx          ← aarch64 ELF binary
      libs.aarch64/ ← bundled SDL3, FFmpeg, libdrm, libgbm
      port.json
      gameinfo.xml
      ...
```

---

## Setup

### Windows

1. Install [MSYS2](https://www.msys2.org/).
	* Steps after #4 on the official instructions can be skipped.
2. Launch the MinGW64 shell (there should be a start menu entry for it).
3. Install the required packages:

    ```bash
    pacman -S --needed $(cat tools/requirements-windows.txt)
    ```

### Linux

#### Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y $(cat tools/requirements-ubuntu.txt)
```

### macOS

You should be able to build the project with just Xcode Command Line Tools.

1. Check if Command Line Tools are installed:

    ```bash
    xcode-select -p
    ```

2. Install if needed:

    ```bash
    xcode-select --install
    ```

## Building

1. Build dependencies

    ```bash
    sh build-deps.sh
    ```

2. Build the game

    ```bash
    CC=clang cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build --parallel --config Release
    cmake --install build --prefix build/application
    ```

3. Copy from build/application to the desired location
