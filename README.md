# linux-setup

Re-runnable provisioning for Alex's workstation: Kubuntu 26.04 LTS, KDE Plasma (Wayland), Intel Arc B570.
Turns a fresh install into the full data-science + AI-agent setup with one command, and keeps the machine
converged to the lists in this repo afterwards. The desktop layer (launcher, look, tiling) is code too.

```
sudo apt install -y git
git clone https://github.com/aleponce4/linux-setup ~/linux-setup
cd ~/linux-setup
cp config.env.example config.env   # edit if the defaults are wrong
./bootstrap.sh                     # runs every module in setup.d/ in order
./bootstrap.sh --format 20         # first time only: create /data on the SATA SSD and /backup on the HDD (asks for confirmation)
./bootstrap.sh 40 50               # re-run only the modules whose number starts with 40 or 50
./bootstrap.sh --list              # show modules
```

## Layout

```
bootstrap.sh          entry point: preflight, then runs setup.d/NN-*.sh in order, logs to logs/
config.env            machine-specific values (user, hostname, git identity, disk ids, feature switches, vendor URLs)
lib/common.sh         shared helpers (log, apt_install, add_apt_repo, download_deb, github_latest_asset, ensure_line, write_file_sudo, link_dotfile ...)
setup.d/
  00-preflight.sh     distro check, hostname, timezone, apt components, full upgrade, unattended security updates, fwupd
  10-base-cli.sh      core packages + modern CLI tools, Nerd Font, zsh as login shell
  20-storage.sh       @docker subvolume, Timeshift + timeshift-autosnap-apt + grub-btrfs, zram, /data (SSD), /backup + WINRESCUE (HDD), btrbk
  22-secrets.sh       restores D:\WINRESCUE\secrets.7z (SSH key, agent credentials, Wi-Fi passwords -> NetworkManager); asks the passphrase once
  25-gpu-intel.sh     Intel Arc: VA-API media driver, Vulkan, Level Zero / OpenCL runtime, render group, workaround env file
  30-desktop-kde.sh   Flatpak/Flathub, Chrome, Zoom, glow, look (Breeze Dark, Papirus, Inter, JetBrainsMono), panel layout,
                      Meta -> KRunner, KRunner agent plugin, Polonium (off), ydotool for dictation, optional Dropbox/OneDrive/KVM
  40-dev-tools.sh     VS Code + extensions, Cursor (opt), Docker Engine, Apptainer, gh, Node (fnm) + npm CLIs, uv, micromamba,
                      Claude Code, Antigravity CLI, yazi, lazydocker, agent sudo rules
  50-science.sh       R 4.6 (CRAN) + r2u binaries + package lists, RStudio, Positron, Quarto + TinyTeX, PyMOL, DuckDB, MEGA/ChimeraX (URLs), spectrometer udev rule
  60-remote.sh        Tailscale (+SSH), hardened sshd (keys only, never locks you out), fail2ban, ufw, mosh, Wake-on-LAN
  70-dotfiles.sh      symlinks dotfiles/ into $HOME, git identity, agent machine guide -> ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md
  80-envs.sh          conda envs from envs/conda/*.yml (micromamba), clone lists/git-repos.txt into ~/work, distroboxes
  85-backup-restic.sh encrypted daily restic backup of /data, /home, /etc to /backup/restic + weekly check
  90-verify.sh        pass/fail table of everything above
lists/                one item per line, '#' comments; the files an agent edits
  apt-base.txt apt-desktop.txt apt-dev.txt apt-science.txt flatpaks.txt git-repos.txt
  vscode-extensions.txt positron-extensions.txt python-uv-tools.txt npm-globals.txt r-packages-cran.txt r-packages-bioc.txt
envs/conda/*.yml      conda-forge environment specs (from the old WSL)
dotfiles/
  zshrc tmux.conf starship.toml ghostty/config ssh/config claude/settings.json vscode/settings.json
  agents/MACHINE.md   the guide every agent reads (linked as CLAUDE.md / AGENTS.md)
  krunner/            agent-runner.py (D-Bus KRunner plugin: cc/cx/agy/ssh/repo/setup) + its .desktop
  kde/panel.js        Plasma panel layout applied through the scripting API
docs/manual-steps.md  logins, KDE shortcut tweaks, VPN, data restore
```

## Rules for agents editing this repo

- Add software by appending to the right file in `lists/`, then run the matching module (`./bootstrap.sh 40`). Do not hand-install things outside the lists; the point is that a re-run reproduces the machine.
- Modules must stay idempotent: check before install, use `ensure_line`/`write_file_sudo` for config edits, never `rm -rf` outside `$HOME/.cache`.
- Anything destructive to disks lives only in `20-storage.sh` behind `--format` and a typed confirmation.
- Secrets never go in this repo. Logins are manual; tokens live in each tool's own store.
- After a successful run, `./bootstrap.sh 90` must pass; fix the module, not the verify script.
- Commit after every change.
