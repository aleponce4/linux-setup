# This machine (strix): guide for AI agents

Read this before changing anything system-wide. It is linked as `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.

## What this is
Alex Ponce's single-user research workstation: Kubuntu 26.04 LTS, KDE Plasma (Wayland), AMD Ryzen 5 3600, 32 GB RAM,
Intel Arc B570 (xe driver; VA-API and Level Zero available), two monitors. Work: LIBS spectroscopy analysis (Python), seed image
classification, R/Shiny apps, bioinformatics pipelines that run on the ISAAC HPC cluster (SLURM, Apptainer).

## How to write for Alex

Plain prose. Mannered prose substitutes metaphor and flourish for direct statement: "a dial worth turning" for
"a parameter worth varying", "this point earns its keep" for "this point still matters". Those phrases display the
writer instead of conveying the idea, and they make the reader work harder. Do not write them.

- Active voice, and name the actor: "we review the roadmap quarterly".
- Imperatives for rules: "State both in advance."
- Verbs instead of abstract nouns: "carries the work", "planning runs on its own clock".
- One idea per sentence. Split a sentence that stacks a claim, a caveat and an aside.
- Concrete instead of categorical: real names, real numbers, real channels.
- No em dashes. Use a period, a comma or a colon.
- Cut filler: actually, really, just, simply, on purpose, in the first place, right away, quite, very, that said.
- Deduplicate across the whole document. If a line lands twice, keep the stronger placement and rewrite the other.
- Keep a figure of speech only where the plain version loses content. "Work that never ships, never dies, and
  quietly ties up an engineer" names a real failure state, so it stays.

Never:

- Define something by what it is not: "not X, but Y", "isn't A. It's B", "Not a soft launch. Not a beta."
  State the thing.
- Use counts as a rhetorical seesaw: "two seats to fill, one filled", "three habits, one purpose". Counting facts
  is fine.
- Write tautologies: "the point of launching is to launch". Rewrite as a consequence or an instruction.
- Explain your own rhetorical move.
- Write sentence fragments as sentences, call-and-response headlines, or empty mottos: "X is the work",
  "X is the moat", "Fluency is baseline."
- Reach for wedge, substrate, the bar, ship cadence, compounding, the brief. Where a noun does heavy abstract work
  a plain word would do, use the plain word.
- Sound like a startup landing page, a YC pitch, or an AI assistant.

## Layout
- `~/linux-setup/`  the provisioning repo. **The lists in `lists/` and the files in `dotfiles/` are the source of truth for what is installed and configured.**
- `/`  Samsung 990 PRO `/dev/nvme0n1p2`, ext4, UUID `1e0539dd-c9b4-4222-9076-48a11c6154d9`. This is the current supported layout; Btrfs is optional for a future reinstall.
- `~/work/<repo>/`  git repositories (clone new ones here). Never store datasets inside repos.
- `/data/` (also `~/data/`)  the Samsung 860 SATA SSD when mounted: `libs/`, `onteko/`, `seed/`, `datasets/`, `scratch/`. Verify the mount before writing large files.
- `/backup/`  the HGST HDD's backup filesystem when mounted: encrypted restic repository and, on an optional Btrfs layout, possible `btrbk/` data. Verify the mount before every backup or restore.
- `/mnt/winrescue/`  read-only NTFS image of the old Windows machine (data copy, WSL export). Do not write.
- `~/micromamba/envs/`  conda envs (conda-forge only). `~/.local/share/uv/`  uv-managed Pythons.

## How to install or change things
- **Packages**: append to `~/linux-setup/lists/apt-*.txt`, `flatpaks.txt`, `vscode-extensions.txt`, `python-uv-tools.txt`, `npm-globals.txt`, `r-packages-*.txt`, then run `cd ~/linux-setup && ./bootstrap.sh <module-number>` (e.g. `40` for dev tools, `50` for R/science, `30` for desktop). Do not hand-install outside the lists; a reinstall must reproduce the machine.
- **Dotfiles / KDE settings**: edit `~/linux-setup/dotfiles/...` and re-run `./bootstrap.sh 70` (or `30` for Plasma). Files in `$HOME` are symlinks into the repo.
- **System files under /etc**: only through a module using `write_file_sudo`/`ensure_line` from `lib/common.sh`, so the change is versioned.
- **Commit** every change to `~/linux-setup` with a clear message (`git -C ~/linux-setup commit -am "..."`).
- `sudo` works without a password for: apt, apt-get, dpkg, flatpak, systemctl, journalctl, timeshift, btrbk, tailscale, ufw, fwupdmgr, apptainer. Anything else prompts Alex.
- The current ext4 root has no filesystem snapshots. Before a significant system change, verify `/data` and `/backup`, then run `backupnow` for a restic backup. Recovery is reinstall/bootstrap/restore, not a root rollback.
- On a future optional Btrfs root, `snapnow` may create a Timeshift snapshot and `grub-btrfs`/`btrbk` may provide additional rollback points when enabled. The helper refuses to run on ext4, and the repo has never used Snapper.
- Snapshots are not backups. restic runs daily at 02:30 into `/backup/restic` (`backupnow` to run now; list with `sudo restic -r /backup/restic -p /etc/restic/password snapshots`; restore with `... restore latest --target /tmp/restore --include <path>`). Confirm `/backup` is mounted from the HGST disk first.
- Read `~/linux-setup/docs/storage.md` and the tracked facts in `config/storage.conf` before changing storage configuration. Never identify the SATA SSD or HDD by `/dev/sdX` ordering.
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
- Add themes, icon sets, Plasma widgets, docks, KWin effects/scripts or fonts outside the choices in `~/linux-setup/docs/design-system.md` (one font pair, one icon set, one palette, one window style, one panel, KRunner). Replacing a choice is fine in a commit that removes the old one; stacking is not.
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
