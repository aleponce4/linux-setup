#!/usr/bin/env bash
# 20-storage.sh - Btrfs layout on the NVMe, Timeshift + grub-btrfs snapshots, zram,
#                 /data on the SATA SSD, /backup + WINRESCUE on the HDD, btrbk send/receive.
# Formatting the SSD/HDD only happens with:  ./bootstrap.sh --format 20   (and a typed confirmation)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config
ALLOW_FORMAT="${ALLOW_FORMAT:-no}"
UID_T="$(id -u "$TARGET_USER")"; GID_T="$(id -g "$TARGET_USER")"

apt_install btrfs-progs gdisk parted ntfs-3g

# ---------- 1. root filesystem: expect the Kubuntu installer's Btrfs layout ----------
ROOT_SRC="$(findmnt -no SOURCE / | sed 's/\[.*//')"
ROOT_FSTYPE="$(findmnt -no FSTYPE /)"
[[ "$ROOT_FSTYPE" == "btrfs" ]] || die "root is $ROOT_FSTYPE, not btrfs; install with Btrfs (erase disk -> btrfs) for snapshots"
ROOT_UUID="$(findmnt -no UUID /)"
BTRFS_ROOT=/mnt/btrfs-root
sudo mkdir -p "$BTRFS_ROOT"
ensure_line /etc/fstab "UUID=$ROOT_UUID $BTRFS_ROOT btrfs subvolid=5,noatime,nofail 0 0" "^UUID=$ROOT_UUID[[:space:]]+$BTRFS_ROOT[[:space:]]"
mountpoint -q "$BTRFS_ROOT" || sudo mount "$BTRFS_ROOT"
for sv in @ @home; do
  sudo btrfs subvolume show "$BTRFS_ROOT/$sv" >/dev/null 2>&1 || die "top-level subvolume $sv missing; Timeshift needs the Ubuntu @/@home layout"
done

# Docker data outside the snapshots (and out of Timeshift's way)
if ! sudo btrfs subvolume show "$BTRFS_ROOT/@docker" >/dev/null 2>&1; then
  sudo btrfs subvolume create "$BTRFS_ROOT/@docker"
  log "created @docker subvolume"
fi
sudo mkdir -p /var/lib/docker
ensure_line /etc/fstab "UUID=$ROOT_UUID /var/lib/docker btrfs subvol=@docker,noatime,compress=zstd:1 0 0" "^UUID=$ROOT_UUID[[:space:]]+/var/lib/docker[[:space:]]"
mountpoint -q /var/lib/docker || sudo mount /var/lib/docker

# compression on the root fs if the installer did not enable it
if ! findmnt -no OPTIONS / | grep -q compress; then
  sudo sed -i -E "s|^(UUID=$ROOT_UUID[[:space:]]+/[[:space:]]+btrfs[[:space:]]+)([^[:space:]]+)|\1\2,compress=zstd:1|" /etc/fstab
  sudo mount -o remount / || true
fi

# ---------- 2. snapshots: Timeshift (btrfs mode) + apt hook + GRUB menu ----------
if [[ "${ENABLE_SNAPSHOTS:-yes}" == "yes" ]]; then
  apt_install timeshift inotify-tools make git
  write_file_sudo /etc/timeshift/timeshift.json 0644 <<EOF
{
  "backup_device_uuid" : "$ROOT_UUID",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "true",
  "count_monthly" : "0",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "0",
  "count_boot" : "3",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : [ "/var/lib/docker/**", "/home/**", "/root/**" ],
  "exclude-apps" : []
}
EOF
  # pre-apt snapshots
  if [[ ! -x /usr/bin/timeshift-autosnap-apt ]]; then
    sudo rm -rf /usr/local/src/timeshift-autosnap-apt
    sudo git clone -q https://github.com/wmutschl/timeshift-autosnap-apt.git /usr/local/src/timeshift-autosnap-apt
    (cd /usr/local/src/timeshift-autosnap-apt && sudo make install >/dev/null)
    log "installed timeshift-autosnap-apt"
  fi
  write_file_sudo /etc/timeshift-autosnap-apt.conf 0644 <<'EOF'
# timeshift-autosnap-apt: snapshot before every apt install/upgrade/remove
skipAutosnap=false
deleteSnapshots=true
maxSnapshots=5
updateGrub=true
EOF
  # bootable snapshots in GRUB
  if ! [[ -x /usr/bin/grub-btrfsd || -x /usr/sbin/grub-btrfsd ]]; then
    sudo rm -rf /usr/local/src/grub-btrfs
    sudo git clone -q https://github.com/Antynea/grub-btrfs.git /usr/local/src/grub-btrfs
    (cd /usr/local/src/grub-btrfs && sudo make install >/dev/null)
    log "installed grub-btrfs"
  fi
  sudo mkdir -p /etc/systemd/system/grub-btrfsd.service.d
  write_file_sudo /etc/systemd/system/grub-btrfsd.service.d/override.conf 0644 <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto
EOF
  sudo systemctl daemon-reload
  systemd_enable_now grub-btrfsd
  sudo timeshift --create --comments "linux-setup baseline" --tags O >/dev/null 2>&1 || warn "initial timeshift snapshot failed (run 'sudo timeshift --create' after reboot)"
  sudo update-grub >/dev/null 2>&1 || warn "update-grub failed"
fi

# ---------- 3. zram swap ----------
apt_install systemd-zram-generator
write_file_sudo /etc/systemd/zram-generator.conf 0644 <<'EOF'
[zram0]
zram-size = min(ram / 2, 16384)
compression-algorithm = zstd
swap-priority = 100
EOF
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
# vm tuning that suits zram
write_file_sudo /etc/sysctl.d/99-zram.conf 0644 <<'EOF'
vm.swappiness = 150
vm.page-cluster = 0
EOF
sudo sysctl -q --system >/dev/null

# ---------- 4. /data on the SATA SSD ----------
setup_btrfs_disk() {   # setup_btrfs_disk DEVICE_ID LABEL -> ensures a single btrfs partition with LABEL exists (formats only when allowed)
  local dev="$1" label="$2" part
  [[ -e "$dev" ]] || { warn "$dev not present; skipping $label"; return 1; }
  if blkid -L "$label" >/dev/null 2>&1; then return 0; fi
  # NEVER format the disk this system is running from. Without this, pointing SATA_SSD_ID at the
  # root disk (which happens if root was installed there) makes this function wipe its own OS.
  local target root_src root_disk
  target="$(readlink -f "$dev")"
  root_src="$(findmnt -no SOURCE / | sed 's/\[.*//')"
  root_disk="$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1)"
  if [[ -n "$root_disk" && "$target" == "/dev/$root_disk" ]]; then
    warn "REFUSING to format $target as '$label': it holds the running root filesystem"
    return 1
  fi
  # also refuse anything currently mounted
  if lsblk -no MOUNTPOINT "$target" 2>/dev/null | grep -qE '^/'; then
    warn "REFUSING to format $target as '$label': it has mounted filesystems"
    return 1
  fi
  if [[ "$ALLOW_FORMAT" != "yes" ]]; then
    warn "no filesystem labeled $label on $dev. Re-run with --format to create it (destroys everything on that disk)."; return 1
  fi
  echo; lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$dev"
  if [[ "${AUTO_FORMAT:-no}" == "yes" ]]; then
    log "AUTO_FORMAT=yes: formatting $(readlink -f "$dev") (serial-matched $dev) as btrfs '$label'"
  else
    read -r -p "Type FORMAT to wipe $(readlink -f "$dev") and create btrfs '$label': " ans
    [[ "$ans" == "FORMAT" ]] || { warn "skipped formatting $dev"; return 1; }
  fi
  sudo wipefs -a "$dev" >/dev/null
  sudo sgdisk -Z "$dev" >/dev/null
  sudo sgdisk -n 1:0:0 -t 1:8300 -c "1:$label" "$dev" >/dev/null
  sudo partprobe "$dev"; sleep 2
  part="$(lsblk -nrpo NAME,PARTLABEL "$(readlink -f "$dev")" | awk -v l="$label" '$2==l {print $1}' | head -n1)"
  [[ -n "$part" ]] || die "could not find the new partition on $dev"
  sudo mkfs.btrfs -q -f -L "$label" "$part"
  log "formatted $part as btrfs '$label'"
}

if setup_btrfs_disk "$SATA_SSD_ID" data; then
  DATA_UUID="$(blkid -s UUID -o value -L data)"
  sudo mkdir -p /mnt/btrfs-data "$DATA_MOUNT"
  ensure_line /etc/fstab "UUID=$DATA_UUID /mnt/btrfs-data btrfs subvolid=5,noatime,nofail 0 0" "^UUID=$DATA_UUID[[:space:]]+/mnt/btrfs-data[[:space:]]"
  mountpoint -q /mnt/btrfs-data || sudo mount /mnt/btrfs-data
  sudo btrfs subvolume show /mnt/btrfs-data/@data >/dev/null 2>&1 || sudo btrfs subvolume create /mnt/btrfs-data/@data >/dev/null
  ensure_line /etc/fstab "UUID=$DATA_UUID $DATA_MOUNT btrfs subvol=@data,noatime,compress=zstd:1,nofail 0 0" "^UUID=$DATA_UUID[[:space:]]+$DATA_MOUNT[[:space:]]"
  mountpoint -q "$DATA_MOUNT" || sudo mount "$DATA_MOUNT"
  if [[ "${ENABLE_VM_STACK:-no}" == "yes" ]]; then
    sudo btrfs subvolume show /mnt/btrfs-data/@vms >/dev/null 2>&1 || { sudo btrfs subvolume create /mnt/btrfs-data/@vms >/dev/null; sudo chattr +C /mnt/btrfs-data/@vms; }
    sudo mkdir -p /var/lib/libvirt/images
    ensure_line /etc/fstab "UUID=$DATA_UUID /var/lib/libvirt/images btrfs subvol=@vms,noatime,nodatacow,nofail 0 0" "^UUID=$DATA_UUID[[:space:]]+/var/lib/libvirt/images[[:space:]]"
    mountpoint -q /var/lib/libvirt/images || sudo mount /var/lib/libvirt/images
  fi
  sudo chown "$UID_T:$GID_T" "$DATA_MOUNT"
  for d in $DATA_DIRS; do mkdir -p "$DATA_MOUNT/$d"; done
  [[ -L "$HOME/data" ]] || ln -sfn "$DATA_MOUNT" "$HOME/data"
fi

# ---------- 5. HDD: WINRESCUE (NTFS, read-only) + /backup (btrfs on the remaining space) ----------
if [[ -e "$HDD_ID" ]]; then
  if blkid -L "$WINRESCUE_LABEL" >/dev/null 2>&1; then
    sudo mkdir -p /mnt/winrescue
    ensure_line /etc/fstab "LABEL=$WINRESCUE_LABEL /mnt/winrescue ntfs3 ro,nofail,uid=$UID_T,gid=$GID_T,x-systemd.automount 0 0" "^LABEL=$WINRESCUE_LABEL[[:space:]]"
    sudo systemctl daemon-reload
    log "WINRESCUE will auto-mount read-only at /mnt/winrescue"
  else
    warn "no partition labeled $WINRESCUE_LABEL on the HDD (expected from the Windows pre-wipe steps)"
  fi
  if ! blkid -L backup >/dev/null 2>&1; then
    if [[ "$ALLOW_FORMAT" == "yes" ]]; then
      echo; sudo sgdisk -p "$HDD_ID"
      ans="FORMAT"
      if [[ "${AUTO_FORMAT:-no}" != "yes" ]]; then
        read -r -p "Type FORMAT to create a btrfs 'backup' partition in the largest free space on $(readlink -f "$HDD_ID") (existing partitions untouched): " ans
      fi
      if [[ "$ans" == "FORMAT" ]]; then
        sudo sgdisk -n 0:0:0 -t 0:8300 -c 0:backup "$HDD_ID" >/dev/null
        sudo partprobe "$HDD_ID"; sleep 2
        part="$(lsblk -nrpo NAME,PARTLABEL "$(readlink -f "$HDD_ID")" | awk '$2=="backup" {print $1}' | head -n1)"
        [[ -n "$part" ]] && sudo mkfs.btrfs -q -f -L backup "$part" && log "formatted $part as btrfs 'backup'"
      fi
    else
      warn "no 'backup' filesystem on the HDD; re-run with --format to create it in the free space"
    fi
  fi
  if blkid -L backup >/dev/null 2>&1; then
    sudo mkdir -p "$BACKUP_MOUNT"
    ensure_line /etc/fstab "LABEL=backup $BACKUP_MOUNT btrfs noatime,compress=zstd:3,nofail 0 0" "^LABEL=backup[[:space:]]"
    mountpoint -q "$BACKUP_MOUNT" || sudo mount "$BACKUP_MOUNT"
    sudo mkdir -p "$BACKUP_MOUNT/btrbk/nvme" "$BACKUP_MOUNT/btrbk/data" "$BACKUP_MOUNT/restic"
    sudo chown "$UID_T:$GID_T" "$BACKUP_MOUNT/restic"
  fi
fi

# ---------- 6. btrbk: hourly snapshots of @, @home, @data sent to /backup ----------
if [[ "${ENABLE_BTRBK:-yes}" == "yes" ]] && mountpoint -q "$BACKUP_MOUNT" 2>/dev/null; then
  apt_install btrbk
  sudo mkdir -p "$BTRFS_ROOT/btrbk_snapshots"
  [[ -d /mnt/btrfs-data ]] && sudo mkdir -p /mnt/btrfs-data/btrbk_snapshots
  {
    cat <<EOF
timestamp_format        long
snapshot_preserve_min   2d
snapshot_preserve       14d
target_preserve_min     no
target_preserve         20d 8w 6m
snapshot_dir            btrbk_snapshots

volume $BTRFS_ROOT
  subvolume @
  subvolume @home
  target send-receive $BACKUP_MOUNT/btrbk/nvme
EOF
    if mountpoint -q /mnt/btrfs-data 2>/dev/null; then
      cat <<EOF

volume /mnt/btrfs-data
  subvolume @data
  target send-receive $BACKUP_MOUNT/btrbk/data
EOF
    fi
  } | write_file_sudo /etc/btrbk/btrbk.conf 0644
  sudo mkdir -p /etc/systemd/system/btrbk.timer.d
  write_file_sudo /etc/systemd/system/btrbk.timer.d/override.conf 0644 <<'EOF'
[Timer]
OnCalendar=
OnCalendar=hourly
EOF
  sudo systemctl daemon-reload
  systemd_enable_now btrbk.timer
  sudo btrbk -q run || warn "first btrbk run failed; check 'sudo btrbk -v run'"
fi

log "storage done"; lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | grep -v loop
