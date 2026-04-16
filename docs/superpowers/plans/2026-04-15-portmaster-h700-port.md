# PortMaster Anbernic H700 Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cross-compile 3sx for Anbernic H700 handhelds (Knulli/Rocknix) and ship as a standard PortMaster zip.

**Architecture:** Reuse the existing `CRS_APP_DRIVER_SDL` / `CRS_VIDEO_DRIVER_SDL` backend with a new `PORTMASTER` CMake option that gates dependency removal (libcdio, ImGui, CHECKSUM) and runtime tweaks (force fullscreen, integer scale default, skip resource-copying flow, gamepad remap for Anbernic arcade layout, periodic fps log). Cross-compile with a Docker image (`debian:bullseye` + `crossbuild-essential-arm64`). Bundle the aarch64 binary plus shared `libSDL3.so.0` and FFmpeg `.so` files into `libs.aarch64/`, with a PortMaster-conventional launcher script.

**Tech Stack:** C11, CMake ≥3.24, SDL3 3.4.4, FFmpeg 8.0 (only `adpcm_adx`), GekkoNet (static), SDL3_net (static), minizip-ng (static), tf-psa-crypto (static), zlib (Debian aarch64 sysroot). Docker (`debian:bullseye`) with `gcc-aarch64-linux-gnu` and `qemu-aarch64-static`. PortMaster runtime: `gptokeyb`, `control.txt`.

**Spec:** `docs/superpowers/specs/2026-04-15-portmaster-h700-port-design.md`

---

## File Map

**Created:**
- `portmaster/Dockerfile`
- `portmaster/build.sh`
- `portmaster/build-deps-aarch64.sh`
- `portmaster/cmake/aarch64-linux-gnu.cmake`
- `portmaster/bundle/Street Fighter III 3rd Strike.sh`
- `portmaster/bundle/3sx/port.json`
- `portmaster/bundle/3sx/gameinfo.xml`
- `portmaster/bundle/3sx/README.md`
- `portmaster/bundle/3sx/screenshot.png` (placeholder, replaced before release)
- `portmaster/bundle/3sx/cover.png` (placeholder, optional)
- `portmaster/bundle/3sx/3sx.gptk`
- `portmaster/bundle/3sx/conf-defaults/config`
- `portmaster/bundle/3sx/licenses/` (one file per third-party dep)
- `docs/portmaster.md`

**Modified:**
- `CMakeLists.txt` — add `PORTMASTER` option and conditional defines/links
- `src/port/paths.c` — `#if CRS_PLATFORM_PORTMASTER` branch in `Paths_GetPrefPath`
- `src/port/resources.c` — gate libcdio include + `Resources_RunResourceCopyingFlow` body
- `src/platform/app/sdl/sdl_app.c` — fullscreen, scale, hidden cursor, skip resource flow, fps log
- `src/port/sdk/sdk_libpad2.c` — `#if CRS_PLATFORM_PORTMASTER` gamepad remap
- `.gitignore` — ignore `dist/`, `build-aarch64/`, `third_party/aarch64/`

**Untouched:**
- All other `src/sf33rd/**`, `src/core/**`, `src/platform/video/**`, `src/imgui/**` code
- `build-deps.sh`, `docs/building.md` — desktop flow stays as-is
- `cmake/imgui_sources.cmake`

---

## Task 1: Add `PORTMASTER` CMake option (no behavior changes yet)

**Files:**
- Modify: `CMakeLists.txt:1-79`

- [ ] **Step 1: Read the current CMakeLists.txt header**

Run: `cat -n CMakeLists.txt | head -80`

Confirm the existing structure has `if(PSP) ... else() ...` blocks for compile definitions and link libraries, and that `set(THIRD_PARTY_DIR "${CMAKE_SOURCE_DIR}/third_party")` is on line 147.

- [ ] **Step 2: Insert the option declaration after `project(...)`**

Edit `CMakeLists.txt`. Find:

```cmake
cmake_minimum_required(VERSION 3.24)
project(3sx LANGUAGES C CXX)

include(${PROJECT_SOURCE_DIR}/cmake/imgui_sources.cmake)
```

Replace with:

```cmake
cmake_minimum_required(VERSION 3.24)
project(3sx LANGUAGES C CXX)

option(PORTMASTER "Build for PortMaster aarch64 handhelds (Knulli/Rocknix on Anbernic H700)" OFF)

include(${PROJECT_SOURCE_DIR}/cmake/imgui_sources.cmake)
```

- [ ] **Step 3: Add the `PORTMASTER` branch alongside the existing `if(PSP) ... else()`**

Find the block starting at:

```cmake
if(PSP)
    target_compile_definitions(3sx PRIVATE
        $<$<CONFIG:Debug>:DEBUG>
```

Replace the entire `if(PSP) ... else() ... endif()` definitions block (lines ~44-72) with:

```cmake
if(PSP)
    target_compile_definitions(3sx PRIVATE
        $<$<CONFIG:Debug>:DEBUG>

        $<$<CONFIG:Release>:RELEASE>

        CRS_APP_DRIVER_PSP
        CRS_VIDEO_DRIVER_PSP
    )
elseif(PORTMASTER)
    target_compile_definitions(3sx PRIVATE
        RELEASE

        # GekkoNet is a pre-built static lib; these were previously propagated by its cmake target
        GEKKONET_STATIC
        GEKKONET_NO_ASIO

        CRS_APP_DRIVER_SDL
        CRS_VIDEO_DRIVER_SDL
        CRS_PLATFORM_PORTMASTER

        ARCADE_ROM
        SOUND_ENABLED
        NETPLAY_ENABLED
    )
else()
    target_compile_definitions(3sx PRIVATE
        $<$<CONFIG:Debug>:DEBUG>
        $<$<CONFIG:Debug>:NETPLAY_ENABLED>

        $<$<CONFIG:Release>:RELEASE>
        $<$<CONFIG:Release>:CHECKSUM>

        # GekkoNet is a pre-built static lib; these were previously propagated by its cmake target
        GEKKONET_STATIC
        GEKKONET_NO_ASIO

        CRS_APP_DRIVER_SDL
        CRS_VIDEO_DRIVER_SDL

        ARCADE_ROM
        SOUND_ENABLED
        IMGUI
    )
endif()
```

- [ ] **Step 4: Verify desktop build is unchanged**

Run: `cmake -B build-verify -DCMAKE_BUILD_TYPE=Release -DPORTMASTER=OFF -Wno-dev 2>&1 | tail -20`

Expected: configure succeeds with no errors. (Don't actually build; we just want to confirm the cmake parse is healthy.)

- [ ] **Step 5: Verify `PORTMASTER=ON` configure also parses**

Run: `cmake -B build-verify-pm -DCMAKE_BUILD_TYPE=Release -DPORTMASTER=ON -Wno-dev 2>&1 | tail -20`

Expected: configure succeeds. It will fail later at link time because libcdio is still in the link line and we haven't gated it yet — that's fine, this step only checks cmake parse.

- [ ] **Step 6: Clean up verification dirs**

Run: `rm -rf build-verify build-verify-pm`

- [ ] **Step 7: Commit**

Run:
```bash
git add CMakeLists.txt
git commit -m "Add PORTMASTER CMake option (no behavior yet)"
```

---

## Task 2: Add `.gitignore` entries for cross-build artifacts

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Read current .gitignore**

Run: `cat .gitignore 2>/dev/null || echo "(no .gitignore yet)"`

- [ ] **Step 2: Append PortMaster build artifacts**

Append these lines to `.gitignore` (create the file if missing):

```
# PortMaster cross-build outputs
/build-aarch64/
/third_party/aarch64/
/dist/
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "Ignore PortMaster cross-build artifacts"
```

---

## Task 3: Skip libcdio in CMake when `PORTMASTER=ON`

**Files:**
- Modify: `CMakeLists.txt:147-197`

- [ ] **Step 1: Locate the include block**

Find lines that read:

```cmake
include_directories(
    ${FFMPEG_ROOT}/include
    ${SDL3_ROOT}/include
    ${LIBCDIO_ROOT}/include
    ${GEKKONET_ROOT}/include
    ${SDL3_NET_ROOT}/include
    ${MINIZIP_NG_ROOT}/include
    ${TF_PSA_CRYPTO_ROOT}/include
)
```

- [ ] **Step 2: Conditionally skip libcdio include**

Replace with:

```cmake
include_directories(
    ${FFMPEG_ROOT}/include
    ${SDL3_ROOT}/include
    ${GEKKONET_ROOT}/include
    ${SDL3_NET_ROOT}/include
    ${MINIZIP_NG_ROOT}/include
    ${TF_PSA_CRYPTO_ROOT}/include
)

if(NOT PORTMASTER)
    include_directories(${LIBCDIO_ROOT}/include)
endif()
```

- [ ] **Step 3: Locate the desktop link block**

Find:

```cmake
else()
    target_link_libraries(3sx PRIVATE
        m
        "${LIBCDIO_ROOT}/lib/libiso9660.a"
        "${LIBCDIO_ROOT}/lib/libcdio.a"
        "${GEKKONET_ROOT}/lib/libGekkoNet.a"
        "${SDL3_NET_ROOT}/lib/libSDL3_net.a"
        "${MINIZIP_NG_ROOT}/lib/libminizip-ng.a"
        "${TF_PSA_CRYPTO_ROOT}/lib/libtfpsacrypto.a"
        ZLIB::ZLIB
        stdc++ # For GekkoNet
    )
endif()
```

- [ ] **Step 4: Add a `PORTMASTER` branch above the `else()`**

Replace with:

```cmake
elseif(PORTMASTER)
    target_link_libraries(3sx PRIVATE
        m
        "${GEKKONET_ROOT}/lib/libGekkoNet.a"
        "${SDL3_NET_ROOT}/lib/libSDL3_net.a"
        "${MINIZIP_NG_ROOT}/lib/libminizip-ng.a"
        "${TF_PSA_CRYPTO_ROOT}/lib/libtfpsacrypto.a"
        ZLIB::ZLIB
        stdc++ # For GekkoNet
    )
else()
    target_link_libraries(3sx PRIVATE
        m
        "${LIBCDIO_ROOT}/lib/libiso9660.a"
        "${LIBCDIO_ROOT}/lib/libcdio.a"
        "${GEKKONET_ROOT}/lib/libGekkoNet.a"
        "${SDL3_NET_ROOT}/lib/libSDL3_net.a"
        "${MINIZIP_NG_ROOT}/lib/libminizip-ng.a"
        "${TF_PSA_CRYPTO_ROOT}/lib/libtfpsacrypto.a"
        ZLIB::ZLIB
        stdc++ # For GekkoNet
    )
endif()
```

(Note: this places `elseif(PORTMASTER)` between the existing `if(PSP)` link block and the desktop `else()`. Verify in your editor that the surrounding `if(PSP) target_link_libraries(...)` block is still intact directly above the new `elseif`.)

- [ ] **Step 5: Locate the UNIX-shared-libs block**

Find:

```cmake
elseif(UNIX)
    target_link_libraries(3sx PRIVATE
        ${FFMPEG_ROOT}/lib/libavcodec.so
        ${FFMPEG_ROOT}/lib/libavformat.so
        ${FFMPEG_ROOT}/lib/libavutil.so
        ${FFMPEG_ROOT}/lib/libswresample.so
        ${SDL3_ROOT}/lib/libSDL3.so
    )
endif()
```

This block already runs unconditionally on Linux, including PortMaster. No change needed here — confirm by reading lines and moving on.

- [ ] **Step 6: Add `INSTALL_RPATH` for PORTMASTER and skip MACOSX/UNIX-rpath logic**

Find:

```cmake
elseif(UNIX AND NOT APPLE)
    set_target_properties(3sx PROPERTIES
        INSTALL_RPATH "\$ORIGIN/../lib"
    )
endif()
```

Replace with:

```cmake
elseif(PORTMASTER)
    set_target_properties(3sx PROPERTIES
        INSTALL_RPATH "\$ORIGIN/libs.aarch64"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
elseif(UNIX AND NOT APPLE)
    set_target_properties(3sx PROPERTIES
        INSTALL_RPATH "\$ORIGIN/../lib"
    )
endif()
```

- [ ] **Step 7: Verify cmake parse**

Run: `cmake -B build-verify-pm -DPORTMASTER=ON -Wno-dev 2>&1 | tail -10`

Expected: configure succeeds.

- [ ] **Step 8: Clean up + commit**

```bash
rm -rf build-verify-pm
git add CMakeLists.txt
git commit -m "Skip libcdio + set RPATH when PORTMASTER=ON"
```

---

## Task 4: Gate libcdio code in `src/port/resources.c`

**Files:**
- Modify: `src/port/resources.c:1-15` and `src/port/resources.c:88-242`
- Test: build under `PORTMASTER` succeeds without libcdio headers (covered later in Task 11 verification)

- [ ] **Step 1: Read the current includes**

Run: `head -20 src/port/resources.c`

Confirm lines 10-12 read:

```c
#if CRS_APP_DRIVER_SDL
#include <cdio/iso9660.h>
#endif
```

- [ ] **Step 2: Tighten the libcdio include guard**

Replace:

```c
#if CRS_APP_DRIVER_SDL
#include <cdio/iso9660.h>
#endif
```

With:

```c
#if CRS_APP_DRIVER_SDL && !CRS_PLATFORM_PORTMASTER
#include <cdio/iso9660.h>
#endif
```

- [ ] **Step 3: Tighten the resource-copying-flow guard**

Find the block that begins with:

```c
#if CRS_APP_DRIVER_SDL

#define ERROR_LEN_MAX 512
```

(around line 88) and ends at:

```c
#endif // CRS_APP_DRIVER_SDL
```

(around line 242).

Change the opening guard from:

```c
#if CRS_APP_DRIVER_SDL
```

to:

```c
#if CRS_APP_DRIVER_SDL && !CRS_PLATFORM_PORTMASTER
```

And change the closing comment to:

```c
#endif // CRS_APP_DRIVER_SDL && !CRS_PLATFORM_PORTMASTER
```

- [ ] **Step 4: Verify desktop build still parses**

Run: `cmake -B build-verify -DCMAKE_BUILD_TYPE=Release -Wno-dev 2>&1 | tail -5 && cmake --build build-verify --target 3sx -j2 2>&1 | tail -20`

Expected: build succeeds. (Requires `build-deps.sh` to have been run previously; if not, skip to Step 5.)

- [ ] **Step 5: Commit**

```bash
rm -rf build-verify
git add src/port/resources.c
git commit -m "Gate libcdio resource flow behind !CRS_PLATFORM_PORTMASTER"
```

---

## Task 5: Override `Paths_GetPrefPath` for PortMaster

**Files:**
- Modify: `src/port/paths.c`

- [ ] **Step 1: Read current paths.c**

Run: `cat src/port/paths.c`

Confirm `Paths_GetPrefPath` returns `SDL_GetPrefPath("CrowdedStreet", "3SX")`.

- [ ] **Step 2: Add PORTMASTER branch**

Replace the entire file with:

```c
#include "port/paths.h"

#include <SDL3/SDL.h>

#include <stdlib.h>

static const char* pref_path = NULL;

const char* Paths_GetPrefPath() {
    if (pref_path != NULL) {
        return pref_path;
    }

#if CRS_PLATFORM_PORTMASTER
    // The PortMaster launcher sets XDG_DATA_HOME to the per-port conf
    // directory (e.g. /roms/ports/3sx/conf). We use that directly without
    // the "CrowdedStreet/3SX" nesting that SDL_GetPrefPath would apply.
    const char* xdg = SDL_getenv("XDG_DATA_HOME");

    if (xdg != NULL && xdg[0] != '\0') {
        // Ensure trailing slash for downstream string concatenation.
        const size_t len = SDL_strlen(xdg);
        const bool needs_slash = (xdg[len - 1] != '/');
        char* buf = NULL;
        SDL_asprintf(&buf, "%s%s", xdg, needs_slash ? "/" : "");
        pref_path = buf;
    } else {
        pref_path = SDL_strdup("/tmp/3sx/");
    }
#else
    pref_path = SDL_GetPrefPath("CrowdedStreet", "3SX");
#endif

    return pref_path;
}

const char* Paths_GetBasePath() {
    return SDL_GetBasePath();
}
```

- [ ] **Step 3: Verify desktop compile**

Run: `cmake -B build-verify -DCMAKE_BUILD_TYPE=Release -Wno-dev 2>&1 | tail -3 && cmake --build build-verify --target 3sx -j2 2>&1 | tail -10`

Expected: build succeeds (assuming third_party deps already built).

- [ ] **Step 4: Commit**

```bash
rm -rf build-verify
git add src/port/paths.c
git commit -m "Use XDG_DATA_HOME directly when CRS_PLATFORM_PORTMASTER"
```

---

## Task 6: SDL app tweaks for PortMaster (fullscreen, scale, cursor, resource flow, fps log)

**Files:**
- Modify: `src/platform/app/sdl/sdl_app.c`

- [ ] **Step 1: Read the affected functions**

Run: `grep -n "init_window\|init_scalemode\|loop()\|hide_cursor_if_needed\|update_metrics\|APP_PHASE_COPYING_RESOURCES" src/platform/app/sdl/sdl_app.c`

Confirm the functions exist at the line numbers you'll be editing.

- [ ] **Step 2: Force-fullscreen and current display mode in `init_window`**

Find:

```c
static bool init_window() {
    SDL_WindowFlags window_flags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;

    if (Config_GetBool(CFG_KEY_FULLSCREEN)) {
        window_flags |= SDL_WINDOW_FULLSCREEN;
    }

    int window_width = Config_GetInt(CFG_KEY_WINDOW_WIDTH);

    if (window_width < window_min_width) {
        window_width = window_min_width;
    }

    int window_height = Config_GetInt(CFG_KEY_WINDOW_HEIGHT);

    if (window_height < window_min_height) {
        window_height = window_min_height;
    }
```

Replace with:

```c
static bool init_window() {
    SDL_WindowFlags window_flags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;

    if (Config_GetBool(CFG_KEY_FULLSCREEN)) {
        window_flags |= SDL_WINDOW_FULLSCREEN;
    }

#if CRS_PLATFORM_PORTMASTER
    // Always fullscreen on the H700; window flags from config are ignored.
    window_flags |= SDL_WINDOW_FULLSCREEN;
    window_flags &= ~SDL_WINDOW_RESIZABLE;

    int window_width = window_min_width;
    int window_height = window_min_height;

    SDL_DisplayID primary = SDL_GetPrimaryDisplay();
    const SDL_DisplayMode* mode = SDL_GetCurrentDisplayMode(primary);

    if (mode != NULL) {
        window_width = mode->w;
        window_height = mode->h;
    }
#else
    int window_width = Config_GetInt(CFG_KEY_WINDOW_WIDTH);

    if (window_width < window_min_width) {
        window_width = window_min_width;
    }

    int window_height = Config_GetInt(CFG_KEY_WINDOW_HEIGHT);

    if (window_height < window_min_height) {
        window_height = window_min_height;
    }
#endif
```

- [ ] **Step 3: Default to integer scale mode on PortMaster**

Find:

```c
static void init_scalemode() {
    const char* raw_scalemode = Config_GetString(CFG_KEY_SCALEMODE);

    if (raw_scalemode == NULL) {
        return;
    }
```

Replace with:

```c
static void init_scalemode() {
#if CRS_PLATFORM_PORTMASTER
    // H700 panels are 640x480 / 720x720 / 720x480 — integer scaling looks
    // best on all of them. Override the desktop default ("soft-linear")
    // unless the user has explicitly configured a different mode.
    scale_mode = SCALEMODE_INTEGER;
#endif

    const char* raw_scalemode = Config_GetString(CFG_KEY_SCALEMODE);

    if (raw_scalemode == NULL) {
        return;
    }
```

- [ ] **Step 4: Skip the resource-copying phase on PortMaster**

Find the `loop()` function's `APP_PHASE_INIT` case:

```c
        case APP_PHASE_INIT:
            pre_init();

            if (Resources_Check()) {
                full_init();
                phase = APP_PHASE_INITIALIZED;
            } else {
                phase = APP_PHASE_COPYING_RESOURCES;
            }

            break;
```

Replace with:

```c
        case APP_PHASE_INIT:
            pre_init();

            if (Resources_Check()) {
                full_init();
                phase = APP_PHASE_INITIALIZED;
            } else {
#if CRS_PLATFORM_PORTMASTER
                // The launcher already verified SF33RD.AFS is present; if
                // we got here something is wrong and there's no UI to
                // recover from it. Fail loudly into the launcher's log.
                SDL_Log("FATAL: SF33RD.AFS missing from %s — copy it from "
                        "your PS2 SF3:3S ISO. See README.md.",
                        Resources_GetAFSPath());
                is_running = false;
#else
                phase = APP_PHASE_COPYING_RESOURCES;
#endif
            }

            break;
```

- [ ] **Step 5: Hide the cursor on PortMaster startup**

Find:

```c
static int full_init() {
    Config_Init();
    Keymap_Init();
    init_scalemode();
```

Insert after `init_scalemode();`:

```c
#if CRS_PLATFORM_PORTMASTER
    // No mouse on these handhelds — make sure SDL doesn't show one.
    SDL_HideCursor();
#endif
```

So the function reads:

```c
static int full_init() {
    Config_Init();
    Keymap_Init();
    init_scalemode();

#if CRS_PLATFORM_PORTMASTER
    SDL_HideCursor();
#endif
```

- [ ] **Step 6: Add periodic fps log line on PortMaster**

Find:

```c
static void update_metrics(Uint64 sleep_time) {
    const Uint64 new_frame_end_time = SDL_GetTicksNS();
    const Uint64 frame_time = new_frame_end_time - last_frame_end_time;
    const float frame_time_ms = (float)frame_time / 1e6;

    frame_metrics.frame_time[frame_metrics.head] = frame_time_ms;
    frame_metrics.idle_time[frame_metrics.head] = (float)sleep_time / 1e6;
    frame_metrics.fps[frame_metrics.head] = 1000 / frame_time_ms;

    frame_metrics.head = (frame_metrics.head + 1) % SDL_arraysize(frame_metrics.frame_time);
    last_frame_end_time = new_frame_end_time;
}
```

Replace with:

```c
static void update_metrics(Uint64 sleep_time) {
    const Uint64 new_frame_end_time = SDL_GetTicksNS();
    const Uint64 frame_time = new_frame_end_time - last_frame_end_time;
    const float frame_time_ms = (float)frame_time / 1e6;

    frame_metrics.frame_time[frame_metrics.head] = frame_time_ms;
    frame_metrics.idle_time[frame_metrics.head] = (float)sleep_time / 1e6;
    frame_metrics.fps[frame_metrics.head] = 1000 / frame_time_ms;

    frame_metrics.head = (frame_metrics.head + 1) % SDL_arraysize(frame_metrics.frame_time);
    last_frame_end_time = new_frame_end_time;

#if CRS_PLATFORM_PORTMASTER
    // Periodic perf line every ~5s for PortMaster log triage.
    static Uint64 last_log_time = 0;

    if (last_log_time == 0) {
        last_log_time = new_frame_end_time;
    }

    if (new_frame_end_time - last_log_time >= 5000000000ULL) {
        const size_t n = SDL_arraysize(frame_metrics.fps);
        float fps_sum = 0.0f, ft_sum = 0.0f, idle_sum = 0.0f;

        for (size_t i = 0; i < n; i++) {
            fps_sum += frame_metrics.fps[i];
            ft_sum += frame_metrics.frame_time[i];
            idle_sum += frame_metrics.idle_time[i];
        }

        SDL_Log("[perf] fps_avg=%.1f frame_ms_avg=%.2f idle_ms_avg=%.2f",
                fps_sum / n, ft_sum / n, idle_sum / n);
        last_log_time = new_frame_end_time;
    }
#endif
}
```

- [ ] **Step 7: Verify desktop build still passes**

Run: `cmake -B build-verify -DCMAKE_BUILD_TYPE=Release -Wno-dev 2>&1 | tail -3 && cmake --build build-verify --target 3sx -j2 2>&1 | tail -10`

Expected: build succeeds; no new warnings on Linux.

- [ ] **Step 8: Commit**

```bash
rm -rf build-verify
git add src/platform/app/sdl/sdl_app.c
git commit -m "PortMaster: force fullscreen, integer scale, hide cursor, skip resource flow, log perf"
```

---

## Task 7: Gamepad remap for Anbernic arcade layout

**Files:**
- Modify: `src/port/sdk/sdk_libpad2.c:28-76`

- [ ] **Step 1: Read current scePad2Read**

Run: `sed -n '28,76p' src/port/sdk/sdk_libpad2.c`

Confirm the SDL→PS2 mapping is 1:1 (south=cross, west=square, etc.).

- [ ] **Step 2: Add the PortMaster-only remap**

Find:

```c
    data->sw1.bits.l1 = !button_state.left_shoulder;
    data->sw1.bits.r1 = !button_state.right_shoulder;
    data->sw1.bits.l2 = button_state.left_trigger == 0;
    data->sw1.bits.r2 = button_state.right_trigger == 0;
    data->sw1.bits.cross = !button_state.south;
    data->sw1.bits.circle = !button_state.east;
    data->sw1.bits.square = !button_state.west;
    data->sw1.bits.triangle = !button_state.north;
```

Replace with:

```c
#if CRS_PLATFORM_PORTMASTER
    // Anbernic H700 arcade-stick remap. Goal (Anbernic labels → SF3 actions,
    // assuming the in-game default PS2 button config):
    //   X (top, SDL north)        -> square   = LP
    //   Y (left, SDL west)        -> triangle = MP
    //   R1                        -> r1       = HP
    //   A (right, SDL east)       -> cross    = LK
    //   B (bottom, SDL south)     -> circle   = MK
    //   L1                        -> r2       = HK
    //   L2 (digital trigger)      -> l1       = 3P macro
    //   R2 (digital trigger)      -> l2       = 3K macro
    data->sw1.bits.l1 = button_state.left_trigger == 0;        // L2 -> l1
    data->sw1.bits.r1 = !button_state.right_shoulder;          // R1 -> r1
    data->sw1.bits.l2 = button_state.right_trigger == 0;       // R2 -> l2
    data->sw1.bits.r2 = !button_state.left_shoulder;           // L1 -> r2
    data->sw1.bits.cross = !button_state.east;                 // A  -> cross
    data->sw1.bits.circle = !button_state.south;               // B  -> circle
    data->sw1.bits.square = !button_state.north;               // X  -> square
    data->sw1.bits.triangle = !button_state.west;              // Y  -> triangle
#else
    data->sw1.bits.l1 = !button_state.left_shoulder;
    data->sw1.bits.r1 = !button_state.right_shoulder;
    data->sw1.bits.l2 = button_state.left_trigger == 0;
    data->sw1.bits.r2 = button_state.right_trigger == 0;
    data->sw1.bits.cross = !button_state.south;
    data->sw1.bits.circle = !button_state.east;
    data->sw1.bits.square = !button_state.west;
    data->sw1.bits.triangle = !button_state.north;
#endif
```

- [ ] **Step 3: Mirror the remap in the pressure-value block**

Find:

```c
    data->crossP = button_state.south ? 0xFF : 0;
    data->circleP = button_state.east ? 0xFF : 0;
    data->squareP = button_state.west ? 0xFF : 0;
    data->triangleP = button_state.north ? 0xFF : 0;
```

Replace with:

```c
#if CRS_PLATFORM_PORTMASTER
    data->crossP = button_state.east ? 0xFF : 0;
    data->circleP = button_state.south ? 0xFF : 0;
    data->squareP = button_state.north ? 0xFF : 0;
    data->triangleP = button_state.west ? 0xFF : 0;
#else
    data->crossP = button_state.south ? 0xFF : 0;
    data->circleP = button_state.east ? 0xFF : 0;
    data->squareP = button_state.west ? 0xFF : 0;
    data->triangleP = button_state.north ? 0xFF : 0;
#endif
```

- [ ] **Step 4: Verify desktop build is unchanged**

Run: `cmake -B build-verify -DCMAKE_BUILD_TYPE=Release -Wno-dev 2>&1 | tail -3 && cmake --build build-verify --target 3sx -j2 2>&1 | tail -10`

Expected: build succeeds; desktop input behavior is unchanged because the `#if CRS_PLATFORM_PORTMASTER` is false.

- [ ] **Step 5: Commit**

```bash
rm -rf build-verify
git add src/port/sdk/sdk_libpad2.c
git commit -m "PortMaster: remap gamepad to Anbernic arcade layout"
```

---

## Task 8: Cross-compile Dockerfile

**Files:**
- Create: `portmaster/Dockerfile`

- [ ] **Step 1: Create the portmaster directory**

Run: `mkdir -p portmaster`

- [ ] **Step 2: Write the Dockerfile**

Create `portmaster/Dockerfile`:

```dockerfile
# Cross-compile environment for the Anbernic H700 (aarch64 glibc).
# Pinned to debian:bullseye for forward-compatibility with current
# Knulli/Rocknix images (glibc >= 2.31).
FROM debian:bullseye

ENV DEBIAN_FRONTEND=noninteractive

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
        bsdtar \
        file \
        binutils-aarch64-linux-gnu \
        qemu-user-static \
        libdrm-dev:arm64 \
        libgbm-dev:arm64 \
        libgles2-mesa-dev:arm64 \
        libegl1-mesa-dev:arm64 \
        libwayland-dev:arm64 \
        wayland-protocols \
        libxkbcommon-dev:arm64 \
        libdecor-0-dev:arm64 \
        libasound2-dev:arm64 \
        libudev-dev:arm64 \
        libpulse-dev:arm64 \
        zlib1g-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

# pkg-config wrapper that knows about the arm64 multiarch sysroot.
ENV PKG_CONFIG=aarch64-linux-gnu-pkg-config
ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
ENV PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
ENV PKG_CONFIG_SYSROOT_DIR=/

WORKDIR /src
```

- [ ] **Step 3: Build the image**

Run: `docker build -t 3sx-portmaster portmaster/ 2>&1 | tail -10`

Expected: image builds successfully. The first build will take 5-10 minutes due to the cross-arch packages.

- [ ] **Step 4: Smoke-test the cross compiler**

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster bash -c '
echo "int main(void){return 0;}" > /tmp/t.c &&
aarch64-linux-gnu-gcc /tmp/t.c -o /tmp/t &&
file /tmp/t'
```

Expected output contains: `ELF 64-bit LSB ... ARM aarch64`.

- [ ] **Step 5: Smoke-test qemu-user**

Run:
```bash
docker run --rm 3sx-portmaster bash -c '
echo "int main(void){return 42;}" > /tmp/t.c &&
aarch64-linux-gnu-gcc /tmp/t.c -o /tmp/t &&
qemu-aarch64-static -L /usr/aarch64-linux-gnu /tmp/t; echo "exit=$?"'
```

Expected: `exit=42`.

- [ ] **Step 6: Commit**

```bash
git add portmaster/Dockerfile
git commit -m "Add aarch64 cross-compile Dockerfile"
```

---

## Task 9: CMake toolchain file for aarch64

**Files:**
- Create: `portmaster/cmake/aarch64-linux-gnu.cmake`

- [ ] **Step 1: Create the toolchain file**

Create `portmaster/cmake/aarch64-linux-gnu.cmake`:

```cmake
# CMake toolchain file for aarch64 Linux glibc cross-builds (Anbernic H700).
# Used together with portmaster/Dockerfile.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_AR           aarch64-linux-gnu-ar)
set(CMAKE_RANLIB       aarch64-linux-gnu-ranlib)
set(CMAKE_STRIP        aarch64-linux-gnu-strip)
set(CMAKE_OBJCOPY      aarch64-linux-gnu-objcopy)

set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# pkg-config inside the container is set up via env in the Dockerfile;
# CMake's FindPkgConfig will honor it.
```

- [ ] **Step 2: Smoke-test the toolchain file**

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster bash -c '
cd /tmp && cat > CMakeLists.txt <<EOF
cmake_minimum_required(VERSION 3.16)
project(t C)
add_executable(t t.c)
EOF
echo "int main(void){return 0;}" > t.c
cmake -B build -DCMAKE_TOOLCHAIN_FILE=/src/portmaster/cmake/aarch64-linux-gnu.cmake -Wno-dev > /dev/null &&
cmake --build build > /dev/null &&
file build/t'
```

Expected output contains: `ELF 64-bit LSB ... ARM aarch64`.

- [ ] **Step 3: Commit**

```bash
git add portmaster/cmake/aarch64-linux-gnu.cmake
git commit -m "Add aarch64 CMake toolchain file"
```

---

## Task 10: Cross-compile third-party deps

**Files:**
- Create: `portmaster/build-deps-aarch64.sh`

- [ ] **Step 1: Read the existing host build-deps.sh for reference**

Run: `cat -n build-deps.sh | head -80`

Note pinned versions: FFmpeg 8.0, SDL3 release-3.4.4, GekkoNet 7be848c, SDL3_net 92022dc, libcdio 2.3.0 (skip), minizip-ng 4.1.0, tf-psa-crypto 1.0.0.

- [ ] **Step 2: Write the cross build script**

Create `portmaster/build-deps-aarch64.sh`:

```bash
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

if [ -d "$SDL_BUILD" ]; then
    echo "SDL3 already built at $SDL_BUILD"
else
    echo "Building SDL3 (cross) at $SDL_BUILD..."
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
        -DCMAKE_PREFIX_PATH="$SDL_BUILD" \
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
        -DTF_PSA_CRYPTO_CONFIG_FILE="configs/crypto-config-ccm-aes-sha256.h"

    cmake --build "$TF_PSA_CRYPTO_SRC/cmake-build" -j"$JOBS"
    cmake --install "$TF_PSA_CRYPTO_SRC/cmake-build"

    rm -rf "$TF_PSA_CRYPTO_SRC"
    echo "tf-psa-crypto installed to $TF_PSA_CRYPTO_BUILD"
fi

echo "All aarch64 dependencies installed under $THIRD_PARTY"
```

- [ ] **Step 3: Make it executable**

Run: `chmod +x portmaster/build-deps-aarch64.sh`

- [ ] **Step 4: Run it inside the container**

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/build-deps-aarch64.sh 2>&1 | tail -30
```

Expected: completes successfully with `All aarch64 dependencies installed under /src/third_party/aarch64`. This will take 10-20 minutes on first run.

- [ ] **Step 5: Verify each dep produced its artifact**

Run:
```bash
ls -la third_party/aarch64/ffmpeg/build/lib/libavcodec.so* \
       third_party/aarch64/sdl3/build/lib/libSDL3.so* \
       third_party/aarch64/GekkoNet/build/lib/libGekkoNet.a \
       third_party/aarch64/SDL_net/build/lib/libSDL3_net.a \
       third_party/aarch64/minizip-ng/build/lib/libminizip-ng.a \
       third_party/aarch64/tf-psa-crypto/build/lib/libtfpsacrypto.a
```

Expected: every file exists.

- [ ] **Step 6: Verify SDL3 was built with KMSDRM/Wayland**

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster bash -c \
    'aarch64-linux-gnu-nm -D /src/third_party/aarch64/sdl3/build/lib/libSDL3.so | grep -E "KMSDRM|WAYLAND|kmsdrm|wayland" | head -5'
```

Expected: at least one symbol containing `KMSDRM` or `kmsdrm`, and one containing `WAYLAND` or `wayland`.

- [ ] **Step 7: Commit**

```bash
git add portmaster/build-deps-aarch64.sh
git commit -m "Add aarch64 cross-build script for third-party deps"
```

---

## Task 11: Make CMake honor `THIRD_PARTY_DIR` override for cross-builds

**Files:**
- Modify: `CMakeLists.txt:147`

- [ ] **Step 1: Read the current third_party setup**

Run: `sed -n '143,170p' CMakeLists.txt`

Confirm line 147 reads `set(THIRD_PARTY_DIR "${CMAKE_SOURCE_DIR}/third_party")`.

- [ ] **Step 2: Allow caller-supplied override and default to per-arch dir for PortMaster**

Find:

```cmake
set(THIRD_PARTY_DIR "${CMAKE_SOURCE_DIR}/third_party")
find_package(ZLIB REQUIRED)
```

Replace with:

```cmake
if(NOT DEFINED THIRD_PARTY_DIR)
    if(PORTMASTER)
        set(THIRD_PARTY_DIR "${CMAKE_SOURCE_DIR}/third_party/aarch64")
    else()
        set(THIRD_PARTY_DIR "${CMAKE_SOURCE_DIR}/third_party")
    endif()
endif()

find_package(ZLIB REQUIRED)
```

- [ ] **Step 3: Verify desktop cmake parse**

Run: `cmake -B build-verify -DCMAKE_BUILD_TYPE=Release -Wno-dev 2>&1 | tail -3`

Expected: success, `THIRD_PARTY_DIR` resolves to `<repo>/third_party`.

- [ ] **Step 4: Verify cross cmake parse inside the container**

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster bash -c '
cd /src && cmake -B build-aarch64 \
    -DCMAKE_TOOLCHAIN_FILE=portmaster/cmake/aarch64-linux-gnu.cmake \
    -DPORTMASTER=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -Wno-dev 2>&1 | tail -10'
```

Expected: configure succeeds.

- [ ] **Step 5: Build the binary**

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster bash -c '
cd /src && cmake --build build-aarch64 --target 3sx -j$(nproc) 2>&1 | tail -20'
```

Expected: link succeeds. Output binary at `build-aarch64/3sx`.

- [ ] **Step 6: Verify the binary's basics**

Run: `file build-aarch64/3sx`

Expected: `ELF 64-bit LSB ... ARM aarch64, dynamically linked, interpreter /lib/ld-linux-aarch64.so.1`.

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster aarch64-linux-gnu-readelf -d /src/build-aarch64/3sx | grep -E "RUNPATH|RPATH"
```

Expected: a line like `(RUNPATH) Library runpath: [$ORIGIN/libs.aarch64]`.

- [ ] **Step 7: Clean up + commit**

```bash
rm -rf build-verify
git add CMakeLists.txt
git commit -m "Default THIRD_PARTY_DIR to aarch64 sub-dir for PortMaster"
```

---

## Task 12: Bundle template files (port.json, gameinfo.xml, README, gptk, config defaults)

**Files:**
- Create: `portmaster/bundle/Street Fighter III 3rd Strike.sh`
- Create: `portmaster/bundle/3sx/port.json`
- Create: `portmaster/bundle/3sx/gameinfo.xml`
- Create: `portmaster/bundle/3sx/README.md`
- Create: `portmaster/bundle/3sx/3sx.gptk`
- Create: `portmaster/bundle/3sx/conf-defaults/config`

- [ ] **Step 1: Create the bundle directory structure**

Run:
```bash
mkdir -p "portmaster/bundle/3sx/conf-defaults" "portmaster/bundle/3sx/licenses"
```

- [ ] **Step 2: Write the launcher script**

Create `portmaster/bundle/Street Fighter III 3rd Strike.sh`:

```bash
#!/bin/bash
# PortMaster launcher for 3sx (Street Fighter III: 3rd Strike).
# Targets Anbernic H700 handhelds (Knulli/Rocknix), aarch64 glibc.

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# CFW detection — standard PortMaster boilerplate.
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

> "$GAMEDIR/log.txt"
exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Seed default config on first run (does not overwrite user changes).
if [ -d "$GAMEDIR/conf-defaults" ]; then
    cp -n "$GAMEDIR/conf-defaults/"* "$CONFDIR/" 2>/dev/null || true
fi

# Verify game data is present.
if [ ! -f "$CONFDIR/resources/SF33RD.AFS" ]; then
    pm_message "Missing SF33RD.AFS in $CONFDIR/resources/."
    pm_message "Extract it from your PS2 SF3:3S ISO (path /THIRD/SF33RD.AFS"
    pm_message "or /SF33RD.AFS) and copy it there. See README.md."
    sleep 5
    exit 1
fi

export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
export XDG_DATA_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# gptokeyb only handles the start+select quit combo; the game reads the
# gamepad through SDL directly.
$GPTOKEYB "3sx" -c "./3sx.gptk" &
pm_platform_helper "$GAMEDIR/3sx"
./3sx
pm_finish
```

- [ ] **Step 3: Make the launcher executable**

Run: `chmod +x "portmaster/bundle/Street Fighter III 3rd Strike.sh"`

- [ ] **Step 4: Write the gptokeyb keymap**

Create `portmaster/bundle/3sx/3sx.gptk`:

```ini
# 3sx — Street Fighter III: 3rd Strike
# gptokeyb is only used to translate the PortMaster quit combo
# (start + select) into the appropriate signal. The game reads gamepad
# input directly through SDL3, so all other buttons are passthrough.

back = "esc"
hotkey = "select"
```

- [ ] **Step 5: Write port.json**

Create `portmaster/bundle/3sx/port.json`:

```json
{
    "version": 2,
    "name": "3sx.zip",
    "items": [
        "Street Fighter III 3rd Strike.sh",
        "3sx"
    ],
    "items_opt": null,
    "attr": {
        "title": "Street Fighter III: 3rd Strike",
        "desc": "Native port of Street Fighter III: 3rd Strike for the Anbernic H700 family. Requires SF33RD.AFS extracted from a legally owned PS2 disc.",
        "inst": "Place SF33RD.AFS in /roms/ports/3sx/conf/resources/.",
        "genres": [
            "fighting",
            "arcade"
        ],
        "porter": [
            "TODO_porter_handle"
        ],
        "rtr": false,
        "runtime": null,
        "arch": [
            "aarch64"
        ]
    }
}
```

(The `TODO_porter_handle` literal is intentionally a string the porter must replace before submitting the PR — we keep it here rather than in a vague `<porter>` placeholder so it's grep-able.)

- [ ] **Step 6: Write gameinfo.xml**

Create `portmaster/bundle/3sx/gameinfo.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<gameList>
    <game>
        <path>./Street Fighter III 3rd Strike.sh</path>
        <name>Street Fighter III: 3rd Strike</name>
        <desc>Native port of Street Fighter III: 3rd Strike (3sx) for handhelds. Requires SF33RD.AFS extracted from a legally owned PS2 copy of Street Fighter III: 3rd Strike or Street Fighter Anniversary Collection.</desc>
        <releasedate>20260415T000000</releasedate>
        <developer>Capcom (original); CrowdedStreet (port)</developer>
        <publisher>Capcom</publisher>
        <genre>Fighting</genre>
        <image>./3sx/cover.png</image>
    </game>
</gameList>
```

- [ ] **Step 7: Write README.md**

Create `portmaster/bundle/3sx/README.md`:

```markdown
# 3sx — Street Fighter III: 3rd Strike (PortMaster build)

Native port of *Street Fighter III: 3rd Strike* targeting Anbernic H700
handhelds (RG35XX H, RG35XX SP, RG35XX 2024, RG28XX) running Knulli or
Rocknix.

Thanks to the [CrowdedStreet team](https://github.com/crowded-street/3sx)
for the upstream port.

## Requirements

- Anbernic H700 device (aarch64) running Knulli or Rocknix with PortMaster
  installed.
- A legally owned copy of *Street Fighter III: 3rd Strike* or *Street
  Fighter Anniversary Collection* for PlayStation 2.

## Installation

1. Install via PortMaster, **or** copy `Street Fighter III 3rd Strike.sh`
   and the `3sx/` folder into `/roms/ports/`.
2. On a PC, mount your PS2 disc image (`.iso`) and copy the file
   `/THIRD/SF33RD.AFS` (or `/SF33RD.AFS`) onto the device at:
   ```
   /roms/ports/3sx/conf/resources/SF33RD.AFS
   ```
3. Launch from the Ports menu.

## Controls

| Action       | Button             |
| ------------ | ------------------ |
| Light Punch  | X                  |
| Med  Punch   | Y                  |
| Heavy Punch  | R1                 |
| Light Kick   | A                  |
| Med  Kick    | B                  |
| Heavy Kick   | L1                 |
| 3-Punch      | L2                 |
| 3-Kick       | R2                 |
| Movement     | DPad / Left Stick  |
| Coin         | Select             |
| Start        | Start              |
| Quit game    | Start + Select     |

## Troubleshooting

- **Game complains about missing SF33RD.AFS** — recheck the file is at
  `/roms/ports/3sx/conf/resources/SF33RD.AFS`. Check `log.txt` in the
  port directory.
- **Frame drops** — `log.txt` records a `[perf]` line every 5 seconds
  with rolling fps and frame time averages. Anything below 58 fps in-match
  is worth reporting.

## Credits

- Game: Capcom
- Port: CrowdedStreet (3sx)
- PortMaster packaging: TODO_porter_handle

See `licenses/` for third-party software notices.
```

- [ ] **Step 8: Write the default config**

Create `portmaster/bundle/3sx/conf-defaults/config`:

```ini
# 3sx default config for the H700 PortMaster build.
# See https://github.com/crowded-street/3sx/blob/main/docs/config.md for
# the full list of options. The launcher copies this file into
# /roms/ports/3sx/conf/config on first launch (without overwriting an
# existing user config).

fullscreen = true
scalemode = integer
scanlines = 0
```

- [ ] **Step 9: Stage placeholder screenshot/cover**

Create one-pixel PNG placeholders so the bundle layout is complete; the
porter is expected to replace these with real screenshots before
submitting the PR.

```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster bash -c '
python3 -c "
import struct, zlib, sys
def png(path, w, h, rgba):
    sig = b\"\\x89PNG\\r\\n\\x1a\\n\"
    def chunk(t, d):
        return struct.pack(\">I\", len(d)) + t + d + struct.pack(\">I\", zlib.crc32(t + d) & 0xffffffff)
    ihdr = struct.pack(\">IIBBBBB\", w, h, 8, 6, 0, 0, 0)
    raw = b\"\".join(b\"\\x00\" + bytes(rgba)*w for _ in range(h))
    idat = zlib.compress(raw)
    open(path, \"wb\").write(sig + chunk(b\"IHDR\", ihdr) + chunk(b\"IDAT\", idat) + chunk(b\"IEND\", b\"\"))
png(\"/src/portmaster/bundle/3sx/screenshot.png\", 640, 480, (32,32,32,255))
png(\"/src/portmaster/bundle/3sx/cover.png\", 320, 480, (16,16,32,255))
"'
```

Verify:
```bash
file portmaster/bundle/3sx/screenshot.png portmaster/bundle/3sx/cover.png
```

Expected: both report `PNG image data`.

- [ ] **Step 10: Stage license file placeholders**

The licenses dir gets populated by the staging script in Task 14 (it copies
`LICENSE` and `THIRD_PARTY_NOTICES.txt` from the repo root and the bundled
gptokeyb license from the runtime). For now, just keep the directory.

Run: `touch portmaster/bundle/3sx/licenses/.gitkeep`

- [ ] **Step 11: Commit**

```bash
git add portmaster/bundle "portmaster/bundle/Street Fighter III 3rd Strike.sh"
git commit -m "Add PortMaster bundle template (launcher, port.json, README, defaults)"
```

---

## Task 13: Top-level `build.sh` and bundle staging

**Files:**
- Create: `portmaster/build.sh`

- [ ] **Step 1: Write the build entrypoint**

Create `portmaster/build.sh`:

```bash
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

# Strip bundled shared libs
for f in "$PORT_DIR/libs.aarch64/"*.so*; do
    if [ -f "$f" ] && [ ! -L "$f" ]; then
        aarch64-linux-gnu-strip --strip-unneeded "$f" || true
    fi
done

# Bundle template (port.json, gameinfo.xml, README, gptk, screenshot,
# cover, conf-defaults).
cp -r "$PM_DIR/bundle/3sx/." "$PORT_DIR/"
cp "$PM_DIR/bundle/Street Fighter III 3rd Strike.sh" "$STAGE_DIR/"
chmod +x "$STAGE_DIR/Street Fighter III 3rd Strike.sh"

# Licenses
cp "$ROOT_DIR/LICENSE" "$PORT_DIR/licenses/LICENSE-3sx"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.txt" "$PORT_DIR/licenses/" 2>/dev/null || true

# Drop the .gitkeep marker that was needed to keep the dir in git.
rm -f "$PORT_DIR/licenses/.gitkeep"

# 4. Build the zip.
echo "==> Building dist/3sx.zip"
( cd "$STAGE_DIR" && zip -r -X "$DIST_DIR/3sx.zip" "Street Fighter III 3rd Strike.sh" "3sx" )
ls -la "$DIST_DIR/3sx.zip"

if [ "$DO_VERIFY" = "1" ]; then
    "$PM_DIR/verify.sh"
fi

echo "==> Done. Output: $DIST_DIR/3sx.zip"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x portmaster/build.sh`

- [ ] **Step 3: Run the full build**

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/build.sh 2>&1 | tail -40
```

Expected: ends with `==> Done. Output: /src/dist/3sx.zip` and the file exists.

- [ ] **Step 4: Inspect the resulting zip**

Run:
```bash
unzip -l dist/3sx.zip | head -40
```

Expected: see `Street Fighter III 3rd Strike.sh`, `3sx/3sx`, `3sx/port.json`, `3sx/libs.aarch64/libSDL3.so.0`, etc.

- [ ] **Step 5: Commit**

```bash
git add portmaster/build.sh
git commit -m "Add top-level build.sh that produces dist/3sx.zip"
```

---

## Task 14: Verification script

**Files:**
- Create: `portmaster/verify.sh`

- [ ] **Step 1: Write the verifier**

Create `portmaster/verify.sh`:

```bash
#!/usr/bin/env bash
# Post-build verification for the 3sx PortMaster bundle.
# Run from inside the 3sx-portmaster Docker image OR after `build.sh`
# (assumes aarch64-linux-gnu-* binutils + qemu-aarch64-static available).
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/src}"
STAGE_DIR="$ROOT_DIR/dist/staging"
PORT_DIR="$STAGE_DIR/3sx"
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
python3 -m json.tool "$PORT_DIR/port.json" > /dev/null
pass "port.json is valid JSON"

# 4. Required files present
for f in \
    "$PORT_DIR/3sx" \
    "$PORT_DIR/3sx.gptk" \
    "$PORT_DIR/port.json" \
    "$PORT_DIR/gameinfo.xml" \
    "$PORT_DIR/README.md" \
    "$PORT_DIR/screenshot.png" \
    "$PORT_DIR/conf-defaults/config" \
    "$STAGE_DIR/Street Fighter III 3rd Strike.sh" ; do
    [ -e "$f" ] || fail "missing required file: $f"
done
pass "all required bundle files present"

# 5. Bundled libs include SDL3 and FFmpeg shared libs
for lib in libSDL3.so libavcodec.so libavformat.so libavutil.so libswresample.so; do
    ls "$LIBDIR/$lib"* > /dev/null || fail "missing bundled lib: $lib*"
done
pass "all bundled .so files present"

# 6. SDL3 has KMSDRM and Wayland support compiled in
sdl_lib=$(ls "$LIBDIR"/libSDL3.so* | head -1)
if aarch64-linux-gnu-nm -D "$sdl_lib" 2>/dev/null | grep -qE "KMSDRM|kmsdrm"; then
    pass "SDL3 has KMSDRM symbols"
else
    fail "SDL3 missing KMSDRM symbols (needed for X11-less handhelds)"
fi
if aarch64-linux-gnu-nm -D "$sdl_lib" 2>/dev/null | grep -qE "WAYLAND|wayland"; then
    pass "SDL3 has Wayland symbols"
else
    fail "SDL3 missing Wayland symbols"
fi

# 7. ldd-style dependency check via qemu-aarch64-static
# We add libs.aarch64 to LD_LIBRARY_PATH so the bundled libs resolve;
# anything still unresolved should be a core glibc lib.
deps=$(qemu-aarch64-static -L /usr/aarch64-linux-gnu \
    -E LD_LIBRARY_PATH="$LIBDIR" \
    /usr/aarch64-linux-gnu/lib/ld-linux-aarch64.so.1 --list "$BIN" 2>&1 || true)

# Allowlist of acceptable system libs (core glibc + dl/pthread/rt + dynamic linker)
allowed_re='libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libgcc_s\.so|ld-linux-aarch64\.so|libstdc\+\+\.so'

unexpected=$(echo "$deps" | awk '/=>/ && $3 !~ /(^'"$LIBDIR"'\/)/' | grep -vE "$allowed_re" || true)
if [ -n "$unexpected" ]; then
    echo "FAIL: unexpected library deps:" >&2
    echo "$unexpected" >&2
    exit 1
fi
pass "no unexpected library dependencies"

# 8. Binary at least loads under qemu (no --help flag exists, but it
#    should at least dlopen its libs and reach SDL_Init or fail with a
#    runtime-related message rather than a loader error).
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x portmaster/verify.sh`

- [ ] **Step 3: Run verification**

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/verify.sh 2>&1 | tee /tmp/verify.log
```

Expected: every line is `ok: ...` and final line is `All verification checks passed.`

If any check fails, stop and fix the underlying cause before continuing.

- [ ] **Step 4: Run the combined build+verify**

Run:
```bash
docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/build.sh --verify 2>&1 | tail -20
```

Expected: `All verification checks passed.` near the end.

- [ ] **Step 5: Commit**

```bash
git add portmaster/verify.sh
git commit -m "Add post-build verification script"
```

---

## Task 15: docs/portmaster.md guide

**Files:**
- Create: `docs/portmaster.md`

- [ ] **Step 1: Write the doc**

Create `docs/portmaster.md`:

```markdown
# PortMaster build (Anbernic H700 / Knulli / Rocknix)

This document covers building, packaging, and on-device testing of the
3sx PortMaster bundle for Anbernic H700 handhelds (RG35XX H, RG35XX SP,
RG35XX 2024, RG28XX) running Knulli or Rocknix.

For desktop builds (Windows / macOS / Linux), see
[building.md](./building.md).

## Requirements

- Linux or macOS host with Docker installed.
- Source checkout of this repo.

## Build

```bash
# One-time: build the cross-compile image.
docker build -t 3sx-portmaster portmaster/

# Build + verify; produces dist/3sx.zip.
docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/build.sh --verify
```

The final zip is at `dist/3sx.zip`. Layout:

```
Street Fighter III 3rd Strike.sh
3sx/
  3sx                       (aarch64 binary)
  3sx.gptk                  (gptokeyb keymap — quit combo only)
  port.json
  gameinfo.xml
  README.md
  screenshot.png
  cover.png
  conf-defaults/config      (seeded into conf/ on first run)
  libs.aarch64/             (bundled SDL3 + FFmpeg .so)
  licenses/
```

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
```

- [ ] **Step 2: Verify the file is well-formed Markdown**

Run: `wc -l docs/portmaster.md`

Expected: ~70 lines.

- [ ] **Step 3: Commit**

```bash
git add docs/portmaster.md
git commit -m "Add PortMaster build + on-device test guide"
```

---

## Task 16: Final integration check

**Files:** none modified

- [ ] **Step 1: Clean rebuild from scratch in a throwaway worktree**

Run:
```bash
WT=$(mktemp -d)
git worktree add "$WT" HEAD
docker run --rm -v "$WT:/src" 3sx-portmaster /src/portmaster/build.sh --verify 2>&1 | tail -20
ls -la "$WT/dist/3sx.zip"
git worktree remove "$WT" --force
```

Expected: `All verification checks passed.` and `3sx.zip` exists in the throwaway worktree.

- [ ] **Step 2: Confirm desktop build is still healthy**

Run: `cmake -B build-verify -DCMAKE_BUILD_TYPE=Release && cmake --build build-verify --target 3sx -j$(nproc) 2>&1 | tail -10`

Expected: build succeeds. (Requires `build-deps.sh` to have been run.)

Run: `rm -rf build-verify`

- [ ] **Step 3: Sanity-check git log**

Run: `git log --oneline main..HEAD`

Expected: a sequence of focused commits (one per task), each describing a single concern.

- [ ] **Step 4: No pending uncommitted changes**

Run: `git status --short`

Expected: empty output (or only untracked files unrelated to this work, e.g. `.serena/`).

---

## Self-review (done before handoff)

**Spec coverage:**
- Bundle layout ........... Tasks 12, 13
- Default control mapping . Tasks 7, 12 (config + gptk)
- Build pipeline .......... Tasks 8, 9, 10, 11, 13
- Pinning ................. Task 10 (versions match build-deps.sh)
- `CMakeLists.txt` changes  Tasks 1, 3, 11
- `paths.c` change ........ Task 5
- `resources.c` changes ... Task 4
- `sdl_app.c` changes ..... Task 6
- Default config + keymap.. Task 12
- `sdk_libpad2.c` remap ... Task 7
- `docs/portmaster.md` .... Task 15
- Launcher script ......... Task 12
- port.json ............... Task 12
- Verification ............ Tasks 11, 14, 16

**Placeholder scan:** `TODO_porter_handle` is intentional and called out
in Task 12 step 5 and in `docs/portmaster.md`. The screenshot.png/cover.png
are 1-pixel-color placeholders, also called out for replacement before PR.
No "TBD"/"implement later"/"add appropriate error handling" anywhere.

**Type/name consistency:** `CRS_PLATFORM_PORTMASTER` (define) /
`PORTMASTER` (CMake option) / `3sx-portmaster` (Docker tag) are used
consistently across all tasks. Bundle dir is `3sx/` everywhere; launcher
filename is `Street Fighter III 3rd Strike.sh` everywhere.
