---
name: linux-setup
description: Changing anything installed or configured on strix - packages, dotfiles, KDE settings, /etc files, systemd units. Use whenever a task would install software or edit configuration outside a project directory.
---

# Changing this machine

`~/linux-setup` is the source of truth. A reinstall must reproduce the machine, so a change
that exists only in `$HOME` is a bug even when it works.

## The rule

Never hand-install. Append to the list, then run the module:

| Change | Edit | Then run |
|---|---|---|
| apt package | `lists/apt-{base,desktop,dev,science,llm}.txt` | `./bootstrap.sh <NN>` |
| Flatpak | `lists/flatpaks.txt` | `./bootstrap.sh 30` |
| npm global | `lists/npm-globals.txt` | `./bootstrap.sh 40` |
| uv tool | `lists/python-uv-tools.txt` | `./bootstrap.sh 40` |
| R package | `lists/r-packages-*.txt` | `./bootstrap.sh 50` |
| dotfile / KDE | `dotfiles/...` | `./bootstrap.sh 70` (or `30` for Plasma) |
| `/etc` file | a module using `write_file_sudo` | that module |

Modules: 00 preflight, 10 base-cli, 20 storage, 22 secrets, 25 gpu-intel, 30 desktop-kde,
40 dev-tools, 45 local-llm, 46 agent-mcp, 50 science, 60 remote, 70 dotfiles, 80 envs,
85 backup-restic, 90 verify.

Commit every change with a clear message. `./bootstrap.sh 90` verifies; it should read
`59 passed, 0 failed`.

## sudo is granted per command, not blanket

`/etc/sudoers.d/90-agent-admin` allows **only**: apt-get, apt, dpkg, flatpak, snap, systemctl,
journalctl, timeshift, btrbk, tailscale, ufw, fwupdmgr, apptainer, update-grub, udevadm.

Everything else prompts, including `sudo true`, `sudo cmp`, `sudo install`, `sudo tee`,
`sudo restic`, `sudo sshd -T`. Consequences that have already caused real failures:

- **Do not probe with `sudo -n true`** - it fails here. Probe the capability you need,
  e.g. `sudo -n apt-get --version`.
- **Do not set env vars on the sudo line** (`sudo DEBIAN_FRONTEND=... apt-get`). Without
  SETENV sudo refuses outright. `lib/common.sh` probes and adapts.
- **Never let a no-change fast path spend sudo.** `write_file_sudo` compared with `sudo cmp`
  and `add_apt_repo` ran `sudo install` unconditionally; both prompted on runs where nothing
  needed doing, which fails unattended runs.
- A check that cannot authenticate should report **SKIP, not FAIL** (see `check_sudo` in
  `90-verify.sh`). Reporting a healthy backup as a failure trains you to ignore the report.

## Before a significant system change

Root is ext4 with no snapshots. Verify `/data` and `/backup` are mounted, then back up:

    sudo systemctl start restic-backup.service    # `backupnow` is an alias for `sudo restic-backup`,
                                                  # which is NOT passwordless; the unit is

Recovery is reinstall/bootstrap/restore, not a rollback.

## Do not

- Add themes, icon sets, fonts, KWin scripts or panels outside `docs/design-system.md`.
- Touch `/data`, `/backup`, `/mnt/winrescue` without an explicit instruction.
- Edit `/etc/fstab` or `/etc/sudoers*` by hand.
- Install Anaconda, Docker Desktop, or snaps of apps that have apt/Flatpak versions.
- Commit secrets. Public keys are fine; tokens and passphrases are not.
