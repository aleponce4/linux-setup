#!/usr/bin/env bash
# 50-science.sh - R 4.6 (CRAN apt) + r2u binary packages + CRAN/Bioconductor lists, RStudio, Positron, Quarto+TinyTeX,
#                 PyMOL, MEGA/ChimeraX (URLs from config.env), DuckDB CLI, spectrometer udev rule
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"; load_config
export PATH="$HOME/.local/bin:$PATH"

apt_install_list "$LISTS_DIR/apt-science.txt"

# ---- R from CRAN's Ubuntu repo ----
add_apt_repo cran https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
  "deb [signed-by=/etc/apt/keyrings/cran.gpg] https://cloud.r-project.org/bin/linux/ubuntu ${R_CRAN_CODENAME}-cran40/"
# r2u declares this same CRAN repo in deb822 form (cran.sources) signed by Rutter's key.
# Two Signed-By values for one repo make apt refuse to read EVERY source, system-wide:
#   E: Conflicting values set for option Signed-By regarding source .../resolute-cran40/
#   E: The list of sources could not be read.
# Whichever ran first, keep r2u's and drop ours. This must sit outside the bspm branch
# below: once bspm is installed that branch is skipped, but add_apt_repo above still
# recreates cran.list on every run, so the conflict would silently return.
if [[ -f /etc/apt/sources.list.d/cran.sources && -f /etc/apt/sources.list.d/cran.list ]]; then
  sudo rm -f /etc/apt/sources.list.d/cran.list
  _APT_UPDATED=""
  log "dropped cran.list; r2u's cran.sources already declares CRAN"
fi

apt_install r-base r-base-dev

# ---- r2u: every CRAN package as a binary .deb, wired into install.packages() via bspm ----
if ! dpkg -l r-cran-bspm 2>/dev/null | grep -q '^ii'; then
  R2U="https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_${R_CRAN_CODENAME}.sh"
  if curl -fsI "$R2U" >/dev/null 2>&1; then
    # Keep the output: when this fails, every R package compiles from source instead of
    # installing as a binary, which turns minutes into hours. A silent warning hides why.
    r2u_log="${LOG_DIR:-/tmp}/r2u-setup.log"
    if curl -fsSL "$R2U" | sudo bash >"$r2u_log" 2>&1; then
      log "r2u + bspm configured"
    else
      warn "r2u setup failed (R packages will compile from source); last lines of $r2u_log:"
      tail -n 15 "$r2u_log" | sed 's/^/    /' | tee -a "$RUN_LOG" >&2
      warn "re-runnable on its own: curl -fsSL $R2U | sudo bash"
    fi
  else
    warn "no r2u script for $R_CRAN_CODENAME yet; R packages will compile from source (slow but works)"
  fi
fi

# ---- R packages from the lists (bspm turns these into apt installs when available) ----
tmp_r="$(mktemp --suffix=.R)"
cat >"$tmp_r" <<EOF
options(Ncpus = max(1L, parallel::detectCores() - 1L), repos = c(CRAN = "https://cloud.r-project.org"))
suppressWarnings(try(bspm::enable(), silent = TRUE))
read_list <- function(f) { x <- readLines(f); x <- sub("#.*", "", x); x <- trimws(x); x[nzchar(x)] }
want <- read_list("$LISTS_DIR/r-packages-cran.txt")
have <- rownames(installed.packages())
miss <- setdiff(want, have)
if (length(miss)) { cat("installing", length(miss), "CRAN packages\n"); install.packages(miss, quiet = TRUE) }
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager", quiet = TRUE)
bioc <- read_list("$LISTS_DIR/r-packages-bioc.txt")
missb <- setdiff(bioc, rownames(installed.packages()))
if (length(missb)) { cat("installing", length(missb), "Bioconductor packages\n"); BiocManager::install(missb, ask = FALSE, update = FALSE, quiet = TRUE) }
still <- setdiff(c(want, bioc), rownames(installed.packages()))
if (length(still)) cat("NOT installed:", paste(still, collapse = " "), "\n") else cat("all R packages present\n")
EOF
sudo Rscript "$tmp_r" 2>&1 | tail -n 20 || warn "R package installation reported errors"
rm -f "$tmp_r"
# radian needs R on PATH (it is); languageserver for VS Code comes from the list

# ---- RStudio Desktop ----
if ! have rstudio; then
  if [[ -n "${RSTUDIO_DEB_URL:-}" ]]; then download_deb "$RSTUDIO_DEB_URL"; else warn "RSTUDIO_DEB_URL empty; get the Ubuntu 26 .deb from https://posit.co/download/rstudio-desktop/"; fi
fi

# ---- Positron (latest GitHub release .deb) ----
if ! have positron; then
  # posit-dev/positron tags its releases on GitHub but attaches NO assets to them, so
  # github_latest_asset can never resolve a .deb here. The package is published on Posit's
  # CDN, named after the release tag.
  ptag="$(curl -fsSL 'https://api.github.com/repos/posit-dev/positron/releases?per_page=1' 2>/dev/null \
          | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
  if [[ -n "$ptag" ]]; then
    download_deb "https://cdn.posit.co/positron/releases/deb/x86_64/Positron-${ptag}-x64.deb"
  else
    warn "could not determine the latest Positron release tag"
  fi
fi
if have positron; then
  installed="$(positron --list-extensions 2>/dev/null | tr 'A-Z' 'a-z')"
  while read -r ext; do
    grep -qx "${ext,,}" <<<"$installed" || positron --install-extension "$ext" --force >/dev/null 2>&1 || warn "positron extension failed: $ext"
  done < <(read_list "$LISTS_DIR/positron-extensions.txt")
fi

# ---- Quarto + TinyTeX ----
if ! have quarto; then
  url="$(github_latest_asset quarto-dev/quarto-cli 'linux-amd64\.deb$' || true)"
  [[ -n "$url" ]] && download_deb "$url" || warn "could not resolve Quarto .deb"
fi
if have quarto && [[ ! -d "$HOME/.TinyTeX" ]]; then quarto install tinytex --no-prompt >/dev/null 2>&1 || warn "tinytex install failed"; fi

# ---- science apps with vendor downloads (fill URLs in config.env) ----
have chimerax || { [[ -n "${CHIMERAX_DEB_URL:-}" ]] && download_deb "$CHIMERAX_DEB_URL" || warn "ChimeraX: download the Ubuntu .deb after registering at https://www.rbvi.ucsf.edu/chimerax/download.html and set CHIMERAX_DEB_URL"; }
have megax || have mega || { [[ -n "${MEGA_DEB_URL:-}" ]] && download_deb "$MEGA_DEB_URL" || warn "MEGA: download the Ubuntu .deb from https://www.megasoftware.net/ and set MEGA_DEB_URL"; }

# ---- DuckDB CLI ----
if ! have duckdb; then
  # install.duckdb.org fails quietly in a non-interactive shell. DuckDB publishes no .deb,
  # only a zipped static binary, so take that directly.
  if ! curl -fsSL https://install.duckdb.org | sh >/dev/null 2>&1 || ! have duckdb; then
    durl="$(github_latest_asset duckdb/duckdb 'duckdb_cli-linux-amd64\.zip$' || true)"
    if [[ -n "$durl" ]]; then
      dtmp="$(mktemp -d)"
      if curl -fL --retry 3 -o "$dtmp/d.zip" "$durl" && unzip -q -o "$dtmp/d.zip" -d "$dtmp"; then
        install -m0755 "$dtmp/duckdb" "$HOME/.local/bin/duckdb" && log "installed duckdb CLI"
      else
        warn "duckdb download failed"
      fi
      rm -rf "$dtmp"
    else
      warn "could not resolve the duckdb CLI zip"
    fi
  fi
fi

# ---- Ocean Optics spectrometer (python-seabreeze / pyusb) without root ----
write_file_sudo /etc/udev/rules.d/10-oceanoptics.rules 0644 <<'EOF'
# Ocean Optics / Ocean Insight USB spectrometers (vendor 0x2457): allow user access for pyseabreeze
SUBSYSTEM=="usb", ATTRS{idVendor}=="2457", MODE="0666", GROUP="plugdev"
EOF
usergroup_add plugdev
sudo udevadm control --reload-rules || true

log "science done. Manual: RStudio/MEGA/ChimeraX .deb URLs in config.env if they were empty; CVAT via 'docker compose up -d' in ~/work/cvat."
