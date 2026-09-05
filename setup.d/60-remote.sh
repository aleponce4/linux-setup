#!/usr/bin/env bash
# 60-remote.sh - Tailscale (with Tailscale SSH), hardened sshd, fail2ban, ufw, mosh, Wake-on-LAN
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config

# ---- Tailscale ----
if ! have tailscale; then
  curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1 || warn "tailscale install failed"
fi
if have tailscale; then
  systemd_enable_now tailscaled
  if ! tailscale status >/dev/null 2>&1; then
    log "Tailscale is installed but not logged in. Run:  sudo tailscale up --ssh --accept-dns   (opens a browser login)"
  fi
fi

# ---- OpenSSH server: keys only, but never lock yourself out ----
apt_install openssh-server
systemd_enable_now ssh
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
if [[ -s "$HOME/.ssh/authorized_keys" ]]; then
  PASSWD_AUTH="no"
else
  PASSWD_AUTH="yes"
  warn "~/.ssh/authorized_keys is empty: password SSH login stays enabled. Add your public key (from the Windows secrets archive) and re-run 60."
fi
write_file_sudo /etc/ssh/sshd_config.d/90-linux-setup.conf 0644 <<EOF
PasswordAuthentication $PASSWD_AUTH
KbdInteractiveAuthentication $PASSWD_AUTH
PermitRootLogin no
AllowUsers $TARGET_USER
X11Forwarding no
ClientAliveInterval 60
ClientAliveCountMax 3
EOF
sudo sshd -t && sudo systemctl reload ssh || warn "sshd config test failed; not reloaded"

# ---- fail2ban for sshd ----
apt_install fail2ban
write_file_sudo /etc/fail2ban/jail.d/sshd.local 0644 <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
bantime = 1h
EOF
systemd_enable_now fail2ban
sudo systemctl restart fail2ban || true

# ---- ufw: SSH + mosh + KDE Connect; everything on the tailnet allowed ----
apt_install ufw mosh
sudo ufw --force default deny incoming >/dev/null
sudo ufw --force default allow outgoing >/dev/null
sudo ufw allow OpenSSH >/dev/null
sudo ufw allow 60000:61000/udp comment mosh >/dev/null
sudo ufw allow 1714:1764/tcp comment kdeconnect >/dev/null
sudo ufw allow 1714:1764/udp comment kdeconnect >/dev/null
sudo ufw allow in on tailscale0 comment tailnet >/dev/null 2>&1 || true
sudo ufw --force enable >/dev/null

# ---- Wake-on-LAN on the wired NIC (Intel I225-V) ----
apt_install ethtool
while IFS=: read -r name type dev; do
  [[ "$type" == "802-3-ethernet" ]] || continue
  cur="$(nmcli -g 802-3-ethernet.wake-on-lan con show "$name" 2>/dev/null || true)"
  if [[ "$cur" != "magic" ]]; then
    sudo nmcli con modify "$name" 802-3-ethernet.wake-on-lan magic && log "WoL (magic packet) enabled on '$name'"
  fi
done < <(nmcli -t -f NAME,TYPE,DEVICE con show)
log "Also enable 'Power On By PCI-E' / WoL and disable ErP in the ASUS UEFI for wake from full power-off."

# ---- Chrome Remote Desktop host (virtual X11 Plasma session; the console Wayland session cannot be shared unattended) ----
# WARNING: Chrome Remote Desktop installs a user unit with
#   WantedBy=gnome-session.target plasma-workspace.target
# so it starts with every Plasma login and launches `kwin_x11 --replace`. On a Wayland
# session that aborts (SIGABRT in qFatal) and takes the whole session down with it -
# observed on this machine 2026-09-05, losing every open window. Default is now "no";
# KDE RDP (krdp, installed above) over Tailscale does the same job without fighting the
# compositor. If you enable this, mask the unit or expect to lose your session.
if [[ "${ENABLE_CRD:-no}" == "yes" ]]; then
  dpkg -s chrome-remote-desktop >/dev/null 2>&1 || download_deb https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
  if dpkg -s chrome-remote-desktop >/dev/null 2>&1; then
    usergroup_add chrome-remote-desktop
    if [[ ! -x /usr/bin/startplasma-x11 ]] && apt-cache show plasma-workspace-x11 >/dev/null 2>&1; then apt_install plasma-workspace-x11; fi
    if [[ -x /usr/bin/startplasma-x11 ]]; then
      printf 'export XDG_SESSION_TYPE=x11\nexec /usr/bin/startplasma-x11\n' >"$HOME/.chrome-remote-desktop-session"
      grep -q CHROME_REMOTE_DESKTOP_DEFAULT_DESKTOP_SIZES "$HOME/.profile" 2>/dev/null || echo 'export CHROME_REMOTE_DESKTOP_DEFAULT_DESKTOP_SIZES=2560x1440,1920x1080' >>"$HOME/.profile"
      log "CRD host installed. Authorize once: https://remotedesktop.google.com/headless > Set up via SSH > Debian Linux > run the printed command here."
    else
      warn "no X11 Plasma session package available; CRD host installed but its virtual session is unconfigured (use krdp/Tailscale for GUI remote)"
    fi
  fi
fi

log "remote done. Manual: 'sudo tailscale up --ssh', then from another device: ssh $TARGET_USER@$HOSTNAME_TARGET  (MagicDNS). GUI: KDE RDP (System Settings > Remote Desktop) or CRD. VS Code: 'code tunnel user login' then 'code tunnel service install'."
