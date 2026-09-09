# Remote access to strix

Three independent ways in, deliberately. When one breaks it is usually the thing you would
have used to fix it.

| path | what it gives you | needs |
|---|---|---|
| **Tailscale SSH + `strix-remote`** | terminal, survives disconnects | tailnet |
| **KRDP** (`3389`) | the real Plasma desktop | tailnet |
| **Claude Code Remote Control** | reply to a running session from phone/laptop | Claude app |

## The persistent session

    ssh alexponce@strix
    strix-remote

`strix-remote` attaches to a tmux session named `strix`, creating it if needed, with a window
already running Claude Code. The session is held open by `strix-remote-session.service` and
survives both the SSH connection and the desktop session.

**Linger is what makes this reliable.** `loginctl enable-linger` keeps the user systemd
instance running without a login, so the session exists at boot and after logout -- which is
exactly the situation where you need a way in. Without it, a broken Plasma session takes the
recovery path down with it.

`claude` resolves only from a **login** shell: it lives in fnm's node-versions tree, not on the
default PATH. Every unit and script here uses `bash -lc` for that reason. A non-login shell
silently produces a session with no claude in it.

## KRDP, not Chrome Remote Desktop

RDP is on `3389`, scoped by ufw: `ALLOW on tailscale0`, `DENY on enp6s0`. Credentials and TLS
material live in `~/.config/krdp/` (0700) and never enter the repo.

Two things that cost time:

- `krdpserver --help` says it generates a temporary certificate when none is given. Under
  systemd it does not -- it exits 255 with `A valid TLS certificate ("") and key ("") is
  required`. The certificate is passed explicitly.
- Testing a port against the machine's own LAN IP proves nothing: the packet routes over `lo`,
  which ufw permits. Test from another host, or scope the rule by interface as done here.

## What went wrong on 2026-09-09

Plasma came up broken and the machine rebooted twice. The chain:

    chrome-remote-desktop@alexponce.service   enabled, starts at boot
      -> ~/.chrome-remote-desktop-session      unset WAYLAND_DISPLAY; exec startplasma-x11
        -> a SECOND Plasma session (kwin_x11 + Xorg) beside the Wayland one
          -> plasma-kglobalaccel cannot acquire org.kde.kglobalaccel: on Plasma 6 Wayland
             KWin owns that D-Bus name
            -> hang, 5s start timeout, restart ... 216 times in one boot
              -> plasmashell dead, both desktop portals dead, every autostart failed

Both sessions share one user systemd instance, so they fight over a single unit. The restart
loop is what turned a benign conflict into a dead desktop.

**The config switch was already off and did not help.** `ENABLE_CRD="no"` had been set since
2026-09-05, but it only guarded *installation*; the system unit had been enabled by an earlier
authorization and nothing ever disabled it. A flag that only prevents installing is not an off
switch -- module 60 now actively disables the unit when `ENABLE_CRD != yes`.

### Guards now in place

- `plasma-kglobalaccel.service.d/strix-restart-limit.conf` -- `StartLimitBurst=5` per 120s, so
  a failure becomes one visible failed unit instead of a session-killing loop.
- `bootstrap.sh 90` checks for: an X11 Plasma session running beside Wayland, CRD enabled, any
  unit in an active restart storm, plasmashell running, portal active, RDP listening, RDP
  denied on the LAN, the tmux session, and linger.

### Recovery, if it happens again

    systemctl --user list-units --state=failed
    systemctl --user stop plasma-kglobalaccel.service     # break the loop first
    sudo systemctl disable --now chrome-remote-desktop@alexponce.service
    systemctl --user restart plasma-xdg-desktop-portal-kde.service
    systemctl --user start plasma-plasmashell.service

Restart the portals before the shell; plasmashell depends on them.
