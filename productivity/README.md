# Optional productivity phase

This directory is deliberately outside `setup.d/`. `bootstrap.sh` never discovers or runs it, and there is
no install-all action. Start with the read-only doctor, then opt into one component at a time:

```bash
cd ~/linux-setup
./productivity.sh list
./productivity.sh doctor
./productivity.sh install handlers --dry-run
./productivity.sh install handlers
./productivity.sh install dictation
./productivity.sh install research
./productivity.sh install kando
```

Every installer is idempotent, shows its exact scope, asks before changing anything, and is forbidden from
touching disks, partitions, filesystems, or mounts. Existing non-repo files are preserved before a link is
created. `doctor` is read-only: it does not read the clipboard, start the microphone, synthesize input, pair
a phone, or call an AI service.

## What each component does

### `handlers`

- Installs the small host packages needed for Wayland clipboard access, English OCR, dialogs, and notifications.
- Adds `ai-clipboard`, which supports `summarize`, `rewrite`, `explain`, `actions`, `table`, and
  `translate LANGUAGE`.
- Adds `run-notify -- long-command ...` for success/failure desktop alerts.
- Adds KRunner-visible entries for the four common AI actions.

`ai-clipboard` uses the already-provisioned Claude CLI in restricted, bare, tool-free, non-persistent print
mode. It rejects likely secrets and hidden control characters, caps input at 50 KB, shows provider/action/size
and a preview, and requires confirmation. The result is copied to the clipboard but never pasted or executed.
The clipboard text still leaves the machine and is subject to the provider's data policy; do not send secrets,
credentials, patient/regulated data, or unpublished sensitive research.

Kubuntu 26.04's Spectacle has built-in OCR. After `handlers`, take a region with `Meta+Shift+S`, open the
capture in Spectacle, use **Extract Text**, then copy the result. Keeping OCR inside Spectacle avoids a fragile
screen-capture wrapper and leaves selection under your control.

### `dictation`

The normal desktop module already installs Speech Note and ydotool, but its historical service/Flatpak bridge
can be incomplete on Wayland. This repair uses Ubuntu's packaged `ydotool.service`, a private
`$XDG_RUNTIME_DIR/ydotool/socket`, a dedicated `uinput` group, and a narrow Flatpak filesystem grant. It also
prevents the old repo-created `ydotoold.service` from becoming a second daemon after a bootstrap rerun.

Access to `/dev/uinput` permits synthetic keyboard input. That is why this repair is explicit and why the
service is started as the logged-in user with mouse injection disabled. A logout/login is normally required
after the group is first added. An earlier bootstrap may already have added the account to the broader
`input` group; the doctor warns about that, but this phase does not remove existing group memberships
automatically because they may be user-owned.

First run remains manual:

1. Log out and back in, then run `./productivity.sh doctor dictation`.
2. Open Speech Note and choose a Whisper.cpp English model. Start with Small for responsiveness; try Medium
   if accuracy matters more. The base Flatpak already carries the Intel-capable backends; do not install the
   NVIDIA or AMD add-ons for Intel Arc.
3. In Speech Note accessibility settings, enable global shortcuts and **Insert into active window**.
4. Assign a hold-to-talk shortcut through Plasma's portal. Test in an empty Kate document first.
5. If active-window insertion is unreliable, use Speech Note's copy-to-clipboard mode and paste manually.

The safe voice-to-agent workflow is: dictate to clipboard, press `Meta`, type `cx ` or `cc `, paste, review,
then press Enter yourself. Nothing here sends dictated text directly to a shell or auto-submits an AI prompt.

### `research`

Installs Zotero from the `zotero-pkg` apt repository, which repackages Zotero's upstream binaries for Debian
systems. It stages a pinned and SHA-256-verified Better BibTeX XPI in `~/Downloads`, but never edits a Zotero
profile or library. Import the XPI through **Tools > Plugins > gear > Install Plugin From File**. In Better
BibTeX, create an automatic `references.bib` export for Quarto projects when useful.

### `kando`

Installs the developer-verified Flatpak only. Kando supports Plasma Wayland through the global-shortcuts
portal, but it overlaps KRunner. No shortcut or autostart is assigned; try it for a week and remove it if it
does not earn a place in the workflow.

## Intentionally deferred

ActivityWatch is not installed. Its official Linux window watcher is X11-only, and its official Wayland
watcher does not support KDE/KWin, so it would collect incomplete data on this Kubuntu Wayland workstation.
Revisit it when upstream KWin support lands rather than adding a brittle community workaround now.

## Cheat sheet

The editable source is [`docs/productivity-cheatsheet.md`](../docs/productivity-cheatsheet.md). Rebuild the
four-page PDF with the bundled-workspace Python runtime (which provides ReportLab):

```bash
python3 scripts/build-productivity-cheatsheet.py
```

The generated files are `output/html/strix-productivity-cheatsheet.html` (opened by Meta+/ and the launcher entry in a chromeless browser window; `strix-cheatsheet --pdf` opens the print version) and `output/pdf/strix-productivity-cheatsheet.pdf`. The builder fails if a card overflows
its page so a content edit cannot silently produce a clipped reference sheet.
