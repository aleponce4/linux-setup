#!/usr/bin/env bash
# 85-backup-restic.sh - real backups (as opposed to snapshots): encrypted, deduplicated restic repository on /backup/restic,
#                       daily at 02:30 for /data, /home, /etc and the setup repo; weekly integrity check; retention 7d/4w/6m.
#                       Off-site copy later: 'rclone sync /backup/restic <remote>:restic' (the repo is already encrypted).
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config
[[ "${ENABLE_RESTIC:-yes}" == "yes" ]] || { log "restic disabled"; exit 0; }
: "${DATA_DISK_ID:?storage facts must define DATA_DISK_ID}"
: "${DATA_DISK_SERIAL:?storage facts must define DATA_DISK_SERIAL}"
: "${BACKUP_DISK_ID:?storage facts must define BACKUP_DISK_ID}"
: "${BACKUP_DISK_SERIAL:?storage facts must define BACKUP_DISK_SERIAL}"

require_labeled_mount_from_disk() {
  local mount_path="$1" disk_id="$2" expected_serial="$3" expected_label="$4" expected_fsroot="$5"
  mount_matches_btrfs_label "$mount_path" "$disk_id" "$expected_serial" "$expected_label" "$expected_fsroot" \
    || die "$mount_path is not the expected '$expected_label' Btrfs mount on $disk_id with serial $expected_serial"
}

require_labeled_mount_from_disk "$DATA_MOUNT" "$DATA_DISK_ID" "$DATA_DISK_SERIAL" data /@data
require_labeled_mount_from_disk "$BACKUP_MOUNT" "$BACKUP_DISK_ID" "$BACKUP_DISK_SERIAL" backup /
DATA_FS_UUID="$(findmnt -nro UUID --target "$DATA_MOUNT")"
BACKUP_FS_UUID="$(findmnt -nro UUID --target "$BACKUP_MOUNT")"
[[ -n "$DATA_FS_UUID" && -n "$BACKUP_FS_UUID" ]] || die "data/backup filesystem UUID is unavailable"

apt_install restic jq
REPO="$BACKUP_MOUNT/restic"
sudo mkdir -p /etc/restic "$REPO"

# repository password: generated once, kept in /etc/restic/password (root) and ~/.config/restic/password (you)
if [[ ! -s /etc/restic/password ]]; then
  openssl rand -base64 32 | sudo tee /etc/restic/password >/dev/null
  sudo chmod 600 /etc/restic/password
  log "generated the restic repository password"
fi
mkdir -p "$HOME/.config/restic"
# The redirect intentionally runs as the target user; sudo is needed only to read the root-owned source.
# shellcheck disable=SC2024
sudo cat /etc/restic/password >"$HOME/.config/restic/password"; chmod 600 "$HOME/.config/restic/password"
log "SAVE A COPY of ~/.config/restic/password somewhere off this machine (password manager or the secrets archive); without it the backups are unreadable"

write_file_sudo /etc/restic/excludes 0644 <<EOF
$HOME/.cache
$HOME/.local/share/Trash
$HOME/.local/share/uv
$HOME/.local/share/fnm
$HOME/micromamba
$HOME/.vscode/extensions
$HOME/.positron/extensions
$HOME/.var/app/*/cache
$HOME/snap
$DATA_MOUNT/scratch
**/node_modules
**/.venv
**/venv
**/__pycache__
**/.ruff_cache
**/.pytest_cache
**/renv/library
**/.Rproj.user
EOF

{
  cat <<'EOF'
#!/bin/bash
# daily backup + retention; run by restic-backup.timer, or by hand: sudo restic-backup
set -euo pipefail
EOF
  printf 'DATA_MOUNT=%q\n' "$DATA_MOUNT"
  printf 'BACKUP_MOUNT=%q\n' "$BACKUP_MOUNT"
  printf 'DATA_DISK_ID=%q\n' "$DATA_DISK_ID"
  printf 'DATA_DISK_SERIAL=%q\n' "$DATA_DISK_SERIAL"
  printf 'DATA_FS_UUID=%q\n' "$DATA_FS_UUID"
  printf 'BACKUP_DISK_ID=%q\n' "$BACKUP_DISK_ID"
  printf 'BACKUP_DISK_SERIAL=%q\n' "$BACKUP_DISK_SERIAL"
  printf 'BACKUP_FS_UUID=%q\n' "$BACKUP_FS_UUID"
  printf 'BACKUP_SOURCE_HOME=%q\n' "$TARGET_HOME"
  printf 'BACKUP_SOURCE_REPO=%q\n' "$REPO_DIR"
  printf 'RESTIC_REPOSITORY=%q\n' "$REPO"
  cat <<'EOF'
export RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE=/etc/restic/password
export RESTIC_CACHE_DIR=/var/cache/restic

fail() { printf 'restic-backup: %s\n' "$*" >&2; exit 1; }

canonical_block_device() {
  local resolved
  resolved="$(readlink -f "$1" 2>/dev/null)" || return 1
  [[ -b "$resolved" ]] || return 1
  printf '%s\n' "$resolved"
}

parent_disk() {
  local current type depth=0 parents=()
  current="$(canonical_block_device "$1")" || return 1
  while (( depth < 8 )); do
    type="$(lsblk -dnro TYPE "$current" 2>/dev/null | head -n1)"
    if [[ "$type" == "disk" ]]; then
      printf '%s\n' "$current"
      return 0
    fi
    mapfile -t parents < <(lsblk -dnro PKNAME "$current" 2>/dev/null | awk 'NF' | sort -u)
    (( ${#parents[@]} == 1 )) || return 1
    current="/dev/${parents[0]}"
    current="$(canonical_block_device "$current")" || return 1
    depth=$((depth + 1))
  done
  return 1
}

normalized_disk_serial() {
  local disk
  disk="$(canonical_block_device "$1")" || return 1
  lsblk -dnro SERIAL "$disk" 2>/dev/null \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]][[:space:]]*/_/g'
}

disk_matches() {
  local disk_id="$1" expected_serial="$2" disk
  [[ -L "$disk_id" ]] || return 1
  disk="$(canonical_block_device "$disk_id")" || return 1
  [[ "$(lsblk -dnro TYPE "$disk" 2>/dev/null | head -n1)" == "disk" ]] || return 1
  [[ "$(normalized_disk_serial "$disk")" == "$expected_serial" ]]
}

require_mount_from_disk() {
  local mount_path="$1" disk_id="$2" expected_serial="$3" expected_uuid="$4" expected_fsroot="$5"
  local source source_disk expected_disk actual_uuid actual_fstype actual_fsroot
  mountpoint -q "$mount_path" || fail "$mount_path is not a mountpoint"
  disk_matches "$disk_id" "$expected_serial" || fail "configured disk identity mismatch: $disk_id ($expected_serial)"
  source="$(findmnt -nro SOURCE --target "$mount_path" 2>/dev/null)" || fail "cannot resolve source for $mount_path"
  source="${source%%\[*}"
  source_disk="$(parent_disk "$source")" || fail "cannot resolve parent disk for $mount_path ($source)"
  expected_disk="$(canonical_block_device "$disk_id")" || fail "cannot resolve $disk_id"
  [[ "$source_disk" == "$expected_disk" ]] || fail "$mount_path is on $source_disk, expected $disk_id ($expected_disk)"
  actual_uuid="$(findmnt -nro UUID --target "$mount_path" 2>/dev/null)" || fail "cannot read UUID for $mount_path"
  [[ "$actual_uuid" == "$expected_uuid" ]] || fail "$mount_path UUID is $actual_uuid, expected $expected_uuid"
  actual_fstype="$(findmnt -nro FSTYPE --target "$mount_path" 2>/dev/null)" || fail "cannot read filesystem type for $mount_path"
  actual_fsroot="$(findmnt -nro FSROOT --target "$mount_path" 2>/dev/null)" || fail "cannot read filesystem root for $mount_path"
  [[ "$actual_fstype" == "btrfs" ]] || fail "$mount_path is $actual_fstype, expected btrfs"
  [[ "$actual_fsroot" == "$expected_fsroot" ]] || \
    fail "$mount_path filesystem root is $actual_fsroot, expected $expected_fsroot"
}

require_mount_from_disk "$BACKUP_MOUNT" "$BACKUP_DISK_ID" "$BACKUP_DISK_SERIAL" "$BACKUP_FS_UUID" /
mkdir -p "$RESTIC_CACHE_DIR"

if [[ "${1:-}" == "--check" ]]; then
  [[ -f "$RESTIC_REPOSITORY/config" ]] || fail "restic repository is not initialized at $RESTIC_REPOSITORY"
  exec restic check --read-data-subset=5%
fi
[[ $# -eq 0 ]] || fail "usage: restic-backup [--check]"

require_mount_from_disk "$DATA_MOUNT" "$DATA_DISK_ID" "$DATA_DISK_SERIAL" "$DATA_FS_UUID" /@data
[[ -f "$RESTIC_REPOSITORY/config" ]] || restic init
restic snapshots >/dev/null
restic backup --quiet --one-file-system --exclude-caches --exclude-file=/etc/restic/excludes \
  "$DATA_MOUNT" "$BACKUP_SOURCE_HOME" /etc "$BACKUP_SOURCE_REPO"
restic forget --quiet --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6
EOF
} | write_file_sudo /usr/local/sbin/restic-backup 0755

write_file_sudo /etc/systemd/system/restic-backup.service 0644 <<EOF
[Unit]
Description=restic backup to $REPO
RequiresMountsFor=$BACKUP_MOUNT $DATA_MOUNT
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/restic-backup
Nice=10
IOSchedulingClass=idle
EOF
write_file_sudo /etc/systemd/system/restic-backup.timer 0644 <<'EOF'
[Unit]
Description=daily restic backup
[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
RandomizedDelaySec=10m
[Install]
WantedBy=timers.target
EOF
write_file_sudo /etc/systemd/system/restic-check.service 0644 <<EOF
[Unit]
Description=restic integrity check (5% of data)
RequiresMountsFor=$BACKUP_MOUNT
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/restic-backup --check
Nice=10
IOSchedulingClass=idle
EOF
write_file_sudo /etc/systemd/system/restic-check.timer 0644 <<'EOF'
[Unit]
Description=weekly restic check
[Timer]
OnCalendar=Sun *-*-* 04:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
systemd_enable_now restic-backup.timer
systemd_enable_now restic-check.timer

# An initialized but empty repository is not a backup. Start the first backup without blocking the
# rest of bootstrap; module 90 deliberately stays FAIL until that first snapshot completes.
if ! sudo env RESTIC_REPOSITORY="$REPO" RESTIC_PASSWORD_FILE=/etc/restic/password \
    restic snapshots --json 2>/dev/null | jq -e 'length > 0' >/dev/null; then
  log "restic repository is new or empty; starting the first backup (journalctl -u restic-backup -f)"
  sudo systemctl start --no-block restic-backup.service
fi
log "restic done. List: sudo restic -r $REPO -p /etc/restic/password snapshots ; restore: ... restore latest --target /tmp/restore --include /data/libs"
