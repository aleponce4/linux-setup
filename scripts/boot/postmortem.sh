#!/usr/bin/env bash
# Say what happened to the previous boot, while the evidence still exists.
#
# The Sep 10 2026 crash was undiagnosable after the fact: the journal simply stopped, and by the
# time anyone looked, the only question that mattered -- did the machine lose power, or did the
# kernel die with the power still on? -- had no answer left anywhere on disk. This runs at every
# boot, notices when the previous one ended without a shutdown sequence, and writes down the
# evidence before the next crash overwrites the context.
#
# Read-only with respect to the system; the only things it writes are its own state and reports.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd /
. "$SCRIPT_DIR/lib-common.sh"

STATE_DIR=/var/lib/strix-postmortem
REPORT_DIR=/var/log/strix-postmortem
BOOT=-1
FORCE=0

usage() {
    cat <<'USAGE'
postmortem.sh [--boot N] [--force] [--stdout]

  --boot N    which boot to examine, journalctl style (default -1, the previous one)
  --force     write a report even when that boot shut down cleanly
  --stdout    print the report instead of writing it to /var/log/strix-postmortem

With no arguments: report only if the previous boot died without shutting down. This is how
the systemd unit invokes it, so a clean boot leaves no noise behind.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --boot)   BOOT="$2"; shift 2 ;;
        --force)  FORCE=1; shift ;;
        --stdout) STDOUT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done
need_root

# --- the drive's own opinion, which survives what the journal does not -------------------
# An NVMe increments unsafe_shutdowns when it loses power without being told first. Comparing
# it against the value recorded at the last boot distinguishes "power was cut" from "the kernel
# stopped but the drive was shut down properly". It cannot separate a power-cable yank from
# someone holding the power button on a frozen machine -- both are unsafe -- so the report says
# so rather than pretending to more precision than the counter has.
nvme_counter() {
    smartctl -a "$OS_DISK" 2>/dev/null \
        | awk -F: "/^$1/ { gsub(/[ ,]/,\"\",\$2); print \$2; exit }"
}

read_baseline() {
    BASE_UNSAFE=""; BASE_CYCLES=""
    [ -r "$STATE_DIR/nvme-counters" ] || return 0
    # shellcheck disable=SC1091
    . "$STATE_DIR/nvme-counters"
    BASE_UNSAFE="${UNSAFE_SHUTDOWNS:-}"; BASE_CYCLES="${POWER_CYCLES:-}"
}

now_unsafe=$(nvme_counter 'Unsafe Shutdowns')
now_cycles=$(nvme_counter 'Power Cycles')
read_baseline

# Only the boot-time run owns the counter baseline. A --stdout dry run, or a manual look at some
# older boot, must not touch it: overwriting it destroys the one value the next real crash has to
# compare against, and lets a read-only command silently decide a future verdict. This bit me
# during development -- test runs against the Sep 10 crash left a baseline that made the report
# claim power had not been cut, a conclusion the data could not support.
record_baseline() {
    [ "$BOOT" = "-1" ] || return 0
    [ "${STDOUT:-0}" != 1 ] || return 0
    install -d -m 0755 "$STATE_DIR"
    printf 'UNSAFE_SHUTDOWNS=%s\nPOWER_CYCLES=%s\n' "$now_unsafe" "$now_cycles" >"$STATE_DIR/nvme-counters"
}

# --- did that boot end on purpose? -------------------------------------------------------
# systemd logs a shutdown sequence on the way out. Its absence is the signal: the kernel stopped
# without being asked to. Matching several markers rather than one keeps a changed unit name in
# some future systemd from silently turning every crash into a "clean" boot.
boot_id=$(journalctl -b "$BOOT" -o json -n 1 2>/dev/null \
            | python3 -c 'import sys,json; print(json.loads(sys.stdin.readline())["_BOOT_ID"])' 2>/dev/null)
[ -n "$boot_id" ] || { echo "no such boot: $BOOT" >&2; exit 1; }

shutdown_markers=$(journalctl -b "$BOOT" --no-pager 2>/dev/null \
    | grep -cEi 'Reached target.*(Power-Off|Reboot|Halt)|Shutting down|systemd-shutdown|Deactivated successfully.*(reboot|poweroff)')
first_entry=$(journalctl -b "$BOOT" -o short-iso --no-pager 2>/dev/null | head -1 | awk '{print $1}')
last_entry=$(journalctl -b "$BOOT" -o short-iso --no-pager 2>/dev/null | tail -1 | awk '{print $1}')

if [ "$shutdown_markers" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
    # Clean boot: record the counters for next time and say nothing.
    record_baseline
    exit 0
fi

# --- gather -------------------------------------------------------------------------------
section() { printf '\n## %s\n\n' "$*"; }
fenced()  { printf '```\n'; cat; printf '```\n'; }
none_if_empty() { local o; o=$(cat); [ -n "$o" ] && printf '%s\n' "$o" || echo '(nothing)'; }

power_verdict() {
    if [ -z "$BASE_UNSAFE" ] || [ -z "$now_unsafe" ]; then
        echo "unknown -- no counter baseline from the previous boot yet"
    elif [ "$now_unsafe" -gt "$BASE_UNSAFE" ]; then
        echo "POWER WAS LOST: the NVMe unsafe-shutdown counter rose ${BASE_UNSAFE} -> ${now_unsafe}."
        echo "That means the drive lost power without warning -- a mains/PSU event, or someone"
        echo "holding the power button on a machine that was already frozen."
    else
        echo "Power was NOT cut abruptly: the NVMe unsafe-shutdown counter is unchanged (${now_unsafe})."
        echo "The kernel stopped while the drive was shut down properly, which points at software"
        echo "(panic, hang, or a forced reset) rather than a power event."
    fi
}

build_report() {
    printf '# Postmortem: boot %s (%s)\n\n' "$BOOT" "${boot_id:0:12}"
    printf -- '- generated: %s\n' "$(date -Is)"
    printf -- '- that boot ran: %s -> %s\n' "${first_entry:-?}" "${last_entry:-?}"
    printf -- '- shutdown markers found: %s\n' "$shutdown_markers"
    if [ "$shutdown_markers" -eq 0 ]; then
        printf -- '- **ended without a shutdown sequence**\n'
    else
        printf -- '- ended cleanly (report forced)\n'
    fi

    section 'Verdict'
    power_verdict

    section 'Kernel crash evidence'
    {
        echo "# pstore (panic traces surviving reboot):"
        ls -la /sys/fs/pstore/ /var/lib/systemd/pstore/ 2>/dev/null | grep -vE '^total|^d' | none_if_empty
        echo
        echo "# panic / oops / lockup / BUG in that boot:"
        journalctl -b "$BOOT" -k --no-pager 2>/dev/null \
            | grep -iE 'kernel panic|Oops:|BUG:|soft lockup|hard LOCKUP|watchdog: BUG|general protection|RIP:' \
            | tail -25 | none_if_empty
        echo
        echo "# machine check / hardware errors:"
        journalctl -b "$BOOT" -k --no-pager 2>/dev/null \
            | grep -iE 'Machine Check Exception|Hardware Error|mce:.*(error|corrected)|EDAC.*(CE|UE) ' \
            | tail -15 | none_if_empty
        echo
        echo "# GPU resets / hangs (this box has had xe driver noise):"
        journalctl -b "$BOOT" -k --no-pager 2>/dev/null \
            | grep -iE "xe $GPU_PCI|drm.*(reset|hang|timeout|GPU HANG)|GPU HANG" | tail -20 | none_if_empty
        echo
        echo "# OOM kills:"
        journalctl -b "$BOOT" --no-pager 2>/dev/null \
            | grep -iE 'Out of memory|oom-kill|oom_reaper' | tail -15 | none_if_empty
        echo
        echo "# thermal events:"
        journalctl -b "$BOOT" -k --no-pager 2>/dev/null \
            | grep -iE 'thermal.*(throttl|critical)|temperature above|critical temperature' \
            | tail -10 | none_if_empty
    } | fenced

    section 'Last words'
    printf 'The final 40 journal lines before the machine stopped. When a box dies silently this\nis usually the only description of the moment that exists.\n\n'
    journalctl -b "$BOOT" --no-pager -n 40 2>/dev/null | fenced

    section 'Errors during that boot'
    journalctl -b "$BOOT" -p err --no-pager 2>/dev/null | tail -40 | none_if_empty | fenced

    section 'Units that had failed'
    journalctl -b "$BOOT" --no-pager 2>/dev/null \
        | grep -E 'Failed with result|entered failed state' | tail -20 | none_if_empty | fenced

    section 'Resource history around the end'
    printf 'From sysstat, which samples every 10 minutes and survives the crash. A load or memory\nwall here turns "it just froze" into something with a cause.\n\n'
    {
        if [ -n "$last_entry" ]; then
            day=$(date -d "$last_entry" +%d 2>/dev/null)
            start=$(date -d "$last_entry -40 min" +%H:%M:%S 2>/dev/null)
            end=$(date -d "$last_entry" +%H:%M:%S 2>/dev/null)
            sa="/var/log/sysstat/sa${day}"
            if [ -r "$sa" ]; then
                echo "# CPU  ($sa, ${start}-${end})"; sar -f "$sa" -s "$start" -e "$end" 2>/dev/null | tail -8
                echo; echo "# memory"; sar -r -f "$sa" -s "$start" -e "$end" 2>/dev/null | tail -8
                echo; echo "# load"; sar -q -f "$sa" -s "$start" -e "$end" 2>/dev/null | tail -8
            else
                echo "(no sysstat archive for day $day)"
            fi
        else
            echo "(no end timestamp)"
        fi
    } | none_if_empty | fenced

    section 'Disk health now'
    {
        printf '%-22s %s\n' 'NVMe unsafe shutdowns:' "${now_unsafe:-?} (baseline ${BASE_UNSAFE:-none})"
        printf '%-22s %s\n' 'NVMe power cycles:'     "${now_cycles:-?} (baseline ${BASE_CYCLES:-none})"
        echo
        smartctl -H "$OS_DISK" 2>/dev/null | grep -iE 'result|SMART Health'
        smartctl -a "$OS_DISK" 2>/dev/null | grep -iE 'Critical Warning|Media and Data Integrity|Percentage Used'
    } | fenced

    section 'What to do with this'
    cat <<'NEXT'
- Counter rose -> suspect power. Check the PSU, the wall, and anything on the same circuit.
- Counter unchanged and pstore empty -> the kernel stopped without recording why. That is a hang
  or an external reset; the hardware watchdog and kdump are the next escalation, both deliberately
  left off here because they cost RAM and can reboot the machine on their own.
- GPU reset lines present -> the xe driver is the first suspect; this machine runs an Arc B570.
NEXT
}

install -d -m 0755 "$STATE_DIR" "$REPORT_DIR"
if [ "${STDOUT:-0}" = 1 ]; then
    build_report
elif existing=$(ls "$REPORT_DIR"/*-boot"${boot_id:0:8}".md 2>/dev/null | head -1) && [ -n "$existing" ]; then
    # One report per dead boot. bootstrap.sh runs this module on every provisioning run, and
    # without this a machine that crashed once would collect a new identical report each time.
    echo "already reported: $existing"
else
    report="$REPORT_DIR/$(date +%Y%m%d-%H%M%S)-boot${boot_id:0:8}.md"
    build_report >"$report"
    chmod 0644 "$report"
    echo "wrote $report"
    # Make the finding visible to anyone reading the journal, not only to whoever opens the file.
    logger -t strix-postmortem -p daemon.warning \
        "previous boot ended without a shutdown sequence; report: $report"
    # Reports are a few KB each and only appear after a crash, but a box in a reboot loop would
    # produce one per boot; keep the newest 50 so this can never be the thing that fills /var.
    ls -1t "$REPORT_DIR"/*.md 2>/dev/null | tail -n +51 | xargs -r rm -f
fi

record_baseline
