---
name: hpc-slurm
description: Work on the ISAAC-NG SLURM cluster at UTK and the bioinformatics pipelines that run there - akodon-genome-assembly-workflow, rnaseq-nfcore-wrapper-alphavirus, viral-intrahost-variant-workflow, hantavirus-ngs-workflow. Use for SLURM job scripts, Apptainer images, cluster SSH or transfers, or anything submitted with sbatch.
---

# HPC / SLURM workflows

Target is the ISAAC-NG cluster at UTK (SLURM + Apptainer). Jobs are submitted from a login
node; nothing heavy runs on strix itself.

## Cluster facts come from isaac-hpc

`~/work/tools/isaac-hpc` (private repo `aleponce4/isaac-hpc`) is the authoritative source for
partitions, QOS limits, GRES syntax, filesystems, SSH handling and known failures. Pull it
before a session of cluster work, since Alex updates it from other machines. Read its
`README.md` and `GOTCHAS.md` before the first cluster command, and follow `AGENTS.md` on what
needs Alex's approval. Point to its files from this skill and from project docs. Do not copy
its facts elsewhere: they are date-stamped and change.

| For | Read in `~/work/tools/isaac-hpc` |
|---|---|
| Partitions, QOS limits, which partition accepts which QOS | `CLUSTER.md`, "Partitions" |
| Requesting a specific GPU type (GRES) | `CLUSTER.md`, "Partitions" |
| GPU models, memory and bf16 support | `CLUSTER.md`, "Hardware" |
| Home, scratch and project paths and quotas | `CLUSTER.md`, "Filesystems" |
| SSH master sockets, one Duo push per host, `BatchMode` | `lib/ssh_common.sh`, `GOTCHAS.md` #1 |
| `sbatch` missing or `$SCRATCHDIR` empty over SSH | `GOTCHAS.md` #2 |
| An array refused with `QOSMaxSubmitJobPerUserLimit` | `GOTCHAS.md` #12 and #13 |
| Moving data through a DTN | `recipes/01_connect_and_transfer.md` |
| A Python or GPU environment on a compute node | `recipes/02_python_env_gpu.md` |
| Submit, wait for a marker file, pull results | `recipes/03_submit_and_wait.md` |
| Job script skeletons | `templates/cpu_job.slurm`, `templates/gpu_array.slurm` |

### Using it from strix

isaac-hpc was written on a Windows laptop running WSL. On strix:

- Follow the README quickstart from the clone directory. A fresh clone has no `env.sh`; create
  it from `env.example.sh`. It is git-ignored.
- Skip the WSL advice (`GOTCHAS.md` #15 and the WSL line in recipe 01). Read `/mnt/d/...` in
  the recipes as a local path such as `/data/...`, and `~/isaac-hpc` as `~/work/tools/isaac-hpc`.
- `~/.ssh/config` (tracked as `dotfiles/ssh/config` in `~/linux-setup`) defines `Host isaac`
  with the placeholder `User CHANGE_ME_netid` and a global `ControlPersist 10m`. The
  `lib/ssh_common.sh` helpers set their own `ControlPath`, so `ssh isaac` opens a separate
  master and asks for its own Duo push.

## Pipeline repos

### The settings that ship are placeholders

`config/pipeline.env` (and `slurm_toy.env`, `smoke_test.env`) hold the tunables. In
akodon-genome-assembly-workflow the SLURM account ships as `ACF-UTKXXXX`, and the submit
scripts refuse to run while `SBATCH_ACCOUNT` contains `XXXX`. Set it from isaac-hpc's
`env.sh`: `export SBATCH_ACCOUNT="$ISAAC_ACCOUNT"`. The partition and QoS defaults carry ISAAC
partition names. Check each pair against `CLUSTER.md` before a real run. `config/samples.tsv`
ships with synthetic rows.

Everything is `${VAR:-default}`, so override by environment rather than editing tracked files:

    PROJECT_ROOT=/lustre/... SAMPLES_TSV=... sbatch ...

Paths derive from `PROJECT_ROOT`: `DATA_DIR`, `OUTPUT_DIR`, `LOG_DIR` (`logs/slurm`), and
stage-specific dirs like `SUPERNOVA_RUN_DIR`, `PSEUDOHAP_DIR`, `FILTERED_DIR`.

### Orchestration is native SLURM, deliberately

No Nextflow/Snakemake for the Akodon workflow. It uses bash + job arrays (`--array`), explicit
dependency chains (`--dependency=afterok:<jobid>`), and submission manifests. This was chosen
for fine-grained control of array bounds, submission throttling and stage recovery without an
external engine on the cluster. Do not "modernise" it into a workflow engine.

- Stages are numbered `00`-`21` under `slurm/`; the number is the dependency order.
- `run_pipeline.sh` submits the whole stage range in one pass (`00`-`21` by default).
  `run_pipeline_chained.sh` submits the stages in chunks
  so fewer jobs wait in the queue at once, which matters under the per-user submit limit
  (`GOTCHAS.md` #12).
- `run_smoke_test.sh` / `run_slurm_smoke_test.sh` before a real submission.
- Stage 00 is preflight - run it and read it rather than assuming the environment is right.

`viral-intrahost-variant-workflow` **is** Nextflow DSL2, and
`rnaseq-nfcore-wrapper-alphavirus` is a SLURM execution wrapper around `nf-core/rnaseq`.
Check which model a repo uses before editing. Nextflow runs hit `GOTCHAS.md` #3 (compute nodes
may have no network) and #4 (the `work/` directory uses up the file-count quota).

### Containers

Containers run under Apptainer, since nobody has root on the cluster. Pull a published image
on a DTN as `recipes/02_python_env_gpu.md` describes. Build custom images on strix with
`apptainer` (passwordless sudo covers it), then push the `.sif` into scratch through a DTN with
`isaac_push`.

## Before submitting anything

1. Set `SBATCH_ACCOUNT`, and confirm each partition/QoS pair is one you hold (`CLUSTER.md`).
2. Run the smoke test.
3. Put `LOG_DIR` on Lustre scratch or project space, never home (`CLUSTER.md`, "Filesystems").
4. Keep large data on scratch, never in the repo.
5. Ask Alex before any `sbatch` or `salloc`, and report the job ID (`AGENTS.md`).
