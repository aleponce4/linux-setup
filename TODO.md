# TODO — strix

Open decisions and deferred work. Not blocking; the machine is usable.

## Work is split: Onteko vs UTHSC

Two separate work contexts, and they should not be mixed in `~/work`:

| Context | What | Status |
|---|---|---|
| **Onteko** | the startup | **clone everything** |
| **UTHSC** | the main job | **not needed for now** — defer |
| personal / tools | everything else | as needed |

### Action items

1. **`gh auth login` must happen before any of this.** Most of these repos are private;
   `80-envs.sh` clones with plain `git clone` and will fail silently-ish (it warns and
   continues) on anything private until `gh auth setup-git` has run.

2. **"All Onteko repos" is not what module 80 does today.** `lists/git-repos.txt` is a
   *static list* and currently names exactly one Onteko repo (`Onteko/ProLIBSpector`).
   To actually clone the whole org, module 80 needs something like:

   ```sh
   gh repo list Onteko --limit 200 --json nameWithOwner -q '.[].nameWithOwner'
   ```

   Proposal: add a `GITHUB_ORGS_CLONE_ALL="Onteko"` switch to `config.env` and have
   `80-envs.sh` expand it at runtime, keeping the static list for one-off repos.
   Not implemented yet — needs a decision.

3. **`lists/git-repos.txt` needs classifying.** The `aleponce4/*` entries are a mix and
   it is not obvious from the names which belong to UTHSC and which to Onteko:

   ```
   aleponce4/libs-spectroscopy-workbench          ?
   Onteko/ProLIBSpector                           Onteko
   aleponce4/Seed_LIBS_Classification             ?
   aleponce4/Bell_Seed_project                    ?
   aleponce4/lab-bioinfo-templates                ?
   aleponce4/preclinical-study-analysis-shiny     ?
   aleponce4/Survival_Shinny_App                  ?
   aleponce4/veeev-nat-hist-nfcore-isaac          ? (ISAAC = UTHSC HPC, likely UTHSC)
   aleponce4/akodon-genome-assembly-workflow      ?
   aleponce4/baby-weight-tracker                  personal
   eponce00/family-life-plan                      personal
   cvat-ai/cvat                                   third-party tool
   ```

4. **Proposed `~/work` layout** once classified:

   ```
   ~/work/onteko/     all Onteko org repos
   ~/work/uthsc/      deferred
   ~/work/personal/
   ~/work/tools/      cvat and other third-party checkouts
   ```

   `80-envs.sh` currently flattens everything into `$WORK_DIR/<repo-name>`. Supporting
   subdirectories means a small change to its clone loop.

## Other open items

- **Module 22 (secrets) has not been run.** No `~/.ssh/id_ed25519` yet. Run
  `./bootstrap.sh 22`; passphrase is at `/mnt/winrescue/secrets-passphrase.txt`.
  Until then `60-remote.sh` leaves password SSH login enabled (it refuses to lock you
  out with an empty `authorized_keys`).
- **Wallpaper not chosen.** ~40 KDE wallpapers already at `/usr/share/wallpapers/`;
  `plasma-wallpapers-addons` and `kubuntu-wallpapers` add more. Set `WALLPAPER` in
  `config.env` and re-run `./bootstrap.sh 30`.
- **Wispr Flow** — no Linux client is known to exist. `net.mkiol.SpeechNote` is already
  installed and wired to `ydotool` for insert-into-active-window, which is the same
  workflow. Needs confirming.
- **PDF handler is Chrome** now that Okular is removed. `sudo apt install okular` if you
  want annotation; module 30 picks it back up automatically.
- **No media player installed** (VLC removed). `sudo apt install mpv` if wanted.
- **Remove the temporary sudo file** when setup is finished:
  `sudo rm /etc/sudoers.d/99-claude-setup-TEMPORARY`
  (module 40 installs the properly scoped `/etc/sudoers.d/90-agent-admin` to replace it)
- **Save the restic password off-machine** — module 85 generates it at
  `~/.config/restic/password`. Without it the backups are unreadable.
- **HANDOFF §4 housekeeping**: revoke the Tailscale auth key, `passwd`, delete the
  `strix-installer` and `keycheck-throwaway` tailnet nodes, delete
  `/mnt/winrescue/secrets-passphrase.txt` once it is in a password manager.
