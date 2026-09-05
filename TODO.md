# TODO — strix

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
