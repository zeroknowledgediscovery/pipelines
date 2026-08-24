#!/bin/bash
set -euo pipefail

DATAFILE=""
STEP=50
MODEL_DIR="models"
PREFIX="qmodel"
CORES=20
ALPHA=0.2
SAMPLES=0
K=1
SEED=42
MANIFEST="model_manifest.json"
MODE="prepare"   # prepare | submit | local
FORCE=false
TIME="5:10:00"
MEMORY="200g"
PARTITION="short"
ACCOUNT="coa_ich248_uksr"
CONDAENVPATH="/project/ich248_uksr/IXC/condaenv"

usage() {
cat <<EOF
Usage: $0 -d CSV [options]
  -w N       chunk width (default 50)
  -o DIR     model directory (default models)
  -p PREFIX  model prefix (default qmodel)
  -c N       CPUs per chunk (default 20)
  -a FLOAT   Qnet alpha (default 0.2)
  -s N       training sample rows, 0=all
  -k N       minimum unique non-empty values per retained column
  -r N       random seed
  -M FILE    manifest path
  -t TIME    Slurm time
  -m MEM     Slurm memory
  -P PART    Slurm partition
  -A ACCT    Slurm account
  -E PATH    conda environment
  -l         submit all missing chunks with sbatch
  -L         run all missing chunks locally (test/small data)
  -F         force regeneration even if model file exists
EOF
}

while getopts ":d:w:o:p:c:a:s:k:r:M:t:m:P:A:E:lLFh" opt; do
  case "$opt" in
    d) DATAFILE="$OPTARG" ;;
    w) STEP="$OPTARG" ;;
    o) MODEL_DIR="$OPTARG" ;;
    p) PREFIX="$OPTARG" ;;
    c) CORES="$OPTARG" ;;
    a) ALPHA="$OPTARG" ;;
    s) SAMPLES="$OPTARG" ;;
    k) K="$OPTARG" ;;
    r) SEED="$OPTARG" ;;
    M) MANIFEST="$OPTARG" ;;
    t) TIME="$OPTARG" ;;
    m) MEMORY="$OPTARG" ;;
    P) PARTITION="$OPTARG" ;;
    A) ACCOUNT="$OPTARG" ;;
    E) CONDAENVPATH="$OPTARG" ;;
    l) MODE="submit" ;;
    L) MODE="local" ;;
    F) FORCE=true ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage; exit 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
  esac
done

if [[ -z "$DATAFILE" ]]; then
  usage
  exit 2
fi

python3 ./make_manifest.py -f "$DATAFILE" --step "$STEP" --model-dir "$MODEL_DIR" \
  --prefix "$PREFIX" -k "$K" -a "$ALPHA" -samples "$SAMPLES" -njobs "$CORES" \
  --seed "$SEED" -o "$MANIFEST" >/dev/null

echo "Manifest written: $MANIFEST"

mapfile -t JOBS < <(python3 - "$MANIFEST" <<'PY'
import json, sys
m=json.load(open(sys.argv[1]))
for r in m['ranges']:
    print(f"{r['begin']}\t{r['end']}\t{r['model_file']}")
PY
)

for row in "${JOBS[@]}"; do
  IFS=$'\t' read -r BEG END EXPECTED <<< "$row"
  if [[ "$FORCE" != true && -s "$EXPECTED" ]]; then
    echo "SKIP existing: [$BEG,$END) $EXPECTED"
    continue
  fi

  if [[ "$MODE" == "local" ]]; then
    echo "LOCAL [$BEG,$END)"
    python3 ./createLSM.py -f "$DATAFILE" -b "$BEG" -e "$END" -njobs "$CORES" \
      -a "$ALPHA" -samples "$SAMPLES" -k "$K" --seed "$SEED" \
      -o "$MODEL_DIR/$PREFIX"
  else
    LAUNCH=(./launch_create.sh -d "$DATAFILE" -b "$BEG" -e "$END" -c "$CORES" \
      -a "$ALPHA" -s "$SAMPLES" -k "$K" -r "$SEED" -o "$MODEL_DIR/$PREFIX" \
      -t "$TIME" -m "$MEMORY" -p "$PARTITION" -A "$ACCOUNT" -E "$CONDAENVPATH")
    [[ "$MODE" == "submit" ]] && LAUNCH+=(-l)
    "${LAUNCH[@]}"
  fi
done

if [[ "$MODE" == "prepare" ]]; then
  echo "SBATCH files prepared but not submitted. Re-run with -l to submit."
elif [[ "$MODE" == "submit" ]]; then
  echo "Jobs submitted. After they finish, run: ./finish.sh -M '$MANIFEST'"
else
  echo "Local chunk generation complete. Run: ./finish.sh -M '$MANIFEST'"
fi
