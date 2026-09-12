#!/usr/bin/env bash
# PreToolUse hook: the blast radius of the unattended crash agent, enforced.
#
# The agent runs with bypassPermissions because nobody is awake to answer prompts. That makes this
# the only thing standing between a bad inference at 3am and an unbootable machine, so the limits
# live here as code rather than as a paragraph in a prompt that a model can reason its way around.
#
# Allowed: systemd units, config files, the linux-setup repo, and apt.
# Refused: bootloader, initramfs, kernel packages, partitions and filesystems, /boot, fstab,
#          user accounts, reboots, and git push.
#
# Contract: read the hook JSON on stdin, exit 2 to block with the reason on stderr, exit 0 to
# stay out of the way. Exit 2 blocks regardless of permission mode.
set -uo pipefail

payload=$(cat)
log() { logger -t strix-crash-agent-guard -p daemon.warning "$*"; }

deny() {
    log "DENIED: $1 -- $2"
    printf 'Blocked by the crash-agent guard: %s\n\nRefused command: %s\n' "$1" "$2" >&2
    printf 'This limit is deliberate. Fix what you can within it, and write anything that needs\n' >&2
    printf 'bootloader, kernel, partition or push access into your summary for a human instead.\n' >&2
    exit 2
}

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)

case "$tool" in
Bash)
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
    # Nothing to inspect on a Bash call means the payload is not what this hook expects. Refuse
    # rather than wave it through: an unparseable command is exactly the one worth stopping.
    [ -n "$cmd" ] || deny "could not read the command from the hook payload" "(unparseable)"

    # Publishing. Local git is fine -- committing is part of the job -- but nothing leaves the box.
    printf '%s' "$cmd" | grep -Eq '\bgit\b[^|;&]*\bpush\b' \
        && deny "git push: the agent commits locally, a human decides what gets published" "$cmd"

    # Bootloader and initramfs: the failure mode is a machine that does not come back.
    printf '%s' "$cmd" | grep -Eq '\b(grub-install|update-grub|grub-mkconfig|grub2-mkconfig|update-initramfs|mkinitramfs|dracut|efibootmgr|kernel-install|bootctl)\b' \
        && deny "bootloader/initramfs changes need a human at the keyboard" "$cmd"

    # Partitioning and filesystems.
    printf '%s' "$cmd" | grep -Eq '\b(mkfs(\.[a-z0-9]+)?|fdisk|sfdisk|sgdisk|cfdisk|parted|partprobe|wipefs|badblocks|cryptsetup|mdadm|pvcreate|pvremove|vgremove|lvremove|lvresize|resize2fs|btrfstune)\b' \
        && deny "partition/filesystem operations are out of scope for an unattended fix" "$cmd"

    # Raw writes to block devices, including dd and shell redirection.
    printf '%s' "$cmd" | grep -Eq '(\bdd\b[^|;&]*\bof=[[:space:]]*/dev/|>[[:space:]]*/dev/(sd|nvme|vd|mapper))' \
        && deny "writing directly to a block device" "$cmd"

    # Mutating /boot, fstab, crypttab or the grub defaults. Reading them is fine and often useful.
    printf '%s' "$cmd" | grep -Eq '((^|[|;&[:space:]])(rm|mv|cp|tee|truncate|install|chmod|chown|ln)\b[^|;&]*(/boot/|/etc/fstab|/etc/crypttab|/etc/default/grub))|(sed\b[^|;&]*-i[^|;&]*(/boot/|/etc/fstab|/etc/crypttab|/etc/default/grub))|(>[[:space:]]*(/boot/|/etc/fstab|/etc/crypttab|/etc/default/grub))' \
        && deny "modifying /boot, fstab, crypttab or grub defaults" "$cmd"

    # Removing the packages that make the machine bootable, reachable, or administrable. apt is
    # otherwise allowed: installing a missing package is a legitimate fix.
    printf '%s' "$cmd" | grep -Eq '\b(apt|apt-get|dpkg|aptitude)\b[^|;&]*(remove|purge|autoremove|--remove)' \
        && printf '%s' "$cmd" | grep -Eq '(linux-image|linux-headers|linux-generic|linux-firmware|\bgrub|\bsystemd\b|\bsudo\b|openssh-server|tailscale|network-manager|\bufw\b)' \
        && deny "removing a boot-critical, network-critical or access-critical package" "$cmd"

    # Rebooting is a judgement call with unsaved work on the line, and a reboot loop is the exact
    # failure this whole system exists to catch rather than cause.
    printf '%s' "$cmd" | grep -Eq '\b(reboot|poweroff|halt|kexec)\b|\bshutdown\b[^|;&]*-[hrHR]|\bsystemctl\b[^|;&]*\b(reboot|poweroff|halt|kexec|emergency|rescue)\b|\btelinit\b' \
        && deny "rebooting or changing runlevel; recommend it in your summary instead" "$cmd"

    # Accounts, credentials and sudo policy.
    printf '%s' "$cmd" | grep -Eq '\b(userdel|useradd|usermod|passwd|chpasswd|visudo|gpasswd)\b|>[[:space:]]*/etc/sudoers' \
        && deny "changing user accounts or sudo policy" "$cmd"

    # rm -rf against a root-level path.
    printf '%s' "$cmd" | grep -Eq '\brm\b[^|;&]*-[a-zA-Z]*[rR][a-zA-Z]*f|\brm\b[^|;&]*-[a-zA-Z]*f[a-zA-Z]*[rR]' \
        && printf '%s' "$cmd" | grep -Eq '[[:space:]]/(bin|boot|dev|etc|lib|lib64|proc|root|sbin|sys|usr|var)?/?([[:space:]]|$)' \
        && deny "recursive delete of a system path" "$cmd"
    ;;

Edit|Write|NotebookEdit|MultiEdit)
    path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
    case "$path" in
        /boot/*|/etc/fstab|/etc/crypttab|/etc/default/grub|/etc/sudoers|/etc/sudoers.d/*|/dev/*)
            deny "editing a boot-critical or privilege-critical file" "$path" ;;
    esac
    ;;
esac

exit 0
