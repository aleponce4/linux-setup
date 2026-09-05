#!/usr/bin/env bash
# 20-storage.sh - ext4/Btrfs-aware root setup, zram, independently mounted data/backup disks,
#                 and optional Btrfs-only Timeshift/grub-btrfs/btrbk support.
# No disk is formatted or repartitioned unless this invocation is exactly:
#   ./bootstrap.sh --format 20
# Even then, each serial-verified target requires its own typed confirmation.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config
ALLOW_FORMAT="no"
if [[ "${1:-}" == "--format" && $# -eq 1 ]]; then
  ALLOW_FORMAT="yes"
elif (( $# != 0 )); then
  die "usage: $0 [--format] (normally invoked as ./bootstrap.sh --format 20)"
fi
UID_T="$(id -u "$TARGET_USER")"; GID_T="$(id -g "$TARGET_USER")"

ensure_fstab_mount() {
  local source_spec="$1" mountpoint_path="$2" fstype="$3" options="$4" dump="$5" passno="$6"
  local wanted="$source_spec $mountpoint_path $fstype $options $dump $passno"
  local current_source current_mount current_fstype current_options current_dump current_pass
  local current_device wanted_device
  local -a fstab_entries=()
  mapfile -t fstab_entries < <(
    awk -v mountpoint_path="$mountpoint_path" \
      '!/^[[:space:]]*#/ && NF >= 2 && $2 == mountpoint_path {print}' /etc/fstab
  )
  if (( ${#fstab_entries[@]} == 0 )); then
    ensure_line /etc/fstab "$wanted"
    return 0
  fi
  (( ${#fstab_entries[@]} == 1 )) || \
    die "refusing to change /etc/fstab: $mountpoint_path has duplicate entries"
  read -r current_source current_mount current_fstype current_options current_dump current_pass \
    <<<"${fstab_entries[0]}"
  if [[ "$current_source" == "$source_spec" && "$current_mount" == "$mountpoint_path" \
      && "$current_fstype" == "$fstype" && "$current_options" == "$options" \
      && "$current_dump" == "$dump" && "$current_pass" == "$passno" ]]; then
    return 0
  fi
  # Accept an older repo-generated LABEL= entry only when it resolves to the same exact filesystem
  # and all mount behavior is otherwise identical. New entries are always written with UUID=.
  if [[ "$current_mount" == "$mountpoint_path" && "$current_fstype" == "$fstype" \
      && "$current_options" == "$options" && "$current_dump" == "$dump" \
      && "$current_pass" == "$passno" ]]; then
    current_device="$(findfs "$current_source" 2>/dev/null || true)"
    wanted_device="$(findfs "$source_spec" 2>/dev/null || true)"
    if [[ -n "$current_device" && -n "$wanted_device" \
        && "$(canonical_block_device "$current_device")" == "$(canonical_block_device "$wanted_device")" ]]; then
      log "existing equivalent fstab source retained for $mountpoint_path: $current_source"
      return 0
    fi
  fi
  die "refusing to change /etc/fstab: $mountpoint_path already has a different entry"
}

partition_with_label_on_disk() {
  local disk_id="$1" label="$2" disk matches=()
  disk="$(canonical_block_device "$disk_id")" || return 1
  mapfile -t matches < <(
    lsblk -nrpo NAME,TYPE,LABEL "$disk" 2>/dev/null \
      | awk -v wanted="$label" '$2 == "part" && $3 == wanted {print $1}'
  )
  (( ${#matches[@]} == 1 )) || {
    (( ${#matches[@]} == 0 )) || die "more than one partition labeled '$label' exists on $disk_id"
    return 1
  }
  printf '%s\n' "${matches[0]}"
}

partition_with_partlabel_on_disk() {
  local disk_id="$1" label="$2" disk matches=()
  disk="$(canonical_block_device "$disk_id")" || return 1
  mapfile -t matches < <(
    lsblk -nrpo NAME,TYPE,PARTLABEL "$disk" 2>/dev/null \
      | awk -v wanted="$label" '$2 == "part" && $3 == wanted {print $1}'
  )
  (( ${#matches[@]} == 1 )) || {
    (( ${#matches[@]} == 0 )) || die "more than one partition with PARTLABEL '$label' exists on $disk_id"
    return 1
  }
  printf '%s\n' "${matches[0]}"
}

show_exact_disk() {
  local disk_id="$1" serial="$2" purpose="$3" disk
  disk="$(canonical_block_device "$disk_id")" || die "$purpose disk is unavailable: $disk_id"
  printf '\n%s\n' "EXACT $purpose TARGET"
  printf '  stable id: %s\n  resolved:  %s\n  serial:    %s\n' "$disk_id" "$disk" "$serial"
  lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS,MODEL,SERIAL "$disk"
}

assert_disk_safe_for_change() {
  local disk_id="$1" serial="$2" purpose="$3" disk root_disk node holder_dir
  disk_matches "$disk_id" "$serial" || \
    die "$purpose target does not match its stable by-id and serial: $disk_id / $serial"
  disk="$(canonical_block_device "$disk_id")"
  root_disk="$(parent_disk "$ROOT_DEVICE_ACTUAL")" || die "cannot resolve the running root's parent disk"
  [[ "$disk" != "$root_disk" ]] || die "REFUSING: $purpose target $disk holds the running root filesystem"

  if lsblk -nrpo MOUNTPOINTS "$disk" 2>/dev/null | awk 'NF {found=1} END {exit !found}'; then
    die "REFUSING: $purpose target $disk has mounted filesystems; unmount and inspect it manually"
  fi
  while IFS= read -r node; do
    [[ -n "$node" ]] || continue
    if swapon --noheadings --raw --show=NAME 2>/dev/null | grep -Fqx "$node"; then
      die "REFUSING: $purpose target contains active swap: $node"
    fi
    holder_dir="/sys/class/block/$(basename "$node")/holders"
    if [[ -d "$holder_dir" ]] && compgen -G "$holder_dir/*" >/dev/null; then
      die "REFUSING: $purpose target has active device-mapper/RAID holders: $node"
    fi
  done < <(lsblk -nrpo NAME "$disk")
  show_exact_disk "$disk_id" "$serial" "$purpose"
}

confirm_disk_change() {
  local disk_id="$1" serial="$2" description="$3" answer expected
  expected="FORMAT $serial"
  printf '%s\n' "DESTRUCTIVE ACTION: $description"
  read -r -p "Type '$expected' to continue: " answer
  [[ "$answer" == "$expected" ]] || { warn "confirmation did not match; skipped $disk_id"; return 1; }
}

# ---------- 1. Validate the running root before any storage configuration ----------
ROOT_SOURCE="$(findmnt -nro SOURCE /)"
ROOT_SOURCE="${ROOT_SOURCE%%\[*}"
ROOT_DEVICE_ACTUAL="$(canonical_block_device "$ROOT_SOURCE")" || die "cannot resolve running root source: $ROOT_SOURCE"
ROOT_FSTYPE_ACTUAL="$(findmnt -nro FSTYPE /)"
ROOT_UUID_ACTUAL="$(findmnt -nro UUID / 2>/dev/null || true)"
[[ -n "$ROOT_UUID_ACTUAL" ]] || ROOT_UUID_ACTUAL="$(blkid -s UUID -o value "$ROOT_DEVICE_ACTUAL")"

expected_root="$(canonical_block_device "$ROOT_DEVICE")" || die "configured ROOT_DEVICE is unavailable: $ROOT_DEVICE"
[[ "$ROOT_DEVICE_ACTUAL" == "$expected_root" ]] || \
  die "running root is $ROOT_DEVICE_ACTUAL, but config/storage.conf expects $expected_root"
[[ "$ROOT_FSTYPE_ACTUAL" == "$ROOT_FS" ]] || \
  die "running root filesystem is $ROOT_FSTYPE_ACTUAL, but config/storage.conf expects $ROOT_FS"
[[ "$ROOT_UUID_ACTUAL" == "$ROOT_UUID" ]] || \
  die "running root UUID is $ROOT_UUID_ACTUAL, but config/storage.conf expects $ROOT_UUID"
disk_matches "$ROOT_DISK_ID" "$ROOT_DISK_SERIAL" || \
  die "configured 990 PRO identity does not match: $ROOT_DISK_ID / $ROOT_DISK_SERIAL"
root_parent="$(parent_disk "$ROOT_DEVICE_ACTUAL")" || die "cannot resolve the running root's parent disk"
expected_root_parent="$(canonical_block_device "$ROOT_DISK_ID")"
[[ "$root_parent" == "$expected_root_parent" ]] || \
  die "running root is on $root_parent, not the configured 990 PRO $expected_root_parent"
for protected_id in "$DATA_DISK_ID" "$BACKUP_DISK_ID"; do
  if [[ -e "$protected_id" ]]; then
    [[ "$(canonical_block_device "$protected_id")" != "$root_parent" ]] || \
      die "REFUSING: a protected data/backup disk is the running root: $protected_id"
  fi
done
if [[ -e "$DATA_DISK_ID" && -e "$BACKUP_DISK_ID" ]]; then
  [[ "$(canonical_block_device "$DATA_DISK_ID")" != "$(canonical_block_device "$BACKUP_DISK_ID")" ]] || \
    die "REFUSING: data and backup identities resolve to the same physical disk"
fi
log "root verified: $ROOT_DEVICE_ACTUAL, $ROOT_FSTYPE_ACTUAL, UUID=$ROOT_UUID_ACTUAL, disk=$ROOT_DISK_ID"

apt_install btrfs-progs gdisk parted ntfs-3g
BTRFS_ROOT=""

# ---------- 2. Root-filesystem-specific configuration ----------
case "$ROOT_FSTYPE_ACTUAL" in
  ext4)
    log "ext4 root: leaving root mounts and /var/lib/docker unchanged; recovery is provided by restic"
    [[ "${ENABLE_SNAPSHOTS:-yes}" != "yes" ]] || \
      log "ext4 root: skipping Btrfs-only Timeshift/grub-btrfs snapshots"
    ;;
  btrfs)
    BTRFS_ROOT=/mnt/btrfs-root
    sudo mkdir -p "$BTRFS_ROOT"
    ensure_fstab_mount "UUID=$ROOT_UUID_ACTUAL" "$BTRFS_ROOT" btrfs "subvolid=5,noatime,nofail" 0 0
    mountpoint -q "$BTRFS_ROOT" || sudo mount "$BTRFS_ROOT"
    mount_matches_btrfs_filesystem "$BTRFS_ROOT" "$ROOT_DISK_ID" "$ROOT_DISK_SERIAL" \
      "$ROOT_UUID_ACTUAL" / || \
      die "$BTRFS_ROOT is not the top-level filesystem from the configured 990 PRO root"
    for sv in @ @home; do
      sudo btrfs subvolume show "$BTRFS_ROOT/$sv" >/dev/null 2>&1 || \
        die "top-level subvolume $sv missing; the optional Btrfs layout requires @ and @home"
    done

    # Docker data remains outside Timeshift root snapshots.
    if ! sudo btrfs subvolume show "$BTRFS_ROOT/@docker" >/dev/null 2>&1; then
      sudo btrfs subvolume create "$BTRFS_ROOT/@docker"
      log "created @docker subvolume"
    fi
    sudo mkdir -p /var/lib/docker
    ensure_fstab_mount "UUID=$ROOT_UUID_ACTUAL" /var/lib/docker btrfs \
      "subvol=@docker,noatime,compress=zstd:1" 0 0
    mountpoint -q /var/lib/docker || sudo mount /var/lib/docker
    mount_matches_btrfs_filesystem /var/lib/docker "$ROOT_DISK_ID" "$ROOT_DISK_SERIAL" \
      "$ROOT_UUID_ACTUAL" /@docker || \
      die "/var/lib/docker is not the @docker subvolume from the configured Btrfs root filesystem"

    if ! findmnt -nro OPTIONS / | grep -q compress; then
      sudo sed -i -E \
        "s|^(UUID=${ROOT_UUID_ACTUAL}[[:space:]]+/[[:space:]]+btrfs[[:space:]]+)([^[:space:]]+)|\1\2,compress=zstd:1|" \
        /etc/fstab
      sudo mount -o remount / || warn "could not enable Btrfs root compression until next boot"
    fi

    if [[ "${ENABLE_SNAPSHOTS:-yes}" == "yes" ]]; then
      apt_install timeshift inotify-tools make git
      write_file_sudo /etc/timeshift/timeshift.json 0644 <<EOF
{
  "backup_device_uuid" : "$ROOT_UUID_ACTUAL",
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
      if ! sudo timeshift --list 2>/dev/null | grep -q 'linux-setup baseline'; then
        sudo timeshift --create --comments "linux-setup baseline" --tags O >/dev/null 2>&1 \
          || warn "initial Timeshift snapshot failed (run it after reboot)"
      fi
      sudo update-grub >/dev/null 2>&1 || warn "update-grub failed"
    fi
    ;;
  *)
    die "unsupported root filesystem: $ROOT_FSTYPE_ACTUAL (supported: ext4, btrfs)"
    ;;
esac

# ---------- 3. zram swap (independent of root filesystem) ----------
apt_install systemd-zram-generator
write_file_sudo /etc/systemd/zram-generator.conf 0644 <<'EOF'
[zram0]
zram-size = min(ram / 2, 16384)
compression-algorithm = zstd
swap-priority = 100
EOF
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
write_file_sudo /etc/sysctl.d/99-zram.conf 0644 <<'EOF'
vm.swappiness = 150
vm.page-cluster = 0
EOF
sudo sysctl -q --system >/dev/null

# ---------- 4. /data on the serial-verified SATA SSD ----------
SETUP_PART=""
setup_btrfs_data_disk() {
  local disk_id="$1" serial="$2" label="$3" disk part
  disk_matches "$disk_id" "$serial" || { warn "$label disk missing or identity mismatch: $disk_id"; return 1; }
  if part="$(partition_with_label_on_disk "$disk_id" "$label")"; then
    [[ "$(sudo blkid -s TYPE -o value "$part")" == "btrfs" ]] || \
      die "$part is labeled $label but is not Btrfs; refusing to alter it"
    SETUP_PART="$part"
    return 0
  fi
  if [[ "$ALLOW_FORMAT" != "yes" ]]; then
    warn "no Btrfs filesystem labeled '$label' on $disk_id; leaving the existing disk unchanged"
    return 1
  fi

  assert_disk_safe_for_change "$disk_id" "$serial" "$label"
  confirm_disk_change "$disk_id" "$serial" \
    "wipe and repartition $(canonical_block_device "$disk_id") as one Btrfs filesystem labeled '$label'" || return 1
  # Revalidate after the interactive pause so hotplug or mount changes cannot retarget the write.
  assert_disk_safe_for_change "$disk_id" "$serial" "$label"
  disk="$(canonical_block_device "$disk_id")"
  sudo wipefs -a "$disk" >/dev/null
  sudo sgdisk -Z "$disk" >/dev/null
  sudo sgdisk -n 1:0:0 -t 1:8300 -c "1:$label" "$disk" >/dev/null
  sudo partprobe "$disk"; sleep 2
  part="$(partition_with_partlabel_on_disk "$disk_id" "$label")" || \
    die "could not find the new '$label' partition on $disk_id"
  sudo mkfs.btrfs -q -f -L "$label" "$part"
  SETUP_PART="$part"
  log "formatted $part as Btrfs '$label'"
}

if setup_btrfs_data_disk "$DATA_DISK_ID" "$DATA_DISK_SERIAL" data; then
  DATA_PART="$SETUP_PART"
  DATA_UUID="$(sudo blkid -s UUID -o value "$DATA_PART")"
  [[ "$(parent_disk "$DATA_PART")" == "$(canonical_block_device "$DATA_DISK_ID")" ]] || \
    die "data partition is not on the configured Samsung 860"
  sudo mkdir -p /mnt/btrfs-data "$DATA_MOUNT"
  ensure_fstab_mount "UUID=$DATA_UUID" /mnt/btrfs-data btrfs "subvolid=5,noatime,nofail" 0 0
  mountpoint -q /mnt/btrfs-data || sudo mount /mnt/btrfs-data
  mount_matches_btrfs_filesystem /mnt/btrfs-data "$DATA_DISK_ID" "$DATA_DISK_SERIAL" "$DATA_UUID" / || \
    die "/mnt/btrfs-data is not the expected filesystem from the configured Samsung 860"
  sudo btrfs subvolume show /mnt/btrfs-data/@data >/dev/null 2>&1 \
    || sudo btrfs subvolume create /mnt/btrfs-data/@data >/dev/null
  ensure_fstab_mount "UUID=$DATA_UUID" "$DATA_MOUNT" btrfs \
    "subvol=@data,noatime,compress=zstd:1,nofail" 0 0
  mountpoint -q "$DATA_MOUNT" || sudo mount "$DATA_MOUNT"
  mount_matches_btrfs_filesystem "$DATA_MOUNT" "$DATA_DISK_ID" "$DATA_DISK_SERIAL" \
    "$DATA_UUID" /@data || \
    die "$DATA_MOUNT is not the @data subvolume from the configured Samsung 860"
  if [[ "${ENABLE_VM_STACK:-no}" == "yes" ]]; then
    sudo btrfs subvolume show /mnt/btrfs-data/@vms >/dev/null 2>&1 \
      || { sudo btrfs subvolume create /mnt/btrfs-data/@vms >/dev/null; sudo chattr +C /mnt/btrfs-data/@vms; }
    sudo mkdir -p /var/lib/libvirt/images
    ensure_fstab_mount "UUID=$DATA_UUID" /var/lib/libvirt/images btrfs \
      "subvol=@vms,noatime,nodatacow,nofail" 0 0
    mountpoint -q /var/lib/libvirt/images || sudo mount /var/lib/libvirt/images
    mount_matches_btrfs_filesystem /var/lib/libvirt/images "$DATA_DISK_ID" "$DATA_DISK_SERIAL" \
      "$DATA_UUID" /@vms || die "/var/lib/libvirt/images is not the expected @vms subvolume"
  fi
  sudo chown "$UID_T:$GID_T" "$DATA_MOUNT"
  for d in $DATA_DIRS; do mkdir -p "$DATA_MOUNT/$d"; done
  if [[ -L "$HOME/data" ]]; then
    ln -sfn "$DATA_MOUNT" "$HOME/data"
  elif [[ ! -e "$HOME/data" ]]; then
    ln -s "$DATA_MOUNT" "$HOME/data"
  else
    warn "$HOME/data exists and is not a symlink; leaving it unchanged"
  fi
fi

# ---------- 5. HDD: existing WINRESCUE plus optional existing /backup ----------
if disk_matches "$BACKUP_DISK_ID" "$BACKUP_DISK_SERIAL"; then
  if WINRESCUE_PART="$(partition_with_label_on_disk "$BACKUP_DISK_ID" "$WINRESCUE_LABEL")"; then
    [[ "$(sudo blkid -s TYPE -o value "$WINRESCUE_PART")" =~ ^ntfs ]] || \
      die "$WINRESCUE_PART is labeled $WINRESCUE_LABEL but is not NTFS"
    WINRESCUE_UUID="$(sudo blkid -s UUID -o value "$WINRESCUE_PART")"
    sudo mkdir -p /mnt/winrescue
    ensure_fstab_mount "UUID=$WINRESCUE_UUID" /mnt/winrescue ntfs3 \
      "ro,nofail,uid=$UID_T,gid=$GID_T,x-systemd.automount" 0 0
    sudo systemctl daemon-reload
    log "WINRESCUE will auto-mount read-only from the configured HGST disk"
  else
    warn "no partition labeled $WINRESCUE_LABEL on the configured HGST disk"
  fi

  BACKUP_PART=""
  if BACKUP_PART="$(partition_with_label_on_disk "$BACKUP_DISK_ID" backup)"; then
    [[ "$(sudo blkid -s TYPE -o value "$BACKUP_PART")" == "btrfs" ]] || \
      die "$BACKUP_PART is labeled backup but is not Btrfs; refusing to alter it"
  elif [[ "$ALLOW_FORMAT" == "yes" ]]; then
    assert_disk_safe_for_change "$BACKUP_DISK_ID" "$BACKUP_DISK_SERIAL" backup
    if confirm_disk_change "$BACKUP_DISK_ID" "$BACKUP_DISK_SERIAL" \
      "create one new Btrfs 'backup' partition in unallocated space on $(canonical_block_device "$BACKUP_DISK_ID"); existing partitions are preserved"; then
      # Revalidate after the interactive pause so hotplug or mount changes cannot retarget the write.
      assert_disk_safe_for_change "$BACKUP_DISK_ID" "$BACKUP_DISK_SERIAL" backup
      backup_disk="$(canonical_block_device "$BACKUP_DISK_ID")"
      sudo sgdisk -n 0:0:0 -t 0:8300 -c 0:backup "$backup_disk" >/dev/null
      sudo partprobe "$backup_disk"; sleep 2
      BACKUP_PART="$(partition_with_partlabel_on_disk "$BACKUP_DISK_ID" backup)" || \
        die "could not find the new backup partition on $BACKUP_DISK_ID"
      sudo mkfs.btrfs -q -f -L backup "$BACKUP_PART"
      log "formatted $BACKUP_PART as Btrfs 'backup'"
    fi
  else
    warn "no Btrfs filesystem labeled 'backup' on the configured HGST disk; leaving it unchanged"
  fi

  if [[ -n "$BACKUP_PART" ]]; then
    BACKUP_UUID="$(sudo blkid -s UUID -o value "$BACKUP_PART")"
    [[ "$(parent_disk "$BACKUP_PART")" == "$(canonical_block_device "$BACKUP_DISK_ID")" ]] || \
      die "backup partition is not on the configured HGST disk"
    sudo mkdir -p "$BACKUP_MOUNT"
    ensure_fstab_mount "UUID=$BACKUP_UUID" "$BACKUP_MOUNT" btrfs \
      "noatime,compress=zstd:3,nofail" 0 0
    mountpoint -q "$BACKUP_MOUNT" || sudo mount "$BACKUP_MOUNT"
    mount_matches_btrfs_filesystem "$BACKUP_MOUNT" "$BACKUP_DISK_ID" "$BACKUP_DISK_SERIAL" \
      "$BACKUP_UUID" / || \
      die "$BACKUP_MOUNT is not the top-level Btrfs filesystem from the configured HGST disk"
    sudo mkdir -p "$BACKUP_MOUNT/restic"
    sudo chown "$UID_T:$GID_T" "$BACKUP_MOUNT/restic"
  fi
else
  warn "configured HGST disk missing or identity mismatch; WINRESCUE and /backup were not touched"
fi

# ---------- 6. Optional Btrfs-only send/receive layer ----------
if [[ "${ENABLE_BTRBK:-yes}" == "yes" ]]; then
  if [[ "$ROOT_FSTYPE_ACTUAL" != "btrfs" ]]; then
    log "ext4 root: skipping Btrfs-only btrbk; restic is the system recovery path"
  elif [[ -n "${BACKUP_UUID:-}" ]] \
      && mount_matches_btrfs_filesystem "$BACKUP_MOUNT" "$BACKUP_DISK_ID" "$BACKUP_DISK_SERIAL" \
        "$BACKUP_UUID" /; then
    apt_install btrbk
    sudo mkdir -p "$BACKUP_MOUNT/btrbk/nvme" "$BACKUP_MOUNT/btrbk/data"
    sudo mkdir -p "$BTRFS_ROOT/btrbk_snapshots"
    if [[ -n "${DATA_UUID:-}" ]] \
        && mount_matches_btrfs_filesystem /mnt/btrfs-data "$DATA_DISK_ID" "$DATA_DISK_SERIAL" \
          "$DATA_UUID" /; then
      sudo mkdir -p /mnt/btrfs-data/btrbk_snapshots
    fi
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
      if [[ -n "${DATA_UUID:-}" ]] \
          && mount_matches_btrfs_filesystem /mnt/btrfs-data "$DATA_DISK_ID" "$DATA_DISK_SERIAL" \
            "$DATA_UUID" /; then
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
  else
    warn "Btrfs root detected, but the verified Btrfs backup target is unavailable; btrbk skipped"
  fi
fi

log "storage done"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,SERIAL | grep -v loop
