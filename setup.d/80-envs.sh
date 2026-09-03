#!/usr/bin/env bash
# 80-envs.sh - named conda envs from envs/conda/*.yml (micromamba), clone the git repos in lists/git-repos.txt
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config
export PATH="$HOME/.local/bin:$PATH"
export MAMBA_ROOT_PREFIX="$HOME/micromamba"

# ---- conda envs (conda-forge only; Anaconda's defaults channel is never used) ----
if have micromamba; then
  mkdir -p "$MAMBA_ROOT_PREFIX"
  cat >"$HOME/.condarc" <<'EOF'
channels:
  - conda-forge
channel_priority: strict
auto_activate_base: false
EOF
  existing="$(micromamba env list 2>/dev/null | awk 'NR>2 {print $1}')"
  for yml in "$REPO_DIR"/envs/conda/*.yml; do
    [[ -f "$yml" ]] || continue
    name="$(sed -n 's/^name:[[:space:]]*//p' "$yml" | head -n1)"
    [[ -n "$name" ]] || continue
    if grep -qx "$name" <<<"$existing"; then continue; fi
    log "creating conda env $name"
    micromamba env create -y -q -f "$yml" >/dev/null 2>&1 || warn "env $name failed (run: micromamba env create -f $yml)"
  done
else
  warn "micromamba missing; run module 40 first"
fi

# ---- git repos into $WORK_DIR ----
mkdir -p "$WORK_DIR"
if have gh && gh auth status >/dev/null 2>&1; then gh auth setup-git >/dev/null 2>&1 || true; fi
while read -r repo; do
  name="${repo##*/}"; name="${name%.git}"
  dest="$WORK_DIR/$name"
  [[ -d "$dest/.git" ]] && continue
  url="$repo"; [[ "$repo" =~ ^https?:// ]] || url="https://github.com/$repo.git"
  git clone -q "$url" "$dest" 2>/dev/null && log "cloned $repo" || warn "clone failed (private? run 'gh auth login' then re-run 80): $repo"
done < <(read_list "$LISTS_DIR/git-repos.txt")

# ---- distrobox: other distros' userlands sharing $HOME (Docker backend; 'sg docker' works before the group is active) ----
if [[ "${ENABLE_DISTROBOX:-yes}" == "yes" ]] && have distrobox; then
  while read -r name image; do
    [[ -n "$name" && -n "$image" ]] || continue
    if sg docker -c "distrobox list" 2>/dev/null | grep -q "| $name "; then continue; fi
    log "creating distrobox '$name' from $image"
    if sg docker -c "distrobox create -Y -n '$name' -i '$image'" >/dev/null 2>&1; then log "distrobox $name ready (distrobox enter $name)"; else warn "distrobox $name failed; re-run 80 after re-login"; fi
  done < <(read_list "$LISTS_DIR/distroboxes.txt")
fi

log "envs done. Project Python envs: 'uv sync' / 'uv venv' inside each repo; R projects with renv: renv::restore(); other distros: distrobox enter arch."
