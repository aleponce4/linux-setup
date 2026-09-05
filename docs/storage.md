# Storage architecture

`strix` currently runs Kubuntu 26.04 with an ext4 root. Btrfs is an optional layout for a future reinstall,
not a prerequisite for provisioning the workstation.

## Current machine facts

| Role | Identity | Expected use |
|---|---|---|
| OS | Samsung 990 PRO 1 TB NVMe | `/dev/nvme0n1p2` mounted at `/`, ext4, UUID `1e0539dd-c9b4-4222-9076-48a11c6154d9` |
| Data | Samsung 860 EVO 500 GB SATA SSD | separate `/data` mount when configured; never the root filesystem |
| Rescue and backup | 8 TB HGST HDD | read-only `WINRESCUE` and separate `/backup` when configured; never the root filesystem |

The stable whole-disk identities are recorded in `config/storage.conf` using `/dev/disk/by-id/` paths. The Samsung
860 and HGST disks must never be identified by `/dev/sda` or `/dev/sdb`, because those names can change
between boots. Persistent filesystem mounts should use filesystem UUIDs; serial-backed `by-id` paths are
used to confirm which physical disk owns a filesystem.

The known `/dev/nvme0n1p2` name is recorded as a current-machine fact, but its filesystem UUID and the
Samsung 990 PRO whole-disk identity are the durable checks.

Use these read-only commands when checking the layout:

```bash
findmnt -no SOURCE,FSTYPE,UUID /
lsblk -o NAME,PATH,MODEL,SERIAL,SIZE,FSTYPE,UUID,MOUNTPOINTS
readlink -f /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_with_Heatsink_1TB_0025_3848_4140_33A2
readlink -f /dev/disk/by-id/ata-Samsung_SSD_860_EVO_500GB_S3Z1NY0M404409Z
readlink -f /dev/disk/by-id/ata-HGST_HUH728080ALE604_VLJAA2TY
```

Stop if `/` resolves to the Samsung 860 or HGST disk, or if its filesystem type or UUID differs from the
configured current-machine facts.

## Root-filesystem behavior

Module 20 detects the live root with `findmnt -n -o FSTYPE /` and treats the configured root filesystem as
an assertion. It does not convert one filesystem into another.

### Current ext4 root

- Keep the installer's ordinary ext4 root mount and Docker directory.
- Do not run Btrfs subvolume, compression, send/receive, Timeshift, or `grub-btrfs` operations against `/`.
- Continue configuring root-independent services such as zram and safe discovery of existing `/data`,
  `WINRESCUE`, and `/backup` filesystems.
- Use restic plus ordinary file backups for recovery. There is no root-snapshot rollback path.

For complete root loss, reinstall Kubuntu on the Samsung 990 PRO only, rerun this repository's bootstrap,
verify the external mounts, and restore the required files from restic or `WINRESCUE`.

### Optional future Btrfs root

A deliberately installed Btrfs root retains the repo's existing optional behavior: validation of the `@`
and `@home` layout, an `@docker` subvolume, Timeshift in Btrfs mode, boot entries through `grub-btrfs`, and
`btrbk` snapshots/send-receive when their feature flags are enabled. The repo has never used Snapper.

Snapshots are quick local rollback points, not backups. Restic remains required on a Btrfs installation.

The files under `autoinstall/` are an archived prototype, not a supported way to create that future layout.
They do not yet establish the required subvolume contract or update the generated root UUID in
`config/storage.conf`. Do not write that prototype to USB until it is deliberately redesigned and validated.

## `/data`, `WINRESCUE`, and `/backup`

External storage is independent of the root filesystem. An ext4 root does not imply that the data or
backup filesystems must be ext4, and a future Btrfs root does not authorize changing either external disk.

Before a restore, backup, or large copy, confirm that every path involved is an actual mount and inspect
the owning disk:

```bash
mountpoint -q /data && findmnt /data
mountpoint -q /backup && findmnt /backup
mountpoint -q /mnt/winrescue && findmnt /mnt/winrescue
lsblk -o NAME,PATH,MODEL,SERIAL,SIZE,FSTYPE,UUID,MOUNTPOINTS
```

Do not continue if `mountpoint` fails. A plain `/data` or `/backup` directory on the ext4 root is not an
acceptable substitute: copying into it would fill the OS disk, and a backup written there would not survive
root-disk loss. `WINRESCUE` must remain read-only.

## Destructive-operation policy

Normal bootstrap and module runs are non-destructive. They may inspect disks and configure mounts for
filesystems that already exist, but they must not create partition tables, partitions, or filesystems.

The `--format` option is reserved for a future, deliberately selected blank replacement disk. It is not part
of the current-machine setup. Even with that runtime flag, module 20 must first display the exact resolved
`by-id` target and require an exact typed confirmation naming that device. A config-file setting alone never
authorizes formatting.

Do not use that option on the current Samsung 990 PRO, Samsung 860, or HGST disks. Do not format or
repartition any existing disk during this migration.

## Recovery commands

Run an immediate restic backup with `backupnow` after `/data` and `/backup` have both been verified. List
available restore points with:

```bash
sudo restic -r /backup/restic -p /etc/restic/password snapshots
```

Restore into a temporary directory first, inspect it, and then copy only the intended files into place. The
`snapnow` shell helper deliberately refuses to run on ext4; it is available only on an optional Btrfs root
with Timeshift installed.

When module 85 initializes an empty repository, it queues the first backup without blocking bootstrap.
Module 90 will report `Backup: restic has snapshots` as `FAIL` until it finishes; watch it with
`journalctl -u restic-backup -f`, then rerun `./bootstrap.sh 90`.
