# Shared constants for strix. Sourced by the other scripts.
# shellcheck shell=bash

ROOT_UUID="1e0539dd-c9b4-4222-9076-48a11c6154d9"
ESP_UUID="58B5-F976"
ESP_PARTUUID="905e1ae0-5f9e-420a-8981-0daf2275ad36"
OS_DISK="/dev/nvme0n1"
ROOT_DEV="/dev/nvme0n1p2"
ESP_DEV="/dev/nvme0n1p1"
GPU_PCI="09:00.0"

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must run as root: sudo $0" >&2
        exit 1
    fi
}

# Guard against ever operating on the data disks.
assert_os_disk_only() {
    for dev in "$@"; do
        case "$dev" in
            /dev/nvme0n1*) ;;
            *) echo "REFUSING: $dev is not on the OS disk ($OS_DISK)" >&2; exit 1 ;;
        esac
    done
}
