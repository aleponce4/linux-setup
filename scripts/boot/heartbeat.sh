#!/usr/bin/env bash
# heartbeat.sh - append one line of machine state, every 20 s, to a file on disk.
#
# Six silent freezes left nothing behind. sysstat samples every 10 minutes and records no
# temperature, no power and no idle-state data, so the last thing ever known about the machine
# was up to ten minutes stale and said nothing about why it stopped.
#
# The load-bearing column is c2_usage: how many times the cores have entered their deepest idle
# state. If the freezes are the Ryzen idle freeze, this counter is climbing right up to the last
# line. If it is flat while the machine dies, the idle theory is wrong and the cause is elsewhere.
#
# Written straight to a plain file, not the journal: journald buffers, and a buffered line is
# lost in exactly the case this exists for.
set -uo pipefail
OUT_DIR="${STRIX_HEARTBEAT_DIR:-$HOME/.local/state/strix-heartbeat}"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$(date +%Y%m%d).tsv"

hw() {  # hw <driver-name> -> hwmon path
    local want="$1" h
    for h in /sys/class/hwmon/hwmon*; do
        [ "$(cat "$h/name" 2>/dev/null)" = "$want" ] && { printf '%s' "$h"; return; }
    done
}
rd() { cat "$1" 2>/dev/null || printf 'NA'; }
scale() { local v; v=$(rd "$1"); [ "$v" = NA ] && { printf 'NA'; return; }; awk -v v="$v" -v d="$2" 'BEGIN{printf "%.1f", v/d}'; }

K10=$(hw k10temp); XE=$(hw xe); NVME=$(hw nvme)

# Resolve GPU temperature inputs by LABEL, not by index. The xe driver exposes 15 inputs and the
# numbering is not stable across driver versions; hardcoding temp1 gave NA on the first run.
lbl() {  # lbl <hwmon> <label> -> input path
    local h="$1" want="$2" f
    for f in "$h"/temp*_label; do
        [ -r "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "$want" ] && { printf '%s' "${f%_label}_input"; return; }
    done
}
GPU_PKG=$(lbl "$XE" pkg); GPU_VRAM=$(lbl "$XE" vram)

# Deep-idle entry counts and residency, summed across cores. state2 is the deepest state
# acpi_idle exposes on this Ryzen; the name is recorded so a kernel change that renumbers the
# states is visible in the data rather than silently changing what the column means.
c2_name=$(rd /sys/devices/system/cpu/cpu0/cpuidle/state2/name)
c2_usage=0; c2_time=0
for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/usage; do
    [ -r "$f" ] && c2_usage=$(( c2_usage + $(cat "$f" 2>/dev/null || echo 0) ))
done
for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/time; do
    [ -r "$f" ] && c2_time=$(( c2_time + $(cat "$f" 2>/dev/null || echo 0) ))
done

read -r _ u n s idle iow rest < /proc/stat
blocked=$(awk '/^procs_blocked/{print $2}' /proc/stat)
load=$(awk '{print $1}' /proc/loadavg)
up=$(awk '{printf "%d", $1}' /proc/uptime)

[ -s "$OUT" ] || printf 'epoch\ttime\tup_s\tload1\tblocked\tcpu_idle_j\tcpu_iowait_j\tc2_state\tc2_usage\tc2_time_us\tcpu_C\tgpu_C\tvram_C\tgpu_fan\tgpu_uJ\tnvme_C\n' >> "$OUT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date +%s)" "$(date +%H:%M:%S)" "$up" "$load" "${blocked:-NA}" "$idle" "$iow" \
    "$c2_name" "$c2_usage" "$c2_time" \
    "$(scale "$K10/temp1_input" 1000)" "$(scale "${GPU_PKG:-/nonexistent}" 1000)" "$(scale "${GPU_VRAM:-/nonexistent}" 1000)" \
    "$(rd "$XE/fan1_input")" "$(rd "$XE/energy1_input")" "$(scale "$NVME/temp1_input" 1000)" >> "$OUT"

# Keep two weeks; each day is well under a megabyte.
find "$OUT_DIR" -name '*.tsv' -mtime +14 -delete 2>/dev/null || true
