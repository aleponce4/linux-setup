#!/usr/bin/env bash
# Rebuild strix's generated boot artifacts: initramfs, UEFI GRUB, grub.cfg.
# Backs up first. Never repartitions or formats. Only ever writes to /dev/nvme0n1.
set -euo pipefail
# cd / so that a relative root= path (e.g. the typo'd "root=dev/nvme0n1p2")
# still canonicalizes. See docs/boot-and-graphics.md.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd /
. "$SCRIPT_DIR/lib-common.sh"
need_root
assert_os_disk_only "$ROOT_DEV" "$ESP_DEV"

bk="/root/boot-repair-backup-$(date +%Y%m%d-%H%M%S)"
echo "== backing up to $bk =="
mkdir -p "$bk/esp"
cp -a /etc/fstab "$bk/fstab"
cp -a /etc/default/grub "$bk/default-grub"
cp -a /boot/grub/grub.cfg "$bk/grub.cfg"
cp -a /boot/efi/EFI "$bk/esp/EFI"
efibootmgr -v > "$bk/efibootmgr-v.txt" 2>&1 || true
blkid > "$bk/blkid.txt" 2>&1 || true

echo "== sanity: does GRUB resolve /boot correctly? =="
probed=$(grub-probe --target=fs_uuid /boot/grub)
if [ "$probed" != "$ROOT_UUID" ]; then
    echo "REFUSING: grub-probe says $probed, expected $ROOT_UUID" >&2
    exit 1
fi
echo "  grub-probe fs_uuid = $probed  (matches)"

echo "== regenerating initramfs for all installed kernels =="
update-initramfs -u -k all

echo "== reinstalling UEFI GRUB to the existing ESP =="
# --target is mandatory here: grub-pc is also installed on this box.
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
             --bootloader-id=ubuntu --recheck

echo "== regenerating grub.cfg =="
update-grub

echo
echo "== done. backup: $bk =="
echo "Now run: sudo scripts/verify-boot.sh"
