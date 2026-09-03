#!/usr/bin/env bash
# 90-verify.sh - pass/fail table for the whole setup. Never fixes anything.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"
[[ -x "$HOME/.local/share/fnm/fnm" ]] && eval "$("$HOME/.local/share/fnm/fnm" env --shell bash)" 2>/dev/null

pass=0; fail=0; rows=()
check() {  # check NAME COMMAND...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then rows+=("PASS  $name"); ((pass++)); else rows+=("FAIL  $name"); ((fail++)); fi
}
ver() { "$@" 2>/dev/null | head -n1 | tr -d '\r' | cut -c1-60; }
SHELL_WANT="${LOGIN_SHELL:-bash}"

check "GPU: xe driver bound"                bash -c "lspci -k | grep -A3 -i 'VGA.*Intel' | grep -q 'xe'"
check "GPU: VA-API (iHD) decode"            bash -c "vainfo 2>/dev/null | grep -q VAEntrypointVLD"
check "GPU: OpenGL renderer Intel"          bash -c "glxinfo -B 2>/dev/null | grep -qi 'intel'"
[[ "${ENABLE_INTEL_COMPUTE:-yes}" == "yes" ]] && check "GPU: OpenCL/Level Zero (clinfo)" bash -c "clinfo -l 2>/dev/null | grep -qi intel"
check "Storage: root is btrfs"               bash -c "[[ \$(findmnt -no FSTYPE /) == btrfs ]]"
check "Storage: /var/lib/docker on @docker"  bash -c "findmnt -no OPTIONS /var/lib/docker | grep -q subvol=/@docker"
check "Storage: $DATA_MOUNT mounted"         mountpoint -q "$DATA_MOUNT"
check "Storage: $BACKUP_MOUNT mounted"       mountpoint -q "$BACKUP_MOUNT"
check "Storage: zram swap active"            bash -c "swapon --show | grep -q zram"
[[ "${ENABLE_SNAPSHOTS:-yes}" == "yes" ]] && check "Snapshots: timeshift has snapshots" bash -c "sudo timeshift --list 2>/dev/null | grep -qE '^[0-9]+ +>'"
[[ "${ENABLE_SNAPSHOTS:-yes}" == "yes" ]] && check "Snapshots: grub-btrfsd running" systemctl is-active --quiet grub-btrfsd
[[ "${ENABLE_BTRBK:-yes}" == "yes" ]] && check "Backup: btrbk timer enabled" systemctl is-enabled --quiet btrbk.timer
[[ "${ENABLE_RESTIC:-yes}" == "yes" ]] && check "Backup: restic timers + repo readable" bash -c "systemctl is-enabled --quiet restic-backup.timer && systemctl is-enabled --quiet restic-check.timer && sudo restic -r $BACKUP_MOUNT/restic -p /etc/restic/password snapshots"
check "Secrets: ssh key present"             test -f "$HOME/.ssh/id_ed25519"
check "Shell: login shell is $SHELL_WANT"    bash -c "[[ \$(getent passwd $TARGET_USER | cut -d: -f7) == */$SHELL_WANT ]]"
check "Shell: starship zoxide fzf rg fd bat eza lazygit tmux ghostty" bash -c "for t in starship zoxide fzf rg fd bat eza lazygit tmux ghostty; do command -v \$t >/dev/null || exit 1; done"
check "Shell: yazi lazydocker glow fastfetch btop direnv" bash -c "for t in yazi lazydocker glow fastfetch btop direnv; do command -v \$t >/dev/null || exit 1; done"
check "Shell: ssh-agent user service"        systemctl --user is-active --quiet ssh-agent.service
check "Font: JetBrainsMono Nerd Font + Inter" bash -c "fc-list | grep -qi 'JetBrainsMono Nerd' && fc-list | grep -qi 'Inter'"
check "Desktop: flathub remote"              bash -c "flatpak remote-list | grep -q flathub"
check "Desktop: Speech Note, Mark Text, Obsidian flatpaks" bash -c "flatpak info net.mkiol.SpeechNote && flatpak info com.github.marktext.marktext && flatpak info md.obsidian.Obsidian"
check "Desktop: Chrome default browser, Zoom" bash -c "xdg-settings get default-web-browser | grep -qi chrome && command -v zoom"
check "Desktop: Papirus icons, Meta -> KRunner" bash -c "[[ -d /usr/share/icons/Papirus-Dark ]] && grep -q 'org.kde.krunner' $HOME/.config/kwinrc"
check "Desktop: 5 named workspaces"          bash -c "[[ \$(kreadconfig6 --file kwinrc --group Desktops --key Number) == 5 ]]"
check "Desktop: accent colour from wallpaper" bash -c "[[ \$(kreadconfig6 --file kdeglobals --group General --key AccentColorFromWallpaper) == true ]]"
[[ "${ENABLE_KLASSY:-yes}" == "yes" ]] && check "Desktop: Klassy window style active" bash -c "dpkg -s klassy && kreadconfig6 --file kdeglobals --group KDE --key widgetStyle | grep -qi klassy"
check "Desktop: window rules present"        grep -q 'linux-setup' "$HOME/.config/kwinrulesrc"
check "Desktop: agent-runner plugin installed" bash -c "[[ -L $HOME/.local/share/krunner/dbusplugins/agentrunner.desktop && -x $HOME/.local/bin/agent-runner ]] && python3 -c 'import dbus, gi'"
[[ "${ENABLE_TILING_SCRIPT:-yes}" == "yes" ]] && check "Desktop: Polonium KWin script present" bash -c "kpackagetool6 --type=KWin/Script --list 2>/dev/null | grep -q polonium"
check "Dev: VS Code + extensions (>= 20)"    bash -c "[[ \$(code --list-extensions 2>/dev/null | wc -l) -ge 20 ]]"
check "Dev: docker info (group active?)"     docker info
check "Dev: docker compose plugin"           docker compose version
[[ "${ENABLE_APPTAINER:-yes}" == "yes" ]] && check "Dev: apptainer" apptainer --version
[[ "${ENABLE_DISTROBOX:-yes}" == "yes" ]] && check "Dev: distrobox 'arch' exists" bash -c "distrobox list | grep -q '| arch '"
check "Dev: gh, git, delta"                  bash -c "command -v gh && command -v git && command -v delta"
check "Dev: node $NODE_VERSION via fnm"      bash -c "node --version | grep -q '^v${NODE_VERSION}\.'"
check "Dev: uv, micromamba"                  bash -c "command -v uv && command -v micromamba"
check "Dev: uv tools (labelme, radian, ruff, jupyter)" bash -c "command -v labelme && command -v radian && command -v ruff && command -v jupyter"
check "Agents: claude, codex, agy, copilot"  bash -c "command -v claude && command -v codex && command -v agy && command -v copilot"
check "Agents: machine guide linked"         bash -c "[[ -L $HOME/.claude/CLAUDE.md && -L $HOME/.codex/AGENTS.md ]]"
[[ "${ENABLE_AGENT_SUDO:-yes}" == "yes" ]] && check "Agents: passwordless admin sudo" sudo -n apt-get --version
check "Agents: bubblewrap for sandboxes"     command -v bwrap
check "R: Rscript 4.6+"                      bash -c "Rscript -e 'quit(status = as.integer(getRversion() < \"4.6.0\"))'"
check "R: bspm (r2u binaries) installed"     Rscript -e 'quit(status = as.integer(!requireNamespace("bspm", quietly = TRUE)))'
check "R: tidyverse, shiny, languageserver load" Rscript -e 'suppressPackageStartupMessages({library(tidyverse); library(shiny); library(languageserver)})'
check "R: DESeq2 loads (Bioconductor)"       Rscript -e 'suppressPackageStartupMessages(library(DESeq2))'
check "R: RStudio, Positron, Quarto"         bash -c "command -v rstudio && command -v positron && command -v quarto"
check "R: TinyTeX"                           test -d "$HOME/.TinyTeX"
check "Science: pymol, duckdb"               bash -c "command -v pymol && command -v duckdb"
check "Remote: tailscale logged in"          bash -c "tailscale status 2>/dev/null | grep -q '$HOSTNAME_TARGET'"
check "Remote: sshd active, keys only"       bash -c "systemctl is-active --quiet ssh && sudo sshd -T | grep -q 'passwordauthentication no'"
check "Remote: fail2ban, ufw active"         bash -c "systemctl is-active --quiet fail2ban && sudo ufw status | grep -q 'Status: active'"
check "Remote: mosh, krdp"                   bash -c "command -v mosh && dpkg -s krdp"
[[ "${ENABLE_CRD:-yes}" == "yes" ]] && check "Remote: Chrome Remote Desktop host + session" bash -c "dpkg -s chrome-remote-desktop && test -f $HOME/.chrome-remote-desktop-session"
check "Dotfiles: bashrc/zshrc/ghostty/ssh config linked" bash -c "[[ -L $HOME/.bashrc && -L $HOME/.zshrc && -L $HOME/.config/ghostty/config && -L $HOME/.ssh/config ]]"
check "Envs: conda env juq-ana exists"       bash -c "MAMBA_ROOT_PREFIX=$HOME/micromamba micromamba env list | grep -q juq-ana"
check "Envs: work dir with repos"            bash -c "[[ \$(ls -1d $WORK_DIR/*/ 2>/dev/null | wc -l) -ge 1 ]]"

printf '\n%s\n' "== linux-setup verify ($(date +%F' '%H:%M)) =="
printf '%s\n' "${rows[@]}"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
printf 'versions: kernel %s | %s | %s | %s | %s | %s\n' "$(uname -r)" "$(ver code --version)" "$(ver Rscript --version)" "$(ver docker --version)" "$(ver uv --version)" "$(ver claude --version)"
(( fail == 0 ))
