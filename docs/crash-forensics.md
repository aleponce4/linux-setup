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

## Leading hypothesis after the third silent hang: Ryzen idle freeze (2026-09-15)

Three hangs with no kernel evidence: Sep 10 17:41, Sep 13 03:49, Sep 14 01:11. The Sep 14 box sat
dead for 30 hours. Every one happened with the machine idle: load average 0.10 to 0.27, CPU 82% idle.

What the third one ruled out:

- **Kernel lockup.** softlockup_panic and hardlockup_panic were on. A lockup would have panicked,
  written a trace to efi_pstore, and rebooted after 10 seconds. pstore stayed empty and nothing
  rebooted, so the CPUs stopped below the point where the NMI watchdog can run.
- **GPU firmware.** The Arc B570 was on 21.1182 by then.
- **The ChatGPT app.** Open for one hang, closed for another.

Hardware: AMD Ryzen 5 3600 (Zen 2), ASUS ROG STRIX B550-XE GAMING WIFI, BIOS 3607 (2024-03-18),
microcode 0x8701034, idle driver acpi_idle.

A Zen 2 package freezing at idle with no log and no watchdog is the documented Ryzen idle-freeze
failure. The standard fix is a BIOS setting, and it touches no bootloader or kernel configuration:

    Advanced > AMD CBS > CPU Common Options > Power Supply Idle Control = Typical Current Idle

Change only that, then wait. Changing several things at once would hide which one worked.

If it hangs again with that set, in order:

1. Disable the deepest C-state at runtime with a oneshot unit writing `1` to
   `/sys/devices/system/cpu/cpu*/cpuidle/state2/disable`. Boot config stays untouched.
2. Load BIOS defaults for memory (DOCP/XMP off) to rule out RAM instability.
3. BIOS update. A flash resets settings, and this machine needs Above 4G Decoding and Resizable BAR
   re-enabled afterwards or the Arc B570 will not boot (see docs/boot-and-graphics.md).

The NVMe unsafe-shutdown counter rose 128 to 129. The power button was held, so it does not
distinguish a freeze from power loss here.

## Fourth hang, and the hardware watchdog (2026-09-17)

Sep 16 03:17: idle again (load 0.16, CPU 82% idle), no kernel lines, pstore empty. The box sat dead
for 40 hours. The BIOS idle setting had not been changed yet, so this hang confirms the pattern and
does not test the fix.

Module 15 now loads the AMD chipset watchdog `sp5100_tco`, which Ubuntu blacklists by default, and
sets systemd `RuntimeWatchdogSec=60s`. The chipset timer runs outside the CPU, so it resets the
board when the cores are frozen too hard for the kernel's own watchdog. This caps an outage at about
a minute. It does not prevent the hang.

## Fifth hang: the BIOS change was not enough on its own (2026-09-19)

Sep 18 21:38:18, after the BIOS visit that morning: idle again (load 0.02 to 0.19, CPU 82% idle),
no kernel lines, no GPU errors, pstore empty, sysstat's 21:40 sample never ran. Alex found the
machine powered on with every window black except a terminal, which did not respond.

Ruled out this time:

- **Screen blanking.** Displays are set never to turn off and the lock screen is disabled.
- **GPU or PCIe power states.** The Arc B570 never entered runtime suspend (0 s suspended) and
  L1 ASPM is off on its link.

The BIOS setting cannot be read back from Linux, so it may not have been saved. The Linux C-state
guard had never been installed. Module 15 now installs only that guard by default; the chipset
watchdog is opt-in (`STRIX_HW_WATCHDOG=yes`) because Alex would rather not risk a self-reboot.

### The test to run at the next hang

Before pressing the power button, find out whether the kernel is still alive:

1. From the MacBook: `ping 100.101.86.5`, or `ssh alexponce@strix`. A reply means the kernel is
   alive and the hang is in the display stack (GPU, KWin), which points somewhere else entirely.
2. At the keyboard: hold **Alt + PrtSc** and press **S**, then **U**, then **B**, a second apart.
   `kernel.sysrq=176` permits exactly sync, remount read-only and reboot. If the machine reboots,
   the kernel was alive. If nothing happens, the whole machine was frozen.

Write down which one happened. That single answer separates a CPU/platform freeze from a GPU one.

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

## Both mitigations finally live (2026-09-22)

A seventh unclean stop (Sep 19 16:44, idle, silent, 26 hours dead) was handled by the crash agent,
but a check on Sep 22 showed that **neither guard had ever reached the running system**: every
core still had its deepest idle state enabled, and no watchdog was loaded. Module 15 had never
been run after the Sep 19 commit. So seven freezes tested nothing.

Installed by hand on Sep 22, as root, with the exact files Module 15 writes:

- `strix-no-deep-cstate.service` enabled and active; `state2/disable` reads 1 on all 12 cores.
- `sp5100_tco` loaded, `RuntimeWatchdogSec=60s`; systemd reports
  `Using hardware watchdog /dev/watchdog0: 'SP5100 TCO timer'`, state active.
- `STRIX_HW_WATCHDOG="yes"` in `config.env` (gitignored, so it lives only on the box).

Alex reversed the watchdog decision: the machine now has to be reachable remotely at all times,
and a one-minute self-reboot is the lesser evil. After a reset the box returns on its own: no
disk encryption, SSH and Tailscale enabled at boot, SDDM autologin, linger for alexponce. GRUB
holds the menu for 30 s after an unclean boot, then continues.

What the next freeze now means:

- **No freeze for two weeks** -> the idle guard did it. Then set `STRIX_NO_DEEP_CSTATE=no`, rerun
  module 15, and see whether the BIOS setting alone holds.
- **Freeze, watchdog reboots it** -> the C-state theory is wrong. Next: DOCP off in the BIOS
  (RAM is four sticks at 3066 MT/s; Zen 2 rates four sticks at 2933), then BIOS 3636
  (2026-01-30), re-enabling Above 4G Decoding and Resizable BAR afterwards.
- **Freeze and no reboot** -> the chipset timer did not fire either; suspect the PSU or the
  mains, and check the NVMe unsafe-shutdown counter in the postmortem.

## Seventh hang, with both guards live (2026-09-23 06:53:41)

The first freeze that actually tested the mitigations. Both were confirmed running beforehand:
`state2/disable` read 1 on all 12 cores, and systemd held `/dev/watchdog0` with a 60 s hardware
timeout from Sep 22 09:36.

The heartbeat's last sample is 06:53:36. The machine was idle and cool:

    06:53:36  load 0.34  blocked 4  CPU 57.8 C  GPU pkg 30 C  VRAM 34 C  fan 1095 rpm  NVMe 33.9 C

The C2 usage counter reads 69350345 and had not moved for hours, so the cores never entered deep
idle. The journal's last entry is 06:53:41.046. Both records stop inside five seconds of each
other, with no thermal ramp, no load spike, no kernel message and an empty pstore.

Three conclusions:

- **The Ryzen idle-freeze theory is dead.** The cores were held out of C2 and the machine froze
  anyway. The BIOS Power Supply Idle Control change is not the answer either.
- **The chipset watchdog did not reset the box.** It was armed, the timeout was 60 s, and the
  machine sat dead for 75 minutes until Alex power-cycled it at 08:08. Either the SP5100 reset
  path is masked in this board's firmware, or whatever stops the CPU also stops the chipset
  timer. A watchdog that cannot fire is not a remote-availability guarantee.
- **The power supply is not dropping out.** The box stays powered with fans spinning through
  every one of these events. A rail collapse would not leave it running.

What is left: the DIMMs. Four sticks run at 3066 MT/s under DOCP, and Zen 2 rates four sticks at
2933. A memory controller or Infinity Fabric hang stops every core at once with no exception to
log, which is exactly this signature. That is the next test, and it costs nothing to run.

### Order of tests from here

1. **DOCP off** in the BIOS, RAM back to JEDEC. Run a week. No software changes, no new risk.
2. **Memtest86+** overnight if a freeze follows, from the GRUB menu.
3. **BIOS 3636** (2026-01-30), then re-enable Above 4G Decoding and Resizable BAR.
4. **Pull the Arc B570** and run headless over Tailscale SSH. The Ryzen 5 3600 has no integrated
   graphics, so this is display-free by necessity, and that is the point: a headless box that
   never freezes implicates the card.

### The watchdog never survived a reboot

`/etc/modules-load.d/strix-watchdog.conf` does nothing on Ubuntu. The kernel packages deny-list
`sp5100_tco` in `/lib/modprobe.d/blacklist_linux_*.conf`, and systemd-modules-load obeys it:

    systemd-modules-load[392]: Module 'sp5100_tco' is deny-listed (by kmod)
    systemd[1]: Failed to open any watchdog device before the initial transaction completed

So the watchdog was live only because it was modprobed by hand on Sep 22, and it vanished at the
next boot. Module 15 now installs `strix-watchdog-module.service`, which runs an explicit
`modprobe` before `sysinit.target`. An explicit modprobe ignores the deny-list. Verify after a
reboot that `/dev/watchdog0` exists and systemd reports it.

### The dead monitor is the monitor, not the GPU

Both outputs still work as far as the machine is concerned. `card0-DP-2` and `card0-HDMI-A-3`
report `connected`, `dpms=On`, and a full 256-byte EDID read over DDC. kscreen-doctor shows both
enabled with modes set and geometry assigned. A panel that answers EDID has a live controller
board, so the failure is downstream: backlight, inverter or panel. Confirm by plugging it into
another machine. Do not read anything into `stat` reporting `edid` as 0 bytes; sysfs binary
attributes always report size 0 and still return data.

## The board sensors, and a failing CPU fan (2026-09-24)

`acpi_enforce_resources=lax` plus `nct6775` made the NCT6798D readable. The first hour of data
found something no other sensor on this machine could see.

Fan response against the duty cycle the board commands:

| | at 76% PWM | at 96% PWM | RPM per % duty |
|---|---|---|---|
| fan1 | 1105 | 1275 | 8.5 |
| fan2 | 1190 (at 49%) | 2008 (at 76%) | 30 |

fan2 scales the way a working fan scales. fan1 is nearly flat: a fifth more duty buys 170 RPM,
and at 96% it delivers 1275 RPM where a Wraith Stealth is rated near 2600. At the same time the
CPU sat at Tctl 77.8 C with roughly a third of its threads busy, on a 65 W part.

The header mapping is unconfirmed, because reading the ASUS fan labels needs the BIOS and Alex is
usually remote. It does not change the conclusion: the CPU is running far hotter than this cooler
should allow, and idle temperature rose 7 C in five days while the case warmed 2 C. Replace the
cooler. A 35 dollar tower beats repasting the Wraith.

Two unrelated readings that look alarming and are not: AUXTIN0 and AUXTIN3 both sit at exactly
95.0 C with alarms while three neighbours read 28.0 C, which is the open-circuit value for
unconnected thermistors. The `in*` voltage channels have no board-specific divider mapping, so
`in2`, `in3`, `in7` and `in8` are clearly the 3.3 V rails but nothing yet identifies +12 V.

The watchdog fix worked: `/dev/watchdog0` now exists after a plain reboot, systemd holds it at a
60 s timeout, and `strix-watchdog-module.service` is enabled. DOCP is off, four sticks at
2400 MT/s. The deep-idle guard is still active.

### Thermal cap, for the remote case

`strix-cpu-thermal-cap.service` turns boost off and optionally caps `scaling_max_freq`. It is not
a fix. It exists because a freeze while Alex is away means the machine is gone until he is back in
the room, so running the CPU cooler than a failing heatsink allows is worth a slower single thread.
Arm it with `STRIX_CPU_MAX_MHZ` in `config.env`: `base` for boost off, or a number in MHz.

### Remote recovery is the real gap

Nine freezes, and the only way back has been a hand on the power button. The watchdog is armed but
did not fire on Sep 23. A smart plug on the wall outlet, plus **Restore AC Power Loss = Power On**
in the BIOS, turns every freeze into a 30-second phone tap. That BIOS setting is the one thing
that has to wait for someone to be at the machine.
