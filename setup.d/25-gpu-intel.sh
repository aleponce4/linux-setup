#!/usr/bin/env bash
# 25-gpu-intel.sh - Intel Arc B570: VA-API media driver, Vulkan, optional Level Zero / OpenCL compute runtime
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config

# the xe kernel driver is in-tree; confirm it bound to the card
if ! lspci -k 2>/dev/null | grep -A3 -i 'VGA.*Intel' | grep -q 'Kernel driver in use: xe'; then
  warn "xe driver not active for the Intel GPU (kernel $(uname -r)); check 'lspci -k' and 'dmesg | grep xe'"
fi

apt_install intel-media-va-driver-non-free vainfo intel-gpu-tools libvpl2 libvpl-tools mesa-vulkan-drivers mesa-utils vulkan-tools
usergroup_add render
usergroup_add video

if [[ "${ENABLE_INTEL_COMPUTE:-yes}" == "yes" ]]; then
  # Intel's PPA carries newer compute-runtime builds than the archive; fall back to archive packages if the PPA has none for this release
  if ! grep -rqs 'kobuk-team' /etc/apt/sources.list.d/ 2>/dev/null; then
    sudo add-apt-repository -y ppa:kobuk-team/intel-graphics >/dev/null 2>&1 || warn "could not add ppa:kobuk-team/intel-graphics"
    _APT_UPDATED=""
  fi
  apt_update_once
  apt_install libze-intel-gpu1 libze1 intel-opencl-icd clinfo intel-gsc
fi

# Workarounds documented for Battlemage; disabled by default, uncomment if you see flicker or half framerate
write_file_sudo /etc/environment.d/90-intel-arc.conf 0644 <<'EOF'
# GTK4 artifacts on older Mesa (Fedora 43 reports):   GSK_RENDERER=gl
# KWin half-framerate on multi-monitor (2025 reports): KWIN_DRM_OVERRIDE_SAFETY_MARGIN=1
LIBVA_DRIVER_NAME=iHD
EOF

log "GPU done. Quick checks after reboot: vainfo | head; clinfo -l; glxinfo -B | grep -i renderer"
