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

# ---- git repos into $WORK_DIR, in per-context subdirectories ----
mkdir -p "$WORK_DIR"
if have gh && gh auth status >/dev/null 2>&1; then gh auth setup-git >/dev/null 2>&1 || true; fi

# clone_repo OWNER/REPO [SUBDIR] -> $WORK_DIR/[SUBDIR/]REPO, skipping anything already cloned
clone_repo() {
  local repo="$1" subdir="${2:-}" name dest url
  name="${repo##*/}"; name="${name%.git}"
  dest="$WORK_DIR/${subdir:+$subdir/}$name"
  [[ -d "$dest/.git" ]] && return 0
  # A repo that was cloned flat by an earlier run gets moved rather than cloned twice.
  if [[ -n "$subdir" && -d "$WORK_DIR/$name/.git" ]]; then
    mkdir -p "$(dirname "$dest")"
    mv "$WORK_DIR/$name" "$dest" && { log "moved $name -> $subdir/"; return 0; }
  fi
  url="$repo"; [[ "$repo" =~ ^https?:// ]] || url="https://github.com/$repo.git"
  mkdir -p "$(dirname "$dest")"
  if git clone -q "$url" "$dest" 2>/dev/null; then
    log "cloned $repo -> ${subdir:+$subdir/}$name"
  else
    warn "clone failed (private? run 'gh auth login' then re-run 80): $repo"
  fi
}

# Every repo in the configured orgs. Requires gh auth; skipped cleanly without it.
if [[ -n "${GITHUB_ORGS_CLONE_ALL:-}" ]]; then
  if have gh && gh auth status >/dev/null 2>&1; then
    for org in $GITHUB_ORGS_CLONE_ALL; do
      org_dir="$(printf '%s' "$org" | tr '[:upper:]' '[:lower:]')"
      mapfile -t org_repos < <(gh repo list "$org" --limit 200 --json nameWithOwner \
                                 -q '.[].nameWithOwner' 2>/dev/null)
      if ((${#org_repos[@]})); then
        log "org $org: ${#org_repos[@]} repos -> $WORK_DIR/$org_dir/"
        for r in "${org_repos[@]}"; do [[ -n "$r" ]] && clone_repo "$r" "$org_dir"; done
      else
        warn "could not list repos for org '$org' (no access, or the org is empty)"
      fi
    done
  else
    warn "GITHUB_ORGS_CLONE_ALL is set but gh is not authenticated; run 'gh auth login' then re-run 80"
  fi
fi

# Explicit entries: "<owner/repo> [subdir]"
while read -r repo subdir; do
  [[ -n "$repo" ]] && clone_repo "$repo" "$subdir"
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
