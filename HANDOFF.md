# Handoff: finishing the migration without this chat session

This session runs on the Windows install and disappears when the machine reboots into the installer.
Everything you need afterwards is here. This file also lives at `/mnt/winrescue/Linux_migration/HANDOFF.md`
on the new system, and the setup repo is public at `https://github.com/aleponce4/linux-setup`.

Machine facts you will need:

| | |
|---|---|
| Login | `alexponce` (lowercase; the installer rejects capitals) |
| Password | the one you chose earlier. **Change it after first login**, it passed through a chat log |
| Hostname | `strix` |
| SSH key | your existing `id_ed25519` is already authorised, password login also works |
| Root disk | NVMe, Btrfs, no encryption |
| Setup repo | `https://github.com/aleponce4/linux-setup` |

---

## 1. Getting in

The machine joins your tailnet by itself. Two names appear, in order:

- **`strix-installer`** — the live installer, during the install. Appears within a few minutes of the reboot.
- **`strix`** — the installed system. Appears after it reboots, and stays.

```bash
ssh alexponce@strix
```

Tailscale SSH is enabled, so from a device on your tailnet this works without key juggling. `mosh strix`
also works once the desktop stack is in, and survives flaky links better.

If neither name shows up after about 25 minutes, jump to section 5.

---

## 2. What runs on its own

You should not have to do anything for this. Sequence after the reboot:

1. The stick boots and the installer runs unattended, no prompts.
2. Before touching any disk it brings up Tailscale, so a stall is still reachable.
3. It checks the NVMe is present and between 900 GB and 1.1 TB, and **aborts rather than guessing** if not.
4. It wipes the NVMe, installs Ubuntu Server with a Btrfs root and a 1 GB EFI partition, and reboots.
5. On first boot a one-shot service rejoins the tailnet and runs `bootstrap.sh`, which installs the
   Kubuntu desktop and everything else. **60 to 90 minutes of downloads.**

Watch it:

```bash
ssh alexponce@strix 'sudo tail -f /var/log/firstboot-setup.log'
```

The 8 TB rescue drive and the 500 GB SATA SSD are never touched by the installer.

---

## 3. First things to do once you are in

**Restore your secrets** (SSH key, agent tokens, all your Wi-Fi networks). The passphrase is the one you
saved; it is also at `/mnt/winrescue/secrets-passphrase.txt`.

```bash
cd ~/linux-setup
./bootstrap.sh 22          # prompts once for the passphrase
```

**Check the machine came out right.** This prints a pass/fail table of every component:

```bash
cd ~/linux-setup && ./bootstrap.sh 90
```

**Restore your data** from the rescue drive, which auto-mounts read-only:

```bash
ls /mnt/winrescue/data      # Desktop Documents LIBS_Data Pictures Downloads Akodon_repo dotfiles
rsync -avh --info=progress2 /mnt/winrescue/data/LIBS_Data/ /data/libs/
rsync -avh --info=progress2 /mnt/winrescue/data/Desktop/Onteko/ /data/onteko/
rsync -avh --info=progress2 /mnt/winrescue/data/Documents/Seed_LIBS_Classification/ /data/seed/Seed_LIBS_Classification/
rsync -avh /mnt/winrescue/data/Documents/ ~/Documents/ --exclude Seed_LIBS_Classification
rsync -avh /mnt/winrescue/data/Pictures/  ~/Pictures/
rsync -avh /mnt/winrescue/data/dotfiles/.claude/projects/ ~/.claude/projects/   # per-project agent memory
rsync -avh /mnt/winrescue/usb-stick-backup/ /data/libs/ball-horticulture/       # the LIBS spectra off the old stick
```

**Log in to the things that need a browser:**

```bash
sudo tailscale up --ssh --accept-dns   # if it needs re-auth
gh auth login
claude                                  # then follow the login
codex login
agy                                     # Antigravity
```

**Get an agent working on the machine.** `claude` is installed and `~/.claude/CLAUDE.md` already describes
this machine's layout, conventions and rules, so a fresh agent knows where things live and how to change
them reproducibly. Point it at `~/linux-setup` for anything system-level.

---

## 4. Housekeeping, do not skip

- **Revoke the Tailscale auth key** at login.tailscale.com > Settings > Keys. It is embedded in the USB
  stick and sits on the rescue drive, so it should not stay valid.
- **Change the account password** (`passwd`).
- **Delete leftover tailnet nodes**: `strix-installer` after the install finishes, and `keycheck-throwaway`
  if it is still listed.
- **Wipe the USB stick** when done; it carries the auth key and your password hash.
- Delete `/mnt/winrescue/secrets-passphrase.txt` once the passphrase is in your password manager.

---

## 5. If it does not come back

**Nothing is lost in any of these cases.** Your data is on the 8 TB drive, hash-verified (122,649 files,
zero mismatches), and the plan and scripts are on that drive and on GitHub.

**Case A: neither name appears on the tailnet within 25 minutes.**
Most likely the firmware ignored the boot entry again and the machine is sitting in Windows, exactly as it
did on the first attempt. Try Chrome Remote Desktop. If Windows is up, the fix is to press **F8** at the
ASUS logo when you are physically there and pick the USB entry; the stick is already built and correct.

**Case B: `strix-installer` appears but `strix` never does.**
The install stalled. You can get into the live installer:

```bash
ssh root@strix-installer
tail -f /var/log/installer/subiquity-server-debug.log
```

**Case C: `strix` appears but the desktop never arrives.**
The install worked and the bootstrap failed. You have a working machine with SSH; nothing is broken.

```bash
ssh alexponce@strix
sudo tail -100 /var/log/firstboot-setup.log
cd ~/linux-setup && ./bootstrap.sh        # re-run; it is idempotent
./bootstrap.sh 30                          # or just the desktop module
```

**Case D: you want Windows back.**
The Windows system image was skipped at your request, so there is no one-click restore. You would
reinstall Windows and pull your files from `/mnt/winrescue/data`. The old WSL is preserved as a tarball at
`/mnt/winrescue/wsl/ubuntu-2404.tar`.

---

## 6. How the setup repo works

`~/linux-setup` **is** the machine's configuration. Do not hand-install things outside it, or a rebuild
will not reproduce what you have.

```
./bootstrap.sh          # run everything; safe to re-run, skips what is done
./bootstrap.sh 40 50    # run only those modules
./bootstrap.sh --list   # list modules
```

| Module | What it does |
|---|---|
| 00 | preflight, hostname, timezone, full upgrade |
| 10 | core CLI tools, fonts, shell |
| 20 | Btrfs subvolumes, snapshots, `/data` on the SSD, `/backup` on the HDD |
| 22 | restore the secrets archive |
| 25 | Intel Arc drivers, VA-API, compute runtime |
| 30 | Kubuntu desktop, look and feel, panel, KRunner agent plugin |
| 40 | VS Code, Docker, Apptainer, Node, uv, micromamba, the AI agent CLIs |
| 50 | R with r2u binaries, RStudio, Positron, Quarto, science packages |
| 60 | Tailscale, hardened SSH, firewall, Wake-on-LAN |
| 70 | dotfiles, git identity, the agent machine guide |
| 80 | conda envs, clone your repos, distroboxes |
| 85 | restic backups to the HDD |
| 90 | verify everything |

To add software: edit the matching file in `lists/`, then re-run that module. Commit the change.

---

## 7. Your repos

Four repos had diverged between this machine and GitHub. Their full local history was pushed to a branch
called **`pre-migration-2026-09-02`** on each: `Baby_weight`, `Bell_Seed_project_repo`,
`lab-bioinfo-templates`, `family-life-plan`. Clone the normal branch and merge or cherry-pick from that one
when convenient. Module 80 clones everything into `~/work`.

---

## 8. Known rough edges

- **Wi-Fi is not configured in the installer**, deliberately: a malformed wireless block can break netplan
  and take working Ethernet down with it. Add Wi-Fi from the desktop, or module 22 imports your saved
  networks from the secrets archive.
- **Snapshots use snapper, not Timeshift.** The automated installer creates a plain Btrfs root without the
  `@`/`@home` subvolume layout Timeshift's Btrfs mode needs.
- **The Ethernet port only works in one particular wall socket.** The other one it was in had no DHCP
  server. If networking is dead, check the cable is in the port that worked.
- The desktop design rules are in `~/linux-setup/docs/design-system.md`: one font pair, one icon set, one
  panel, no stacking themes. Worth reading before letting an agent restyle anything.
