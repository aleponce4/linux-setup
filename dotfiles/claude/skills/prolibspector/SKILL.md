---
name: prolibspector
description: Working in the ProLIBSpector LIBS instrument product repo (Onteko) - acquisition, calibration, QC, ranking/classification, UI, packaging. Also covers seed-libs-classification and libs-spectroscopy-workbench.
---

# ProLIBSpector

Private product codebase for the LIBS instrument software, at `~/work/onteko/ProLIBSpector`.
Product work starts here, never in the public `libs-spectroscopy-workbench`; public backports
are deliberate and limited.

## Running the tests - the flag is load-bearing

    python -m unittest discover -s tests -t . -v

`-t .` enables the suite's environment isolation. Dropping it does not just change output, it
changes what the tests do. Never "simplify" this command.

## The architectural boundary that must not break

`tests/test_repo_boundaries.py` enforces that **`prolibspector/` must not import `research/`
or an ML runtime at module level.** The shipped product and the research/ML side are separate
dependency worlds:

- product deps: `requirements.txt` (Windows) / `requirements-linux.txt`
- release build: the separate `LIBS_venv`
- research/ML: its own venv and dependency file

Training runtimes must never appear in `requirements.txt`. If you need a model at runtime, it
is added deliberately to `compile.py`'s `--add-data` allowlist.

## Before every PR

1. Run the suite exactly as above.
2. `test_repo_boundaries.py` must pass.
3. Touched dependencies or bundled assets? Update `THIRD_PARTY_NOTICES.md` and confirm
   `python compile.py` release-compliance checks still pass.
4. Touched `qc_calibrations/`? State in the PR which calibration is canonical and how it was
   verified (per-folder READMEs).

Branches: `feature/<topic>`, `fix/<topic>`, `docs/<topic>`. `main` is always releasable.

Owner review required for: `prolibspector/`, `compile.py`, `packaging/`, `qc_calibrations/`,
root CSV reference data, and the legal files (`NOTICE.md`, `THIRD_PARTY_NOTICES.md`,
`IMPORT_BASELINE.md`). Docs-only and `tools/`/`tests/`-only may land direct to main.

## Data rules

- Fixtures under `prolibspector/*/fixtures/` are **synthetic only**. Never commit customer,
  field, or hardware-serial data.
- Datasets, experiment outputs and model weights never enter git (`research/**` is ignored).
- Vendor binaries/manuals only with license terms recorded in `THIRD_PARTY_NOTICES.md`.
- **Never commit `libs_token.txt`** or any credential.

## Releases

- Version source of truth: `prolibspector/__init__.py` `__version__`. Tags are `vX.Y.Z`.
- `release.bat` runs from `LIBS_venv` on a clean, up-to-date `main`; it runs `compile.py`,
  commits, pushes, and creates the GitHub release.
- `compile.py` is the single source of build truth for both platforms. Linux `.deb` comes from
  Ubuntu 24.04 via `packaging/linux/build_release.py`.

## Related repos

- `seed-libs-classification` - research spectra and notebooks. **Git LFS, ~13 GB checkout.**
- `libs-spectroscopy-workbench` - public community edition; ProLIBSpector was snapshotted from
  it on 2026-04-22 without history.
- `LIBS-Software-Releases` - release assets only, no source.
