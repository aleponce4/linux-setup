#!/usr/bin/env bash
# Assert that strix's boot configuration is correct. Read-only.
# Run this before every reboot. Exits non-zero if any check fails.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd /
. "$SCRIPT_DIR/lib-common.sh"
need_root

fails=0
pass() { printf '  [PASS] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; fails=$((fails + 1)); }
warn() { printf '  [WARN] %s\n' "$1"; }

echo "== 1. root UUID in grub.cfg =="
stale=$(grep -oE 'root=UUID=[0-9a-f-]+' /boot/grub/grub.cfg | sort -u | grep -v "root=UUID=$ROOT_UUID" || true)
[ -z "$stale" ] && pass "all root=UUID= entries are $ROOT_UUID" || fail "stale UUID: $stale"

seen=$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' /boot/grub/grub.cfg | sort -u)
[ "$seen" = "$ROOT_UUID" ] && pass "no foreign UUID anywhere in grub.cfg" \
                           || fail "unexpected UUIDs in grub.cfg: $seen"

echo "== 2. blkid agrees with config =="
actual=$(blkid -s UUID -o value "$ROOT_DEV")
[ "$actual" = "$ROOT_UUID" ] && pass "$ROOT_DEV is $ROOT_UUID" \
                             || fail "$ROOT_DEV is $actual, expected $ROOT_UUID"

echo "== 3. /etc/fstab =="
grep -qE "^UUID=$ROOT_UUID[[:space:]]+/[[:space:]]+ext4" /etc/fstab \
    && pass "fstab root entry correct" || fail "fstab root entry wrong"
grep -qE "^UUID=$ESP_UUID[[:space:]]+/boot/efi" /etc/fstab \
    && pass "fstab ESP entry correct" || fail "fstab ESP entry wrong"

echo "== 4. no permanent nomodeset =="
if grep -rq 'nomodeset' /etc/default/grub /etc/default/grub.d/ 2>/dev/null; then
    fail "nomodeset present in /etc/default/grub*"
else
    pass "no nomodeset in /etc/default/grub*"
fi
total=$(grep -c 'nomodeset' /boot/grub/grub.cfg || true)
inrec=$(grep 'nomodeset' /boot/grub/grub.cfg | grep -c 'recovery' || true)
[ "$total" = "$inrec" ] && pass "nomodeset only in recovery entry ($total)" \
                        || fail "nomodeset in a normal boot entry"

echo "== 5. EFI boot entry =="
entry=$(efibootmgr -v | grep -iE '^Boot[0-9A-F]{4}\*?.*shimx64\.efi' | head -1)
if [ -z "$entry" ]; then
    fail "no EFI boot entry referencing shimx64.efi"
else
    echo "  $entry" | cut -c1-120
    if printf '%s' "$entry" | grep -qi "$ESP_PARTUUID"; then
        pass "EFI entry is on the OS-disk ESP ($ESP_PARTUUID)"
    else
        fail "EFI entry is NOT on $ESP_PARTUUID - it points at another disk"
    fi
    # Derive the on-disk path from NVRAM instead of assuming EFI/ubuntu.
    efipath=$(printf '%s' "$entry" | grep -oiE '\\EFI\\[^\\]+\\shimx64\.efi' | head -1 | tr '\\' '/')
    ondisk="/boot/efi${efipath}"
    if [ -f "$ondisk" ]; then
        pass "NVRAM target exists on disk: $ondisk"
        ESP_DIR=$(dirname "$ondisk")
    else
        fail "NVRAM points at $ondisk which DOES NOT EXIST - machine will not boot"
        ESP_DIR=""
    fi
fi
efibootmgr | grep -qE '^BootOrder: 0003' && pass "Kubuntu first in BootOrder" \
                                         || warn "Kubuntu is not first in BootOrder"

echo "== 6. ESP mounted and populated =="
findmnt -no SOURCE /boot/efi | grep -q "^$ESP_DEV$" && pass "/boot/efi <- $ESP_DEV" \
                                                    || fail "/boot/efi not mounted from $ESP_DEV"
if [ -n "${ESP_DIR:-}" ]; then
    for f in shimx64.efi grubx64.efi grub.cfg; do
        [ -f "$ESP_DIR/$f" ] && pass "$(basename "$ESP_DIR")/$f present" \
                             || fail "$(basename "$ESP_DIR")/$f missing"
    done
    grep -q "$ROOT_UUID" "$ESP_DIR/grub.cfg" && pass "ESP stub points at correct fs_uuid" \
                                             || fail "ESP stub has wrong fs_uuid"
fi
# Note any other bootable GRUB dirs on the ESP (duplicates are harmless but worth seeing).
others=$(find /boot/efi/EFI -maxdepth 1 -mindepth 1 -type d ! -name BOOT \
         ! -name "$(basename "${ESP_DIR:-none}")" -printf '%f ' 2>/dev/null)
[ -n "$others" ] && warn "other GRUB dirs on ESP (unused duplicates): $others"

echo "== 7. kernel and initramfs paired =="
for k in /boot/vmlinuz-*; do
    v=${k#/boot/vmlinuz-}
    [ -f "/boot/initrd.img-$v" ] && pass "initramfs present for $v" \
                                 || fail "no initramfs for kernel $v"
done

echo "== 8. GRUB menu reachable =="
ts=$(grep -E '^GRUB_TIMEOUT_STYLE=' /etc/default/grub | cut -d= -f2)
to=$(grep -E '^GRUB_TIMEOUT=' /etc/default/grub | cut -d= -f2)
if [ "$ts" = "menu" ] && [ "${to:-0}" -ge 3 ] 2>/dev/null; then
    pass "GRUB menu visible (style=$ts timeout=$to) - recovery mode reachable"
else
    warn "GRUB menu style=$ts timeout=$to - recovery mode may be hard to reach"
fi

echo "== 9. GPU Resizable BAR (the known open issue) =="
if dmesg 2>/dev/null | grep -qi 'Small BAR device'; then
    warn "GPU is in Small BAR mode - enable Above 4G Decoding + Re-Size BAR in BIOS"
    warn "see docs/boot-and-graphics.md"
elif lspci -vv -s "$GPU_PCI" 2>/dev/null | grep -q 'BAR 2: current size: 16GB'; then
    pass "Resizable BAR active (16GB)"
else
    warn "could not determine BAR state (are we booted with nomodeset?)"
fi

echo
if [ "$fails" -eq 0 ]; then
    echo "RESULT: boot configuration OK ($fails failures)"
else
    echo "RESULT: $fails FAILURE(S) - do not reboot until resolved"
fi
exit "$fails"
