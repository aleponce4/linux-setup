#!/usr/bin/env bash
# 46-agent-mcp.sh - MCP servers for Claude Code, registered at user scope.
#
# These are declared here rather than left to ad-hoc `claude mcp add` runs so the agent
# environment is reproducible like the rest of the machine. Registration is idempotent:
# each server is removed and re-added, so editing this file is how you change one.
#
# Scoping note: the filesystem server is pointed at the work and data trees, NOT at $HOME.
# An agent that can read $HOME can read ~/.ssh, ~/.config/restic/password and the browser
# profiles; there is no reason for a code agent to reach those.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"
mkdir -p "$HOME/.local/bin"

have claude || { warn "claude CLI not found; skipping MCP registration"; exit 0; }

# ---- GitHub MCP server (official Go binary) ----
GH_MCP_VER="${GH_MCP_VER:-v1.12.0}"
if ! have github-mcp-server; then
  log "installing github-mcp-server $GH_MCP_VER"
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/gh-mcp.tar.gz" \
      "https://github.com/github/github-mcp-server/releases/download/${GH_MCP_VER}/github-mcp-server_Linux_x86_64.tar.gz"; then
    tar -xzf "$tmp/gh-mcp.tar.gz" -C "$tmp" github-mcp-server 2>/dev/null || tar -xzf "$tmp/gh-mcp.tar.gz" -C "$tmp"
    install -m 0755 "$tmp/github-mcp-server" "$HOME/.local/bin/github-mcp-server" 2>/dev/null \
      || warn "could not install github-mcp-server binary"
  else
    warn "github-mcp-server download failed"
  fi
  rm -rf "$tmp"
fi
ln -sfn "$REPO_DIR/productivity/bin/github-mcp-stdio" "$HOME/.local/bin/github-mcp-stdio"

# ---- register servers ----
# add_mcp <name> <command...>   -- remove first so the definition here always wins
add_mcp() {
  local name="$1"; shift
  claude mcp remove --scope user "$name" >/dev/null 2>&1 || true
  if claude mcp add --scope user "$name" -- "$@" >/dev/null 2>&1; then
    log "mcp: $name"
  else
    warn "mcp: failed to register $name"
  fi
}

FS_ROOTS=("$HOME/work")
[[ -d /data ]] && FS_ROOTS+=(/data)

add_mcp filesystem npx -y @modelcontextprotocol/server-filesystem "${FS_ROOTS[@]}"
add_mcp playwright npx -y @playwright/mcp@latest
add_mcp sequential-thinking npx -y @modelcontextprotocol/server-sequential-thinking

if have gh && gh auth status >/dev/null 2>&1; then
  add_mcp github "$HOME/.local/bin/github-mcp-stdio"
else
  warn "gh not authenticated; skipping the github MCP server (run: gh auth login, then ./bootstrap.sh 46)"
fi

log "registered MCP servers:"
claude mcp list 2>/dev/null | sed 's/^/    /' || true
