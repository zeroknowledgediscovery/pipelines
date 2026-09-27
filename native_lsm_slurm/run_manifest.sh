#!/usr/bin/env bash
set -euo pipefail

MANIFEST=""
DATA_DIR="."
OUTPUT_ROOT=""
LSM_BIN="${LSM_BIN:-}"
CORES="${NUMCORES:-120}"
ALPHA="${ALPHA:-0.1}"
TIME="${TIME:-50:00:00}"
MEMORY="${MEMORY:-500g}"
PARTITION="${PARTITION:-normal}"
ACCOUNT="${ACCOUNT:-coa_ich248_uksr}"
SUBMIT=false
FORCE=false

usage() {
  cat <<'EOF'
Usage: run_manifest.sh -M manifest.txt [options]

  -M FILE      one CSV filename/path per line
  -D DIR       directory containing CSVs (default: .)
  -O DIR       output root (default: DATA_DIR)
  -x PATH      native LSM executable (or set LSM_BIN)
  -c N         CPUs/threads per model (default: 120)
  -a FLOAT     alpha (default: 0.1)
  -t TIME      Slurm time (default: 50:00:00)
  -m MEM       Slurm memory (default: 500g)
  -p PART      partition (default: normal)
  -A ACCOUNT   account (default: coa_ich248_uksr)
  -l           submit jobs; omit to only prepare sbatch files
  -F           force existing models
EOF
}

while getopts ":M:D:O:x:c:a:t:m:p:A:lFh" opt; do
  case "$opt" in
    M) MANIFEST="$OPTARG" ;;
    D) DATA_DIR="$OPTARG" ;;
    O) OUTPUT_ROOT="$OPTARG" ;;
    x) LSM_BIN="$OPTARG" ;;
    c) CORES="$OPTARG" ;;
    a) ALPHA="$OPTARG" ;;
    t) TIME="$OPTARG" ;;
    m) MEMORY="$OPTARG" ;;
    p) PARTITION="$OPTARG" ;;
    A) ACCOUNT="$OPTARG" ;;
    l) SUBMIT=true ;;
    F) FORCE=true ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage; exit 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
  esac
done

[[ -n "$MANIFEST" ]] || { usage; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 2; }
[[ -n "$LSM_BIN" ]] || { echo "Set LSM_BIN or pass -x /path/to/bin/LSM" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$(readlink -f "$DATA_DIR")"
if [[ -z "$OUTPUT_ROOT" ]]; then
  OUTPUT_ROOT="$DATA_DIR"
else
  mkdir -p "$OUTPUT_ROOT"
  OUTPUT_ROOT="$(readlink -f "$OUTPUT_ROOT")"
fi

count=0
while IFS= read -r entry || [[ -n "$entry" ]]; do
  entry="${entry%%#*}"
  entry="$(echo "$entry" | xargs)"
  [[ -n "$entry" ]] || continue

  if [[ "$entry" = /* ]]; then
    csv="$entry"
  else
    csv="$DATA_DIR/$entry"
  fi

  base="$(basename "$csv")"
  out="$OUTPUT_ROOT/${base%.csv}"

  args=(
    "$SCRIPT_DIR/launch_native.sh"
    -d "$csv"
    -o "$out"
    -x "$LSM_BIN"
    -c "$CORES"
    -a "$ALPHA"
    -t "$TIME"
    -m "$MEMORY"
    -p "$PARTITION"
    -A "$ACCOUNT"
  )
  [[ "$SUBMIT" == true ]] && args+=(-l)
  [[ "$FORCE" == true ]] && args+=(-F)

  "${args[@]}"
  count=$((count + 1))
done < "$MANIFEST"

if [[ "$SUBMIT" == true ]]; then
  echo "Submitted/processed $count manifest entries."
else
  echo "Prepared $count manifest entries. Re-run with -l to submit."
fi
