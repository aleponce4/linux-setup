#!/usr/bin/env bash
# 70-dotfiles.sh - symlink dotfiles/ into $HOME, git identity, VS Code settings, Claude settings, work dirs
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config

link_dotfile bashrc           "$HOME/.bashrc"
link_dotfile zshrc            "$HOME/.zshrc"
link_dotfile tmux.conf        "$HOME/.tmux.conf"
link_dotfile starship.toml    "$HOME/.config/starship.toml"
link_dotfile ghostty/config   "$HOME/.config/ghostty/config"
link_dotfile ssh/config       "$HOME/.ssh/config"
link_dotfile claude/settings.json "$HOME/.claude/settings.json"
link_dotfile vscode/settings.json "$HOME/.config/Code/User/settings.json"
# one machine guide for every agent
link_dotfile agents/MACHINE.md "$HOME/.claude/CLAUDE.md"
link_dotfile agents/MACHINE.md "$HOME/.codex/AGENTS.md"
link_dotfile agents/MACHINE.md "$HOME/.config/agents/MACHINE.md"
chmod 700 "$HOME/.ssh"; chmod 600 "$HOME/.ssh/config"

# git identity and defaults (kept out of dotfiles so the repo stays generic)
git config --global user.name  "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global push.autoSetupRemote true
git config --global core.editor "code --wait"
if have delta; then
  git config --global core.pager delta
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
  git config --global delta.side-by-side false
fi
have gh && gh auth status >/dev/null 2>&1 && gh auth setup-git >/dev/null 2>&1 || true

# work layout
mkdir -p "$WORK_DIR" "$HOME/.local/bin"
[[ -d "$DATA_MOUNT" && ! -e "$HOME/data" ]] && ln -sfn "$DATA_MOUNT" "$HOME/data"

# ssh-agent as a user service, keys unlocked through KDE's askpass (KWallet remembers passphrases)
mkdir -p "$HOME/.config/systemd/user" "$HOME/.config/environment.d"
cat >"$HOME/.config/systemd/user/ssh-agent.service" <<'EOF'
[Unit]
Description=SSH key agent
[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket
ExecStart=/usr/bin/ssh-agent -D -a $SSH_AUTH_SOCK
[Install]
WantedBy=default.target
EOF
cat >"$HOME/.config/environment.d/10-ssh-agent.conf" <<'EOF'
SSH_AUTH_SOCK=${XDG_RUNTIME_DIR}/ssh-agent.socket
SSH_ASKPASS=/usr/bin/ksshaskpass
SSH_ASKPASS_REQUIRE=prefer
EOF
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now ssh-agent.service 2>/dev/null || warn "ssh-agent user service starts at next login"

log "dotfiles linked. Open a new terminal to pick everything up."
