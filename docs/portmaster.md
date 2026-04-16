# PortMaster build (Anbernic H700 / Rocknix)

This document covers building, packaging, and on-device testing of the
3sx PortMaster bundle for Anbernic H700 handhelds (RG35XX H, RG35XX SP,
RG35XX 2024, RG28XX).

For desktop builds (Windows / macOS / Linux), see
[building.md](./building.md).

## Compatibility

| CFW       | Status       |
| --------- | ------------ |
| **Rocknix** | ✅ Supported  |
| **Knulli**  | ❌ Not currently supported (see below) |

## Requirements

- Linux or macOS host with Docker installed.
- Source checkout of this repo.
- Anbernic H700 device running **Rocknix** (Knulli is not supported —
  see the "Knulli compatibility" section).

## Build

```bash
# One-time: build the cross-compile image.
docker build -t 3sx-portmaster portmaster/

# Build + verify; produces dist/3sx.zip.
docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/build.sh --verify
```

The final zip is at `dist/3sx.zip`. Layout:

```
3sx.sh
3sx/
  3sx                       (aarch64 binary)
  3sx.gptk                  (gptokeyb keymap — quit combo only)
  port.json
  gameinfo.xml
  README.md
  screenshot.png
  cover.png
  conf-defaults/config      (seeded into conf/ on first run)
  libs.aarch64/             (bundled SDL3 + FFmpeg + libdrm/libgbm fallbacks)
  licenses/
```

## Display backend: direct KMSDRM

The port uses SDL3's KMSDRM video driver to talk directly to
`/dev/dri/card0` — no Wayland compositor, no X11. Rocknix uses a
mainline kernel with the `panfrost` DRM driver and ships Mesa with
`libdrm.so.2` / `libgbm.so.1` in `/usr/lib`; SDL3's runtime
`dlopen("libdrm.so.2")` / `dlopen("libgbm.so.1")` resolves against
those. As a last-resort fallback, the bundle also ships `libdrm.so.2`
and `libgbm.so.1` in `libs.aarch64/` (bookworm-era versions; ABI-stable
with Mesa).

WestonPack was tried first and abandoned: its bundled Mesa can't init
EGL on Mali-G31/Panfrost (the platform matrix marks Panfrost as
"Bypassed", and Weston exits with `failed to initialize egl` before
the game ever starts).

## Install on device

1. Copy the contents of `dist/3sx.zip` into `/roms/ports/` on the device.
2. Copy your `SF33RD.AFS` (extracted from a legally owned PS2 SF3:3S
   ISO) to `/roms/ports/3sx/conf/resources/SF33RD.AFS`.
3. Launch from the Ports menu.

## On-device test checklist

After installing, run through this list and note results:

1. **Cold launch** reaches title screen within ~10s.
2. **Performance**: `/roms/ports/3sx/log.txt` records `[perf] fps_avg=...`
   every ~5s. In-match values should be ≥58 fps for at least 30s.
3. **Quit combo**: Start + Select exits cleanly back to the Ports menu.
4. **Audio**: attract mode + first round play without crackle.
5. **All 6 attack buttons + macros register** in training mode using the
   default mapping (see README's controls table).
6. **Save/replay** roundtrip writes to `/roms/ports/3sx/conf/`.
7. **Netplay screen** opens (a successful session is not required;
   we only need to confirm GekkoNet/SDL_net link cleanly at runtime).
8. **Image fills the panel** correctly with 4:3 letterbox/pillarbox
   on whatever display the device has.

## Knulli compatibility

Knulli's current H700 image doesn't expose a DRM/KMS kernel subsystem:

- No `/dev/dri/` directory — DRM char devices aren't created.
- Kernel 4.9 with the legacy `mali_kbase` GPU driver (ARM vendor blob,
  `/dev/mali0`). The mainline `panfrost` DRM driver is not loaded.
- `libdrm`, `libgbm`, and `libseat` are not present anywhere on disk
  because there's no DRM to use them against.
- All graphics is SDL2 over the Allwinner proprietary fb driver.

SDL3 has three Linux video drivers (kmsdrm, wayland, x11). Knulli
H700 provides none of them. Even with bundled `libdrm.so.2` and
`libgbm.so.1`, SDL3's `open("/dev/dri/card0")` returns ENOENT because
the device isn't there.

Making 3sx work on Knulli would require Knulli itself to either
(a) switch the H700 kernel to 5.x with `panfrost` + mainline DRM,
(b) add a `mali_kbase`/fbdev SDL3 video driver, or (c) ship a
compatibility shim exposing `/dev/dri/card0` on top of the current
stack. None of these can be done in the port's packaging layer.

If you maintain Knulli and want to take a shot at this, the relevant
diagnostic script is at `portmaster/drm-diag.sh` in the upstream repo
— it probes the DRM state and library paths and writes to
`/roms/ports/3sx-drm-diag.log`.

## Bumping pinned versions

Pinned versions live in `portmaster/build-deps-aarch64.sh` and the
desktop `build-deps.sh`. Keep them in sync unless there's a reason
not to.

## Submitting to PortMaster

1. Replace `portmaster/bundle/3sx/screenshot.png` and `cover.png`
   with real captures (see PortMaster docs for resolution requirements).
2. Replace `TODO_porter_handle` in `port.json`, `README.md`, and
   `gameinfo.xml` with your handle.
3. Open a PR following the
   [PortMaster contribution guide](https://portmaster.games/packaging.html).
