# STRIX DAILY COCKPIT
> Kubuntu 26.04 - a calm, keyboard-first map for daily work

## Everyday shortcut deck | READY
- **Meta** - Open KRunner: apps, files, calculations, agents, SSH, and repos.
- **Meta+Enter** - Open Ghostty.
- **Meta+W** - Open the Plasma overview.
- **Meta+V** - Open clipboard history.
- **Meta+Shift+S** - Capture a rectangular region with Spectacle.
- **Meta+E** - Open Dolphin.
- **Meta+.** - Open the emoji picker.

## Fast window placement | READY
- **Meta+Left / Right** - Tile to half the screen.
- **Meta+Up** - Maximize.
- **Meta+Left, then Up** - Tile to the upper-left quarter.
- **Meta+T** - Edit Plasma's native tiling zones.
- **Meta+Ctrl+Left / Right** - Move between virtual desktops.

Plasma's native zones are the baseline. Polonium stays installed but off; enable one auto-tiler only if the native workflow feels limiting after a week.

<!-- column -->

## Five-workspace map | READY
- **Meta+1 - CODE** - VS Code, Ghostty, Cursor; edit, test, Git, and agents.
- **Meta+2 - WEB** - Browser, documentation, papers, and dashboards.
- **Meta+3 - SCIENCE** - Positron, RStudio, Jupyter; analyze and report.
- **Meta+4 - COMM** - Zoom, Teams, WhatsApp; meetings and collaboration.
- **Meta+5 - MISC** - Dolphin, Obsidian, and administrative utilities.

Window rules place the common apps automatically. Edit existing rules in System Settings; the repo will not overwrite them.

## Where work lives | READY
- **~/work** - Git repositories and source code.
- **/data** - Large datasets and durable project data on the Samsung 860.
- **~/Documents or /data/notes** - Notes and writing.
- **/backup** - Restic repository on the HGST drive; never a working folder.

# LAUNCH, SPEAK, ASK
> Review before Enter: fast automation still keeps a human confirmation boundary

## KRunner agent prefixes | READY
- **cc fix the failing test** - Open Claude Code in Ghostty.
- **cx review this repo** - Open Codex in Ghostty.
- **agy draft an analysis** - Open Antigravity in Ghostty.
- **ssh isaac** - Open the named HPC host.
- **repo seed** - Open a matching repository in VS Code.
- **setup 90** - Run workstation verification in a terminal.

## AI clipboard actions | FIRST RUN
- **Install** - Run `./productivity.sh install handlers` once.
- **Summarize** - Copy text, press Meta, search `AI Clipboard - Summarize`.
- **Rewrite** - Copy text, launch `AI Clipboard - Rewrite Clearly`.
- **Explain** - Copy an error, launch `AI Clipboard - Explain`.
- **Actions** - Turn meeting notes into a checklist.

Each action shows provider, size, and a preview before sending. Output is copied but never pasted or executed.

<!-- column -->

## Speech Note first run | FIRST RUN
- **Repair** - Run `./productivity.sh install dictation`, then log out and in.
- **Check** - Run `./productivity.sh doctor dictation`.
- **Model** - Choose Whisper.cpp Small English first; try Medium for accuracy.
- **GPU** - Use the base Flatpak on Intel Arc; do not add AMD/NVIDIA packs.
- **Shortcut** - Enable global shortcuts and active-window insertion in Speech Note.
- **Test** - Dictate first into an empty Kate document.

If typing is unreliable, dictate to the clipboard and paste manually. Never voice-submit a shell command or agent prompt.

## Dictation quick diagnosis | READY
- **Service** - `systemctl --user status ydotool.service`
- **Socket** - `ls -l "$XDG_RUNTIME_DIR/ydotool/socket"`
- **Journal** - `journalctl --user -u ydotool.service -n 30`
- **Doctor** - `./productivity.sh doctor dictation`

The doctor does not record audio or synthesize keys.

## Before sending text to AI | SAFETY
- **Never send** - Passwords, tokens, private keys, patient data, or sensitive unpublished research.
- **Always inspect** - The preview and the returned text.
- **Remember** - Clipboard text leaves this machine when you approve the request.

# RESEARCH AND HANDOFF LOOP
> Capture once, organize deliberately, automate the boring transitions

## Research loop | FIRST RUN
- **Capture** - Browser, PDFs, screenshots, dictation, and phone share.
- **Organize** - Zotero for sources; Obsidian for thinking; `/data` for datasets.
- **Analyze** - Positron, RStudio, or Jupyter with a per-project environment.
- **Scale** - Docker locally; Apptainer and `ssh isaac` for HPC.
- **Publish** - Quarto or Markdown to HTML/PDF; commit code and sources with Git.
- **Protect** - Verify mounts, then run `backupnow`.

Run `./productivity.sh install research`; import the staged Better BibTeX XPI through Zotero's Plugins window. Keep an automatic `references.bib` export beside a Quarto manuscript when useful.

## Fast terminal moves | READY
- **z NAME** - Jump with zoxide.
- **fzf / rg / fd** - Find interactively, search text, and find files.
- **bat / eza / yazi** - Read, list, and browse with context.
- **lg** - Open lazygit.
- **uv run ...** - Run Python in the project environment.
- **run-notify -- CMD** - Add a completion alert after installing handlers.

<!-- column -->

## Screenshot to editable text | FIRST RUN
- **Install** - Handlers add Tesseract English data.
- **Capture** - Press Meta+Shift+S and select only what matters.
- **Extract** - In Spectacle, use Extract Text.
- **Clean** - Copy the OCR result; optionally run an AI rewrite or table action.

OCR stays local. Only the later AI step transmits text, and only after consent.

## KDE Connect bridge | FIRST RUN
- **Pair** - Put phone and `strix` on the same LAN and approve both screens.
- **Use** - Share links/files, presentation control, notifications, and clipboard where Android permits.
- **Check** - `kdeconnect-cli -l`
- **Network** - Keep traffic inside TCP/UDP 1714-1764; do not open broader ports.

Android clipboard permissions vary, so file/link sharing is the dependable baseline.

## Kando trial | OPTIONAL
- **Install** - `./productivity.sh install kando`
- **Rule** - Do not bind it to Meta; KRunner owns that key.
- **Trial** - Give one pie menu one week. Keep it only if it replaces repeated travel.

ActivityWatch is deferred: its official watcher does not yet support KWin Wayland well enough for this workstation.

# SAFETY AND QUICK RECOVERY
> Current system: ext4 root, restic recovery, disk identity before convenience

## Machine storage truth | SAFETY
- **Root** - Samsung 990 PRO 1 TB, `/dev/nvme0n1p2`, ext4.
- **Root UUID** - `1e0539dd-c9b4-4222-9076-48a11c6154d9`.
- **Data** - Samsung 860 EVO 500 GB at `/data`; never root.
- **Rescue/backup** - 8 TB HGST at WINRESCUE and `/backup`; never root.

Never identify the SATA SSD or HDD by `/dev/sdX`. Use filesystem UUIDs and the serial-backed `/dev/disk/by-id` facts in `config/storage.conf`.

## Before backup, restore, or large copy | SAFETY
- **Root** - `findmnt -no SOURCE,FSTYPE,UUID /`
- **Data** - `mountpoint -q /data && findmnt /data`
- **Backup** - `mountpoint -q /backup && findmnt /backup`
- **Inventory** - `lsblk -o NAME,MODEL,SERIAL,SIZE,FSTYPE,UUID,MOUNTPOINTS`

Stop if a mount check fails. A plain `/data` or `/backup` directory on root is not a substitute.

<!-- column -->

## ext4 recovery model | READY
- **Daily protection** - Restic backs up normal files; ext4 has no root snapshots.
- **Backup now** - Verify `/data` and `/backup`, then run `backupnow`.
- **Restore** - Restore into a temporary directory, inspect, then copy selected files.
- **Root loss** - Reinstall only on the 990 PRO, bootstrap, verify mounts, then restore.
- **Btrfs later** - Optional future Btrfs may add Timeshift; snapshots still are not backups.

`snapnow` deliberately refuses on the current ext4 root.

## Health commands | READY
- **Workstation** - `./bootstrap.sh 90`
- **Productivity** - `./productivity.sh doctor`
- **Agent runner** - `journalctl --user -u org.kde.agentrunner`
- **Restart KRunner** - `kquitapp6 krunner`
- **Backup** - `systemctl status restic-backup`

## Hard stops | SAFETY
- **No formatting** - Never use `--format` in the current workstation flow.
- **No repartitioning** - Never repartition the Samsung 860 or HGST rescue drive.
- **No blind paste** - Read AI-generated commands before pressing Enter.
- **No auto-submit** - Voice and clipboard helpers stop before execution.
- **No duplicate stack** - One launcher, one tiler, one dictation daemon.
