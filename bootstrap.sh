#!/usr/bin/env bash
# bootstrap.sh - run the provisioning modules in setup.d/ in order.
#   One-liner on a fresh install (clones the repo, creates config.env from the example, runs everything):
#     curl -fsSL https://raw.githubusercontent.com/aleponce4/linux-setup/main/bootstrap.sh | bash
#   Inside the repo:
#     ./bootstrap.sh            run everything
#     ./bootstrap.sh 40 50      run only modules starting with 40 or 50
#     ./bootstrap.sh --list     list modules
#     ./bootstrap.sh --format 20  explicitly unlock destructive storage setup; each exact disk still requires typed confirmation
set -euo pipefail

# ---- standalone mode (piped from curl, or copied somewhere without the repo): clone and re-exec ----
SELF="${BASH_SOURCE[0]:-}"
if [[ -z "$SELF" || ! -d "$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)/setup.d" ]]; then
  DEST="${LINUX_SETUP_DIR:-$HOME/linux-setup}"
  REPO_URL="${LINUX_SETUP_REPO:-https://github.com/aleponce4/linux-setup.git}"
  echo "linux-setup: standalone mode, repo -> $DEST"
  if ! command -v git >/dev/null 2>&1; then sudo apt-get update -qq && sudo apt-get install -y -qq git curl; fi
  if [[ -d "$DEST/.git" ]]; then git -C "$DEST" pull -q --ff-only || true; else git clone -q "$REPO_URL" "$DEST"; fi
  exec bash "$DEST/bootstrap.sh" "$@"
fi

REPO_DIR="$(cd "$(dirname "$SELF")" && pwd)"
export REPO_DIR
export LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"

if [[ ! -f "$REPO_DIR/config.env" ]]; then
  cp "$REPO_DIR/config.env.example" "$REPO_DIR/config.env"
  echo "config.env created from config.env.example (edit later if anything differs)"
fi
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"
load_config

if [[ "${1:-}" == "--list" ]]; then
  for module_path in "$REPO_DIR"/setup.d/*.sh; do basename "$module_path"; done
  exit 0
fi

ALLOW_FORMAT="no"
FORMAT_SCOPE="no"
FORMAT_FLAGS=0
filters=()
for a in "$@"; do
  case "$a" in
    --format)
      ALLOW_FORMAT="yes"
      FORMAT_FLAGS=$((FORMAT_FLAGS + 1))
      ;;
    *)
      filters+=("$a")
      if [[ "$a" == "20" ]]; then FORMAT_SCOPE="yes"; fi
      ;;
  esac
done
if [[ "$ALLOW_FORMAT" == "yes" ]] \
    && { (( FORMAT_FLAGS != 1 )) || [[ "$FORMAT_SCOPE" != "yes" ]] || (( ${#filters[@]} != 1 )); }; then
  die "destructive mode requires the exact arguments: ./bootstrap.sh --format 20"
fi

if [[ $EUID -eq 0 ]]; then
  die "Run as your normal user; modules call sudo where needed."
fi
if sudo -n true 2>/dev/null; then
  :   # passwordless sudo already available (NOPASSWD rule or a live timestamp)
else
  # sudo -v needs a TTY; fail clearly instead of dying on line 1 in an automated run
  [[ -t 0 ]] || die "no passwordless sudo and no terminal to prompt on; run from a terminal, or grant NOPASSWD"
  echo "linux-setup: sudo password needed once"
  sudo -v
fi
# keep sudo alive for the duration of the run
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true' EXIT

ts="$(date +%Y%m%d-%H%M%S)"
RUN_LOG="$LOG_DIR/bootstrap-$ts.log"
export RUN_LOG
log "bootstrap start $ts (user=$USER, host=$(hostname), format=$ALLOW_FORMAT) -> $RUN_LOG"

failed=()
for mod in "$REPO_DIR/setup.d"/*.sh; do
  name="$(basename "$mod")"
  if ((${#filters[@]})); then
    keep="no"
    for f in "${filters[@]}"; do [[ "$name" == "$f"* ]] && keep="yes"; done
    [[ "$keep" == "yes" ]] || continue
  fi
  log "===== $name ====="
  module_args=()
  if [[ "$name" == "20-storage.sh" && "$ALLOW_FORMAT" == "yes" ]]; then
    module_args+=(--format)
  fi
  if bash "$mod" "${module_args[@]}" 2>&1 | tee -a "$RUN_LOG"; then
    log "----- $name ok"
  else
    log "----- $name FAILED (continuing; see $RUN_LOG)"
    failed+=("$name")
  fi
done

if ((${#failed[@]})); then
  log "finished with failures: ${failed[*]}  (re-run: ./bootstrap.sh ${failed[*]%%-*})"
  exit 1
fi
log "all modules finished. Log out and back in (or reboot) to pick up groups, fonts and the Meta key. Then: ~/linux-setup/docs/manual-steps.md"
