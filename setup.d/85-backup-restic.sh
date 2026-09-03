#!/usr/bin/env bash
# 85-backup-restic.sh - real backups (as opposed to snapshots): encrypted, deduplicated restic repository on /backup/restic,
#                       daily at 02:30 for /data, /home, /etc and the setup repo; weekly integrity check; retention 7d/4w/6m.
#                       Off-site copy later: 'rclone sync /backup/restic <remote>:restic' (the repo is already encrypted).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config
[[ "${ENABLE_RESTIC:-yes}" == "yes" ]] || { log "restic disabled"; exit 0; }
mountpoint -q "$BACKUP_MOUNT" || { warn "$BACKUP_MOUNT not mounted; run module 20 first"; exit 0; }

apt_install restic
REPO="$BACKUP_MOUNT/restic"
sudo mkdir -p /etc/restic "$REPO"

# repository password: generated once, kept in /etc/restic/password (root) and ~/.config/restic/password (you)
if [[ ! -s /etc/restic/password ]]; then
  openssl rand -base64 32 | sudo tee /etc/restic/password >/dev/null
  sudo chmod 600 /etc/restic/password
  log "generated the restic repository password"
fi
mkdir -p "$HOME/.config/restic"
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

write_file_sudo /usr/local/sbin/restic-backup 0755 <<EOF
#!/bin/bash
# daily backup + retention; run by restic-backup.timer, or by hand: sudo restic-backup
set -euo pipefail
export RESTIC_REPOSITORY="$REPO"
export RESTIC_PASSWORD_FILE=/etc/restic/password
export RESTIC_CACHE_DIR=/var/cache/restic
mkdir -p "\$RESTIC_CACHE_DIR"
restic snapshots >/dev/null 2>&1 || restic init
restic backup --quiet --one-file-system --exclude-caches --exclude-file=/etc/restic/excludes \\
  "$DATA_MOUNT" "$HOME" /etc "$REPO_DIR" 2>&1 | grep -v 'is a socket' || true
restic forget --quiet --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6
EOF

write_file_sudo /etc/systemd/system/restic-backup.service 0644 <<'EOF'
[Unit]
Description=restic backup to /backup/restic
RequiresMountsFor=/backup /data
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
RequiresMountsFor=/backup
[Service]
Type=oneshot
Environment=RESTIC_REPOSITORY=$REPO RESTIC_PASSWORD_FILE=/etc/restic/password RESTIC_CACHE_DIR=/var/cache/restic
ExecStart=/usr/bin/restic check --read-data-subset=5%%
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

# first backup now (in the background; it can take a while the first time)
if ! sudo RESTIC_REPOSITORY="$REPO" RESTIC_PASSWORD_FILE=/etc/restic/password restic snapshots >/dev/null 2>&1; then
  log "starting the first restic backup in the background (journalctl -u restic-backup -f)"
  sudo systemctl start --no-block restic-backup.service
fi
log "restic done. List: sudo restic -r $REPO -p /etc/restic/password snapshots ; restore: ... restore latest --target /tmp/restore --include /data/libs"
