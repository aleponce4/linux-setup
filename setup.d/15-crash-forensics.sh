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
