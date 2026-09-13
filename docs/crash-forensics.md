# Crash forensics on strix

The machine stopped at 17:41:45 on 2026-09-10 and nothing on disk could say why. The journal ends
mid-sentence, there is no shutdown sequence, `pstore` is empty, and the box stayed off for a day.
By the time anyone looked, the only question worth asking -- *did it lose power, or did the kernel
die with the power still on?* -- had no answer left anywhere.

That is the gap this closes. It does not prevent crashes; it makes the next one explainable.

## What runs

    strix-postmortem.service   oneshot, at every boot, after systemd-pstore
      -> scripts/boot/postmortem.sh   (as /usr/local/sbin/strix-postmortem)
        -> /var/log/strix-postmortem/YYYYmmdd-HHMMSS-boot<id>.md

**A clean boot writes nothing.** The script looks at the *previous* boot, and only produces a
report when that boot ended with no shutdown sequence. Silence means the last shutdown was
deliberate, so the presence of a file is itself the signal.

After any surprise reboot:

    ls -t /var/log/strix-postmortem/ | head
    glow /var/log/strix-postmortem/<newest>.md

The same event is announced in the journal, for the case where you are not looking in that
directory: `journalctl -t strix-postmortem`.

## The one witness that is not the OS

Everything the kernel knows dies with the kernel. The NVMe does not: it keeps its own
`Unsafe Shutdowns` counter, incremented whenever it loses power without being told first. Each
clean boot records that counter to `/var/lib/strix-postmortem/nvme-counters`, so the next crash can
be compared against it:

| counter after the crash | reading |
|---|---|
| **higher** than the baseline | power was actually cut -- mains, PSU, or the power button held on a frozen box |
| **unchanged** | the drive was shut down properly; the kernel stopped for a software reason |
| no baseline | nothing to compare against yet; the first crash after provisioning says "unknown" |

It cannot separate a yanked cable from someone holding the power button on a machine that had
already hung -- both are unsafe from the drive's point of view. The report says so rather than
claiming more than the counter supports.

**Only the automatic boot-time run may write that baseline.** `--stdout`, and any `--boot N`
pointed at an older boot, deliberately leave it alone. This was not theoretical: while developing
the script, test runs against the Sep 10 crash wrote a baseline, and the next report confidently
announced that power had not been cut -- a conclusion drawn entirely from a number the test runs
had just invented.

## What a report contains

Verdict, then the evidence behind it: pstore panic traces, panic/oops/lockup lines, machine-check
and EDAC errors, GPU resets (this box runs an Arc B570 on `xe`, which is noisy), OOM kills, thermal
events, the final 40 journal lines, that boot's errors, units that had failed, and CPU/memory/load
from `sar` for the 40 minutes before the end. `sysstat` samples every 10 minutes and writes to
disk, so its record of the run-up survives the crash; retention is raised to 28 days because the
gap between "it crashed" and "someone looked" is routinely longer than the default 7.

Reading an older boot by hand, without disturbing any state:

    sudo strix-postmortem --boot -3 --stdout
    sudo strix-postmortem --boot -1 --force --stdout   # even if it ended cleanly

## Escalation: panic on lockup (enabled 2026-09-13)

Module 15 sets `kernel.softlockup_panic=1`, `kernel.hardlockup_panic=1` and `kernel.panic=10`.

This was held back "for a single unexplained event". The trigger for escalating was "crashes
become frequent", and it arrived on 2026-09-13 with a second silent hang. That time the box sat
frozen for six hours. The lockup detectors were already running (`nmi_watchdog=1`), but with the
panic switches off each warning stayed in RAM and never reached disk. A lockup now panics, the
trace lands in `efi_pstore`, and the machine reboots itself 10 seconds later. The postmortem
reads pstore, so the next one arrives as a stack trace.

The self-reboot costs no work that the hang had not already lost.

Still deliberately off:

- **hung_task_panic** -- a task in D-state for more than 120 seconds is normal during a large
  restic run to the 8 TB HGST. Panicking on it would reboot a healthy machine mid-backup.
- **kdump** -- permanently reserves RAM for a capture kernel. `efi_pstore` covers the panic
  trace without that cost.

## GPU firmware

The Arc B570 shipped on FWCODE 21.1098. LVFS has 21.1182, marked urgency High. The `xe` driver
logs `Failed to read power limits, check GPU firmware !` at every boot, and both silent hangs
showed a GPU-style failure. Update with `fwupdmgr update`, then do a **full shutdown**, not a
reboot: the flag is "Needs shutdown after installation".

## The crash agent

On a crash, `strix-crash-agent` hands the postmortem report to an unattended Opus session whose
brief is: troubleshoot, restore service, patch the repo so it cannot recur, commit to a branch.
It runs inside a window of the `strix` tmux session, so the same run is both unattended and
attachable from any device -- `ssh alexponce@strix`, then `strix-remote`.

    sudo -u alexponce strix-crash-agent --dry-run   # decide and print, run nothing
    sudo -u alexponce strix-crash-agent             # run it for the newest unhandled report
    sudo -u alexponce strix-crash-agent --force     # ignore the rate limit and the handled marker

### The gates

An agent that reacts to crashes has one genuinely dangerous failure mode, and it is not a single
bad run: it is the loop. Crash, agent changes something, crash again, agent changes more, on a
machine nobody is watching. Four gates in front of it, in order:

1. **Kill switch.** `touch ~/.local/state/strix-crash-agent/disabled` stops it immediately, no
   root and no edit required. `ENABLE_CRASH_AGENT="no"` in `config.env` is the durable form.
2. **One run per crash**, keyed to the boot id, so the same report is never worked twice.
3. **Crash-loop breaker.** More than 2 of the last 4 boots unclean *within 24 hours* and it stands
   down, logs at error level and notifies, rather than compounding the problem. The 24-hour window
   matters: without it the two already-fixed 2026-09-09 crashes kept it standing down on a machine
   that was not looping at all.
4. **Rate limit**, 6 hours minimum between runs.

### The blast radius is enforced, not requested

The session runs with `bypassPermissions`, because nobody is awake to answer prompts. So the
limits cannot live in the prompt -- a model can reason its way around a paragraph. They live in
`scripts/boot/crash-agent-guard.sh`, a `PreToolUse` hook wired in through
`dotfiles/claude/crash-agent-settings.json`, which exits 2 to hard-block the tool call.

**Allowed:** systemd units, configuration files, apt, and the `~/linux-setup` repo including
commits to a branch.

**Blocked:** bootloader and initramfs, kernel-package removal, partitioning and filesystems, raw
block-device writes, `/boot` `/etc/fstab` `/etc/crypttab` and sudoers, user accounts, reboot, and
`git push`. A blocked call returns a reason telling the agent to write the need up for a human
instead of working around it.

`scripts/boot/test-crash-agent-guard.sh` asserts all of this -- 21 deny cases, 12 allow cases.
Module 15 runs it during provisioning and **refuses to install the agent if it fails**, because a
guard that has silently stopped matching is worse than no guard: it looks supervised while being
unsupervised.

### Turning on the automatic trigger

Provisioning deliberately does **not** enable the boot-time trigger. Starting an autonomous
session automatically is a decision to make once, knowingly, rather than something a setup script
does on your behalf. The units are in `dotfiles/systemd/user/`; to enable:

    ln -sfn ~/linux-setup/dotfiles/systemd/user/strix-crash-agent.service ~/.config/systemd/user/
    ln -sfn ~/linux-setup/dotfiles/systemd/user/strix-crash-agent.timer   ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now strix-crash-agent.timer

The timer fires 3 minutes after boot -- enough for the network, the desktop and the tmux session
to come up, since starting the agent before its own escape route exists would be a poor way to
begin. Until then, run it by hand after a crash; everything else here works unchanged.

## What the Sep 10 crash actually shows

Recorded here because the evidence still exists and will not be regenerated:

- no shutdown sequence, no panic trace, `pstore` empty
- no machine-check, EDAC, thermal or OOM events
- no GPU reset lines
- `sar` shows the 40 minutes before the end flat and idle: ~82% idle CPU, ~30% memory, no load spike
- every disk PASSED SMART, zero reallocated or pending sectors, zero media errors
- one failed unit, `app-org.kde.krdpserver.service`, which was the KRDP credentials bug, not a cause

No baseline existed on 2026-09-10, so the power question is genuinely unanswerable for that event.
It is answerable from the next one onward. See [boot-and-graphics.md](boot-and-graphics.md) for the
GPU and boot story, and [remote-access.md](remote-access.md) for the 09-09 session collapse, which
is a separate and fully explained failure.
