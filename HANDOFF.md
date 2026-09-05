# Handoff: the current Kubuntu install and finishing the setup

The automated-installer route was abandoned on 2026-09-04 after a run of Windows-side failures (a flash
controller that refused writes, raw sector writes denied, filenames mangled by Windows' 8.3 view, and a
disk serial Windows reported one character differently from Linux). The reliable path is a normal Kubuntu
install from a Ventoy stick, then the setup repo does everything else from inside Linux.

That stock installation is now complete. Its root filesystem is ext4; reinstalling merely to convert it to
Btrfs is unnecessary. The provisioning repo detects the root filesystem and supports this ext4 system as a
first-class configuration.

This file lives at `https://github.com/aleponce4/linux-setup/blob/main/HANDOFF.md` and on the rescue drive.

| | |
|---|---|
| Login | `alexponce` (lowercase) |
| Hostname | `strix` |
| Root disk | **Samsung 990 PRO 1 TB NVMe**, `/dev/nvme0n1p2`, ext4, UUID `1e0539dd-c9b4-4222-9076-48a11c6154d9` |
| Data disk | Samsung 860 EVO 500 GB SATA SSD, mounted separately at `/data` when configured |
| Rescue/backups | 8 TB HGST HDD: `WINRESCUE` plus the separately mounted `/backup` area when configured |
| Setup repo | `https://github.com/aleponce4/linux-setup` |

---

## 1. Current installation

The machine currently runs the stock Kubuntu 26.04 installation. These read-only checks describe the root
that the repo expects:

```bash
findmnt -no SOURCE,FSTYPE,UUID /
lsblk -o NAME,MODEL,SERIAL,SIZE,FSTYPE,MOUNTPOINTS
```

The expected root is `/dev/nvme0n1p2`, ext4, UUID `1e0539dd-c9b4-4222-9076-48a11c6154d9`, on the Samsung
990 PRO. The Samsung 860 and HGST disks must never appear as `/`.

Btrfs remains an optional layout for a future, deliberate reinstall. On Btrfs, module 20 may additionally
configure the existing Timeshift, `grub-btrfs`, and `btrbk` workflow. The repo has never used Snapper.

**Leave the other two disks alone. Do not format or repartition them.** The 8 TB drive holds the only copy
of some of your data.

---

## Required BIOS settings (NOT stored on disk — re-apply after any CMOS clear or BIOS flash)

Without these the machine boots to a black screen: the Arc B570 runs in "Small BAR" mode
and `kwin_wayland` cannot bring up a display. Diagnosis: `docs/boot-and-graphics.md`.

| Setting | Value | Why |
|---|---|---|
| `Advanced > PCI Subsystem Settings > Above 4G Decoding` | Enabled | Lets the 16 GB GPU BAR live above the 4 GB line |
| `Advanced > PCI Subsystem Settings > Re-Size BAR Support` | Enabled | Intel Arc requires ReBAR |
| `Boot > CSM > Launch CSM` | Disabled | ASUS gates ReBAR behind this |
| `Advanced > APM > Power On By PCI-E` | Enabled | Wake-on-LAN (module 60) |
| `Advanced > APM > ErP Ready` | Disabled | Would cut power to the NIC and break WoL |

Verify: `sudo scripts/boot/verify-boot.sh` (check 9), or
`sudo lspci -vv -s 09:00.0 | grep -A2 'Resizable BAR'` should say `current size: 16GB`.

---

## 2. Hand back to the agent

From the working desktop, open a terminal (Ctrl+Alt+T) and run:

```bash
sudo apt update && sudo apt install -y curl git
curl -fsSL https://claude.ai/install.sh | bash
claude
```

Log in, then tell it: *"Continue the Linux migration. The plan and scripts are at
https://github.com/aleponce4/linux-setup and on the rescue drive. Read HANDOFF.md and the repo README,
then run the bootstrap."*

Or just run it yourself:

```bash
git clone https://github.com/aleponce4/linux-setup ~/linux-setup
cd ~/linux-setup
cp config.env.example config.env
./bootstrap.sh
```

That takes 60 to 90 minutes, mostly downloads. It installs the desktop tooling, dev stack, R and the
science stack, the AI agent CLIs, Docker and Apptainer, Tailscale and the hardened SSH setup, and it sets
up the existing `/data` and `/backup` mounts plus restic backups. Because the current root is ext4, it does
not configure root snapshots.

Storage note: a normal bootstrap run is non-destructive. It must not format or repartition the Samsung 860
or HGST disks. The `--format` path is only for a future blank replacement disk, requires explicit runtime
opt-in, displays the exact resolved target and requires an exact typed confirmation. It is not part of the
current-machine flow. See [docs/storage.md](docs/storage.md).

---

## 3. Restore your secrets and data

The rescue drive auto-mounts read-only at `/mnt/winrescue`.

Before restoring anything, verify that `/data` is a real mount from the Samsung 860 rather than an ordinary
directory on the root filesystem:

```bash
mountpoint -q /data && findmnt /data
lsblk -o NAME,MODEL,SERIAL,SIZE,FSTYPE,MOUNTPOINTS
```

Stop if `/data` is not mounted from the expected SATA SSD.

```bash
cd ~/linux-setup
./bootstrap.sh 22        # SSH key, agent tokens, all your Wi-Fi networks
```

It asks for the passphrase you saved. It is also at `/mnt/winrescue/WINRESCUE/secrets-passphrase.txt`.

```bash
rsync -avh --info=progress2 /mnt/winrescue/WINRESCUE/data/LIBS_Data/ /data/libs/
rsync -avh --info=progress2 /mnt/winrescue/WINRESCUE/data/Desktop/Onteko/ /data/onteko/
rsync -avh --info=progress2 /mnt/winrescue/WINRESCUE/data/Documents/Seed_LIBS_Classification/ /data/seed/Seed_LIBS_Classification/
rsync -avh /mnt/winrescue/WINRESCUE/data/Documents/ ~/Documents/ --exclude Seed_LIBS_Classification
rsync -avh /mnt/winrescue/WINRESCUE/data/Pictures/  ~/Pictures/
rsync -avh /mnt/winrescue/WINRESCUE/data/dotfiles/.claude/projects/ ~/.claude/projects/
rsync -avh /mnt/winrescue/WINRESCUE/usb-stick-backup/ /data/libs/ball-horticulture/
```

Everything in `data/` was verified by SHA-256 against the originals: 122,649 files, zero mismatches. The
old WSL is preserved whole at `/mnt/winrescue/WINRESCUE/wsl/ubuntu-2404.tar` if you need anything from it.

Then the browser logins: `sudo tailscale up --ssh`, `gh auth login`, `codex login`, `agy`, Chrome, Zoom.

Verify the result with `./bootstrap.sh 90`, which prints a pass/fail table of every component.

Only after the base setup passes, inspect the separate productivity phase. It is never run by the bootstrap,
has no install-all action, and does not touch storage:

```bash
./productivity.sh list
./productivity.sh doctor
./productivity.sh install handlers --dry-run
```

Opt into `handlers`, `dictation`, `research`, or `kando` one at a time. The printable learning guide is
[`output/pdf/strix-productivity-cheatsheet.pdf`](output/pdf/strix-productivity-cheatsheet.pdf).

---

## 4. Housekeeping

- **Revoke the Tailscale auth key** at login.tailscale.com. It sat in plain text on the USB stick.
- **Change the account password** (`passwd`) — it passed through a chat log.
- Delete leftover tailnet nodes: `strix-installer`, `keycheck-throwaway`.
- Delete `/mnt/winrescue/WINRESCUE/secrets-passphrase.txt` once it is in your password manager.
- Reclaim the USB stick.

---

## 5. Your repos

Four repos had diverged between the Windows machine and GitHub. Their full local history was pushed to a
branch **`pre-migration-2026-09-02`** on each: `Baby_weight`, `Bell_Seed_project_repo`,
`lab-bioinfo-templates`, `family-life-plan`. Clone the normal branch and merge from that one when
convenient. Module 80 clones everything into `~/work`.

---

## 6. If something goes wrong

Nothing here is fatal. Your data is on the 8 TB drive, hash-verified, and this repo is on GitHub.

- **Installer won't boot the stick** — F8 at the ASUS logo and pick the UEFI USB entry by hand. The stick
  is Ventoy with the stock SHA256-verified ISO.
- **Bootstrap fails partway** — it is idempotent. Re-run `./bootstrap.sh`, or a single module such as
  `./bootstrap.sh 50`. Logs are in `~/linux-setup/logs/`.
- **A system change must be undone on ext4** — use a verified restic backup. For complete root loss,
  reinstall Kubuntu on the Samsung 990 PRO only, rerun the bootstrap, then restore the needed files.
- **A future Btrfs install must be rolled back** — Timeshift/GRUB snapshots may be used in addition to
  restic, when that optional snapshot stack was enabled. Snapshots never replace backups.
- **No network after install** — the Ethernet port only works in one of the two wall sockets; the other
  has no DHCP server. Wi-Fi is `C Spire 9924`, WPA3, and module 22 restores the saved credentials.
- **Wrong disk was erased** — stop, do not write anything further, and restore from `/mnt/winrescue`.

---

## 7. What is already true

- Data copied and hash-verified: 122,649 files, 47.55 GB, zero mismatches.
- Windows cleaned before the wipe: Steam, games, media-server stack, Docker and WSL removed (C: fell from
  495 GB to 255 GB). No Windows system image was taken; you chose to skip it.
- Rescue drive: 2 TB NTFS `WINRESCUE` with your data, WSL export, secrets archive, ISOs and this plan.
  Any separate `/backup` filesystem must be positively identified and mounted before use.
- The setup repo is complete and pushed: 14 modules, package lists, dotfiles, the KRunner agent plugin,
  the design system, and the machine guide that a fresh agent reads on first run.
