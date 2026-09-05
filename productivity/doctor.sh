#!/usr/bin/env bash
# doctor.sh - read-only checks for the optional productivity phase.
set -uo pipefail

PRODUCTIVITY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=productivity/config.sh
source "$PRODUCTIVITY_DIR/config.sh"
COMPONENT="${1:-all}"
FAILURES=0

green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; blue=$'\033[36m'; reset=$'\033[0m'
[[ -t 1 ]] || { green=""; yellow=""; red=""; blue=""; reset=""; }

pass() { printf '%sPASS%s  %s\n' "$green" "$reset" "$*"; }
warn() { printf '%sWARN%s  %s\n' "$yellow" "$reset" "$*"; }
skip() { printf '%sSKIP%s  %s\n' "$blue" "$reset" "$*"; }
fail() { printf '%sFAIL%s  %s\n' "$red" "$reset" "$*"; FAILURES=$((FAILURES + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

heading() { printf '\n== %s ==\n' "$1"; }

doctor_native_kde() {
  heading "Native Plasma workflow"
  if ! have kwriteconfig6; then skip "KDE tools are not available in this session"; return; fi
  if [[ "${XDG_SESSION_TYPE:-unknown}" == "wayland" ]]; then pass "Wayland session"; else warn "session is ${XDG_SESSION_TYPE:-unknown}; target is Wayland"; fi
  check "five virtual desktops configured" test "$(kreadconfig6 --file kwinrc --group Desktops --key Number 2>/dev/null)" = 5
  printf 'INFO  Meta+T zones | Meta+arrows quick tile | Meta+1..5 workspaces | Meta+W overview\n'
  if kpackagetool6 --type=KWin/Script --list 2>/dev/null | grep -q polonium; then
    if [[ "$(kreadconfig6 --file kwinrc --group Plugins --key poloniumEnabled 2>/dev/null)" == "true" ]]; then
      warn "Polonium is enabled; disable it if native Plasma tiling is enough"
    else
      pass "Polonium remains optional and disabled"
    fi
  fi
}

doctor_dictation() {
  local socket_path="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ydotool/socket" permissions daemon_count
  heading "Speech Note dictation"
  if ! have flatpak || ! flatpak info "$SPEECH_NOTE_ID" >/dev/null 2>&1; then
    skip "Speech Note is not installed; run: ./productivity.sh install dictation"
    return
  fi
  pass "Speech Note Flatpak installed"
  check "ydotool client installed" have ydotool
  check "ydotool daemon installed" have ydotoold
  check "dedicated uinput group membership active" bash -c "id -nG | tr ' ' '\n' | grep -qx uinput"
  if id -nG | tr ' ' '\n' | grep -qx input; then
    warn "legacy broad input-group membership remains; the productivity phase does not remove groups automatically"
  fi
  check "/dev/uinput character device exists" test -c /dev/uinput
  check "/dev/uinput is writable by this login" test -w /dev/uinput
  check "single packaged ydotool.service enabled" systemctl --user is-enabled --quiet ydotool.service
  check "single packaged ydotool.service active" systemctl --user is-active --quiet ydotool.service
  if systemctl --user is-active --quiet ydotoold.service; then fail "legacy duplicate ydotoold.service is inactive"; else pass "legacy duplicate ydotoold.service is inactive"; fi
  check "private ydotool socket exists" test -S "$socket_path"
  if [[ -S "$socket_path" ]]; then
    check "ydotool socket owned by this user" test "$(stat -c %u "$socket_path" 2>/dev/null)" = "$(id -u)"
    check "ydotool socket mode is 0600" test "$(stat -c %a "$socket_path" 2>/dev/null)" = 600
  fi
  permissions="$(flatpak info --show-permissions "$SPEECH_NOTE_ID" 2>/dev/null || true)"
  if grep -Fq 'xdg-run/ydotool' <<<"$permissions"; then pass "Flatpak has narrow socket-directory access"; else fail "Flatpak has narrow socket-directory access"; fi
  if grep -Fq 'YDOTOOL_SOCKET=' <<<"$permissions"; then pass "Flatpak has YDOTOOL_SOCKET"; else fail "Flatpak has YDOTOOL_SOCKET"; fi
  daemon_count="$(pgrep -xc ydotoold 2>/dev/null || true)"
  if [[ "$daemon_count" == "1" ]]; then pass "exactly one ydotoold process"; else fail "expected one ydotoold process; found ${daemon_count:-0}"; fi
  if have busctl && busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.GlobalShortcuts >/dev/null 2>&1; then
    pass "Plasma GlobalShortcuts portal available"
  else
    warn "could not confirm the GlobalShortcuts portal from this session"
  fi
  printf 'INFO  No typing test or microphone action was performed. Model selection stays manual.\n'
}

doctor_handlers() {
  local installed="no" item
  heading "Clipboard, OCR, and job handlers"
  for item in ai-clipboard run-notify; do [[ -e "$HOME/.local/bin/$item" || -L "$HOME/.local/bin/$item" ]] && installed="yes"; done
  if [[ "$installed" != "yes" ]]; then skip "handlers are not installed; run: ./productivity.sh install handlers"; return; fi
  check "ai-clipboard executable" test -x "$HOME/.local/bin/ai-clipboard"
  check "run-notify executable" test -x "$HOME/.local/bin/run-notify"
  check "Wayland clipboard tools" bash -c 'command -v wl-copy && command -v wl-paste'
  check "Tesseract English OCR" bash -c "command -v tesseract && tesseract --list-langs 2>/dev/null | grep -qx eng"
  check "desktop notifications" have notify-send
  check "consent dialogs" have kdialog
  check "Claude CLI backend" have claude
  if have claude && claude --restricted --bare --version >/dev/null 2>&1; then pass "Claude supports restricted bare mode"; else fail "Claude needs an update for restricted bare mode"; fi
  if have claude && claude auth status >/dev/null 2>&1; then pass "Claude CLI authenticated"; else warn "Claude CLI authentication not confirmed; no request was sent"; fi
  printf 'INFO  Doctor never reads the clipboard or contacts an AI provider.\n'
}

doctor_research() {
  local xpi="$HOME/Downloads/zotero-better-bibtex-${BBT_VERSION}.xpi" actual
  heading "Research workflow"
  if ! have zotero && [[ ! -f "$xpi" ]]; then skip "research extras are not installed; run: ./productivity.sh install research"; return; fi
  check "Zotero installed" have zotero
  if [[ -f "$xpi" ]]; then
    actual="$(sha256sum "$xpi" | awk '{print $1}')"
    if [[ "$actual" == "$BBT_XPI_SHA256" ]]; then pass "Better BibTeX ${BBT_VERSION} XPI verified"; else fail "Better BibTeX XPI checksum"; fi
  else
    warn "Better BibTeX XPI is not staged in ~/Downloads"
  fi
  printf 'INFO  Plugin enablement and library health must be checked inside Zotero.\n'
}

doctor_kando() {
  heading "Kando experiment"
  if have flatpak && flatpak info "$KANDO_ID" >/dev/null 2>&1; then
    pass "Kando Flatpak installed"
    warn "shortcut and autostart are intentionally not managed"
  else
    skip "Kando not installed (optional experiment)"
  fi
}

if [[ "$(uname -s)" != "Linux" ]]; then
  fail "doctor must run on the target Linux workstation"
  exit 1
fi

case "$COMPONENT" in
  all)
    doctor_native_kde; doctor_dictation; doctor_handlers; doctor_research; doctor_kando
    if have aw-qt && [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then warn "ActivityWatch detected: its official window watcher does not support KWin Wayland"; fi
    ;;
  native-kde) doctor_native_kde ;;
  dictation) doctor_dictation ;;
  handlers) doctor_handlers ;;
  research) doctor_research ;;
  kando) doctor_kando ;;
  *) printf 'Unknown doctor component: %s\n' "$COMPONENT" >&2; exit 2 ;;
esac

printf '\n%d failing check(s).\n' "$FAILURES"
((FAILURES == 0))
