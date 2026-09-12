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

## What is deliberately NOT installed

- **kdump** -- permanently reserves RAM for a capture kernel, and only catches genuine panics. It
  would not have caught the Sep 10 event.
- **panic-on-hung-task / hardware watchdog** -- turns a silent freeze into a recorded panic, at the
  price of rebooting the machine on its own and taking unsaved work with it.

Both are the right escalation if crashes become frequent. Neither earns its cost for a single
unexplained event, and a forensics tool that costs you work is one you will switch off.

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
