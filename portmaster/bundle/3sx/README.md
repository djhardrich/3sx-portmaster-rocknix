# 3sx — Street Fighter III: 3rd Strike (PortMaster build)

Native port of *Street Fighter III: 3rd Strike* targeting Anbernic H700
handhelds (RG35XX H, RG35XX SP, RG35XX 2024, RG28XX).

Thanks to the [CrowdedStreet team](https://github.com/crowded-street/3sx)
for the upstream port.

## Compatibility

| CFW       | Status       | Notes |
| --------- | ------------ | ----- |
| **Rocknix** | ✅ Supported | Tested on H700. Uses mainline kernel + panfrost DRM driver + Mesa. |
| **Knulli**  | ❌ Not currently supported | See "Knulli compatibility" section below. |

If you want this port on Knulli, the Knulli project would need to add
either a DRM subsystem (`/dev/dri/cardN` via panfrost) or SDL3 with a
native `mali_kbase`/fbdev video driver. Neither is feasible at the
port level — it requires changes in Knulli itself.

## Requirements

- Anbernic H700 device (aarch64) running **Rocknix** with PortMaster
  installed.
- A legally owned copy of *Street Fighter III: 3rd Strike* or *Street
  Fighter Anniversary Collection* for PlayStation 2.

## Installation

1. Install via PortMaster, **or** copy `3sx.sh` and the `3sx/` folder
   into `/roms/ports/`.
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
  with rolling fps and frame time averages. Anything below 58 fps
  in-match is worth reporting.
- **`./3sx: Permission denied`** — your filesystem (probably exFAT on
  the SD card) dropped the exec bit on unzip. The launcher re-applies
  it, but if you see this on a device where `chmod` isn't allowed,
  reformat to ext4 or run `chmod +x /roms/ports/3sx/3sx` manually.
- **`Couldn't initialize SDL: kmsdrm not available`** — SDL3 couldn't
  open a DRM node. The bundle ships `libdrm.so.2` and `libgbm.so.1` in
  `libs.aarch64/`, and the launcher adds `/usr/lib`, `/usr/lib64`, and
  `/usr/lib/aarch64-linux-gnu` to `LD_LIBRARY_PATH`. If the error
  persists on Rocknix, run `ls -la /dev/dri/` — you should see at
  least a `card0` there.
- **EGL / GPU rendering glitches** — our bundled `libdrm`/`libgbm`
  may conflict with the device's Mesa/Panfrost GPU driver if their
  versions drift. As a fallback, delete `libdrm.so*` and `libgbm.so*`
  from `libs.aarch64/` to force the launcher to use the device's
  copies.

## Knulli compatibility (why it doesn't work)

Knulli's current H700 image ships with a pre-DRM GPU stack:

- **No `/dev/dri/` at all** — the DRM subsystem is not exposed.
- **Kernel 4.9 + `mali_kbase` module only** — the GPU is driven by ARM's
  legacy Mali kbase driver (vendor blob, `/dev/mali0`), NOT the mainline
  `panfrost` DRM driver.
- **No `libdrm.so.2`, `libgbm.so.1`, or `libseat.so.*` on disk** — Knulli
  doesn't ship a DRM userland because there's no DRM to talk to.
- **Display goes through Allwinner's proprietary framebuffer driver**,
  with SDL2 being the only supported graphics toolkit.

SDL3 upstream supports three video drivers on Linux: `kmsdrm`,
`wayland`, and `x11`. Knulli H700 provides none of them. Even with our
bundled `libdrm`/`libgbm` and explicit `LD_LIBRARY_PATH` tuning, SDL3's
`open("/dev/dri/card0")` fails because the device simply doesn't exist.

**For Knulli devs**: supporting this port (or any SDL3 port) on H700
requires one of:
1. Enable the mainline `panfrost` DRM driver in Knulli's kernel
   (requires kernel 5.x; kernel 4.9 is too old for mature panfrost).
2. Patch SDL3 to add a `mali_kbase` or fbdev video driver.
3. Ship a pre-DRM compatibility shim that exposes `/dev/dri/card0` on
   top of the Allwinner fb + `mali_kbase` stack.

None of these are achievable in the PortMaster packaging layer.

## Rebuilding the bundle from source

The bundle is produced by a Docker-based cross-compile pipeline in the
upstream repo. From a checkout of `crowded-street/3sx`:

```bash
# One-time: build the cross-compile image (~3-5 min).
docker build -t 3sx-portmaster portmaster/

# Build + verify; produces dist/3sx.zip (~10-20 min on first run).
docker run --rm -v "$PWD:/src" 3sx-portmaster /src/portmaster/build.sh --verify
```

See `docs/portmaster.md` in the upstream repo for full build
instructions and the on-device test checklist.

## Credits

- Game: Capcom
- Port: CrowdedStreet (3sx)
- PortMaster packaging: TODO_porter_handle

See `licenses/` for third-party software notices.
