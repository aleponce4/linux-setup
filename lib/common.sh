#!/usr/bin/env bash
# lib/common.sh - helpers shared by every module. Source it; do not run it.
[[ -n "${_COMMON_SH:-}" ]] && return 0
_COMMON_SH=1

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LISTS_DIR="$REPO_DIR/lists"
RUN_LOG="${RUN_LOG:-/dev/null}"
export DEBIAN_FRONTEND=noninteractive

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$RUN_LOG" >&2; }
warn() { log "WARN: $*"; }
die()  { log "ERROR: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

load_config() {
  # shellcheck disable=SC1091
  source "$REPO_DIR/config.env"
  TARGET_USER="${TARGET_USER:-$USER}"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$TARGET_HOME" ]] || die "user $TARGET_USER does not exist"
  export TARGET_USER TARGET_HOME
}

# read_list FILE -> items, ignoring blanks and '#' comments
read_list() {
  local f="$1"
  [[ -f "$f" ]] || { warn "list not found: $f"; return 0; }
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f" | grep -v '^$'
}

apt_update_once() {
  if [[ -z "${_APT_UPDATED:-}" ]]; then
    sudo apt-get update -qq
    _APT_UPDATED=1
  fi
}

# apt_install pkg... -> installs only the ones missing; unknown package names are reported, not fatal
apt_install() {
  local missing=() p
  for p in "$@"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
  done
  ((${#missing[@]})) || return 0
  apt_update_once
  log "apt install: ${missing[*]}"
  if ! sudo apt-get install -y -qq --no-install-recommends "${missing[@]}"; then
    warn "batch install failed; retrying one by one"
    for p in "${missing[@]}"; do
      sudo apt-get install -y -qq --no-install-recommends "$p" || warn "could not install $p"
    done
  fi
}

apt_install_list() {
  local items
  mapfile -t items < <(read_list "$1")
  ((${#items[@]})) || return 0
  apt_install "${items[@]}"
}

# add_apt_repo NAME KEY_URL "deb [arch=amd64 signed-by=/etc/apt/keyrings/NAME.gpg] URL SUITE COMPONENTS"
add_apt_repo() {
  local name="$1" key_url="$2" line="$3"
  sudo install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f "/etc/apt/keyrings/$name.gpg" ]]; then
    curl -fsSL "$key_url" | sudo gpg --dearmor -o "/etc/apt/keyrings/$name.gpg"
    sudo chmod a+r "/etc/apt/keyrings/$name.gpg"
  fi
  if [[ ! -f "/etc/apt/sources.list.d/$name.list" ]] || ! grep -qF "$line" "/etc/apt/sources.list.d/$name.list"; then
    echo "$line" | sudo tee "/etc/apt/sources.list.d/$name.list" >/dev/null
    _APT_UPDATED=""
  fi
}

# download_deb URL -> installs the .deb (apt resolves dependencies); skips if URL empty
download_deb() {
  local url="$1" tmp
  [[ -n "$url" ]] || { warn "empty URL, skipping"; return 0; }
  tmp="$(mktemp --suffix=.deb)"
  log "downloading $url"
  curl -fL --retry 3 -o "$tmp" "$url" || { warn "download failed: $url"; rm -f "$tmp"; return 1; }
  sudo apt-get install -y -qq "$tmp" || warn "install failed: $url"
  rm -f "$tmp"
}

# github_latest_asset OWNER/REPO REGEX -> URL of the first matching asset in the latest release
github_latest_asset() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 | grep -E "$2" | head -n1
}

# ensure_line FILE LINE [MATCH_REGEX] -> appends LINE if no line matches (default: exact LINE)
ensure_line() {
  local file="$1" line="$2" re="${3:-}"
  [[ -n "$re" ]] || re="^$(printf '%s' "$line" | sed 's/[][\.*^$/]/\\&/g')$"
  if [[ -f "$file" ]] && grep -qE "$re" "$file"; then return 0; fi
  if [[ -w "$file" || ( ! -e "$file" && -w "$(dirname "$file")" ) ]]; then
    printf '%s\n' "$line" >>"$file"
  else
    printf '%s\n' "$line" | sudo tee -a "$file" >/dev/null
  fi
}

# write_file_sudo PATH MODE <<EOF ... EOF  (only rewrites when content differs)
write_file_sudo() {
  local path="$1" mode="${2:-0644}" tmp
  tmp="$(mktemp)"; cat >"$tmp"
  if ! sudo cmp -s "$tmp" "$path" 2>/dev/null; then
    sudo install -m "$mode" -D "$tmp" "$path"
    log "wrote $path"
  fi
  rm -f "$tmp"
}

# link_dotfile SRC(relative to dotfiles/) DEST(absolute) -> symlink, backing up a real file once
link_dotfile() {
  local src="$REPO_DIR/dotfiles/$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" && ! -L "$dest" ]]; then mv "$dest" "$dest.pre-linux-setup"; fi
  ln -sfn "$src" "$dest"
}

flatpak_install() {
  local id
  for id in "$@"; do
    flatpak info "$id" >/dev/null 2>&1 || flatpak install -y --noninteractive flathub "$id" || warn "flatpak failed: $id"
  done
}

usergroup_add() { id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx "$1" || sudo usermod -aG "$1" "$TARGET_USER"; }

systemd_enable_now() { systemctl is-enabled --quiet "$1" 2>/dev/null && systemctl is-active --quiet "$1" || sudo systemctl enable --now "$1"; }
