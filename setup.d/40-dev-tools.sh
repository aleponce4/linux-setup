#!/usr/bin/env bash
# 40-dev-tools.sh - VS Code + extensions, Cursor (optional), Docker Engine + compose, Apptainer, GitHub CLI,
#                   Node via fnm + npm CLIs (Codex, Copilot, OpenCode), uv + micromamba, Claude Code, Antigravity CLI,
#                   terminal extras (yazi, lazydocker), passwordless admin sudo for agents
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"
mkdir -p "$HOME/.local/bin"

apt_install_list "$LISTS_DIR/apt-dev.txt"

# ---- VS Code (Microsoft repo) + extensions ----
add_apt_repo microsoft-code https://packages.microsoft.com/keys/microsoft.asc \
  "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft-code.gpg] https://packages.microsoft.com/repos/code stable main"
apt_install code
if have code; then
  installed="$(code --list-extensions 2>/dev/null | tr 'A-Z' 'a-z')"
  while read -r ext; do
    grep -qx "${ext,,}" <<<"$installed" || code --install-extension "$ext" --force >/dev/null 2>&1 || warn "vscode extension failed: $ext"
  done < <(read_list "$LISTS_DIR/vscode-extensions.txt")
fi

# ---- Cursor (only if a .deb URL is configured) ----
if [[ -n "${CURSOR_DEB_URL:-}" ]] && ! have cursor; then download_deb "$CURSOR_DEB_URL"; fi

# ---- Docker Engine + compose (official repo, deb822) ----
if ! have docker; then
  sudo install -m 0755 -d /etc/apt/keyrings
  [[ -f /etc/apt/keyrings/docker.asc ]] || sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  write_file_sudo /etc/apt/sources.list.d/docker.sources 0644 <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  _APT_UPDATED=""
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
usergroup_add docker
systemd_enable_now docker
write_file_sudo /etc/docker/daemon.json 0644 <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" },
  "storage-driver": "overlay2"
}
EOF

# ---- Apptainer (HPC-style containers, same tool as on ISAAC) ----
if [[ "${ENABLE_APPTAINER:-yes}" == "yes" ]] && ! have apptainer; then
  if apt-cache show apptainer >/dev/null 2>&1; then
    apt_install apptainer
  else
    url="$(github_latest_asset apptainer/apptainer 'apptainer_[0-9.]+_amd64\.deb$' || true)"
    [[ -n "$url" ]] && download_deb "$url" || warn "apptainer not resolvable from apt or GitHub"
  fi
fi

# ---- GitHub CLI ----
add_apt_repo githubcli https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main"
apt_install gh

# ---- Node via fnm + npm globals (Codex CLI, Copilot CLI, OpenCode, netlify) ----
if [[ ! -x "$HOME/.local/share/fnm/fnm" ]]; then
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell >/dev/null 2>&1 || warn "fnm install failed"
fi
if [[ -x "$HOME/.local/share/fnm/fnm" ]]; then
  eval "$("$HOME/.local/share/fnm/fnm" env --shell bash)"
  fnm list 2>/dev/null | grep -q "v${NODE_VERSION}\." || fnm install "$NODE_VERSION" >/dev/null
  fnm default "$NODE_VERSION" >/dev/null
  npm config set fund false >/dev/null 2>&1 || true
  while read -r pkg; do
    npm ls -g --depth=0 2>/dev/null | grep -q " ${pkg}@" || npm install -g "$pkg" >/dev/null 2>&1 || warn "npm -g failed: $pkg"
  done < <(read_list "$LISTS_DIR/npm-globals.txt")
else
  warn "fnm missing; Node and npm globals skipped"
fi

# ---- uv (Python versions, projects, tools) + micromamba (named conda envs) ----
have uv || curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || warn "uv install failed"
if ! have micromamba; then
  (cd /tmp && curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba && mv bin/micromamba "$HOME/.local/bin/" && rmdir bin) || warn "micromamba install failed"
fi
if have uv; then
  for v in $PYTHON_VERSIONS; do uv python install "$v" >/dev/null 2>&1 || warn "uv python install $v failed"; done
  while read -r tool; do
    uv tool list 2>/dev/null | grep -q "^$tool " || uv tool install "$tool" >/dev/null 2>&1 || warn "uv tool failed: $tool"
  done < <(read_list "$LISTS_DIR/python-uv-tools.txt")
fi

# ---- AI agents: Claude Code (native installer) and Antigravity CLI (Google's installer script) ----
have claude || curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 || warn "Claude Code install failed"
if ! have agy; then
  curl -fsSL https://antigravity.google/cli | bash >/dev/null 2>&1 \
    || curl -fsSL https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/install.sh | bash >/dev/null 2>&1 \
    || warn "Antigravity CLI install failed; see https://antigravity.google/cli"
fi

# ---- terminal extras not in apt: yazi (file manager), lazydocker ----
if ! have yazi; then
  url="$(github_latest_asset sxyazi/yazi 'yazi-x86_64-unknown-linux-gnu\.zip$' || true)"
  if [[ -n "$url" ]]; then
    tmp="$(mktemp -d)"
    curl -fL -o "$tmp/yazi.zip" "$url" && unzip -q "$tmp/yazi.zip" -d "$tmp" && install -m 0755 "$tmp"/yazi-x86_64-unknown-linux-gnu/yazi "$tmp"/yazi-x86_64-unknown-linux-gnu/ya "$HOME/.local/bin/" || warn "yazi install failed"
    rm -rf "$tmp"
  fi
fi
if ! have lazydocker; then
  url="$(github_latest_asset jesseduffield/lazydocker 'Linux_x86_64\.tar\.gz$' || true)"
  if [[ -n "$url" ]]; then
    tmp="$(mktemp -d)"
    curl -fL -o "$tmp/ld.tgz" "$url" && tar -xzf "$tmp/ld.tgz" -C "$tmp" lazydocker && install -m 0755 "$tmp/lazydocker" "$HOME/.local/bin/" || warn "lazydocker install failed"
    rm -rf "$tmp"
  fi
fi

# ---- passwordless sudo for a bounded set of admin commands (agents administer the machine) ----
if [[ "${ENABLE_AGENT_SUDO:-yes}" == "yes" ]]; then
  write_file_sudo /etc/sudoers.d/90-agent-admin 0440 <<EOF
# linux-setup: let $TARGET_USER (and the AI agents running as that user) administer packages and services without a password.
# A future Btrfs root may add pre-apt Timeshift snapshots; the current ext4 root relies on restic backups.
Cmnd_Alias AGENT_ADMIN = /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dpkg, /usr/bin/flatpak, /usr/bin/snap, \\
    /usr/bin/systemctl, /usr/bin/journalctl, /usr/bin/timeshift, /usr/bin/btrbk, /usr/bin/tailscale, \\
    /usr/sbin/ufw, /usr/bin/fwupdmgr, /usr/bin/apptainer, /usr/sbin/update-grub, /usr/bin/udevadm
$TARGET_USER ALL=(root) NOPASSWD: AGENT_ADMIN
EOF
  if ! sudo visudo -cf /etc/sudoers.d/90-agent-admin >/dev/null; then
    sudo rm -f /etc/sudoers.d/90-agent-admin; warn "sudoers rule rejected by visudo; removed"
  fi
else
  sudo rm -f /etc/sudoers.d/90-agent-admin
fi

log "dev tools done. Manual: 'gh auth login', 'claude' (login), 'codex login', 'agy' (login), 'copilot' then /login. Re-login for the docker group."
