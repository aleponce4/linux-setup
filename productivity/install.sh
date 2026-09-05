#!/usr/bin/env bash
# install.sh - component-scoped installer for the separate productivity phase.
set -euo pipefail

PRODUCTIVITY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$PRODUCTIVITY_DIR/.." && pwd)}"
# shellcheck source=productivity/config.sh
source "$PRODUCTIVITY_DIR/config.sh"

DRY_RUN="no"
ASSUME_YES="no"
COMPONENT=""
APT_UPDATED="no"
# The empty sentinel keeps Bash 3.2 + nounset from treating an empty array as unset.
TEMP_PATHS=("")

cleanup() {
  local path
  for path in "${TEMP_PATHS[@]}"; do
    [[ -n "$path" ]] && rm -f -- "$path"
  done
}
trap cleanup EXIT

log() { printf '[productivity] %s\n' "$*"; }
die() { printf '[productivity] ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: ./productivity.sh install <dictation|handlers|research|kando> [--dry-run] [--yes]

--dry-run  print intended changes without changing the machine
--yes      skip the final confirmation (the named component is still required)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="yes" ;;
    --yes) ASSUME_YES="yes" ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $arg" ;;
    *)
      [[ -z "$COMPONENT" ]] || die "only one component may be installed at a time"
      COMPONENT="$arg"
      ;;
  esac
done

[[ -n "$COMPONENT" ]] || { usage >&2; exit 2; }
case "$COMPONENT" in dictation|handlers|research|kando) ;; *) die "unknown component: $COMPONENT" ;; esac

if [[ "$DRY_RUN" != "yes" ]]; then
  [[ "$(uname -s)" == "Linux" ]] || die "installation is supported only on the target Linux workstation"
  [[ $EUID -ne 0 ]] || die "run as your normal user; this script asks for sudo only where needed"
  [[ -r /etc/os-release ]] || die "cannot identify the Linux distribution"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *ubuntu* ]] || die "this phase currently supports Ubuntu/Kubuntu only"
fi

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  [[ "$DRY_RUN" == "yes" ]] || "$@"
}

confirm() {
  local answer
  [[ "$DRY_RUN" == "yes" || "$ASSUME_YES" == "yes" ]] && return 0
  [[ -t 0 ]] || die "confirmation needs a terminal; rerun interactively or pass --yes"
  printf '\nInstall only the %s component? [y/N] ' "$COMPONENT"
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { log "cancelled; no changes made"; exit 0; }
}

show_plan() {
  case "$COMPONENT" in
    handlers)
      cat <<'EOF'
Plan: handlers
  - apt: wl-clipboard, tesseract-ocr + English data, libnotify-bin, kdialog
  - link ai-clipboard and run-notify into ~/.local/bin
  - add four KRunner-visible desktop actions
  - never call an AI provider during installation
EOF
      ;;
    dictation)
      cat <<'EOF'
Plan: dictation
  - ensure the existing Speech Note Flatpak and Ubuntu ydotool package
  - grant /dev/uinput to a dedicated uinput group (logout/login may be needed)
  - use Ubuntu's single ydotool.service with a private runtime socket
  - grant Speech Note access only to that runtime socket
  - do not download a speech model, record audio, synthesize keys, or bind a shortcut
EOF
      ;;
    research)
      cat <<EOF
Plan: research
  - install Zotero through the signed zotero-pkg apt repository
  - download Better BibTeX ${BBT_VERSION} to ~/Downloads and verify SHA-256
  - leave plugin import and Zotero library/profile changes to the GUI
EOF
      ;;
    kando)
      cat <<'EOF'
Plan: kando
  - install the developer-verified Kando Flatpak
  - do not enable autostart or assign a global shortcut
EOF
      ;;
  esac
  printf '%s\n' 'Storage guarantee: no disks, partitions, filesystems, or mounts are touched.'
}

apt_install() {
  local missing=() package
  for package in "$@"; do
    if [[ "$DRY_RUN" == "yes" ]] || ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
      missing+=("$package")
    fi
  done
  ((${#missing[@]})) || { log "apt dependencies already present"; return 0; }
  if [[ "$APT_UPDATED" != "yes" ]]; then
    run sudo apt-get update -qq
    APT_UPDATED="yes"
  fi
  run sudo apt-get install -y --no-install-recommends "${missing[@]}"
}

ensure_flathub() {
  apt_install flatpak
  if [[ "$DRY_RUN" == "yes" ]] || ! flatpak remote-list --columns=name 2>/dev/null | grep -qx flathub; then
    run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi
}

flatpak_install() {
  local app_id="$1"
  ensure_flathub
  if [[ "$DRY_RUN" == "yes" ]] || ! flatpak info "$app_id" >/dev/null 2>&1; then
    run flatpak install -y --noninteractive flathub "$app_id"
  else
    log "$app_id already installed"
  fi
}

link_repo_file() {
  local source_path="$1" destination="$2" backup
  [[ -f "$source_path" ]] || die "tracked source missing: $source_path"
  if [[ -L "$destination" && "$(readlink "$destination")" == "$source_path" ]]; then
    log "link already correct: $destination"
    return 0
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    backup="${destination}.pre-linux-setup"
    [[ ! -e "$backup" && ! -L "$backup" ]] || die "refusing to replace $destination; backup already exists: $backup"
    run mv "$destination" "$backup"
  fi
  run mkdir -p "$(dirname "$destination")"
  run ln -s "$source_path" "$destination"
}

download_verified() {
  local url="$1" expected="$2" destination="$3" tmp actual backup
  if [[ -f "$destination" ]]; then
    actual="$(sha256sum "$destination" | awk '{print $1}')"
    if [[ "$actual" == "$expected" ]]; then
      log "verified download already present: $destination"
      return 0
    fi
  fi
  if [[ "$DRY_RUN" == "yes" ]]; then
    log "would download and SHA-256 verify $url -> $destination"
    return 0
  fi
  tmp="$(mktemp)"
  TEMP_PATHS+=("$tmp")
  curl -fL --retry 3 --proto '=https' --tlsv1.2 -o "$tmp" "$url"
  actual="$(sha256sum "$tmp" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "checksum mismatch for $url (got $actual)"
  mkdir -p "$(dirname "$destination")"
  if [[ -e "$destination" ]]; then
    backup="${destination}.pre-linux-setup-$(date +%Y%m%d%H%M%S)"
    mv "$destination" "$backup"
    log "preserved prior file as $backup"
  fi
  install -m 0644 "$tmp" "$destination"
  rm -f "$tmp"
  log "downloaded and verified: $destination"
}

install_desktop_actions() {
  local entry
  for entry in "$PRODUCTIVITY_DIR"/applications/*.desktop; do
    link_repo_file "$entry" "$HOME/.local/share/applications/$(basename "$entry")"
  done
  if have update-desktop-database; then run update-desktop-database "$HOME/.local/share/applications"; fi
}

install_handlers() {
  apt_install wl-clipboard tesseract-ocr tesseract-ocr-eng libnotify-bin kdialog
  link_repo_file "$PRODUCTIVITY_DIR/bin/ai-clipboard" "$HOME/.local/bin/ai-clipboard"
  link_repo_file "$PRODUCTIVITY_DIR/bin/run-notify" "$HOME/.local/bin/run-notify"
  link_repo_file "$PRODUCTIVITY_DIR/bin/strix-cheatsheet" "$HOME/.local/bin/strix-cheatsheet"
  install_desktop_actions
  log "handlers ready. AI actions always show a consent dialog before transmitting clipboard text."
  log "Try: copy text, press Meta, then search for 'AI Clipboard'."
}

install_dictation() {
  local udev_rule="$PRODUCTIVITY_DIR/udev/90-linux-setup-uinput.rules"
  apt_install ydotool
  flatpak_install "$SPEECH_NOTE_ID"

  if [[ "$DRY_RUN" == "yes" ]] || ! getent group uinput >/dev/null 2>&1; then
    run sudo groupadd --system --force uinput
  fi
  if [[ "$DRY_RUN" == "yes" ]] || ! id -nG "$USER" | tr ' ' '\n' | grep -qx uinput; then
    run sudo usermod -aG uinput "$USER"
  fi
  if [[ "$DRY_RUN" == "yes" ]] || ! sudo cmp -s "$udev_rule" /etc/udev/rules.d/90-linux-setup-uinput.rules; then
    run sudo install -m 0644 "$udev_rule" /etc/udev/rules.d/90-linux-setup-uinput.rules
    run sudo udevadm control --reload-rules
    run sudo udevadm trigger --name-match=uinput
  fi

  link_repo_file "$PRODUCTIVITY_DIR/systemd/ydotool-override.conf" "$HOME/.config/systemd/user/ydotool.service.d/productivity.conf"
  link_repo_file "$PRODUCTIVITY_DIR/systemd/disable-legacy-ydotoold.conf" "$HOME/.config/systemd/user/ydotoold.service.d/productivity.conf"
  run systemctl --user daemon-reload
  if [[ "$DRY_RUN" == "yes" ]] || systemctl --user list-unit-files ydotoold.service --no-legend 2>/dev/null | grep -q '^ydotoold.service'; then
    run systemctl --user disable --now ydotoold.service
  else
    log "legacy ydotoold.service is absent"
  fi
  run systemctl --user enable ydotool.service

  if [[ "$DRY_RUN" == "yes" || -w /dev/uinput ]]; then
    run systemctl --user restart ydotool.service
  else
    log "ydotool.service enabled but not started: log out/in once so the new uinput group applies"
  fi

  if [[ "$DRY_RUN" == "yes" ]]; then
    log "would grant $SPEECH_NOTE_ID xdg-run/ydotool and set YDOTOOL_SOCKET"
  else
    flatpak override --user \
      --filesystem=xdg-run/ydotool \
      --env=YDOTOOL_SOCKET="/run/user/$(id -u)/ydotool/socket" \
      "$SPEECH_NOTE_ID"
  fi
  log "no model or shortcut was selected. Follow productivity/README.md, then run: ./productivity.sh doctor dictation"
}

install_research() {
  local key_tmp key_actual key_dest source_dest xpi_dest
  apt_install ca-certificates curl gnupg
  key_dest="/usr/share/keyrings/zotero-archive-keyring.gpg"
  source_dest="/etc/apt/sources.list.d/linux-setup-zotero.list"

  if [[ "$DRY_RUN" == "yes" ]]; then
    log "would download and verify Zotero signing key -> $key_dest"
    run sudo install -m 0644 "$PRODUCTIVITY_DIR/apt/zotero.list" "$source_dest"
  else
    key_tmp="$(mktemp)"
    TEMP_PATHS+=("$key_tmp")
    curl -fL --retry 3 --proto '=https' --tlsv1.2 -o "$key_tmp" "$ZOTERO_KEY_URL"
    key_actual="$(sha256sum "$key_tmp" | awk '{print $1}')"
    [[ "$key_actual" == "$ZOTERO_KEY_SHA256" ]] || die "Zotero signing-key checksum mismatch (got $key_actual)"
    if ! sudo cmp -s "$key_tmp" "$key_dest"; then sudo install -m 0644 "$key_tmp" "$key_dest"; fi
    sudo install -m 0644 "$PRODUCTIVITY_DIR/apt/zotero.list" "$source_dest"
    rm -f "$key_tmp"
  fi
  APT_UPDATED="no"
  apt_install zotero

  xpi_dest="$HOME/Downloads/zotero-better-bibtex-${BBT_VERSION}.xpi"
  download_verified "$BBT_XPI_URL" "$BBT_XPI_SHA256" "$xpi_dest"
  log "Better BibTeX is staged, not installed into your profile."
  log "In Zotero: Tools > Plugins > gear > Install Plugin From File, then choose $xpi_dest"
}

install_kando() {
  flatpak_install "$KANDO_ID"
  log "Kando installed but left dormant. Launch it once, then choose a portal shortcut only if it beats KRunner for you."
}

show_plan
confirm
case "$COMPONENT" in
  handlers) install_handlers ;;
  dictation) install_dictation ;;
  research) install_research ;;
  kando) install_kando ;;
esac
