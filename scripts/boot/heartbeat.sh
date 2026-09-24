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

# Motherboard sensors (Nuvoton NCT6798D via nct6775). Absent until the kernel is booted with
# acpi_enforce_resources=lax: ACPI claims the Super-I/O ports and the driver refuses to bind
# without it. These are the columns that answer "is the CPU fan slowing down?" and "is the 12 V
# rail sagging?", the two suspects nothing else on this machine can see.
#
# The channel names are generic (fan1, in0, temp2) because the board ships no sensors3.conf, so
# the columns are emitted dynamically and the header records whatever was present when the day's
# file was created. Confirm the mapping once with `sensors` before reading meaning into a column.
NCT=$(hw nct6798); [ -n "$NCT" ] || NCT=$(hw nct6775); [ -n "$NCT" ] || NCT=$(hw nct6799)
nct_names=(); nct_vals=()
if [ -n "$NCT" ]; then
    for f in "$NCT"/fan*_input; do
        [ -r "$f" ] || continue
        b=$(basename "$f" _input); nct_names+=("mb_$b"); nct_vals+=("$(rd "$f")")
    done
    for f in "$NCT"/in*_input; do
        [ -r "$f" ] || continue
        b=$(basename "$f" _input); nct_names+=("mb_${b}_V"); nct_vals+=("$(scale "$f" 1000)")
    done
    for f in "$NCT"/temp*_input; do
        [ -r "$f" ] || continue
        b=$(basename "$f" _input); nct_names+=("mb_${b}_C"); nct_vals+=("$(scale "$f" 1000)")
    done
fi

# Tctl is the control temperature the fan curve follows; Tccd1 is the actual die sensor. They
# differ by an offset on some Ryzen parts, so record both rather than inferring one from the other.
K10_TCCD=$(lbl "$K10" Tccd1)

read -r _ u n s idle iow rest < /proc/stat
blocked=$(awk '/^procs_blocked/{print $2}' /proc/stat)
load=$(awk '{print $1}' /proc/loadavg)
up=$(awk '{printf "%d", $1}' /proc/uptime)

hdr='epoch\ttime\tup_s\tload1\tblocked\tcpu_idle_j\tcpu_iowait_j\tc2_state\tc2_usage\tc2_time_us\tcpu_C\tccd1_C\tgpu_C\tvram_C\tgpu_fan\tgpu_uJ\tnvme_C'
for n in "${nct_names[@]}"; do hdr="$hdr\t$n"; done
# If the column set changed since the file was created (a sensor driver appeared, or the script
# gained a column), start a fresh file rather than appending rows the header no longer describes.
if [ -s "$OUT" ]; then
    want=$(printf '%b' "$hdr")
    [ "$(head -1 "$OUT")" = "$want" ] || { mv -f "$OUT" "$OUT.$(date +%H%M%S).old"; }
fi
[ -s "$OUT" ] || printf '%b\n' "$hdr" >> "$OUT"
row=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$(date +%s)" "$(date +%H:%M:%S)" "$up" "$load" "${blocked:-NA}" "$idle" "$iow" \
    "$c2_name" "$c2_usage" "$c2_time" \
    "$(scale "$K10/temp1_input" 1000)" "$(scale "${K10_TCCD:-/nonexistent}" 1000)" \
    "$(scale "${GPU_PKG:-/nonexistent}" 1000)" "$(scale "${GPU_VRAM:-/nonexistent}" 1000)" \
    "$(rd "$XE/fan1_input")" "$(rd "$XE/energy1_input")" "$(scale "$NVME/temp1_input" 1000)")
for v in "${nct_vals[@]}"; do row="$row\t$v"; done
printf '%b\n' "$row" >> "$OUT"

# Force the line to disk. Without this, ext4 delayed allocation leaves the most recent writes
# unflushed, and a hard freeze turns them into a block of NUL bytes: on 2026-09-23 the last
# readable sample was almost seven hours before the freeze, losing exactly the part that matters.
sync -d "$OUT" 2>/dev/null || true

# Keep two weeks; each day is well under a megabyte.
find "$OUT_DIR" -name '*.tsv' -mtime +14 -delete 2>/dev/null || true
