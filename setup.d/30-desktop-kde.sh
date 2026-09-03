#!/usr/bin/env bash
# 30-desktop-kde.sh - the curated Plasma layer, native features only:
#   Flatpak/Flathub + desktop apps, Chrome as default browser, look (Breeze Dark, accent from wallpaper, Papirus, Inter,
#   JetBrainsMono, borderless windows), one floating icon-only panel, KRunner on Meta + the agent-runner plugin,
#   five named workspaces with window rules, Windows-habit shortcuts, wallpaper on desktop/lock/login,
#   Polonium tiling (installed, off), ydotool for dictation, optional Dropbox/OneDrive/KVM behind switches.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config

apt_install_list "$LISTS_DIR/apt-desktop.txt"

# ---- Flatpak + Flathub (leaf GUI apps only; IDEs and anything touching the toolchain stay apt/.deb) ----
flatpak remote-list 2>/dev/null | grep -q '^flathub' || sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
mapfile -t fps < <(read_list "$LISTS_DIR/flatpaks.txt")
if ((${#fps[@]})); then flatpak_install "${fps[@]}"; fi

# ---- Google Chrome (the .deb registers Google's apt repo), Zoom, glow ----
have google-chrome-stable || download_deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
have zoom || download_deb https://zoom.us/client/latest/zoom_amd64.deb
if ! have glow; then
  url="$(github_latest_asset charmbracelet/glow '_amd64\.deb$' || true)"
  [[ -n "$url" ]] && download_deb "$url" || warn "could not resolve glow .deb"
fi

# ---- optional cloud clients / VM stack (off by default) ----
if [[ "${ENABLE_DROPBOX:-no}" == "yes" && ! -d "$HOME/.dropbox-dist" ]]; then
  (cd "$HOME" && curl -fsL "https://www.dropbox.com/download?plat=lnx.x86_64" | tar xzf -) && log "Dropbox daemon unpacked" || warn "Dropbox download failed"
  apt_install python3-gpg
fi
if [[ "${ENABLE_ONEDRIVE:-no}" == "yes" ]] && ! have onedrive; then
  OBS="https://download.opensuse.org/repositories/home:/npreining:/debian-ubuntu-onedrive/xUbuntu_26.04"
  if curl -fsI "$OBS/Release.key" >/dev/null 2>&1; then
    add_apt_repo onedrive "$OBS/Release.key" "deb [signed-by=/etc/apt/keyrings/onedrive.gpg] $OBS/ ./"; apt_install onedrive
  else warn "OBS onedrive repo not reachable"; fi
fi
if [[ "${ENABLE_VM_STACK:-no}" == "yes" ]]; then
  apt_install qemu-system-x86 libvirt-daemon-system libvirt-clients virt-manager swtpm swtpm-tools ovmf virtiofsd
  usergroup_add libvirt; usergroup_add kvm; systemd_enable_now libvirtd
fi

# ---- dictation backend: ydotool daemon as a user service ----
if [[ "${ENABLE_DICTATION:-yes}" == "yes" ]]; then
  usergroup_add input
  write_file_sudo /etc/udev/rules.d/80-uinput.rules 0644 <<'EOF'
KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
EOF
  sudo udevadm control --reload-rules && sudo udevadm trigger --name-match=uinput || true
  mkdir -p "$HOME/.config/systemd/user"
  cat >"$HOME/.config/systemd/user/ydotoold.service" <<'EOF'
[Unit]
Description=ydotool daemon (virtual input for dictation)
[Service]
ExecStart=/usr/bin/ydotoold --socket-path=%t/.ydotool_socket --socket-perm=0600
Restart=on-failure
[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now ydotoold.service 2>/dev/null || warn "ydotoold user service not started (starts at next login)"
  flatpak override --user --socket=session-bus --env=YDOTOOL_SOCKET="/run/user/$(id -u)/.ydotool_socket" net.mkiol.SpeechNote 2>/dev/null || true
fi

# ---- default apps ----
if have google-chrome-stable; then
  xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null || true
  have kwriteconfig6 && kwriteconfig6 --file kdeglobals --group General --key BrowserApplication google-chrome.desktop
fi
have xdg-mime && { xdg-mime default com.github.marktext.marktext.desktop text/markdown 2>/dev/null || true; xdg-mime default okularApplication_pdf.desktop application/pdf 2>/dev/null || true; }

if have kwriteconfig6; then
  # ---- look: Breeze Dark, accent colour from the wallpaper (native), Papirus, Inter, JetBrainsMono, no window borders ----
  have plasma-apply-lookandfeel && plasma-apply-lookandfeel -a org.kde.breezedark.desktop >/dev/null 2>&1 || true
  kwriteconfig6 --file kdeglobals --group General --key AccentColorFromWallpaper true
  kwriteconfig6 --file kdeglobals --group Icons --key Theme Papirus-Dark
  for k in font menuFont toolBarFont; do kwriteconfig6 --file kdeglobals --group General --key "$k" "Inter,10,-1,5,50,0,0,0,0,0"; done
  kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "Inter,8,-1,5,50,0,0,0,0,0"
  kwriteconfig6 --file kdeglobals --group General --key fixed "JetBrainsMono Nerd Font,10,-1,5,50,0,0,0,0,0"
  kwriteconfig6 --file kdeglobals --group WM --key activeFont "Inter,10,-1,5,57,0,0,0,0,0"
  kwriteconfig6 --file kdeglobals --group General --key TerminalApplication ghostty
  kwriteconfig6 --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize None
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSizeAuto false
  kwriteconfig6 --file kcminputrc --group Keyboard --key NumLock 0

  # ---- window behaviour: Windows-style snapping, thumbnail Alt+Tab, overview ----
  kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderMaximize true
  kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderTiling true
  kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderCornerRatio 0.25
  kwriteconfig6 --file kwinrc --group TabBox --key LayoutName thumbnail_grid
  kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled true

  # ---- five named workspaces in one row ----
  kwriteconfig6 --file kwinrc --group Desktops --key Number 5
  kwriteconfig6 --file kwinrc --group Desktops --key Rows 1
  i=1; for n in CODE WEB SCIENCE COMM MISC; do kwriteconfig6 --file kwinrc --group Desktops --key "Name_$i" "$n"; i=$((i+1)); done

  # ---- Meta alone opens KRunner (the launcher); KRunner plugins tuned ----
  kwriteconfig6 --file kwinrc --group ModifierOnlyShortcuts --key Meta "org.kde.krunner,/App,,toggleDisplay"
  kwriteconfig6 --file krunnerrc --group General --key FreeFloating true
  kwriteconfig6 --file krunnerrc --group General --key ActivateWhenTypingOnDesktop true
  for r in krunner_services krunner_shell krunner_calculatorrunner krunner_sessions krunner_bookmarksrunner krunner_recentdocuments krunner_kwin krunner_systemsettings krunner_webshortcuts krunner_placesrunner baloosearch; do
    kwriteconfig6 --file krunnerrc --group Plugins --key "${r}Enabled" true
  done
  kwriteconfig6 --file krunnerrc --group Plugins --key krunner_charrunnerEnabled false
  kwriteconfig6 --file krunnerrc --group Plugins --key krunner_spellcheckEnabled false
  kwriteconfig6 --file baloofilerc --group General --key "exclude folders[\$e]" "\$HOME/data/,\$HOME/micromamba/,\$HOME/.cache/,\$HOME/work/*/node_modules/,\$HOME/work/*/.venv/"
  qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  sleep 2

  # ---- window rules: apps open on their workspace (needs the desktop ids KWin generates after reconfigure) ----
  if [[ ! -f "$HOME/.config/kwinrulesrc" ]]; then
    id1="$(kreadconfig6 --file kwinrc --group Desktops --key Id_1 2>/dev/null || true)"
    id2="$(kreadconfig6 --file kwinrc --group Desktops --key Id_2 2>/dev/null || true)"
    id3="$(kreadconfig6 --file kwinrc --group Desktops --key Id_3 2>/dev/null || true)"
    id4="$(kreadconfig6 --file kwinrc --group Desktops --key Id_4 2>/dev/null || true)"
    if [[ -n "$id1" && -n "$id2" && -n "$id3" && -n "$id4" ]]; then
      cat >"$HOME/.config/kwinrulesrc" <<EOF
[General]
count=4
rules=ls-code,ls-web,ls-science,ls-comm

[ls-code]
Description=linux-setup: editors and terminals on CODE
desktops=$id1
desktopsrule=2
wmclass=code|com.mitchellh.ghostty|cursor
wmclassmatch=3
wmclasscomplete=false
types=1

[ls-web]
Description=linux-setup: browser on WEB
desktops=$id2
desktopsrule=2
wmclass=google-chrome
wmclassmatch=2
wmclasscomplete=false
types=1

[ls-science]
Description=linux-setup: RStudio, Positron, Jupyter on SCIENCE
desktops=$id3
desktopsrule=2
wmclass=rstudio|positron|jupyter
wmclassmatch=3
wmclasscomplete=false
types=1

[ls-comm]
Description=linux-setup: Zoom, Teams, WhatsApp on COMM
desktops=$id4
desktopsrule=2
wmclass=zoom|teams|whatsapp
wmclassmatch=3
wmclasscomplete=false
types=1
EOF
      qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
      log "window rules written (System Settings > Window Management > Window Rules to adjust)"
    else
      warn "workspace ids not available yet (no session?); re-run './bootstrap.sh 30' from the desktop to create the window rules"
    fi
  else
    log "kwinrulesrc exists; leaving your window rules alone"
  fi

  # ---- shortcuts: Meta+Enter terminal, Meta+Shift+S region screenshot, Meta+1..5 workspaces, Meta+Ctrl+arrows ----
  ks() { kwriteconfig6 --file kglobalshortcutsrc "$@"; }
  ks --group services --group com.mitchellh.ghostty.desktop --key _launch "Meta+Return"
  ks --group services --group org.kde.spectacle.desktop --key RectangularRegionScreenShot "Meta+Shift+S,Meta+Shift+Print,Capture Rectangular Region"
  ks --group kwin --key "Switch One Desktop to the Left"  "Meta+Ctrl+Left,,Switch One Desktop to the Left"
  ks --group kwin --key "Switch One Desktop to the Right" "Meta+Ctrl+Right,,Switch One Desktop to the Right"
  for i in 1 2 3 4 5; do
    ks --group kwin --key "Switch to Desktop $i" "Meta+$i,,Switch to Desktop $i"
    ks --group plasmashell --key "activate task manager entry $i" "none,Meta+$i,Activate Task Manager Entry $i"
  done
  systemctl --user restart plasma-kglobalaccel.service 2>/dev/null || true

  # ---- wallpaper on desktop, lock screen and login screen (when WALLPAPER is set) ----
  if [[ -n "${WALLPAPER:-}" && -f "$WALLPAPER" ]]; then
    have plasma-apply-wallpaperimage && plasma-apply-wallpaperimage "$WALLPAPER" >/dev/null 2>&1 || true
    kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$WALLPAPER"
    ext="${WALLPAPER##*.}"
    sudo install -m 0644 "$WALLPAPER" "/usr/share/backgrounds/linux-setup-wallpaper.$ext"
    write_file_sudo /usr/share/sddm/themes/breeze/theme.conf.user 0644 <<EOF
[General]
background=/usr/share/backgrounds/linux-setup-wallpaper.$ext
EOF
    log "wallpaper applied to desktop, lock screen and SDDM"
  fi
fi

# ---- panel layout (one floating bottom panel, icon-only tasks, pinned apps) via the Plasma scripting API ----
if have qdbus6 && [[ -f "$REPO_DIR/dotfiles/kde/panel.js" ]] && [[ ! -f "$HOME/.config/.linux-setup-panel-applied" ]]; then
  if qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$REPO_DIR/dotfiles/kde/panel.js")" >/dev/null 2>&1; then
    touch "$HOME/.config/.linux-setup-panel-applied"; log "panel layout applied (delete ~/.config/.linux-setup-panel-applied to re-apply)"
  else
    warn "plasmashell not reachable (no session?); panel layout skipped, re-run 30 from the desktop"
  fi
fi

# ---- KRunner agent plugin (D-Bus runner): cc/cx/agy/ssh/repo/setup entries ----
apt_install python3-dbus python3-gi
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/krunner/dbusplugins" "$HOME/.local/share/dbus-1/services"
ln -sfn "$REPO_DIR/dotfiles/krunner/agent-runner.py" "$HOME/.local/bin/agent-runner"
chmod +x "$REPO_DIR/dotfiles/krunner/agent-runner.py"
ln -sfn "$REPO_DIR/dotfiles/krunner/agentrunner.desktop" "$HOME/.local/share/krunner/dbusplugins/agentrunner.desktop"
cat >"$HOME/.local/share/dbus-1/services/org.kde.agentrunner.service" <<EOF
[D-BUS Service]
Name=org.kde.agentrunner
Exec=$HOME/.local/bin/agent-runner
EOF
kquitapp6 krunner >/dev/null 2>&1 || true

# ---- Polonium auto-tiling (installed, disabled; toggle in System Settings > Window Management > KWin Scripts) ----
if [[ "${ENABLE_TILING_SCRIPT:-yes}" == "yes" ]] && have kpackagetool6; then
  if ! kpackagetool6 --type=KWin/Script --list 2>/dev/null | grep -q polonium; then
    url="$(github_latest_asset zeroxoneafour/polonium '\.kwinscript$' || true)"
    if [[ -n "$url" ]]; then
      tmp="$(mktemp --suffix=.kwinscript)"; curl -fL -o "$tmp" "$url" && kpackagetool6 --type=KWin/Script -i "$tmp" >/dev/null 2>&1 && log "Polonium installed (disabled)" || warn "Polonium install failed"
      rm -f "$tmp"
    else warn "could not resolve Polonium release"; fi
  fi
  kwriteconfig6 --file kwinrc --group Plugins --key poloniumEnabled false
fi

log "desktop done. Log out/in once for fonts, icons, shortcuts and the Meta key. Manual bits: docs/manual-steps.md"
