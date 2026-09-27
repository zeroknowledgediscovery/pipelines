# Native LSM Slurm utilities

This directory is for the native C++ LSM trainer (`bin/LSM`) that produces model directories containing `data_set_0/`, `trees/`, `source_maps/`, and `meta.txt`.

The older Python/Quasinet partial-model pipeline is intentionally retained unchanged in `../lsm_pipeline_slurm/`.

## Files

- `launch_native.sh` — create, and optionally submit, one Slurm job for one CSV.
- `run_manifest.sh` — prepare or submit one native-LSM job for every CSV listed in a manifest.
- `examples/eurobarometer_remaining.sh` — run from the Eurobarometer data folder to identify CSVs without completed sibling LSM directories and optionally upload them to MCC with the `mcp` helper from `zeroknowledgediscovery/bash_utils`.

## One dataset

On the cluster:

```bash
export LSM_BIN=/path/to/lsm/bin/LSM

./launch_native.sh \
  -d ZA3939_v1-0-1.csv \
  -c 120 \
  -a 0.1 \
  -l
```

By default, `ZA3939_v1-0-1.csv` is written to the sibling output directory `ZA3939_v1-0-1/`.

Defaults follow the MCC setup used in the older launch utilities:

```text
threads:   120
time:      50:00:00
memory:    500g
partition: normal
account:   coa_ich248_uksr
```

Native-LSM subset-search defaults in these utilities are:

```text
subset mode:       auto
max exact levels:  20
fast levels:       16
```

Override them when needed:

```bash
export LSM_SUBSET_MODE=exact
export LSM_MAX_EXACT_LEVELS=20
export LSM_FAST_LEVELS=16
```

## Eurobarometer: prepare and optionally copy remaining files

From:

```text
Dropbox/ZED/Research/MAGICS_research/survey/data/eurobarometer
```

run:

```bash
/path/to/pipelines/native_lsm_slurm/examples/eurobarometer_remaining.sh
```

This creates:

```text
remaining_eurobarometer.txt
```

and does not copy anything unless `MCP_TARGET` is set.

To also push every remaining CSV and the manifest to MCC:

```bash
MCP_TARGET=/scratch/ich248/eurobarometer \
  /path/to/pipelines/native_lsm_slurm/examples/eurobarometer_remaining.sh
```

The upload syntax comes from the `mcp` helper in the private `zeroknowledgediscovery/bash_utils` repository:

```bash
mcp put <local_path> <remote_dest>
```

## Submit all manifest files on MCC

Place/copy this `native_lsm_slurm` directory somewhere accessible on MCC, then:

```bash
cd /scratch/ich248/eurobarometer

export LSM_BIN=/path/to/lsm/bin/LSM

/path/to/pipelines/native_lsm_slurm/run_manifest.sh \
  -M remaining_eurobarometer.txt \
  -D . \
  -c 120 \
  -a 0.1 \
  -l
```

Each CSV is submitted as a separate 120-CPU Slurm job. Existing outputs with `meta.txt` are skipped unless `-F` is supplied.

If the allocation only permits 120 CPUs in use at once, Slurm will leave later jobs queued and run them as resources become available.
