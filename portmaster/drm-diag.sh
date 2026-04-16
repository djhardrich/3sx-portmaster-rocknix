#!/bin/bash
# 3sx KMSDRM diagnostic for Knulli H700.
#
# Install: copy this file to /roms/ports/ on the device. Launch from the
# Ports menu. Collects output in /roms/ports/3sx-drm-diag.log and exits.
# Send the log back to the developer.

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

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

LOG="/$directory/ports/3sx-drm-diag.log"
> "$LOG"
exec > >(tee "$LOG") 2>&1

h() { echo; echo "=== $* ==="; }

h "env"
echo "CFW_NAME=$CFW_NAME  DEVICE_NAME=${DEVICE_NAME:-?}  DEVICE_ARCH=$DEVICE_ARCH"
echo "uid/gid: $(id -u):$(id -g)   groups: $(id -Gn 2>/dev/null)"
echo "kernel: $(uname -a)"

h "DRM nodes"
ls -la /dev/dri/ 2>&1
echo
for f in /dev/dri/card* /dev/dri/renderD* ; do
    [ -e "$f" ] || continue
    echo "-- $f --"
    ls -la "$f"
    stat -c 'major=%t minor=%T' "$f" 2>/dev/null
done

h "DRM /sys info"
for c in /sys/class/drm/card*; do
    [ -e "$c" ] || continue
    echo "-- $c --"
    cat "$c/device/uevent" 2>&1 | head -20
    echo "status: $(cat $c/status 2>/dev/null)"
done

h "Loaded modules (drm/gpu/panfrost/mali)"
lsmod 2>&1 | grep -iE 'drm|panfrost|mali|display|mediatek|rockchip|allwinner|sun|lima' || cat /proc/modules | grep -iE 'drm|panfrost|mali' || echo "(no module info)"

h "libs on device (libdrm / libgbm / libseat / libSDL)"
for lib in libdrm.so.2 libgbm.so.1 libseat.so libSDL2-2.0.so.0 libSDL3.so.0; do
    found=$(find / -xdev -name "$lib" 2>/dev/null)
    echo "$lib: ${found:-NOT FOUND}"
done

h "ldconfig cache"
ldconfig -p 2>&1 | grep -iE 'libdrm|libgbm|libseat|libSDL' | head -20 || echo "(no ldconfig)"

h "seatd / libseat state"
which seatd 2>&1
ls -la /run/seatd.sock /var/run/seatd.sock /tmp/seatd.sock 2>&1 | grep -v "No such" || echo "(no seatd socket)"
pgrep -a seatd 2>&1 || echo "(no seatd process)"

h "Who (if anyone) holds DRM fds right now"
for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    if ls -la /proc/$pid/fd 2>/dev/null | grep -q "/dev/dri/"; then
        echo "pid=$pid comm=$(cat /proc/$pid/comm 2>/dev/null)"
        ls -la /proc/$pid/fd 2>/dev/null | grep "/dev/dri/"
    fi
done

h "Currently running user-space"
ps -ef 2>&1 | grep -iE 'emulat|weston|xorg|wayland|seatd|gptokeyb' | grep -v grep

h "Try opening /dev/dri/card0 various ways"

# 1) Shell: read-write via fd
echo "-- test A: sh 'exec 3<>/dev/dri/card0' (read+write) --"
( exec 3<>/dev/dri/card0 ) 2>&1
echo "exit=$?"

# 2) Shell: read-only
echo "-- test B: sh 'exec 3</dev/dri/card0' (read-only) --"
( exec 3</dev/dri/card0 ) 2>&1
echo "exit=$?"

# 3) dd: actually forces kernel open path
echo "-- test C: dd if=/dev/dri/card0 bs=1 count=0 --"
dd if=/dev/dri/card0 bs=1 count=0 2>&1
echo "exit=$?"

# 4) python open (if available)
if command -v python3 >/dev/null 2>&1; then
    echo "-- test D: python3 os.open(O_RDWR) --"
    python3 -c '
import os, errno
try:
    fd = os.open("/dev/dri/card0", os.O_RDWR | os.O_CLOEXEC)
    print("OPENED fd=%d" % fd)
    os.close(fd)
except OSError as e:
    print("FAIL errno=%d (%s): %s" % (e.errno, errno.errorcode.get(e.errno, "?"), e.strerror))
' 2>&1
fi

# 5) strace a minimal open (if available)
if command -v strace >/dev/null 2>&1; then
    echo "-- test E: strace of 'true' forking child opening card0 --"
    strace -f -e trace=openat,open sh -c 'exec 3<>/dev/dri/card0' 2>&1 | tail -15
fi

h "kernel dmesg tail (grep drm|panfrost|mali)"
dmesg 2>/dev/null | tail -100 | grep -iE 'drm|panfrost|mali|display|hdmi|error|fail' | tail -40

h "pm_platform_helper behavior check"
echo "pm_platform_helper path: $(command -v pm_platform_helper)"
type pm_platform_helper 2>&1 | head -20

h "Environment from control.txt"
env | grep -E '^(DEVICE_|CFW_|PM_|weston_|controlfolder|directory|GPTOKEYB)' | sort

echo
echo "=== done ==="
echo "Log written to $LOG"
sleep 5

pm_finish
