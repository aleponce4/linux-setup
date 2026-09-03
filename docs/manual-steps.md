# Manual steps after `./bootstrap.sh`

Everything that needs a browser login, a vendor download behind a form, or a GUI click. About 20 minutes total.
Log out and back in once after the first run (fonts, icons, docker group, Meta key).

## Logins (once)

| Tool | Command / place |
|---|---|
| Tailscale | `sudo tailscale up --ssh --accept-dns`, approve in the browser. Install the Tailscale app on phone/laptop; `ssh alexponce@strix` then works from anywhere via MagicDNS. |
| GitHub CLI | `gh auth login` (HTTPS, browser), then `./bootstrap.sh 80` to clone the private repos. |
| Claude Code | `claude` and follow the login. Settings are in `~/.claude/settings.json`; the machine guide is `~/.claude/CLAUDE.md`. |
| Codex | `codex login` (browser). `~/.codex/AGENTS.md` is the same machine guide. Trusted projects get added as you open repos. |
| Antigravity | `agy` and follow the Google login. |
| Copilot CLI | `copilot` then `/login`. |
| Chrome | sign in; sync restores extensions and bookmarks. Install PWAs from the address-bar icon for Teams, Outlook, WhatsApp, Dropbox, OneDrive. |
| Zoom | SSO/Google login. |
| Spotify | Flatpak, log in. |
| Speech Note | first launch: download a Whisper model (medium.en, or Parakeet), enable "Insert into active window" (ydotool is already running), then System Settings > Shortcuts > add a global shortcut for "Speech Note: listen". |

## The launcher (KRunner) and what the agent plugin adds

Press **Meta** (Windows key) alone. Type an app name, a file name, a calculation (`2*pi*7`), a command (`htop`), or:

| Type | Result |
|---|---|
| `cc fix the failing test in libs-spectroscopy-workbench` | opens Ghostty in `~/work` with Claude Code and that prompt |
| `cx ...` / `agy ...` | same with Codex / Antigravity |
| `ssh isaac` | Ghostty with an SSH session (hosts from `~/.ssh/config`) |
| `repo seed` | open a matching `~/work` repo in VS Code, or a terminal there |
| `setup 40` | re-run a linux-setup module in a terminal |

If the plugin does not show up: `systemctl --user status` is not involved, it is D-Bus activated; check `journalctl --user -f` while typing `cc`, and that `~/.local/share/krunner/dbusplugins/agentrunner.desktop` exists. Restart KRunner with `kquitapp6 krunner`.

## Remote access (all through Tailscale, nothing exposed to the internet)

| Need | How |
|---|---|
| Shell from the MacBook/phone | `ssh alexponce@strix` (Tailscale SSH, no keys needed on the tailnet) or `mosh strix` for flaky links |
| VS Code from anywhere | Remote-SSH to `strix`; or once: `code tunnel user login` then `code tunnel service install`, after which vscode.dev and the desktop app reach the machine without SSH |
| Full desktop, fast | System Settings > Remote Desktop: enable, set a password; connect with any RDP client to `strix:3389` over the tailnet. Needs the desktop session to be logged in (auto-login is on) |
| Full desktop from a browser/Chromebook/phone | Chrome Remote Desktop: open https://remotedesktop.google.com/headless once, "Set up via SSH" > Debian Linux, paste the printed command in a terminal here. It runs its own virtual Plasma session (separate from the monitor's session) |
| A web app (Jupyter, Shiny, CVAT) on the laptop | `tailscale serve --bg 8888` then open `https://strix.<tailnet>.ts.net` |
| Wake the machine when it is off | WoL is enabled on the wired NIC; send a magic packet from any device on the home LAN (or a Tailscale peer at home) |
| Low-latency GUI (optional) | Sunshine host + Moonlight client; not installed by default |

Rule of thumb: everything above works only for devices in your Tailscale network. ufw blocks the rest.

## Window management

Set by the scripts: Meta = launcher, Meta+Enter = terminal, Meta+1..5 = workspaces CODE / WEB / SCIENCE / COMM / MISC, Meta+Ctrl+Left/Right = previous/next workspace, Meta+Shift+S = screenshot region, Meta+W = overview. Built in: Meta+Left/Right halves, Meta+Up maximize, two arrows for a quarter, drag to edges/corners, Meta+T tiling-zone editor, Meta+E Dolphin, Meta+D show desktop, Meta+V clipboard history, Meta+. emoji.

Window rules (System Settings > Window Management > Window Rules) send VS Code/Ghostty/Cursor to CODE, Chrome to WEB, RStudio/Positron/Jupyter to SCIENCE, Zoom/Teams/WhatsApp to COMM. Edit there if you prefer another split; the scripts never overwrite an existing rules file.

Auto-tiling when you want it: System Settings > Window Management > KWin Scripts > tick **Polonium** (installed, off). Untick to go back to a normal desktop. Try it for a week before deciding; Plasma's manual snapping plus window rules is often enough.

## The visual design system (what the scripts aim for, and what to keep doing by hand)

Modern, minimal, unmistakably Plasma, never a Windows or macOS imitation. Native features only: Breeze Dark with the accent colour taken from the wallpaper, Papirus icons, Inter for UI, JetBrainsMono for code, borderless windows, one floating icon-only panel, KRunner instead of a start menu, an empty desktop, named workspaces. Third-party themes, Klassy, Material-You colour daemons and panel widgets are deliberately left out: each is one Plasma update away from breaking.

By hand, once: pick a calm wallpaper (abstract, gradient, architecture; no logos), put it at `~/Pictures/wallpaper.jpg`, set `WALLPAPER` in `config.env`, `./bootstrap.sh 30` applies it to desktop, lock screen and login screen. Then: System Tray > Configure > hide everything you do not glance at; Chrome > Settings > Appearance > "Use system title bar and borders" on and theme "Device" (follows Plasma dark mode); VS Code theme stays "Visual Studio Dark" or any tonally close dark theme.

## Passwords and keys

KWallet (installed by default) stores Chrome, Wi-Fi and SSH passphrases; `kwalletmanager` shows what is in it. The SSH agent runs as a user service and asks through KDE's askpass, so a key passphrase is typed once per login. No password manager is installed; Bitwarden (Flatpak `com.bitwarden.desktop`) is the usual choice if you want one, and its SSH agent can replace the built-in one later.

## Markdown

- Double-click a `.md`: Mark Text (WYSIWYG). Right-click > Open with Okular or Kate for read-only.
- Notes vault: Obsidian (Flatpak); point it at `/data/notes` or `~/Documents/notes`.
- Terminal: `glow README.md`, `glow -p` for a pager.
- VS Code: Markdown Preview Enhanced and Mermaid extensions are installed.

## UTHSC VPN

KDE network applet > Add connection > "OpenConnect (Cisco AnyConnect)" > gateway `UTHSCVPN1.UTHSC.EDU` (backup `UTHSCVPN2.UTHSC.EDU`); the SAML/Duo login opens in a window. If the university enforces ISE posture and openconnect is refused, download the Linux Cisco Secure Client from the VPN portal and run its `vpn_install.sh`.

## Vendor downloads behind forms (set the URL in `config.env`, re-run the module)

- ChimeraX (`CHIMERAX_DEB_URL`): https://www.rbvi.ucsf.edu/chimerax/download.html (Ubuntu .deb, registration) then `./bootstrap.sh 50`
- MEGA 12 (`MEGA_DEB_URL`): https://www.megasoftware.net/ (Ubuntu .deb, GUI)
- Cursor (`CURSOR_DEB_URL`): https://cursor.com/downloads (x64 .deb) then `./bootstrap.sh 40`
- RStudio is already pinned in `config.env`; bump the URL when a new release appears at https://docs.posit.co/ide/user/

## Data restore from the rescue drive

```bash
ls /mnt/winrescue/data            # Desktop Documents LIBS_Data Pictures Downloads Akodon_repo dotfiles
rsync -avh --info=progress2 /mnt/winrescue/data/LIBS_Data/ /data/libs/
rsync -avh --info=progress2 /mnt/winrescue/data/Desktop/Onteko/ /data/onteko/
rsync -avh --info=progress2 /mnt/winrescue/data/Documents/Seed_LIBS_Classification/ /data/seed/Seed_LIBS_Classification/
rsync -avh /mnt/winrescue/data/Documents/ ~/Documents/ --exclude Seed_LIBS_Classification
rsync -avh /mnt/winrescue/data/Pictures/ ~/Pictures/
rsync -avh /mnt/winrescue/data/dotfiles/.claude/projects/ ~/.claude/projects/      # Claude Code memory per project
# secrets: extract secrets.7z into ~/.ssh (chmod 600 id_ed25519) and ~/.claude/.credentials.json etc.
```

Old WSL home, if something is missing: `sudo mkdir /srv/wsl && sudo tar -xpf /mnt/winrescue/wsl/ubuntu-2404.tar -C /srv/wsl --numeric-owner`, then browse `/srv/wsl/home/alex_ubuntu`.
