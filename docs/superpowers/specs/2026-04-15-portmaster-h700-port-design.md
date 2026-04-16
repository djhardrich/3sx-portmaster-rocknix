# PortMaster port for Anbernic H700 (Knulli / Rocknix) — design

Date: 2026-04-15
Status: approved (brainstorming phase complete)

## Summary

Add a PortMaster-distributable build of 3sx targeting Anbernic H700 handhelds
(RG35XX H/SP/2024, RG28XX, etc.) running Knulli or Rocknix. The build is
aarch64 Linux (glibc), uses bundled SDL3 + FFmpeg shared libraries, runs under
KMS/DRM with the GLES2/GLES3 SDL3 renderer, and ships through the standard
PortMaster zip layout. Netplay (GekkoNet + SDL_net) stays enabled. ImGui,
libcdio, the SHA-256 checksum, and the on-device resource-copying flow are
removed for this build.

## Goals

- Produce a single zip installable to `/roms/ports/` on Knulli/Rocknix.
- Reuse the existing `CRS_APP_DRIVER_SDL` / `CRS_VIDEO_DRIVER_SDL` backend —
  no new platform driver.
- Cross-compile from any host via Docker, no on-device build required.
- Keep all H700-specific changes guarded by a single CMake option
  (`PORTMASTER`) and a single preprocessor define (`CRS_PLATFORM_PORTMASTER`)
  so desktop builds remain unchanged.
- Match PortMaster packaging conventions (port.json, gameinfo.xml, control.txt
  sourcing, gptokeyb quit combo, `libs.${DEVICE_ARCH}` layout).

## Non-goals

- New PSP-style platform driver for KMS/DRM.
- Save states, rewind, in-game settings redesign, RetroAchievements,
  custom shaders.
- Dynamic resolution switching while running.
- On-device ISO extraction or recovery UI for missing data.
- 32-bit (armhf) builds. H700 is aarch64 only.

## Architecture

### Where the H700 plugs in

The existing source tree already separates application/video backends behind
compile-time selectors:

- `CRS_APP_DRIVER_SDL` selects `src/platform/app/sdl/sdl_app.c`.
- `CRS_VIDEO_DRIVER_SDL` selects `src/platform/video/sdl/sdl_game_renderer.c`.

The H700 build is **the same SDL backend with different defaults and a few
trims**, expressed as:

- New CMake option `PORTMASTER` (default `OFF`).
- New preprocessor define `CRS_PLATFORM_PORTMASTER` (set when `PORTMASTER=ON`).
- Conditional dependency removal in `CMakeLists.txt` (libcdio, ImGui).
- Conditional `#if` branches inside SDL backend code for: forced-fullscreen
  window init, integer scale-mode default, skipped resource-copying flow,
  hidden cursor, periodic fps log line.

No new files in `src/`. All new artifacts live under `portmaster/`.

### Bundle layout (final installable zip)

```
Street Fighter III 3rd Strike.sh
3sx/
  3sx                                   # cross-compiled aarch64 binary
  3sx.gptk                              # gptokeyb keymap (start+select = quit)
  port.json
  gameinfo.xml
  README.md
  screenshot.png                        # 4:3 ≥640×480
  cover.png                             # optional
  conf-defaults/
    config                              # fullscreen=true, scalemode=integer
    keymap                              # keyboard map (only used if no gamepad)
  libs.aarch64/
    libSDL3.so.0
    libavcodec.so.* libavformat.so.* libavutil.so.* libswresample.so.*
    libSDL3_net.so.0
  licenses/
    LICENSE-3sx, LICENSE-SDL3, LICENSE-FFmpeg, LICENSE-GekkoNet,
    LICENSE-zlib, LICENSE-minizip-ng, LICENSE-tf-psa-crypto, LICENSE-stb,
    LICENSE-argparse, LICENSE-gptokeyb
```

GekkoNet, minizip-ng, tf-psa-crypto remain statically linked (already true in
`build-deps.sh`). SDL3 and FFmpeg ship as `.so` files because they are already
shared on the existing Linux build path.

### Default control mapping

Arcade 2×3 across face + L1, both shoulder triggers as macros:

| Game button | H700 button |
| ----------- | ----------- |
| LP          | X           |
| MP          | Y           |
| HP          | R1          |
| LK          | A           |
| MK          | B           |
| HK          | L1          |
| 3P macro    | L2          |
| 3K macro    | R2          |
| Coin        | Select      |
| Start       | Start       |
| Movement    | DPad / left analog |

The game reads the gamepad through SDL directly. `gptokeyb` is used **only**
to translate Start+Select into a quit signal; all other inputs pass through
unchanged.

## Build pipeline

### New top-level directory

```
portmaster/
  Dockerfile                 # debian:bullseye + crossbuild-essential-arm64,
                             # autoconf, nasm, pkg-config, cmake, python3, etc.
  build.sh                   # entrypoint: build deps then 3sx then stage bundle
  build-deps-aarch64.sh      # cross-compile fork of build-deps.sh
  cmake/
    aarch64-linux-gnu.cmake  # CMake toolchain file
  bundle/                    # template files copied into staging
    Street Fighter III 3rd Strike.sh
    3sx/
      port.json
      gameinfo.xml
      README.md
      screenshot.png
      cover.png
      3sx.gptk
      conf-defaults/
        config
        keymap
      licenses/
        ... (license files)
```

### Build flow

1. `docker build -t 3sx-portmaster portmaster/` (one-time).
2. `docker run --rm -v $PWD:/src 3sx-portmaster /src/portmaster/build.sh` runs:
   1. `build-deps-aarch64.sh` cross-builds SDL3 (3.4.4), FFmpeg (8.0, only
      `adpcm_adx` decoder, only `avcodec/avformat/avutil/swresample`),
      GekkoNet, SDL3_net, minizip-ng, tf-psa-crypto, into
      `third_party/aarch64/`. zlib is taken from the Debian aarch64 sysroot
      (no need to build).
   2. `cmake -B build-aarch64 -DCMAKE_TOOLCHAIN_FILE=portmaster/cmake/aarch64-linux-gnu.cmake -DPORTMASTER=ON -DCMAKE_BUILD_TYPE=Release`
      then `cmake --build build-aarch64 --parallel`.
   3. Staging step copies the binary, the bundled `.so` files, and the
      `portmaster/bundle/` template into a `dist/staging/` tree, then zips it
      to `dist/3sx.zip`.
3. `portmaster/build.sh --verify` runs the verification checks (see
   "Verification" below).

### Pinning

- Docker base: `debian:bullseye` (glibc 2.31). Knulli/Rocknix ship glibc
  ≥ 2.31, so binaries are forward-compatible.
- SDL3 tag: `release-3.4.4` (matches `build-deps.sh`).
- FFmpeg: 8.0 (matches `build-deps.sh`).
- GekkoNet ref: `7be848c` (matches `build-deps.sh`).
- SDL3_net ref: `92022dc` (matches `build-deps.sh`).
- minizip-ng tag: `4.1.0` (matches).
- tf-psa-crypto: `1.0.0` (matches).
- SDL3 build flags: enable KMSDRM, Wayland (libdecor), ALSA, evdev. Disable
  X11, Vulkan, Pipewire (unnecessary for the target). Disable static, build
  shared.

## Source-tree changes

All edits are guarded; desktop builds are byte-identical when `PORTMASTER=OFF`.

### `CMakeLists.txt`

- Add `option(PORTMASTER "Build for PortMaster (aarch64 handhelds)" OFF)`.
- When `PORTMASTER=ON`:
  - Define `CRS_PLATFORM_PORTMASTER`, `CRS_APP_DRIVER_SDL`,
    `CRS_VIDEO_DRIVER_SDL`, `ARCADE_ROM`, `SOUND_ENABLED`, `NETPLAY_ENABLED`,
    `GEKKONET_STATIC`, `GEKKONET_NO_ASIO`, `MEMCARD_DISABLED`.
  - Do **not** define `IMGUI` or `CHECKSUM`.
  - Skip the `LIBCDIO_ROOT` include path and the libcdio link entries.
  - Set `INSTALL_RPATH "$ORIGIN/libs.aarch64"`.
  - Force `CMAKE_BUILD_TYPE=Release`.
- The existing `if(UNIX AND NOT APPLE)` link block continues to apply (FFmpeg
  + SDL3 shared `.so` paths), pointed at `third_party/aarch64/...` via the
  toolchain.

### `src/port/paths.c`

Under `#if CRS_PLATFORM_PORTMASTER`, return `getenv("XDG_DATA_HOME")` (with
trailing `/`) directly instead of `SDL_GetPrefPath("CrowdedStreet","3SX")`.
Falls back to `/tmp/3sx/` if unset (defensive — launcher always sets it).

### `src/port/resources.c`

- Wrap the `cdio/iso9660.h` include and `Resources_RunResourceCopyingFlow`
  body in `#if !CRS_PLATFORM_PORTMASTER`.
- `Resources_Check()` and `Resources_GetAFSPath()` stay unchanged.

### `src/platform/app/sdl/sdl_app.c`

- `init_window`: if `CRS_PLATFORM_PORTMASTER`, OR `SDL_WINDOW_FULLSCREEN` into
  the flags unconditionally, and use the display's current mode for size
  (skip the `Config_GetInt(CFG_KEY_WINDOW_*)` path).
- `init_scalemode`: if `CRS_PLATFORM_PORTMASTER` and the user did not override
  `CFG_KEY_SCALEMODE`, default to `SCALEMODE_INTEGER`.
- `loop()` `APP_PHASE_INIT`: if `CRS_PLATFORM_PORTMASTER`, never enter
  `APP_PHASE_COPYING_RESOURCES`. If `Resources_Check()` returns false, log
  the missing-AFS error and exit.
- After `pre_init`, `SDL_HideCursor()` once on PortMaster.
- Add a periodic fps/frame-time/audio-underrun log line every ~5 seconds
  using existing `frame_metrics`. Compiled in only when
  `CRS_PLATFORM_PORTMASTER`. Goes to stderr (which the launcher tees to
  `log.txt`).

### Default config (no code change)

- The PortMaster-specific defaults live in
  `portmaster/bundle/3sx/conf-defaults/config`.
- The launcher seeds it on first run (`cp -n conf-defaults/* "$CONFDIR/"`),
  so the binary uses its normal config-loading path with no
  `CRS_PLATFORM_PORTMASTER` branch in `src/port/config/config.c`.
- Format is the existing `key = value` text format (see `src/port/config/config.c`).
- Contents: `fullscreen = true`, `scalemode = integer`, plus any other
  values the implementer wants pre-populated.

### `src/port/sdk/sdk_libpad2.c` (gamepad remap for arcade layout)

Under `#if CRS_PLATFORM_PORTMASTER`, remap which SDL gamepad button drives
each PS2 button so the SF3:3S default in-game button config produces the
desired Anbernic-label arcade layout (LP=X, MP=Y, HP=R1, LK=A, MK=B,
HK=L1, 3P macro=L2, 3K macro=R2). Concretely, on the H700's
SDL3-Nintendo-style face buttons:

| SDL gamepad button (Anbernic label) | PS2 button mapped to       |
| ----------------------------------- | -------------------------- |
| `north` (X, top)                    | `square` (LP)              |
| `west` (Y, left)                    | `triangle` (MP)            |
| `right_shoulder` (R1)               | `r1` (HP)                  |
| `east` (A, right)                   | `cross` (LK)               |
| `south` (B, bottom)                 | `circle` (MK)              |
| `left_shoulder` (L1)                | `r2` (HK)                  |
| `left_trigger` (L2)                 | `l1` (3P macro)            |
| `right_trigger` (R2)                | `l2` (3K macro)            |
| `start`, `back`, dpad, sticks       | unchanged 1:1              |

The desktop default mapping (south=cross, east=circle, etc.) is preserved
when `CRS_PLATFORM_PORTMASTER` is not defined.

### `docs/portmaster.md` (new)

Short build + install + on-device-test guide for porters. Replaces nothing
in the existing `docs/building.md`; that file stays unchanged.

### Conditional bundling notes

If a runtime header file genuinely cannot exclude the libcdio include with
`#if`, fall back to a one-line stub `cdio_stub.h` shipped under
`portmaster/include/` that satisfies the type. Only used if the simpler `#if`
fix needs more glue than expected.

## PortMaster launcher

`Street Fighter III 3rd Strike.sh`:

```bash
#!/bin/bash
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# CFW detection (PortMaster boilerplate)
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi
source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/3sx"
CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR/resources"
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Seed default config + keymap on first run
cp -n conf-defaults/* "$CONFDIR/" 2>/dev/null || true

# Verify game data is present
if [ ! -f "$CONFDIR/resources/SF33RD.AFS" ]; then
    pm_message "Missing SF33RD.AFS in $CONFDIR/resources/."
    pm_message "Extract it from your PS2 SF3:3S ISO and copy it there."
    sleep 5
    exit 1
fi

export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
export XDG_DATA_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

$GPTOKEYB "3sx" -c "./3sx.gptk" &
pm_platform_helper "$GAMEDIR/3sx"
./3sx
pm_finish
```

`3sx.gptk` only handles Start+Select → quit; everything else is passthrough so
the game reads the gamepad through SDL directly.

`port.json` (skeleton, full file generated via PortMaster's port.json
generator):

```json
{
  "version": 2,
  "name": "3sx.zip",
  "items": ["Street Fighter III 3rd Strike.sh", "3sx"],
  "items_opt": null,
  "attr": {
    "title": "Street Fighter III: 3rd Strike",
    "desc": "Native port of Street Fighter III: 3rd Strike (3sx).",
    "inst": "Place SF33RD.AFS in /roms/ports/3sx/conf/resources/.",
    "genres": ["fighting"],
    "porter": ["<porter>"],
    "rtr": false,
    "runtime": null,
    "arch": ["aarch64"]
  }
}
```

## Verification

### Build-time (runs in the Docker container, no device required)

- `file dist/staging/3sx/3sx` matches
  `ELF 64-bit LSB ... ARM aarch64, dynamically linked, interpreter /lib/ld-linux-aarch64.so.1`.
- `aarch64-linux-gnu-readelf -d dist/staging/3sx/3sx` shows
  `RUNPATH` (or `RPATH`) containing `$ORIGIN/libs.aarch64`.
- `qemu-aarch64 -L /usr/aarch64-linux-gnu ldd dist/staging/3sx/3sx` resolves
  every needed `.so` from `libs.aarch64/` or core glibc
  (`libc`, `libm`, `libdl`, `libpthread`, `librt`, `ld-linux-aarch64`).
  Anything else fails the build.
- `nm -D dist/staging/3sx/libs.aarch64/libSDL3.so.0 | grep -E '(_kmsdrm|_wayland)'`
  returns at least one match, confirming SDL3 was built with KMSDRM/Wayland
  video drivers.
- `python3 -m json.tool dist/staging/3sx/port.json > /dev/null` validates
  the metadata.
- If PortMaster's `tools/build_release.py --do-check` is reachable, run it on
  the staged port.

### Smoke test under qemu-user (host, no GPU/display)

- `qemu-aarch64 -L /usr/aarch64-linux-gnu dist/staging/3sx/3sx --help`
  exits cleanly. Catches dlopen / RPATH / ABI errors before the device.

### On-device manual checklist (porter, on the H700)

Documented in `docs/portmaster.md`:

1. Boot reaches title screen within ~10s of cold launch.
2. fps log line in `log.txt` reports ≥58 fps in-match for at least 30s.
3. Start+Select quits cleanly via gptokeyb.
4. Audio plays without crackle (attract mode + first round).
5. All 6 attack buttons + both macros register in training mode.
6. Save/replay roundtrip writes to `$CONFDIR`.
7. Netplay screen opens (don't need a successful match — confirms GekkoNet
   and SDL_net linked correctly at runtime).
8. Image fills the panel correctly with 4:3 letterbox/pillarbox on
   640×480 and on 720×720 if available.

## Risks & open questions

1. **SDL3 + Mali-G31 + Panfrost performance.** Likely fine (low draw-call
   count) but unverified until on-device test. Fallback if the GLES renderer
   underperforms: set `SDL_HINT_RENDER_DRIVER=opengles2` explicitly in the
   launcher, or disable the `gpu` renderer at SDL3 build time.
2. **SDL3 availability on Knulli/Rocknix.** PortMaster docs are SDL2-centric;
   bundling our own `libSDL3.so.0` sidesteps this. Symbol scan confirms
   KMSDRM/Wayland support is present in our build.
3. **Knulli vs Rocknix differences.** Both Batocera-based. PortMaster's
   `mod_${CFW_NAME}.txt` boilerplate handles per-CFW quirks. Ship one zip,
   test on whichever the user runs.
4. **glibc version skew.** Building on `debian:bullseye` (glibc 2.31) gives
   forward compatibility with current Knulli/Rocknix images. Re-pin downward
   only if a runtime test forces it.
5. **Cursor/mouse-only UI elements.** Not audited yet. The fullscreen +
   hidden-cursor decision sidesteps most of this; implementation phase will
   grep for `SDL_GetMouseState` / `SDL_EVENT_MOUSE_*` consumers and decide
   whether any need a gamepad fallback.

## Out of scope (deferred)

- Save states, rewind, in-game settings menu redesign, RetroAchievements,
  custom shaders.
- 32-bit (armhf) builds.
- On-device ISO extraction or recovery UI.
- Dynamic resolution switching while running.
