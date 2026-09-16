# Partial Qnet / LSM pipeline

## Quick start

Run this from inside `lsm_pipeline/`. Use a **unique model prefix** and **unique manifest name** for each survey/wave/model run.

For example, to train Afrobarometer R9 in 50-estimator chunks using a fixed sample of 27,830 respondents, 20 CPUs per chunk, alpha 0.2, and seed 42:

```bash
./run.sh \
  -d merged_r9_data.csv \
  -w 50 \
  -o models/r9 \
  -p afro_r9_ \
  -c 20 \
  -a 0.2 \
  -s 27830 \
  -k 1 \
  -r 42 \
  -M afro_r9_manifest.json \
  -l
```

Here:

- `-p afro_r9_` is the unique fragment prefix. Fragments will be named like `afro_r9_0-50.qnet.gz`, `afro_r9_50-100.qnet.gz`, etc.
- `-s 27830` selects exactly 27,830 training respondents. Use `-s 0` to train on all respondents.
- `-M afro_r9_manifest.json` is the unique manifest for this run. It records the exact feature order, chunk ranges, model filenames, sample size, seed, alpha, and other training parameters.
- Every fragment uses the same deterministic sampled respondent set, and the selected respondent indices are saved in each partial model as `training_index`.
- `-l` submits the generated jobs with `sbatch`.

After all fragment jobs have finished, check them and assemble the final model with:

```bash
./finish.sh \
  -M afro_r9_manifest.json \
  -o LSM_merged_r9_data.qnet
```

The final serialized model will be:

```text
LSM_merged_r9_data.qnet.gz
```

If any fragment is missing, corrupt, has the wrong feature ordering, or contains the wrong estimator range, `finish.sh` will stop without assembling and create:

```text
retry_missing.sh
```

Run the retry script, wait for those jobs to finish, and then run the same `finish.sh` command again:

```bash
./retry_missing.sh

./finish.sh \
  -M afro_r9_manifest.json \
  -o LSM_merged_r9_data.qnet
```

For another survey or round, change at least the data file, prefix, output directory, and manifest name. For example, R8 should use names such as `afro_r8_`, `models/r8`, and `afro_r8_manifest.json` rather than reusing the R9 names.

---

This set uses one invariant everywhere: estimator ranges are **half-open `[begin,end)`**. A chunk `0-50` therefore contains estimator keys `0..49`; `50-100` contains `50..99`.

## Why the old pipeline could lose models

1. Multiple partial jobs could be given the same output prefix/path and overwrite each other.
2. The old assembler parsed the filename end as inclusive while training used `np.arange(BEGIN, END)` (exclusive end).
3. The old assembler compared numeric range indices against `feature_names`, even though `Qnet.mix` works with globally indexed `estimators_`.
4. The old `run.sh` counts raw CSV header fields, including the index column. With the supplied CSV that gives 354 fields, but `index_col=0` leaves 353 model features; the final range can therefore request a nonexistent estimator. Raw header counting can also disagree after filtering. This pipeline creates a manifest from the exact post-filter feature list instead.

## Files

- `createLSM.py` — trains full or partial Qnet models using `fit(..., index_array=range)` while retaining the complete feature matrix.
- `inferqnet.py` — backward-compatible alias for the historical partial-generation script.
- `launch_create.sh` / `launch.sh` — create/submit one Slurm chunk.
- `make_manifest.py` — records the exact feature order, expected ranges, and expected model filenames.
- `run.sh` — plans all chunks and either prepares sbatch files, submits them, or runs locally.
- `check_models.py` — detects missing, zero-byte, unloadable, wrong-feature, or wrong-estimator-range models and writes `retry_missing.sh` containing only failed ranges.
- `assemble.py` — refuses incomplete input, merges globally indexed estimator dictionaries, saves the final model, reloads it, and checks all estimators again.
- `finish.sh` — check then assemble; never assembles an incomplete set.
- `clean.sh` — targeted cleanup.
- `test_pipeline.sh` and `test_year2017_2018.csv` — small end-to-end local test.

## HPC use

Prepare sbatch files only:

```bash
./run.sh -d year2017_2018.csv -w 50 -o models -p qmodel -c 20
```

Submit missing chunks:

```bash
./run.sh -d year2017_2018.csv -w 50 -o models -p qmodel -c 20 -l
```

The 353-feature supplied CSV produces ranges `0-50, 50-100, ..., 350-353` when `-k 1` is used.

After the Slurm jobs have completed:

```bash
./finish.sh -M model_manifest.json -o assembled.qnet
```

If any model is absent or corrupt, `finish.sh` stops and creates `retry_missing.sh`. Run:

```bash
./retry_missing.sh
```

After those jobs finish, run `finish.sh` again.

## Local test

Activate the environment containing `quasinet`, then:

```bash
./test_pipeline.sh
```

The test uses the supplied data structure, trains 12 features in 3 chunks of width 4, checks each chunk, assembles them, reloads the final `.qnet.gz`, and verifies estimator keys `0..11`.

## Backward-compatible direct partial call

Either spelling works:

```bash
python3 inferqnet.py -file data.csv -begin 100 -end 150 -njobs 20 -alpha 0.2 -prefix models/qmodel
```

or

```bash
python3 createLSM.py -f data.csv -b 100 -e 150 -njobs 20 -a 0.2 -o models/qmodel
```

Both write `models/qmodel100-150.qnet.gz`, containing globally indexed estimator keys 100 through 149.
