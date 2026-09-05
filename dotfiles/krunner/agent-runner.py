#!/usr/bin/env python3
"""KRunner D-Bus plugin (org.kde.krunner1): agents, SSH hosts, repos and setup modules from the Meta key.

  cc <prompt>      Claude Code in ~/work (or the prompt as the first message)
  cx <prompt>      Codex CLI
  agy <prompt>     Antigravity CLI
  ssh <host>       hosts from ~/.ssh/config
  repo <name>      open ~/work/<name> in VS Code, or a terminal there
  setup <module>   re-run a linux-setup module

Installed by setup.d/30-desktop-kde.sh (desktop file + D-Bus activation). Logs go to journalctl --user.
"""
import glob
import os
import re
import shlex
import subprocess

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

IFACE = "org.kde.krunner1"
TERM = os.environ.get("AGENT_TERMINAL", "ghostty")
WORK = os.path.expanduser(os.environ.get("WORK_DIR", "~/work"))
SETUP = os.path.expanduser("~/linux-setup")
ICON_TERM = "utilities-terminal"

AGENTS = {
    "cc": ("claude", "Claude Code", lambda p: "claude " + shlex.quote(p) if p else "claude"),
    "claude": ("claude", "Claude Code", lambda p: "claude " + shlex.quote(p) if p else "claude"),
    "cx": ("codex", "Codex", lambda p: "codex " + shlex.quote(p) if p else "codex"),
    "codex": ("codex", "Codex", lambda p: "codex " + shlex.quote(p) if p else "codex"),
    "agy": ("agy", "Antigravity", lambda p: "agy -i " + shlex.quote(p) if p else "agy"),
    "gemini": ("agy", "Antigravity", lambda p: "agy -i " + shlex.quote(p) if p else "agy"),
}


def ssh_hosts():
    hosts = []
    try:
        with open(os.path.expanduser("~/.ssh/config")) as fh:
            for line in fh:
                m = re.match(r"^\s*Host\s+(.+)$", line)
                if m:
                    hosts += [h for h in m.group(1).split() if "*" not in h and "?" not in h]
    except OSError:
        pass
    return hosts


def repos():
    return sorted(os.path.basename(p.rstrip("/")) for p in glob.glob(WORK + "/*/") if os.path.isdir(os.path.join(p, ".git")))


def modules():
    return sorted(os.path.basename(m) for m in glob.glob(SETUP + "/setup.d/*.sh"))


def open_terminal(command, cwd=None):
    """Open the terminal, run command, keep the shell open afterwards."""
    script = f"{command}; exec ${{SHELL:-bash}}"
    subprocess.Popen([TERM, "-e", "bash", "-lc", script], cwd=cwd or os.path.expanduser("~"), start_new_session=True)


class AgentRunner(dbus.service.Object):
    def __init__(self):
        bus = dbus.SessionBus()
        name = dbus.service.BusName("org.kde.agentrunner", bus)
        super().__init__(name, "/AgentRunner")

    @dbus.service.method(IFACE, in_signature="s", out_signature="a(sssida{sv})")
    def Match(self, query):
        out = []

        def add(match_id, text, icon, subtext, relevance=0.9, mtype=100):
            out.append((match_id, text, icon, mtype, relevance, {"subtext": subtext, "category": "Agents & work"}))

        parts = query.strip().split(None, 1)
        if not parts:
            return out
        key, rest = parts[0].lower(), (parts[1].strip() if len(parts) > 1 else "")

        if key in AGENTS:
            binary, label, _ = AGENTS[key]
            add(f"agent::{key}::{rest}", f"{label}: {rest or 'open in ~/work'}", ICON_TERM, f"runs {binary} in a new Ghostty window")
        elif key == "ssh":
            for h in ssh_hosts():
                if rest.lower() in h.lower():
                    add("ssh::" + h, f"SSH to {h}", "network-server", "from ~/.ssh/config", 0.85)
        elif key in ("repo", "code"):
            for r in repos():
                if rest.lower() in r.lower():
                    add("code::" + r, f"Open {r} in VS Code", "com.visualstudio.code", os.path.join(WORK, r), 0.85)
                    add("term::" + r, f"Terminal in {r}", ICON_TERM, os.path.join(WORK, r), 0.75)
        elif key == "setup":
            for m in modules():
                if rest.lower() in m.lower():
                    add("setup::" + m[:2], f"linux-setup: run {m}", "system-run", "re-applies this module in a terminal", 0.7)
        return out

    @dbus.service.method(IFACE, out_signature="a(sss)")
    def Actions(self):
        return []

    @dbus.service.method(IFACE, in_signature="ss")
    def Run(self, match_id, action_id):
        kind, _, arg = match_id.partition("::")
        if kind == "agent":
            key, _, prompt = arg.partition("::")
            _, _, build = AGENTS[key]
            open_terminal(build(prompt), WORK if os.path.isdir(WORK) else None)
        elif kind == "ssh":
            open_terminal("ssh " + shlex.quote(arg))
        elif kind == "code":
            subprocess.Popen(["code", os.path.join(WORK, arg)], start_new_session=True)
        elif kind == "term":
            open_terminal("true", os.path.join(WORK, arg))
        elif kind == "setup":
            open_terminal(f"cd {shlex.quote(SETUP)} && ./bootstrap.sh {shlex.quote(arg)}")


if __name__ == "__main__":
    DBusGMainLoop(set_as_default=True)
    AgentRunner()
    GLib.MainLoop().run()
