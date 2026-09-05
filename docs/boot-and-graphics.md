# Boot failure investigation — 2026-09-04

> **STATUS: RESOLVED.** Above 4G Decoding + Re-Size BAR were enabled in the BIOS
> on 2026-09-04. The BAR moved from 256 MB at `0xd0000000` to 16 GB at
> `0x7800000000`, `xe` reports no Small BAR, the PCODE mailbox errors cleared,
> SDDM starts on the first attempt and Plasma is hardware-accelerated.
> See [Resolution](#resolution) for the confirmed before/after.

## Symptom

Normal UEFI boot showed the Kubuntu logo, then a black screen with a blinking `_`.
The system appeared not to boot.

## Conclusion (short version)

**The boot chain was never broken.** GRUB, the EFI entry, `/etc/fstab`, the root
UUID and the initramfs were all correct, and every "failed" boot actually reached
a fully running userspace.

What failed was the **graphical session**: `kwin_wayland` could not drive the
Intel Arc B570, the Plasma session died ~5 s in, and SDDM then crash-looped
forever. The blinking `_` was that loop, not a stalled boot.

The Arc B570 fails because **Resizable BAR / Above 4G Decoding is disabled in the
BIOS**. That is the actual fix and it cannot be made from Linux.

## Evidence

### The "failed" boots used the correct command line

`journalctl` retains boots -6 through -1. Every one of them:

```
Kernel command line: BOOT_IMAGE=/boot/vmlinuz-7.0.0-30-generic \
  root=UUID=1e0539dd-c9b4-4222-9076-48a11c6154d9 ro quiet splash
```

Correct UUID, no `nomodeset`, and each boot reached systemd, logind, dbus,
PipeWire and SDDM. Root was mounted. This rules out every boot-config hypothesis:
stale UUID, wrong EFI entry, malformed GRUB config, missing initramfs driver.

### SDDM crash loop

Greeter restarts per boot: **377, 442, 284, 158, 258, 279**. Each iteration:

```
sddm: Using VT 1
sddm: Auth: sddm-helper (... --autologin) crashed (exit code 1)
sddm: Greeter stopped. SDDM::Auth::HELPER_TTY_ERROR
sddm-helper: Failed to take control of "/dev/tty1": Operation not permitted
```

### The real failure, in kwin

```
kwin_core: Failed to find a working output layer configuration! Enabled layers:
kwin_core:   src KWin::RectF(0,0 2560x1440) -> dst KWin::Rect(0,0 2560x1440)
kwin_wayland_drm: Atomic modeset test failed! Permission denied
kwin_core: Applying output configuration failed!
kwin_core: Failed to open /dev/dri/renderD128 device (No such device)
```

`xe` itself loaded fine — it found the GPU, loaded DMC/GuC/HuC firmware and
registered DRM. The compositor could not configure an output on it.

### Root cause: Small BAR

```
xe 0000:09:00.0: [drm] Attempting to resize bar from 256MiB -> 16384MiB
xe 0000:09:00.0: [drm] Can't resize VRAM BAR - platform support is missing.
                       Consider enabling 'Resizable BAR' support in your BIOS
xe 0000:09:00.0: [drm] Small BAR device
xe 0000:09:00.0: [drm] VRAM: 0x280000000 is larger than resource 0x10000000
xe 0000:09:00.0: [drm] *ERROR* PCODE Mailbox failed: -6 Illegal Command   (x15)
xe 0000:09:00.0: [drm] Failed to read power limits, check GPU firmware !
```

Only **256 MB of the card's 10 GB VRAM is CPU-accessible**. Confirmed by `lspci`:

```
Region 2: Memory at d0000000 (64-bit, prefetchable) [size=256M]
Capabilities: [420 v1] Physical Resizable BAR
        BAR 2: current size: 256MB, supported: 256MB 512MB 1GB 2GB 4GB 8GB 16GB
```

The card supports up to 16 GB. The BIOS is granting 256 MB. The BAR sits at
`0xd0000000` — **below 4 GB**, which is the signature of *Above 4G Decoding*
being disabled. Discrete Intel Arc is not reliably usable in this state.

### The control experiment

Booting with `nomodeset` bypasses `xe` entirely and falls back to `simpledrm`
software rendering. In that boot SDDM logged `Session started true` on the first
attempt, zero greeter restarts, and Plasma came up. Same disks, same GRUB, same
UUID — the only difference was whether the real GPU driver was used.

## The fix — BIOS  *(applied 2026-09-04)*

Reboot into UEFI setup (Del at POST) and set:

1. `Advanced → PCI Subsystem Settings → Above 4G Decoding` = **Enabled**
2. `Advanced → PCI Subsystem Settings → Re-Size BAR Support` = **Enabled**
   (only appears once Above 4G Decoding is on)
3. `Boot → CSM → Launch CSM` = **Disabled** (required; ReBAR will not engage with
   CSM on)

Verify afterwards:

```sh
sudo lspci -vv -s 09:00.0 | grep -A2 'Resizable BAR'   # current size should be 16GB
sudo dmesg | grep -i 'small bar'                       # should print nothing
```

## Resolution

Confirmed after the BIOS change:

| | Before (Small BAR) | After (ReBAR) |
|---|---|---|
| BAR 2 address | `0xd0000000` (3.5 GB, below 4 GB) | `0x7800000000` (480 GB, above 4 GB) |
| BAR 2 size | 256 MB | **16 GB** |
| CPU-accessible VRAM | `0x10000000` (256 MB) | `0x27bc00000` (~9.9 GB) |
| `Small BAR device` | logged | **absent** |
| `PCODE Mailbox failed` | ×15 | **absent** |
| `Failed to read power limits` | logged | **absent** |
| SDDM greeter restarts | 158–442 per boot | **0** |
| OpenGL | n/a (session died) | Mesa Intel Arc B570, direct rendering, 10172 MB |

The PCODE mailbox and power-limit errors turned out to be **downstream of Small
BAR, not stale card firmware** — they cleared with the BIOS change alone. No GPU
firmware update was needed.

### BIOS settings of record

These are part of this machine's reproducible configuration. They are not stored
on disk, so they must be re-applied after a CMOS clear or BIOS flash:

| Setting | Value |
|---|---|
| `Advanced → PCI Subsystem Settings → Above 4G Decoding` | Enabled |
| `Advanced → PCI Subsystem Settings → Re-Size BAR Support` | Enabled |
| `Boot → CSM → Launch CSM` | Disabled |

## Gotcha: manual GRUB boots with a typo'd root=

The recovery boot used `root=dev/nvme0n1p2` — missing the leading `/`. The kernel
still found root, but the *relative* path is recorded verbatim in
`/proc/self/mountinfo`, which breaks anything that canonicalizes the root device:

```
cryptsetup: ERROR: Couldn't resolve device dev/nvme0n1p2
grub-install: error: failed to get canonical path of `dev/nvme0n1p2'
```

Workaround while booted that way: run the tool with `cwd=/`, so `dev/nvme0n1p2`
resolves to `/dev/nvme0n1p2`. `scripts/boot/repair-boot.sh` does this unconditionally.
The same boot also had `system.unit=multi-user.target` — a typo for
`systemd.unit=`, so it was silently ignored and the machine booted to
`graphical.target` regardless.

## Changes made to the system on 2026-09-04

1. `/etc/default/grub`: `GRUB_TIMEOUT_STYLE=hidden` → `menu`, `GRUB_TIMEOUT=0` → `5`.
   The menu was previously invisible with a zero timeout, which is why a failing
   graphical target looked like a dead machine with no way in. Recovery mode
   (which carries `nomodeset`) is now always reachable.
2. Regenerated initramfs, reinstalled UEFI GRUB to the existing ESP, regenerated
   `grub.cfg`. All no-ops that confirmed the config was already correct.

No `nomodeset` was made permanent. `GRUB_CMDLINE_LINUX_DEFAULT` remains
`'quiet splash'`; `nomodeset` appears only in the stock recovery entry.

Backups of the pre-change state: `/root/boot-repair-backup-<timestamp>/`.

## Known-good reference state

```
/etc/fstab
  UUID=58B5-F976                            /boot/efi  vfat  defaults  0 2
  UUID=1e0539dd-c9b4-4222-9076-48a11c6154d9 /          ext4  defaults  0 1
  tmpfs                                     /tmp       tmpfs defaults,noatime,mode=1777 0 0

grub.cfg normal entry
  linux /boot/vmlinuz-7.0.0-30-generic \
    root=UUID=1e0539dd-c9b4-4222-9076-48a11c6154d9 ro quiet splash

efibootmgr
  BootOrder: 0003,...
  Boot0003* Kubuntu  HD(1,GPT,905e1ae0-5f9e-420a-8981-0daf2275ad36,...)/\EFI\ubuntu\shimx64.efi
```

## Follow-up: `grub-pc` is installed on a UEFI system

`grub-pc` and `grub-pc-bin` (BIOS GRUB) are installed alongside
`grub-efi-amd64-bin`/`-signed`. Nothing is broken today — `/boot/grub/i386-pc`
does not exist and the machine boots via shim — but a future GRUB or kernel
upgrade can run `grub-pc`'s postinst and prompt for, or attempt, a BIOS install.
Always pass `--target=x86_64-efi` to `grub-install` here. Cleaning this up
(`apt remove grub-pc grub-pc-bin`) is worth doing, but deliberately, not on the
same day as a boot repair.
