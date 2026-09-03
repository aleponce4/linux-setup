#!/usr/bin/env bash
# 00-preflight.sh - sanity checks, hostname/timezone, apt components, full upgrade
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config

. /etc/os-release
[[ "$ID" == "ubuntu" ]] || die "expected Ubuntu/Kubuntu, found $ID ($PRETTY_NAME)"
[[ "$VERSION_ID" == "26.04" ]] || warn "written for 26.04, running on $VERSION_ID; package names may differ"
[[ "$USER" == "$TARGET_USER" ]] || warn "running as $USER but TARGET_USER=$TARGET_USER; user-level installs go to $HOME"
ping -c1 -W3 deb.debian.org >/dev/null 2>&1 || ping -c1 -W3 archive.ubuntu.com >/dev/null 2>&1 || warn "no network reachable; most modules will fail"

# hostname + timezone
if [[ "$(hostnamectl --static)" != "$HOSTNAME_TARGET" ]]; then
  sudo hostnamectl set-hostname "$HOSTNAME_TARGET"
  log "hostname set to $HOSTNAME_TARGET"
fi
ensure_line /etc/hosts "127.0.1.1 $HOSTNAME_TARGET" "^127\.0\.1\.1[[:space:]]+$HOSTNAME_TARGET\b"
[[ "$(timedatectl show -p Timezone --value)" == "$TIMEZONE" ]] || sudo timedatectl set-timezone "$TIMEZONE"

# apt: all components, no phone-home popups, security auto-updates
for comp in universe multiverse restricted; do
  grep -rqs "$comp" /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null || sudo add-apt-repository -y "$comp" >/dev/null
done
echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections
apt_update_once
log "full-upgrade (first run can take a while)"
sudo apt-get full-upgrade -y -qq
apt_install curl wget gnupg ca-certificates software-properties-common apt-transport-https unattended-upgrades
write_file_sudo /etc/apt/apt.conf.d/20auto-upgrades 0644 <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# firmware updates (motherboard/NVMe) via LVFS
apt_install fwupd
sudo fwupdmgr refresh --force >/dev/null 2>&1 || true

log "preflight done: $(uname -r), $(lsb_release -ds)"
