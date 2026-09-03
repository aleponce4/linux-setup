# This machine (strix): guide for AI agents

Read this before changing anything system-wide. It is linked as `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.

## What this is
Alex Ponce's single-user research workstation: Kubuntu 26.04 LTS, KDE Plasma (Wayland), AMD Ryzen 5 3600, 32 GB RAM,
Intel Arc B570 (xe driver; VA-API and Level Zero available), two monitors. Work: LIBS spectroscopy analysis (Python), seed image
classification, R/Shiny apps, bioinformatics pipelines that run on the ISAAC HPC cluster (SLURM, Apptainer).

## Layout
- `~/linux-setup/`  the provisioning repo. **The lists in `lists/` and the files in `dotfiles/` are the source of truth for what is installed and configured.**
- `~/work/<repo>/`  git repositories (clone new ones here). Never store datasets inside repos.
- `/data/` (also `~/data/`)  the SATA SSD: `libs/`, `onteko/`, `seed/`, `datasets/`, `scratch/`. Large files live here.
- `/backup/`  the HDD: `btrbk/` (hourly Btrfs snapshots of `/`, `/home`, `/data`), `restic/`. Read-mostly.
- `/mnt/winrescue/`  read-only NTFS image of the old Windows machine (data copy, WSL export). Do not write.
- `~/micromamba/envs/`  conda envs (conda-forge only). `~/.local/share/uv/`  uv-managed Pythons.

## How to install or change things
- **Packages**: append to `~/linux-setup/lists/apt-*.txt`, `flatpaks.txt`, `vscode-extensions.txt`, `python-uv-tools.txt`, `npm-globals.txt`, `r-packages-*.txt`, then run `cd ~/linux-setup && ./bootstrap.sh <module-number>` (e.g. `40` for dev tools, `50` for R/science, `30` for desktop). Do not hand-install outside the lists; a reinstall must reproduce the machine.
- **Dotfiles / KDE settings**: edit `~/linux-setup/dotfiles/...` and re-run `./bootstrap.sh 70` (or `30` for Plasma). Files in `$HOME` are symlinks into the repo.
- **System files under /etc**: only through a module using `write_file_sudo`/`ensure_line` from `lib/common.sh`, so the change is versioned.
- **Commit** every change to `~/linux-setup` with a clear message (`git -C ~/linux-setup commit -am "..."`).
- `sudo` works without a password for: apt, apt-get, dpkg, flatpak, systemctl, journalctl, timeshift, btrbk, tailscale, ufw, fwupdmgr, apptainer. Anything else prompts Alex.
- Every `apt` run takes a Timeshift snapshot first (`sudo timeshift --list`). **Before any other system-level change** (config under /etc, GRUB, drivers, desktop settings en masse) run `snapnow` (= `sudo timeshift --create`). Rollback: `sudo timeshift --restore` or boot a snapshot from GRUB.
- Snapshots are not backups. restic runs daily at 02:30 into `/backup/restic` (`sudo restic-backup` to run now; list with `sudo restic -r /backup/restic -p /etc/restic/password snapshots`; restore with `... restore latest --target /tmp/restore --include <path>`). btrbk keeps hourly Btrfs snapshots of `/`, `/home`, `/data` under `/backup/btrbk`.
- Prefer the workstation repo over ad-hoc changes: "modify `~/linux-setup` so the change is reproducible, show the diff, then apply it".

## Environments
- Python projects: `uv` (`uv init`, `uv add`, `uv run`, `uv python install 3.12`). Global CLI tools: `uv tool install <name>`.
- Conda-only packages (bioconda etc.): `micromamba create -n <name> -c conda-forge -c bioconda ...`; keep the spec in `~/linux-setup/envs/conda/<name>.yml`.
- R: system R 4.6 + r2u binaries; `install.packages()` is fast. Project reproducibility with `renv`. IDEs: Positron, RStudio, VS Code.
- Containers: `docker compose` for services (CVAT), `apptainer` for HPC-compatible images. User is in the `docker` group.
- Other distros without touching the host: `distrobox enter arch` (Arch userland sharing `$HOME`; `distrobox-export --app <name>` puts one of its GUI apps in the launcher). Add boxes in `lists/distroboxes.txt`.
- GUI apps: leaf apps (Spotify, Obsidian, Mark Text, Speech Note) are Flatpaks; IDEs and anything that must see the toolchain (VS Code, Positron, RStudio, Chrome, Zoom) are apt/.deb. Keep it that way.
- Node: `fnm` (v24 default), globals in `lists/npm-globals.txt`.

## Do not
- Delete or move anything under `/data`, `/backup`, `/mnt/winrescue` without an explicit instruction.
- Edit `/etc/fstab`, `/etc/sudoers*`, firewall or sshd config by hand; use the storage/remote modules.
- Install Anaconda/`defaults`-channel conda, Docker Desktop, or snap versions of apps that have apt/Flatpak versions.
- Store secrets (tokens, keys, passwords) in `~/linux-setup` or any repo.

## Useful
- Launcher: press Meta, type `cc <prompt>` (Claude Code), `cx` (Codex), `agy` (Antigravity), `ssh <host>`, `repo <name>`, `setup <NN>`.
- Workspaces: Meta+1..5 = CODE, WEB, SCIENCE, COMM, MISC; window rules send editors/terminals, browser, RStudio/Positron and Zoom/Teams to theirs. Meta+Enter = terminal, Meta+W = overview, Meta+Shift+S = screenshot region, Meta+arrows = snap.
- Verify the machine: `cd ~/linux-setup && ./bootstrap.sh 90`.
- Remote: Tailscale (`tailscale status`; `tailscale serve --bg 8888` exposes a local port such as Jupyter to the tailnet), SSH keys only, `mosh`; GUI via KDE's RDP server (System Settings > Remote Desktop) or Chrome Remote Desktop (virtual Plasma X11 session); VS Code Remote-SSH and `code tunnel`.
- GPU checks: `vainfo`, `clinfo -l`, `glxinfo -B`, `intel_gpu_top`.
