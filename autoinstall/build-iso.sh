#!/usr/bin/env bash
# build-iso.sh - remaster an Ubuntu Server ISO into a fully unattended installer for this workstation.
#
# Runs on Linux (or WSL). Needs: xorriso.
#   ./build-iso.sh --src <server.iso> --out <auto.iso> --secrets <dir>
#
# <dir> must contain, one value per file, no trailing newline required:
#   pw.hash   crypt(3) SHA-512 hash for the account password   (openssl passwd -6)
#   ssh.pub   the public key to authorise for root and the user
#   tskey     a Tailscale auth key, so the installer is reachable if it stalls
#
# None of those are ever written into this repository. The finished ISO does contain them, so treat
# the ISO and the USB stick made from it as secret material and wipe the stick afterwards.
set -euo pipefail

SRC=""; OUT=""; SECRETS=""; REPO="https://raw.githubusercontent.com/aleponce4/linux-setup/main"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --src) SRC="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --secrets) SECRETS="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -f "$SRC" ]] || { echo "source ISO not found: $SRC" >&2; exit 2; }
[[ -n "$OUT" ]] || { echo "--out is required" >&2; exit 2; }
[[ -d "$SECRETS" ]] || { echo "secrets directory not found: $SECRETS" >&2; exit 2; }
command -v xorriso >/dev/null || { echo "xorriso is not installed" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$HERE/user-data.template"
[[ -f "$TEMPLATE" ]] || { echo "missing $TEMPLATE" >&2; exit 2; }

PWHASH="$(tr -d '\r\n' < "$SECRETS/pw.hash")"
SSHKEY="$(tr -d '\r\n' < "$SECRETS/ssh.pub")"
TSKEY="$(tr -d '\r\n' < "$SECRETS/tskey")"
[[ "$PWHASH" == \$6\$* ]] || { echo "pw.hash does not look like a SHA-512 crypt hash" >&2; exit 2; }
[[ "$SSHKEY" == ssh-* ]]  || { echo "ssh.pub does not look like a public key" >&2; exit 2; }
[[ "$TSKEY" == tskey-* ]] || { echo "tskey does not look like a Tailscale auth key" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/nocloud"

# ---- 1. render the autoinstall config -------------------------------------------------------
python3 - "$TEMPLATE" "$WORK/nocloud/user-data" <<PY
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding='utf-8').read()
for token, value in (('@@PWHASH@@', """$PWHASH"""), ('@@SSHKEY@@', """$SSHKEY"""),
                     ('@@TSKEY@@', """$TSKEY"""), ('@@REPO@@', """$REPO""")):
    text = text.replace(token, value)
left = [t for t in ('@@PWHASH@@','@@SSHKEY@@','@@TSKEY@@','@@REPO@@') if t in text]
if left:
    sys.exit('placeholders left unsubstituted: %s' % left)
open(dst, 'w', encoding='utf-8', newline='\n').write(text)
PY
: > "$WORK/nocloud/meta-data"
echo "rendered user-data ($(wc -l < "$WORK/nocloud/user-data") lines)"

# fail early on malformed YAML rather than at 3am on the target machine
if python3 -c 'import yaml' 2>/dev/null; then
  python3 -c "import yaml,sys; d=yaml.safe_load(open('$WORK/nocloud/user-data')); a=d['autoinstall']; assert a['version']==1; assert a['storage']['config'][0]['path']=='/dev/nvme0n1'; print('yaml parses; storage target', a['storage']['config'][0]['path'])"
else
  echo "note: pyyaml absent, skipping the YAML syntax check"
fi

# ---- 2. take the boot menu out of the source ISO and patch it -------------------------------
xorriso -osirrox on -indev "$SRC" -extract /boot/grub/grub.cfg "$WORK/grub.cfg" >/dev/null 2>&1
echo "--- original grub.cfg ---"; sed -n '1,40p' "$WORK/grub.cfg"

# Add the autoinstall parameters to every kernel line, and stop waiting at the menu.
# The semicolon is escaped because GRUB would otherwise read it as a command separator.
python3 - "$WORK/grub.cfg" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
param = r' autoinstall ds=nocloud\;s=/cdrom/nocloud/'
def add(m):
    return m.group(0) if 'autoinstall' in m.group(0) else m.group(0) + param
s2, n = re.subn(r'(?m)^\s*linux\s+/casper/vmlinuz\S*.*$', add, s)
if n == 0:
    sys.exit('no /casper/vmlinuz kernel line found in grub.cfg; aborting rather than guessing')
s2 = re.sub(r'(?m)^\s*set\s+timeout=.*$', 'set timeout=1', s2)
if 'set timeout' not in s2:
    s2 = 'set timeout=1\n' + s2
open(p, 'w', encoding='utf-8', newline='\n').write(s2)
print('patched %d kernel line(s)' % n)
PY
echo "--- patched kernel lines ---"; grep -n 'vmlinuz' "$WORK/grub.cfg"

# ---- 3. repack, replaying the original boot records ----------------------------------------
# "-boot_image any replay" reuses the source ISO's El Torito and EFI boot setup, which is far
# safer than reconstructing the boot arguments by hand.
rm -f "$OUT"
xorriso -indev "$SRC" -outdev "$OUT" \
        -boot_image any replay \
        -compliance no_emul_toc \
        -map "$WORK/nocloud" /nocloud \
        -map "$WORK/grub.cfg" /boot/grub/grub.cfg \
        -end

# ---- 4. verify what actually landed in the new ISO ------------------------------------------
echo "--- verification ---"
xorriso -indev "$OUT" -find /nocloud 2>/dev/null | sed 's/^/  /'
xorriso -osirrox on -indev "$OUT" -extract /boot/grub/grub.cfg "$WORK/check.cfg" >/dev/null 2>&1
grep -q 'autoinstall ds=nocloud' "$WORK/check.cfg" || { echo "FAILED: autoinstall parameter missing from the rebuilt ISO" >&2; exit 1; }
xorriso -osirrox on -indev "$OUT" -extract /nocloud/user-data "$WORK/check-ud" >/dev/null 2>&1
grep -q 'hostname: strix' "$WORK/check-ud" || { echo "FAILED: user-data missing from the rebuilt ISO" >&2; exit 1; }
echo "  autoinstall parameter present, user-data present"
echo "  size: $(du -h "$OUT" | cut -f1)"
echo "  sha256: $(sha256sum "$OUT" | cut -d' ' -f1)"
echo "built: $OUT"
