#!/usr/bin/env bash
# Hand the last crash to Claude, once, with the brakes on.
#
# strix-postmortem writes a report when a boot ends without a shutdown sequence. This picks that
# report up and starts an Opus session whose job is to diagnose, restore service, patch the repo
# and commit. It runs in a window of the `strix` tmux session, so the same run is both unattended
# and attachable: `ssh alexponce@strix` then `strix-remote`.
#
# The gates below exist because the dangerous case is not one bad run, it is a loop -- crash, the
# agent changes something, crash again, the agent changes more, on a machine nobody is watching.
# The agent's blast radius is enforced separately, by crash-agent-guard.sh as a PreToolUse hook.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

REPORT_DIR=/var/log/strix-postmortem
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/strix-crash-agent"
LOG_DIR="$STATE_DIR/logs"
TMUX_SESSION=strix
MODEL=opus
MIN_HOURS_BETWEEN_RUNS=6
MAX_UNCLEAN_IN_LAST_4=2
RUN_TIMEOUT=3600
FORCE=0

say()  { printf '%s\n' "$*"; logger -t strix-crash-agent -p daemon.info "$*"; }
skip() { printf '%s\n' "$*"; logger -t strix-crash-agent -p daemon.info "not running: $*"; exit 0; }

while [ $# -gt 0 ]; do
    case "$1" in
        --force)   FORCE=1; shift ;;          # ignore the rate limit and the handled marker
        --dry-run) DRY=1; shift ;;            # print the decision and the command, run nothing
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$STATE_DIR/handled" "$LOG_DIR"

# --- gate 1: is this switched on at all --------------------------------------------------
# A kill switch that needs no edit and no root, for the moment you want it to stop right now.
[ -e "$STATE_DIR/disabled" ] && skip "disabled by $STATE_DIR/disabled"
if [ -r "$REPO_DIR/config.env" ]; then
    # shellcheck disable=SC1091
    ENABLE_CRASH_AGENT=$(. "$REPO_DIR/config.env" 2>/dev/null; printf '%s' "${ENABLE_CRASH_AGENT:-yes}")
    [ "$ENABLE_CRASH_AGENT" = yes ] || skip "ENABLE_CRASH_AGENT=$ENABLE_CRASH_AGENT in config.env"
fi

# --- gate 2: is there a crash to answer for ----------------------------------------------
report=$(ls -1t "$REPORT_DIR"/*.md 2>/dev/null | head -1)
[ -n "$report" ] || skip "no postmortem report; the last boot ended cleanly"
boot_tag=$(basename "$report" | sed -n 's/.*-boot\([0-9a-f]*\)\.md/\1/p')
[ -n "$boot_tag" ] || skip "could not read a boot id from $report"

# One run per crash. Without this the timer would re-run against the same report every boot.
if [ -e "$STATE_DIR/handled/$boot_tag" ] && [ "$FORCE" -eq 0 ]; then
    skip "already handled boot $boot_tag (see $STATE_DIR/handled/$boot_tag)"
fi

# --- gate 3: the crash loop ---------------------------------------------------------------
# If the machine is going down repeatedly, an agent editing config between crashes makes the
# problem harder to understand, not easier. Past this threshold it stays out of the way and says
# so loudly -- this is the case that wants a human.
#
# Only RECENT bad boots count. Without the time window this counted the two 2026-09-09 crashes,
# long since diagnosed and fixed, and stood down on a machine that was not looping at all -- a
# gate that refuses to run because of history it has already dealt with is just broken.
LOOP_WINDOW_HOURS=24
now_epoch=$(date +%s)
unclean=0
for b in -1 -2 -3 -4; do
    journalctl -b "$b" --no-pager >/dev/null 2>&1 || continue
    ended=$(journalctl -b "$b" -o short-unix --no-pager 2>/dev/null | tail -1 | awk '{print int($1)}')
    [ -n "$ended" ] || continue
    [ $(( (now_epoch - ended) / 3600 )) -lt "$LOOP_WINDOW_HOURS" ] || continue
    n=$(journalctl -b "$b" --no-pager 2>/dev/null \
        | grep -cEi 'Reached target.*(Power-Off|Reboot|Halt)|Shutting down|systemd-shutdown')
    [ "${n:-0}" -eq 0 ] && unclean=$((unclean+1))
done
if [ "$unclean" -gt "$MAX_UNCLEAN_IN_LAST_4" ] && [ "$FORCE" -eq 0 ]; then
    logger -t strix-crash-agent -p daemon.err \
        "$unclean of the last 4 boots ended badly: NOT starting the agent, this needs a human"
    command -v notify-send >/dev/null && notify-send -u critical "strix: repeated crashes" \
        "$unclean of the last 4 boots ended badly. The crash agent stood down; look at $report." 2>/dev/null
    skip "$unclean of the last 4 boots were unclean -- standing down rather than compounding it"
fi

# --- gate 4: rate limit --------------------------------------------------------------------
if [ -e "$STATE_DIR/last-run" ] && [ "$FORCE" -eq 0 ]; then
    age=$(( ($(date +%s) - $(stat -c %Y "$STATE_DIR/last-run")) / 3600 ))
    [ "$age" -lt "$MIN_HOURS_BETWEEN_RUNS" ] \
        && skip "last run was ${age}h ago, under the ${MIN_HOURS_BETWEEN_RUNS}h minimum"
fi

# --- build the prompt -----------------------------------------------------------------------
stamp=$(date +%Y%m%d-%H%M%S)
transcript="$LOG_DIR/$stamp-boot$boot_tag.log"
promptfile="$STATE_DIR/prompt-$boot_tag.md"
python3 - "$REPO_DIR/dotfiles/claude/crash-agent-prompt.md" "$report" "$promptfile" <<'PY'
import io, sys
tmpl, report, out = sys.argv[1], sys.argv[2], sys.argv[3]
body = io.open(report, encoding="utf-8", errors="replace").read()
s = io.open(tmpl, encoding="utf-8").read()
s = s.replace("{{REPORT_PATH}}", report).replace("{{REPORT_BODY}}", body)
io.open(out, "w", encoding="utf-8").write(s)
PY

GUARD_NOTE='You are running unattended after a crash on strix. A PreToolUse hook hard-blocks bootloader, kernel-package, partition, /boot, fstab, sudoers, account, reboot and git-push operations; treat a block as a real limit and write the need up for a human rather than working around it. Never commit to main and never push. Verify with ./bootstrap.sh 90 before claiming anything is fixed, and say plainly when you could not determine the cause.'

# claude resolves only from a LOGIN shell: it lives in fnm's node-versions tree, not on the
# default PATH. A non-login shell here produces "claude: command not found" inside tmux, which
# looks like the agent silently declining to run.
inner="cd '$REPO_DIR' && timeout $RUN_TIMEOUT claude -p \"\$(cat '$promptfile')\""
inner="$inner --model $MODEL"
inner="$inner --permission-mode bypassPermissions"
inner="$inner --settings '$REPO_DIR/dotfiles/claude/crash-agent-settings.json'"
inner="$inner --add-dir $REPORT_DIR"
inner="$inner --append-system-prompt '$GUARD_NOTE'"
inner="$inner 2>&1 | tee '$transcript'"

if [ "${DRY:-0}" = 1 ]; then
    echo "would handle : $report (boot $boot_tag)"
    echo "transcript   : $transcript"
    echo "command      :"; printf '  %s\n' "$inner"
    exit 0
fi

date -Is >"$STATE_DIR/last-run"
printf 'report=%s\nstarted=%s\ntranscript=%s\n' "$report" "$(date -Is)" "$transcript" \
    >"$STATE_DIR/handled/$boot_tag"

# Run it inside the persistent tmux session so the same run can be watched or taken over from any
# device, rather than being a log you read after the fact.
tmux has-session -t "$TMUX_SESSION" 2>/dev/null || tmux new-session -d -s "$TMUX_SESSION"
tmux new-window -d -t "$TMUX_SESSION:" -n "crash-$boot_tag" \
    "bash -lc \"$inner; echo; echo '--- crash agent finished, window kept open ---'; exec bash -l\""

say "crash agent started for boot $boot_tag in tmux $TMUX_SESSION:crash-$boot_tag"
say "watch it:  ssh alexponce@strix -t 'tmux attach -t $TMUX_SESSION'    transcript: $transcript"
command -v notify-send >/dev/null && notify-send "strix: crash agent running" \
    "Diagnosing boot $boot_tag. tmux window crash-$boot_tag." 2>/dev/null
exit 0
