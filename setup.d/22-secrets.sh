#!/usr/bin/env bash
# 22-secrets.sh - restore the secrets archive made on Windows (D:\WINRESCUE\secrets.7z): SSH keys, agent credentials,
#                 Wi-Fi passwords (imported into NetworkManager). Asks for the passphrase once; skips silently if the
#                 archive is absent or the key already exists.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config

SEC="/mnt/winrescue/secrets.7z"
ls /mnt/winrescue >/dev/null 2>&1 || true   # trigger the automount
if [[ ! -f "$SEC" ]]; then log "no $SEC; nothing to restore"; exit 0; fi
if [[ -f "$HOME/.ssh/id_ed25519" && -f "$HOME/.claude/.credentials.json" ]]; then log "secrets already restored"; exit 0; fi
apt_install p7zip-full

read -r -s -p "Passphrase for $SEC (Enter to skip): " pw; echo
[[ -n "$pw" ]] || { warn "skipped secrets restore; re-run ./bootstrap.sh 22 later"; exit 0; }
tmp="$(mktemp -d)"; chmod 700 "$tmp"
if ! 7z x -y -p"$pw" -o"$tmp" "$SEC" >/dev/null 2>&1; then rm -rf "$tmp"; die "could not extract $SEC (wrong passphrase?)"; fi
pw=""

# SSH: keys, config is managed by dotfiles (70), known_hosts is handy
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
for f in id_ed25519 id_ed25519.pub known_hosts; do
  [[ -f "$tmp/.ssh/$f" && ! -f "$HOME/.ssh/$f" ]] && install -m 0600 "$tmp/.ssh/$f" "$HOME/.ssh/$f"
done
if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
  touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
  grep -qF "$(cut -d' ' -f2 "$HOME/.ssh/id_ed25519.pub")" "$HOME/.ssh/authorized_keys" || cat "$HOME/.ssh/id_ed25519.pub" >>"$HOME/.ssh/authorized_keys"
fi

# agent credentials (each tool's own store)
[[ -f "$tmp/.claude/.credentials.json" ]] && { mkdir -p "$HOME/.claude"; install -m 0600 "$tmp/.claude/.credentials.json" "$HOME/.claude/.credentials.json"; }
[[ -f "$tmp/.codex/auth.json" ]] && { mkdir -p "$HOME/.codex"; install -m 0600 "$tmp/.codex/auth.json" "$HOME/.codex/auth.json"; }
if [[ -d "$tmp/.gemini" ]]; then mkdir -p "$HOME/.gemini"; cp -n "$tmp/.gemini/"* "$HOME/.gemini/" 2>/dev/null || true; fi

# Wi-Fi profiles exported with netsh (XML) -> NetworkManager connections
n=0
for x in "$tmp"/wifi/*.xml; do
  [[ -f "$x" ]] || continue
  ssid="$(grep -o '<name>[^<]*</name>' "$x" | head -n1 | sed 's/<[^>]*>//g')"
  key="$(grep -o '<keyMaterial>[^<]*</keyMaterial>' "$x" | head -n1 | sed 's/<[^>]*>//g')"
  [[ -n "$ssid" && -n "$key" ]] || continue
  nmcli -t -f NAME con show | grep -qxF "$ssid" && continue
  nmcli con add type wifi con-name "$ssid" ssid "$ssid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$key" >/dev/null 2>&1 && n=$((n+1)) || warn "could not add Wi-Fi '$ssid'"
done
log "imported $n Wi-Fi networks"

rm -rf "$tmp"
log "secrets restored (ssh key, agent credentials). Keep $SEC; it is your off-machine copy."
