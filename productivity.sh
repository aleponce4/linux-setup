#!/usr/bin/env bash
# productivity.sh - explicit, optional productivity add-ons. Never called by bootstrap.sh.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR

usage() {
  cat <<'EOF'
Optional productivity phase (not run by bootstrap.sh)

Usage:
  ./productivity.sh list
  ./productivity.sh doctor [all|native-kde|dictation|handlers|research|kando]
  ./productivity.sh install <dictation|handlers|research|kando> [--dry-run] [--yes]

Components:
  native-kde  guidance/checks for Plasma's built-in tiling and five workspaces
  dictation   repair Speech Note + ydotool on Plasma Wayland (no model download)
  handlers    safe AI clipboard actions, Spectacle OCR dependencies, job alerts
  research    Zotero apt package + a verified Better BibTeX XPI for manual import
  kando       optional pie launcher; no shortcut or autostart is enabled

There is deliberately no "install all" action. Every mutation requires a named
component, prints its plan, and asks for confirmation unless --yes is supplied.
No command here formats, partitions, mounts, or otherwise changes storage.
EOF
}

case "${1:-help}" in
  help|-h|--help)
    usage
    ;;
  list)
    usage
    ;;
  doctor)
    shift
    exec "$REPO_DIR/productivity/doctor.sh" "${1:-all}"
    ;;
  install)
    shift
    exec "$REPO_DIR/productivity/install.sh" "$@"
    ;;
  *)
    printf 'Unknown command: %s\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac
