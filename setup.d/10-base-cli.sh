#!/usr/bin/env bash
# 10-base-cli.sh - core packages, modern CLI tools, Nerd Font, zsh as login shell
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config

apt_install_list "$LISTS_DIR/apt-base.txt"

# Ubuntu renames these binaries; give them their upstream names
sudo install -d /usr/local/bin
[[ -x /usr/bin/fdfind && ! -e /usr/local/bin/fd  ]] && sudo ln -s /usr/bin/fdfind /usr/local/bin/fd
[[ -x /usr/bin/batcat && ! -e /usr/local/bin/bat ]] && sudo ln -s /usr/bin/batcat /usr/local/bin/bat

# JetBrainsMono Nerd Font (icons for starship/eza/lazygit)
FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
if [[ -z "$(fc-list 2>/dev/null | grep -i 'JetBrainsMono Nerd Font')" ]]; then
  url="$(github_latest_asset ryanoasis/nerd-fonts '/JetBrainsMono\.zip$' || true)"
  if [[ -n "$url" ]]; then
    tmp="$(mktemp -d)"
    curl -fL --retry 3 -o "$tmp/f.zip" "$url" && mkdir -p "$FONT_DIR" && unzip -q -o "$tmp/f.zip" -d "$FONT_DIR" -x 'LICENSE*' 'README*' || warn "nerd font download failed"
    rm -rf "$tmp"; fc-cache -f >/dev/null
  else
    warn "could not resolve Nerd Font release asset"
  fi
fi

# login shell: bash by default (HPC docs, agents and copy-pasted snippets all assume it); zsh if LOGIN_SHELL=zsh
want="$(command -v "${LOGIN_SHELL:-bash}" || true)"
cur="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
if [[ -n "$want" && "$cur" != "$want" ]]; then
  sudo chsh -s "$want" "$TARGET_USER"
  log "login shell set to $want for $TARGET_USER"
fi

# tealdeer cache, atuin db init are harmless if repeated
have tldr && tldr --update >/dev/null 2>&1 || true

# inotify instance limit. The kernel default of 128 is a 2000s number and this desktop passed it:
# KDE reported "140% of instances" with 180 in use. Watches were at 0%, so raising
# max_user_watches, which is the advice every search result gives, would have changed nothing.
#
# Instances are per open inotify fd, not per watched file. Electron and Node processes take
# several each: the ChatGPT app plus its codex node_repl children accounted for roughly 52 on
# their own, alongside plasmashell (10), spotify (10), chrome and code (4 each).
#
# 1024 is headroom, not a fix for a leak. If this trips again, count instances per process
# before raising it further:
#   for p in /proc/[0-9]*; do n=$(ls -l $p/fd 2>/dev/null | grep -c anon_inode:inotify);
#     [ "$n" -gt 0 ] && echo "$n $(cat $p/comm)"; done | sort -rn | head
write_file_sudo /etc/sysctl.d/99-inotify.conf 0644 <<'EOF'
fs.inotify.max_user_instances = 1024
EOF
sudo sysctl -q --system >/dev/null 2>&1 || warn "could not apply sysctl; run: sudo sysctl --system"

# sensors for btop
sudo sensors-detect --auto >/dev/null 2>&1 || true
log "base CLI done"
