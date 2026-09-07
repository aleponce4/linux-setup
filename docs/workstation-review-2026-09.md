# Workstation review — 2026-09-07

State: verification 62/63 (the one failure is Chrome Remote Desktop, optional, KDE RDP over
Tailscale already works). Hardware headroom: Arc B570 **10172 MB VRAM**, 31 GB RAM, 850 GB
free on `/`, 400 GB free on `/data`.

Ordered by value, not by effort.

---

## 1. Do this first: get the restic password off this machine

Still open from the original TODO, and it is the only item here that can cost you everything.
`/backup/restic` is encrypted; without `~/.config/restic/password` the backups are
unreadable. Today that password exists **only on the disk it protects**. A root-disk failure
loses the key and the backups in one event.

Bitwarden is already installed and autostarts. This is a five-minute task and it should not
wait behind anything else in this document.

## 2. The biggest available win: a local LLM for dictation cleanup

`dictate-polish` currently pays **~2.5–4 s of network round trip** before the model generates
a single token — measured, not estimated. That is most of the latency, and it is pure
overhead. A local model removes it entirely.

The hardware suits this well:

| Model class | q4 VRAM | Fits 10 GB? |
|---|---|---|
| Qwen3-4B | ~3 GB | comfortably, leaves room for Whisper |
| 7–8B | ~6–7 GB | yes, but competes with the Whisper model for VRAM |

Cleanup is an easy task -- punctuation, filler removal, keeping the corrected half of a
self-correction. It does not need a frontier model. Qwen3-4B is the recommended
latency-per-accuracy point for exactly this kind of voice work.

**Route: llama.cpp with the Vulkan backend.** This is already proven on this machine --
Speech Note transcribes through `libwhisper-vulkan.so` on the same GPU.

**Do not invest in IPEX-LLM.** Intel archived the repository in January 2026. Any guide
recommending it is now stale, regardless of publication date.

Design note: keep both paths. Local model for the common case, Claude for long or difficult
passages. `dictate-polish` already degrades gracefully, so adding a local first attempt with
the existing Claude call as fallback is a small change to a script that already has the
structure for it.

Caveat worth stating plainly: this reduces the **cleanup** latency only. The 8 s
transcription is batch Whisper and scales with how long you speak; no local LLM changes that.

## 3. Agent infrastructure: currently empty

For a machine whose purpose includes agent work, these are all unset:

| | State |
|---|---|
| MCP servers | **none configured** in `~/.claude.json` or settings |
| Skills | none (`~/.claude/skills` does not exist) |
| Subagents | none (`~/.claude/agents` does not exist) |
| Plugins | none installed |

The Google/Gmail/Calendar/PubMed tools available in sessions come from account-level
connectors, not from anything on this machine -- so nothing here is reproducible through the
repo, which is contrary to how the rest of the workstation is managed.

Worth adding, in order of likely payoff for this work:

- **GitHub MCP** -- the most-installed server of 2026; `gh` is already authenticated here.
- **Filesystem MCP** -- scoped to `~/work` and `/data`, not `$HOME`.
- **Playwright MCP** -- browser automation that stays on this hardware; relevant for CVAT and
  any scraping the LIBS/seed work needs.
- **Postgres MCP** -- only if a database becomes the bottleneck.

Security note that applies to all of them: prompt injection and tool poisoning are the live
risks. Self-host anything touching sensitive data, and scope filesystem access to project
directories rather than the whole home directory.

## 4. Parallel agents: use git worktrees

Worktrees have become the standard isolation primitive for running several agents against one
repository -- each gets its own working directory and index over a shared object store, which
removes file-level conflicts without cloning. Claude Code supports this natively.

Caveat: worktrees isolate *files*, not *runtime*. Two agents still contend for the same
ports, the same database volumes, the same `/data` paths. If that becomes a problem, the next
step is a container per agent, not more worktrees.

## 5. Small CLI tools that make agents measurably more effective

Already present: `rg`, `fd`, `jq`, `bat`, `delta`, `zoxide`, `fzf`, `atuin`, `direnv`, `uv`,
`ruff`, `gh`.

Worth adding to `lists/`:

| Tool | Why it helps an agent specifically |
|---|---|
| `ast-grep` | structural code search; far fewer false positives than regex on large repos |
| `yq` | YAML as `jq` does JSON -- Kubernetes, CI configs, conda env files |
| `just` | project command runner; gives an agent one discoverable place to find "how do I run this" |
| `hyperfine` | honest benchmarking, so performance claims can be checked rather than asserted |
| `tokei` | fast repo size/shape summary when orienting in unfamiliar code |
| `difftastic` | syntax-aware diffs; much better review signal than line diffs |

## 6. Fragility worth knowing about

`claude` resolves from
`~/.local/share/fnm/node-versions/v24.20.0/installation/lib/node_modules/...`.

It is found correctly from login shells, non-login shells, and `.desktop` launches -- all
verified. But it is bound to **Node v24.20.0**. Changing fnm's default Node version silently
breaks `dictate-polish` and `ai-clipboard`, and the failure mode is a fallback path rather
than an error, so it would not be obvious. If Node is ever upgraded, reinstall the npm
globals in `lists/npm-globals.txt` and re-test dictation.

## 7. Remaining backlog, unchanged

`CHANGE_ME_netid` in `~/.ssh/config`; UTHSC VPN; CVAT `docker compose up -d`; wallpaper;
KDE Activities for the Onteko/UTHSC split; the six `pre-migration-2026-09-02` remote branches;
HANDOFF section 4 security housekeeping (revoke the Tailscale auth key, `passwd`, delete the
stale tailnet nodes, delete `secrets-passphrase.txt`).
