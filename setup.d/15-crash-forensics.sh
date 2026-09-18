#!/usr/bin/env bash
# 15-crash-forensics.sh - make the next unexplained reboot explainable after the fact
#
# On 2026-09-10 the machine stopped at 17:41:45 and nothing on disk could say why: no shutdown
# sequence, no panic trace, and by the time anyone looked the question "did it lose power, or did
# the kernel die with the power on?" had no answer left. Everything here exists to make that
# question answerable next time, without changing how the machine behaves.
#
# Deliberately NOT installed: kdump (permanently reserves RAM for a capture kernel) and
# panic-on-hung-task / hardware watchdog (they reboot the box on their own and take unsaved work
# with them). Both are the right escalation if crashes become frequent; neither earns its cost yet.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config

# sar samples CPU, memory and load every 10 minutes and writes to disk, so its record of the
# minutes before a crash survives the crash. smartmontools reads the NVMe's unsafe-shutdown
# counter, which is the one witness that is not kept by the OS that died.
apt_install sysstat smartmontools

# Ubuntu ships sysstat with collection switched off; without this there is no history to read.
if [[ -f /etc/default/sysstat ]] && ! grep -q '^ENABLED="true"' /etc/default/sysstat; then
  sudo sed -i 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
  log "enabled sysstat collection"
fi
systemd_enable_now sysstat.service
# The default 7-day retention is shorter than the gap between "it crashed" and "someone looked".
if [[ -f /etc/sysstat/sysstat ]] && ! grep -q '^HISTORY=28' /etc/sysstat/sysstat; then
  sudo sed -i 's/^HISTORY=.*/HISTORY=28/' /etc/sysstat/sysstat
  log "sysstat history set to 28 days"
fi

# Panic traces written to the EFI variable store survive a reboot; this is what moves them
# somewhere durable before the firmware area is reused.
systemd_enable_now systemd-pstore.service

# Turn a silent kernel lockup into a recorded panic plus an automatic reboot.
#
# docs/crash-forensics.md held this back "for a single unexplained event" and named it the right
# escalation "if crashes become frequent". That condition arrived on 2026-09-13: a second silent
# hang, following Sep 10, after which the box sat frozen for six hours with the lockup detectors
# running (nmi_watchdog=1) but every panic switch off, so each warning died in RAM and nothing
# reached disk. The self-reboot this causes costs no unsaved work that the hang had not lost.
#
# efi_pstore stores the panic trace across the reboot and strix-postmortem already reads pstore,
# so a lockup now arrives as a stack trace instead of another "unknown". No RAM is reserved,
# which was the objection to kdump.
#
# hung_task_panic stays OFF on purpose. A task in D-state past 120s is normal here during a large
# restic run to the 8 TB HGST, and panicking on it would reboot a healthy machine mid-backup.
# Only real lockups panic: a CPU stuck in-kernel (soft) or with interrupts off (hard).
write_file_sudo /etc/sysctl.d/99-crash-forensics.conf 0644 <<'EOF'
kernel.softlockup_panic = 1
kernel.hardlockup_panic = 1
kernel.panic = 10
EOF
sudo sysctl -q --system >/dev/null 2>&1 || warn "could not apply sysctl; run: sudo sysctl --system"

# Deep C-state off, as a Linux-side guard against the Ryzen idle freeze. Applied together with the
# BIOS "Power Supply Idle Control = Typical Current Idle" change on 2026-09-17, the night before an
# interview, when stopping the crash mattered more than learning which fix worked. Once the machine
# has been stable for a couple of weeks, set STRIX_NO_DEEP_CSTATE=no to test the BIOS fix alone.
if [[ "${STRIX_NO_DEEP_CSTATE:-yes}" == "yes" ]]; then
  write_file_sudo /etc/systemd/system/strix-no-deep-cstate.service 0644 \
    <"$REPO_DIR/dotfiles/systemd/system/strix-no-deep-cstate.service"
  sudo systemctl daemon-reload
  systemd_enable_now strix-no-deep-cstate.service
else
  sudo systemctl disable --now strix-no-deep-cstate.service 2>/dev/null || true
fi

# Hardware watchdog: reset the machine when the CPU is frozen too hard for any kernel mechanism.
#
# Four silent hangs (Sep 10, 13, 14, 16), all at idle. panic-on-lockup never fired, so the CPUs
# stopped below the NMI watchdog, and the Sep 16 hang sat dead for 40 hours. sp5100_tco is a timer
# in the AMD chipset, outside the CPU, so it still fires when the cores are stuck. systemd pets it
# every 30s; if 60s pass with no pet, the chipset resets the board.
#
# Ubuntu blacklists sp5100_tco in /lib/modprobe.d. A blacklist only stops alias-based autoloading,
# so naming it in modules-load.d loads it anyway. This bounds the outage at about a minute. It does
# not stop the hang, and it restarts the machine on its own, which the docs accepted once hangs
# became frequent.
write_file_sudo /etc/modules-load.d/strix-watchdog.conf 0644 <<'EOF'
sp5100_tco
EOF
write_file_sudo /etc/systemd/system.conf.d/strix-watchdog.conf 0644 <<'EOF'
[Manager]
RuntimeWatchdogSec=60s
RebootWatchdogSec=5min
EOF
sudo modprobe sp5100_tco 2>/dev/null || true
sudo systemctl daemon-reexec
if [ -e /dev/watchdog0 ]; then
  log "hardware watchdog armed: $(cat /sys/class/watchdog/watchdog0/identity 2>/dev/null)"
else
  warn "sp5100_tco loaded no /dev/watchdog0; the chipset watchdog may be disabled in firmware (check: sudo dmesg | grep sp5100)"
fi

# The unit calls a stable path, not a path inside the repo checkout.
sudo ln -sfn "$REPO_DIR/scripts/boot/postmortem.sh" /usr/local/sbin/strix-postmortem

write_file_sudo /etc/systemd/system/strix-postmortem.service 0644 \
  <"$REPO_DIR/dotfiles/systemd/system/strix-postmortem.service"
sudo systemctl daemon-reload
systemd_enable_now strix-postmortem.service

# Run once now so the NVMe counter baseline exists. Without a baseline the first crash after
# provisioning cannot answer the power question -- the comparison needs a previous value.
sudo /usr/local/sbin/strix-postmortem || true

log "crash forensics done. After any unexplained reboot: ls /var/log/strix-postmortem/ (newest first),"
log "  or re-examine any boot by hand: sudo strix-postmortem --boot -2 --stdout"
