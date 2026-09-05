#!/usr/bin/env bash
# Dump everything needed to triage a boot or graphics problem on strix.
# Read-only. Writes one timestamped file in the current directory.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
INVOKED_FROM="$PWD"
cd /
. "$SCRIPT_DIR/lib-common.sh"
need_root

out="$INVOKED_FROM/diagnostics-$(date +%Y%m%d-%H%M%S).txt"
run() { printf '\n########## %s ##########\n' "$*"; "$@" 2>&1 || true; }

{
    run uname -a
    run cat /proc/cmdline
    run findmnt /
    run findmnt /boot/efi
    run cat /etc/fstab
    run cat /etc/default/grub
    run lsblk -f
    run lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,MOUNTPOINT
    run blkid
    run efibootmgr -v
    run ls -laR /boot/efi/EFI
    run cat /boot/efi/EFI/ubuntu/grub.cfg
    run cat /boot/grub/grub.cfg
    run lspci -nnk -s "$GPU_PCI"
    run lspci -vv -s "$GPU_PCI"
    run journalctl --list-boots --no-pager

    printf '\n########## per-boot summary ##########\n'
    for b in 0 -1 -2 -3 -4 -5; do
        journalctl -b "$b" -k --no-pager 2>/dev/null | grep -m1 -i 'Kernel command line' \
            && printf '  boot %s greeter restarts: %s\n' "$b" \
                 "$(journalctl -b "$b" --no-pager 2>/dev/null | grep -c 'Greeter starting')"
    done

    printf '\n########## GPU / drm errors, current boot ##########\n'
    journalctl -b 0 -k --no-pager 2>&1 | grep -iE 'xe |drm|Small BAR|PCODE|firmware' | head -60
    printf '\n########## sddm, current boot ##########\n'
    journalctl -b 0 -u sddm --no-pager 2>&1 | head -60
} > "$out"

echo "wrote $out"
