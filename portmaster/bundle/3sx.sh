#!/bin/bash
# PortMaster launcher for 3sx (Street Fighter III: 3rd Strike).
# Targets Anbernic H700 handhelds running Rocknix (panfrost DRM).
# See README.md and docs/portmaster.md for the Knulli compatibility
# status — Knulli is NOT currently supported.

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

# Some filesystems (exFAT, FAT32) strip the exec bit on unzip. Make sure
# the binary can be executed before we try.
chmod +x "$GAMEDIR/3sx" 2>/dev/null || true

# Library search path, most-specific first:
#   1. our bundled libs.aarch64 (SDL3 + FFmpeg + libdrm/libgbm fallbacks)
#   2. /usr/lib — Rocknix location for libdrm/libgbm/libEGL/libSDL2
#   3. /usr/lib64 — some CFWs use the 64-suffix path instead
#   4. /usr/lib/aarch64-linux-gnu — Debian-multiarch layout
#   5. previously-set LD_LIBRARY_PATH (PortMaster / CFW env)
DEVICE_ARCH="${DEVICE_ARCH:-aarch64}"
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:/usr/lib:/usr/lib64:/usr/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH"

export XDG_DATA_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Video: prefer Wayland when a compositor is active (e.g. PanicOS/sway);
# fall back to KMSDRM on bare-metal CFWs (e.g. ROCKNIX) where WAYLAND_DISPLAY
# is unset.
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-kmsdrm}"
[[ -n "${WAYLAND_DISPLAY}" && "${SDL_VIDEODRIVER}" == "kmsdrm" ]] && export SDL_VIDEODRIVER=wayland

# Audio: bundled SDL3 supports alsa/pulse/dummy/disk — no pipewire driver.
# Map pipewire → pulse so SDL3 routes through the pipewire-pulse socket at
# $XDG_RUNTIME_DIR/pulse/native, which is active on PanicOS.
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
[[ "${SDL_AUDIODRIVER}" == "pipewire" ]] && export SDL_AUDIODRIVER=pulse

# Don't require KMSDRM master if the frontend hasn't released it yet.
export SDL_KMSDRM_REQUIRE_DRM_MASTER="${SDL_KMSDRM_REQUIRE_DRM_MASTER:-0}"

# gptokeyb only handles the start+select quit combo; the game reads the
# gamepad through SDL directly.
$GPTOKEYB "3sx" -c "./3sx.gptk" &
pm_platform_helper "$GAMEDIR/3sx"
./3sx
pm_finish
