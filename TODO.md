# TODO — strix

## State as of 2026-09-05 ~23:15 — verification: 59 passed, 4 failed

Everything that can be done without you is done. `./bootstrap.sh 90` is the source of
truth; the last run is in `logs/verify-final.txt`.

### The 4 remaining failures, and why

| Check | Blocked on |
|---|---|
| `Desktop: window rules present` | **Re-login.** KWin assigns desktop UUIDs when a session starts; only `Id_1` of 5 exists, so the rules cannot be written yet. Restarting KWin on Wayland would kill the live session, so it was left alone. |
| `Dev: docker info (group active?)` | **Re-login.** You are in the `docker` group in `/etc/group`, but the running session predates it. `sg docker -c ...` works today. |
| `Remote: tailscale logged in` | **Your browser.** `sudo tailscale up --ssh --accept-dns` |
| `Remote: Chrome Remote Desktop` | **Your browser.** https://remotedesktop.google.com/headless |

### First thing in the morning

```sh
# 1. log out and back in  (fixes docker + window rules)
# 2. then:
cd ~/linux-setup
./bootstrap.sh 30        # writes the window rules now that desktop ids exist
sudo tailscale up --ssh --accept-dns
./bootstrap.sh 90        # expect 63 / 63
```

### Not blocking, but worth knowing

- **`~/work/personal/baby-weight-tracker` has 12 unpushed commits** and 6 uncommitted files,
  and `~/work/onteko/ProLIBSpector` has 197 uncommitted files on `codex/seed-targeting-learning`.
  Both were moved off the Desktop with all work intact. **Nothing was pushed** — review first.
- `~/Desktop-archive-2026-09-04/` holds the 6 dead shortcuts removed from the desktop.
  Delete when you are satisfied.
- The `fru` R package still fails to build: it needs `cargo`. `sudo apt install cargo` then
  `Rscript -e 'install.packages("fru")'` if you actually need it.
- **Save the restic password off-machine**: `~/.config/restic/password`. Without it the
  backups are unreadable. First backup runs at 02:32.
- Remove the temporary blanket sudo rule once you are happy:
  `sudo rm /etc/sudoers.d/99-claude-setup-TEMPORARY`
  (module 40 installed the scoped `/etc/sudoers.d/90-agent-admin` as the permanent one.)


Open decisions and deferred work. Not blocking; the machine is usable.

## Work is split: Onteko vs UTHSC

Two separate work contexts, and they should not be mixed in `~/work`:

| Context | What | Status |
|---|---|---|
| **Onteko** | the startup | **clone everything** |
| **UTHSC** | the main job | **not needed for now** — defer |
| personal / tools | everything else | as needed |

### Decided 2026-09-04

- **Org bulk-clone: implemented.** `config.env` now has `GITHUB_ORGS_CLONE_ALL="Onteko"`.
  `80-envs.sh` expands it with `gh repo list <org> --limit 200` and clones every repo into
  `$WORK_DIR/onteko/`. Skips cleanly with a warning if `gh` is not authenticated.
- **Layout: per-context subdirectories.** `lists/git-repos.txt` now takes an optional second
  field naming a subdirectory under `$WORK_DIR`. `clone_repo()` also *moves* a repo that an
  earlier flat run already cloned, rather than cloning it twice.

  ```
  ~/work/onteko/     every Onteko org repo (automatic)
  ~/work/uthsc/      deferred
  ~/work/personal/   baby-weight-tracker, family-life-plan
  ~/work/tools/      cvat
  ```

### Still open: classify the remaining repos

`gh auth login` is required before any of this runs — most are private.

These sit directly in `$WORK_DIR` because I cannot tell from the names whether they are
Onteko or UTHSC work. Add the right subdirectory as a second field in `git-repos.txt`:

```
aleponce4/libs-spectroscopy-workbench       ?
aleponce4/Seed_LIBS_Classification          ?
aleponce4/Bell_Seed_project                 ?
aleponce4/lab-bioinfo-templates             ?
aleponce4/preclinical-study-analysis-shiny  ?
aleponce4/Survival_Shinny_App               ?
aleponce4/akodon-genome-assembly-workflow   ?
```

`aleponce4/veeev-nat-hist-nfcore-isaac` is commented out as UTHSC (ISAAC is the UTHSC HPC);
uncomment it when UTHSC work is wanted.

Note: four repos have a `pre-migration-2026-09-02` branch holding local history that had
diverged from GitHub (`Baby_weight`, `Bell_Seed_project_repo`, `lab-bioinfo-templates`,
`family-life-plan`) — merge from it when convenient.

## Other open items

- **Module 22 (secrets) has not been run.** No `~/.ssh/id_ed25519` yet. Run
  `./bootstrap.sh 22`; passphrase is at `/mnt/winrescue/secrets-passphrase.txt`.
  Until then `60-remote.sh` leaves password SSH login enabled (it refuses to lock you
  out with an empty `authorized_keys`).
- **Wallpaper not chosen.** ~40 KDE wallpapers already at `/usr/share/wallpapers/`;
  `plasma-wallpapers-addons` and `kubuntu-wallpapers` add more. Set `WALLPAPER` in
  `config.env` and re-run `./bootstrap.sh 30`.
- **Wispr Flow** — confirmed 2026-09-04: **no official Linux client.** wisprflow.ai/downloads
  ships Mac and Windows only and has a "vote for Linux support" section.

  Three options, in order of how much trust each requires:

  1. **Speech Note** (`net.mkiol.SpeechNote`) — already installed by module 30 and wired to
     `ydotool` + a udev rule + a flatpak override, so it can insert text into the active
     window. Local Whisper models, nothing leaves the machine. This is the same workflow;
     it is the recommended default. First launch: download a model (medium.en or Parakeet),
     enable "Insert into active window", bind a global shortcut.
  2. **Unofficial Linux port** — `github.com/wispr-flow-linux/wispr-flow-linux` repackages
     the proprietary Windows installer and pairs it with a clean-room Rust helper, producing
     .deb / .rpm / AppImage / AUR / Nix builds. Deliberately NOT installed: it is an
     unofficial repackage of closed-source software on a machine that will hold UTHSC data.
     Your call.
  3. **Wait for the official client** and vote on their downloads page.
- ~~PDF handler / media player~~ **resolved 2026-09-04**: `okular` (+ backends) and `mpv`
  are back in `lists/apt-desktop.txt`; module 30 installs them and sets Okular as the PDF
  handler. VLC stays out — mpv covers it without the GUI weight.
- **Remove the temporary sudo file** when setup is finished:
  `sudo rm /etc/sudoers.d/99-claude-setup-TEMPORARY`
  (module 40 installs the properly scoped `/etc/sudoers.d/90-agent-admin` to replace it)
- **Save the restic password off-machine** — module 85 generates it at
  `~/.config/restic/password`. Without it the backups are unreadable.
- **HANDOFF §4 housekeeping**: revoke the Tailscale auth key, `passwd`, delete the
  `strix-installer` and `keycheck-throwaway` tailnet nodes, delete
  `/mnt/winrescue/secrets-passphrase.txt` once it is in a password manager.

---

# Final step: declutter and organize

The last pass that turns a provisioned machine into one that is pleasant to work on.
Everything below is deliberate and reversible; none of it is done automatically, because
several items involve deciding what to keep.

## 0. FIRST — rescue the work sitting on the Desktop

Two Desktop folders are live git checkouts with work that exists **nowhere else**:

| Path | State |
|---|---|
| `~/Desktop/Baby_weight` | branch `main`, **12 unpushed commits**, 6 uncommitted files |
| `~/Desktop/ProLIBSpector` | branch `codex/seed-targeting-learning`, **197 uncommitted files** |

Both are also listed in `lists/git-repos.txt`, so module 80 will clone *fresh copies* into
`~/work/`, leaving two divergent checkouts of the same repo. Resolve before decluttering:

```sh
cd ~/Desktop/Baby_weight     && git status && git push          # then move, do not delete
cd ~/Desktop/ProLIBSpector   && git status                      # review the 197 changes first
```

Then move them into the layout rather than re-cloning:

```sh
mkdir -p ~/work/personal ~/work/onteko
mv ~/Desktop/Baby_weight     ~/work/personal/baby-weight-tracker
mv ~/Desktop/ProLIBSpector   ~/work/onteko/ProLIBSpector
```

`clone_repo()` in `80-envs.sh` skips any destination that already has a `.git`, so moving
them first makes module 80 leave them alone.

## 1. Desktop: from 13 items to zero

Dead Windows shortcuts (`.url` files are Windows internet shortcuts — inert on Linux):

```sh
rm ~/Desktop/"Manor Lords.url" ~/Desktop/"Total War PHARAOH.url" \
   ~/Desktop/"Total War PHARAOH DYNASTIES.url" ~/Desktop/Bazarr.url
```

Kubuntu promo links, shipped with the distro image:

```sh
rm ~/Desktop/org.kubuntu.web.home.desktop ~/Desktop/org.kfocus.web.howtos.desktop
```

The rest is filing, not deleting:

| Item | Home |
|---|---|
| `2026_Resum`, `Pam's resume`, `era-commons-account-request-form.pdf` | `~/Documents/personal/` |
| `Onteko_LIBS_Report`, `Onteko-LIBS-Elemental-Mapping-Demonstration.pdf` | `/data/onteko/reports/` |

Target: **an empty desktop.** The design system in `docs/design-system.md` already calls for
this — the launcher is KRunner, not a field of icons.

## 2. App menu: 213 entries, 82 with no category at all

Kubuntu ships a generic menu that does not match how this machine is used. Group the tools
by what they are *for*, using custom XDG categories:

| Category | Members |
|---|---|
| **AI** | Claude Code, Codex, Antigravity, Copilot CLI, OpenCode, Speech Note |
| **IDEs & Editors** | VS Code, RStudio, Positron, Mark Text, Obsidian |
| **Science** | R, Quarto, DuckDB, Jupyter, CVAT, ChimeraX/MEGA if added later |
| **Containers** | Docker, lazydocker, Distrobox, Apptainer |
| **Terminal** | Ghostty, yazi, btop, lazygit |

The mechanism: put a copy of each `.desktop` file in `~/.local/share/applications/` with an
added `Categories=X-AI;` (etc.), then declare the menus in
`~/.config/menus/applications.menu`. This is XDG-standard, survives Plasma updates, and is
per-user — nothing in `/usr` is modified. `kmenuedit` can do it by hand, but a script in
`dotfiles/kde/` would make it reproducible, which is the point of this repo.

Also worth doing: **hide, do not uninstall**, the entries you never launch — `NoDisplay=true`
in a user-level copy keeps the package (and its libraries) while removing the menu noise.
Many of the 82 uncategorised entries are library helpers that were never meant to be visible.

## 3. Panel: pin what you actually open

`dotfiles/kde/panel.js` already builds one floating icon-only panel via the Plasma scripting
API, and `30-desktop-kde.sh` applies it once (guarded by
`~/.config/.linux-setup-panel-applied`). Decide the pinned set and put it in that script so
it is reproducible rather than hand-arranged:

Suggested: **Ghostty · VS Code · Chrome · Dolphin · Obsidian · Spotify**

Everything else stays in KRunner. A panel is for the six things opened constantly; a launcher
is for the other two hundred. Delete the marker file and re-run `./bootstrap.sh 30` to
re-apply after editing.

System tray: `System Tray > Configure > Entries` — set anything not glanced at to Hidden.
Realistically only network, volume, clipboard and updates earn a permanent slot.

## 4. KDE Activities for the Onteko / UTHSC split

The strongest organizational tool in Plasma and the one almost nobody uses. Activities are
**not** virtual desktops: each has its own wallpaper, widgets, pinned apps and window set, and
persists across reboots.

```
Activity "Onteko"   -> ~/work/onteko,  /data/onteko,  ProLIBSpector
Activity "UTHSC"    -> ~/work/uthsc,   /data/{libs,seed}
Activity "Personal" -> everything else
```

Switch with `Meta+Tab`. The five named workspaces (CODE/WEB/SCIENCE/COMM/MISC) then operate
*inside* whichever context is active, which is a much better fit for two jobs than trying to
encode both jobs into five desktops. Set up under
`System Settings > Workspace Behavior > Activities`.

## 5. Dolphin places sidebar

The default sidebar points at Windows-shaped folders. Replace with the paths actually used:

```
/data/libs        /data/onteko      /data/seed
~/work/onteko     ~/work/personal
/backup           /mnt/winrescue  (read-only rescue drive)
```

## 6. Deduplicate and set defaults

- **Duplicate entries**: Flatpak and apt versions of the same app both appear in the menu.
  `flatpak list --app` against `dpkg -l` finds them; keep one.
- **MIME defaults** worth setting explicitly: `.md` -> Mark Text, `.pdf` -> Okular,
  `.csv` -> a spreadsheet or VS Code, images -> Gwenview, video -> mpv.
  Module 30 sets the first two; the rest by hand or added to the module.
- **Autostart audit**: `System Settings > Autostart` — remove anything inherited from the
  distro image that is not wanted at every login.

## 7. Housekeeping that pays off later

- `~/Downloads` and `~/Documents` were restored wholesale from Windows and carry that
  structure. Worth one pass now while the contents are still familiar.
- `sudo apt autoremove --purge` after the setup settles.
- Once everything is confirmed working, remove the temporary blanket sudo rule:
  `sudo rm /etc/sudoers.d/99-claude-setup-TEMPORARY`
  (module 40's scoped `/etc/sudoers.d/90-agent-admin` is the permanent replacement).
