# Handoff: installing Kubuntu and finishing the setup

The automated-installer route was abandoned on 2026-09-04 after a run of Windows-side failures (a flash
controller that refused writes, raw sector writes denied, filenames mangled by Windows' 8.3 view, and a
disk serial Windows reported one character differently from Linux). The reliable path is a normal Kubuntu
install from a Ventoy stick, then the setup repo does everything else from inside Linux.

This file lives at `https://github.com/aleponce4/linux-setup/blob/main/HANDOFF.md` and on the rescue drive.

| | |
|---|---|
| Login | `alexponce` (lowercase) |
| Hostname | `strix` |
| Root disk | **NVMe Samsung 990 PRO**, Btrfs, no encryption. Windows is erased |
| Data disk | SATA SSD 860 EVO becomes `/data` |
| Backups | 8 TB HDD: `WINRESCUE` (NTFS, your data) + free space for `/backup` |
| Setup repo | `https://github.com/aleponce4/linux-setup` |

---

## 1. Install Kubuntu

Boot the Ventoy stick (F8 at the ASUS logo, pick the UEFI USB entry), choose
`kubuntu-26.04.1-desktop-amd64.iso`, then "Try or Install Kubuntu".

| Screen | Answer |
|---|---|
| Language | English |
| Location | America/Chicago |
| Keyboard | English (US) |
| Installation type | **Erase disk** |
| Target device | **Samsung SSD 990 PRO 1TB** (the NVMe). Do **not** pick the 860 EVO or the 8 TB HGST |
| Filesystem | **btrfs** |
| Swap | No swap |
| Encryption | unchecked |
| Name / login / computer | `Alex Ponce` / **`alexponce`** / **`strix`** |
| Log in automatically | yes |

The username and hostname matter: the setup repo, the SSH config and the scripts all reference them.
Btrfs matters because the snapshot and rollback design depends on it, and Calamares creates the `@` and
`@home` subvolumes that Timeshift's Btrfs mode needs.

**Leave the other two disks alone.** The 8 TB drive holds the only copy of some of your data.

---

## 2. Hand back to the agent

After first boot, open a terminal (Ctrl+Alt+T) and run:

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
up `/data`, snapshots and backups.

Storage note: with `AUTO_FORMAT="yes"` the storage module formats the **SATA SSD** as `/data` and claims
the HDD's free space for `/backup`. It will **not** touch `WINRESCUE`, and it refuses to format the disk
holding the running root. The SSD currently holds only `E:\Linux_migration`, which is mirrored to the
rescue drive and to GitHub, so losing it costs nothing.

---

## 3. Restore your secrets and data

The rescue drive auto-mounts read-only at `/mnt/winrescue`.

```bash
cd ~/linux-setup
./bootstrap.sh 22        # SSH key, agent tokens, all your Wi-Fi networks
```

It asks for the passphrase you saved. It is also at `/mnt/winrescue/secrets-passphrase.txt`.

```bash
rsync -avh --info=progress2 /mnt/winrescue/data/LIBS_Data/ /data/libs/
rsync -avh --info=progress2 /mnt/winrescue/data/Desktop/Onteko/ /data/onteko/
rsync -avh --info=progress2 /mnt/winrescue/data/Documents/Seed_LIBS_Classification/ /data/seed/Seed_LIBS_Classification/
rsync -avh /mnt/winrescue/data/Documents/ ~/Documents/ --exclude Seed_LIBS_Classification
rsync -avh /mnt/winrescue/data/Pictures/  ~/Pictures/
rsync -avh /mnt/winrescue/data/dotfiles/.claude/projects/ ~/.claude/projects/
rsync -avh /mnt/winrescue/usb-stick-backup/ /data/libs/ball-horticulture/
```

Everything in `data/` was verified by SHA-256 against the originals: 122,649 files, zero mismatches. The
old WSL is preserved whole at `/mnt/winrescue/wsl/ubuntu-2404.tar` if you need anything from it.

Then the browser logins: `sudo tailscale up --ssh`, `gh auth login`, `codex login`, `agy`, Chrome, Zoom.

Verify the result with `./bootstrap.sh 90`, which prints a pass/fail table of every component.

---

## 4. Housekeeping

- **Revoke the Tailscale auth key** at login.tailscale.com. It sat in plain text on the USB stick.
- **Change the account password** (`passwd`) — it passed through a chat log.
- Delete leftover tailnet nodes: `strix-installer`, `keycheck-throwaway`.
- Delete `/mnt/winrescue/secrets-passphrase.txt` once it is in your password manager.
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
- **No network after install** — the Ethernet port only works in one of the two wall sockets; the other
  has no DHCP server. Wi-Fi is `C Spire 9924`, WPA3, and module 22 restores the saved credentials.
- **Wrong disk was erased** — stop, do not write anything further, and restore from `/mnt/winrescue`.

---

## 7. What is already true

- Data copied and hash-verified: 122,649 files, 47.55 GB, zero mismatches.
- Windows cleaned before the wipe: Steam, games, media-server stack, Docker and WSL removed (C: fell from
  495 GB to 255 GB). No Windows system image was taken; you chose to skip it.
- Rescue drive: 2 TB NTFS `WINRESCUE` with your data, WSL export, secrets archive, ISOs and this plan.
  About 5.5 TB left unallocated for `/backup`.
- The setup repo is complete and pushed: 14 modules, package lists, dotfiles, the KRunner agent plugin,
  the design system, and the machine guide that a fresh agent reads on first run.
