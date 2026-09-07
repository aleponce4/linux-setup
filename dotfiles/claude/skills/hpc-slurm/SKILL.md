---
name: hpc-slurm
description: Bioinformatics pipelines that run on the ISAAC SLURM cluster - akodon-genome-assembly-workflow, rnaseq-nfcore-wrapper-alphavirus, viral-intrahost-variant-workflow, hantavirus-ngs-workflow. Use for SLURM job scripts, Apptainer images, or anything submitted with sbatch.
---

# HPC / SLURM workflows

Target is the ISAAC institutional cluster (SLURM + Apptainer). Jobs are submitted from a login
node; nothing heavy runs on strix itself.

## The settings that ship are placeholders

`config/pipeline.env` (and `slurm_toy.env`, `smoke_test.env`) hold the tunables. **The SLURM
account, partition and QoS values in the repo are placeholders, not the values used for the
real run.** Anything submitted without setting them will be rejected or land on the wrong
queue. Same for `config/samples.tsv`.

Everything is `${VAR:-default}`, so override by environment rather than editing tracked files:

    PROJECT_ROOT=/lustre/... SAMPLES_TSV=... sbatch ...

Paths derive from `PROJECT_ROOT`: `DATA_DIR`, `OUTPUT_DIR`, `LOG_DIR` (`logs/slurm`), and
stage-specific dirs like `SUPERNOVA_RUN_DIR`, `PSEUDOHAP_DIR`, `FILTERED_DIR`.

## Orchestration is native SLURM, deliberately

No Nextflow/Snakemake for the Akodon workflow. It uses bash + job arrays (`--array`), explicit
dependency chains (`--dependency=afterok,<jobid>`), and submission manifests. This was chosen
for fine-grained control of array bounds, submission throttling and stage recovery without an
external engine on the cluster. Do not "modernise" it into a workflow engine.

- Stages are numbered `00`-`21` under `slurm/`; the number is the dependency order.
- `run_pipeline.sh` submits; `run_pipeline_chained.sh` adds queue throttling.
- `run_smoke_test.sh` / `run_slurm_smoke_test.sh` before a real submission.
- Stage 00 is preflight - run it and read it rather than assuming the environment is right.

`viral-intrahost-variant-workflow` **is** Nextflow DSL2, and
`rnaseq-nfcore-wrapper-alphavirus` is a SLURM execution wrapper around `nf-core/rnaseq`.
Check which model a repo uses before editing.

## Containers

Apptainer, not Docker (no root on the cluster). Images are HPC-compatible; build them on strix
with `apptainer` (passwordless sudo is granted for it) and move the `.sif` to the cluster.

## Before submitting anything

1. Confirm account/partition/QoS are real, not placeholders.
2. Run the smoke test.
3. Check `LOG_DIR` exists and is on cluster storage, not `$HOME`.
4. Large data belongs on cluster scratch/lustre, never in the repo.
