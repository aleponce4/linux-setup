#!/usr/bin/env bash
# Does the crash-agent guard actually block what it claims to block?
#
# This matters more than most tests here. The agent runs unattended with bypassPermissions, so the
# guard is the only thing enforcing its blast radius -- and a guard that silently stops matching
# (a renamed tool, a reworded regex) fails open, quietly, with nobody watching. Run after touching
# crash-agent-guard.sh: ./scripts/boot/test-crash-agent-guard.sh
set -uo pipefail
GUARD="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/crash-agent-guard.sh"
pass=0; fail=0

t() {
    local expect="$1" tool="$2" val="$3" payload got rc
    if [ "$tool" = Bash ]; then
        payload=$(jq -nc --arg c "$val" '{tool_name:"Bash",tool_input:{command:$c}}')
    else
        payload=$(jq -nc --arg p "$val" --arg t "$tool" '{tool_name:$t,tool_input:{file_path:$p}}')
    fi
    printf '%s' "$payload" | "$GUARD" >/dev/null 2>&1; rc=$?
    got=allow; [ $rc -eq 2 ] && got=deny
    if [ "$got" = "$expect" ]; then printf '  ok   %-5s %s\n' "$got" "$val"; pass=$((pass+1))
    else printf '  FAIL expected %s got %s: %s\n' "$expect" "$got" "$val"; fail=$((fail+1)); fi
}

echo "must DENY:"
t deny Bash 'git push origin main'
t deny Bash 'cd /repo && git push'
t deny Bash 'sudo update-grub'
t deny Bash 'sudo update-initramfs -u'
t deny Bash 'sudo grub-install /dev/nvme0n1'
t deny Bash 'sudo mkfs.ext4 /dev/sdb1'
t deny Bash 'sudo parted /dev/sda mklabel gpt'
t deny Bash 'sudo wipefs -a /dev/sdb'
t deny Bash 'sudo dd if=/dev/zero of=/dev/sda bs=1M'
t deny Bash 'echo foo > /dev/nvme0n1'
t deny Bash 'sudo sed -i s/x/y/ /etc/fstab'
t deny Bash 'sudo tee /boot/grub/grub.cfg < x'
t deny Bash 'sudo apt-get remove linux-image-generic'
t deny Bash 'sudo apt purge openssh-server'
t deny Bash 'sudo reboot'
t deny Bash 'sudo systemctl reboot'
t deny Bash 'sudo shutdown -r now'
t deny Bash 'sudo usermod -aG docker bob'
t deny Bash 'sudo rm -rf /usr'
t deny Edit /boot/grub/grub.cfg
t deny Write /etc/sudoers.d/99-bad

echo "must ALLOW (this is the job):"
t allow Bash 'sudo systemctl restart app-org.kde.krdpserver.service'
t allow Bash 'sudo systemctl status sddm --no-pager'
t allow Bash 'journalctl -b -1 -p err --no-pager | tail -50'
t allow Bash 'sudo apt-get install -y krdp'
t allow Bash 'git add -A && git commit -m "fix: restore krdp"'
t allow Bash 'git checkout -b fix/crash-20260911'
t allow Bash 'cd ~/linux-setup && ./bootstrap.sh 90'
t allow Bash 'ls -la /boot'
t allow Bash 'cat /etc/fstab'
t allow Bash 'rm -f /tmp/scratch.txt'
t allow Edit /home/alexponce/linux-setup/setup.d/60-remote.sh
t allow Write /home/alexponce/.config/systemd/user/foo.conf

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
