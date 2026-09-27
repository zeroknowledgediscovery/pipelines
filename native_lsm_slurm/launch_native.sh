#!/usr/bin/env bash
set -euo pipefail

TIME="${TIME:-50:00:00}"
MEMORY="${MEMORY:-500g}"
NUMCORES="${NUMCORES:-120}"
DATAFRAME=""
ALPHA="${ALPHA:-0.1}"
OUTPUT=""
LSM_BIN="${LSM_BIN:-}"
PARTITION="${PARTITION:-normal}"
ACCOUNT="${ACCOUNT:-coa_ich248_uksr}"
SUBSET_MODE="${LSM_SUBSET_MODE:-auto}"
MAX_EXACT_LEVELS="${LSM_MAX_EXACT_LEVELS:-20}"
FAST_LEVELS="${LSM_FAST_LEVELS:-16}"
SUBMIT_JOB=false
FORCE=false

usage() {
  cat <<'EOF'
Usage: launch_native.sh -d CSV [options]

Required:
  -d CSV       input CSV

Options:
  -o DIR       output LSM directory (default: CSV basename without .csv)
  -x PATH      native LSM executable (or set LSM_BIN)
  -c N         CPUs/threads (default: 120)
  -a FLOAT     alpha (default: 0.1)
  -t TIME      Slurm time (default: 50:00:00)
  -m MEM       Slurm memory (default: 500g)
  -p PART      Slurm partition (default: normal)
  -A ACCOUNT   Slurm account (default: coa_ich248_uksr)
  -l           submit with sbatch
  -F           force even if output/meta.txt already exists
  -h           help

Environment:
  LSM_SUBSET_MODE       exact|fast|auto (default: auto)
  LSM_MAX_EXACT_LEVELS  default: 20
  LSM_FAST_LEVELS       default: 16
EOF
}

while getopts ":d:o:x:c:a:t:m:p:A:lFh" opt; do
  case "$opt" in
    d) DATAFRAME="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    x) LSM_BIN="$OPTARG" ;;
    c) NUMCORES="$OPTARG" ;;
    a) ALPHA="$OPTARG" ;;
    t) TIME="$OPTARG" ;;
    m) MEMORY="$OPTARG" ;;
    p) PARTITION="$OPTARG" ;;
    A) ACCOUNT="$OPTARG" ;;
    l) SUBMIT_JOB=true ;;
    F) FORCE=true ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage; exit 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
  esac
done

[[ -n "$DATAFRAME" ]] || { usage; exit 2; }
[[ -f "$DATAFRAME" ]] || { echo "Input not found: $DATAFRAME" >&2; exit 2; }
[[ -n "$LSM_BIN" ]] || { echo "Set LSM_BIN or pass -x /path/to/bin/LSM" >&2; exit 2; }
[[ -x "$LSM_BIN" ]] || { echo "LSM executable is not executable: $LSM_BIN" >&2; exit 2; }

DATAFRAME="$(readlink -f "$DATAFRAME")"
WORKDIR="$(pwd)"

if [[ -z "$OUTPUT" ]]; then
  base="$(basename "$DATAFRAME")"
  OUTPUT="${base%.csv}"
fi

if [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$WORKDIR/$OUTPUT"
fi

if [[ "$FORCE" != true && -f "$OUTPUT/meta.txt" ]]; then
  echo "SKIP complete model: $OUTPUT"
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT")"

tag="$(basename "$OUTPUT" | tr -cs 'A-Za-z0-9_.-' '_')"
SBATCH_FILE="submit_native_${tag}.sbatch"

printf -v Q_DATA '%q' "$DATAFRAME"
printf -v Q_OUT '%q' "$OUTPUT"
printf -v Q_BIN '%q' "$LSM_BIN"

cat > "$SBATCH_FILE" <<EOF
#!/usr/bin/env bash
#SBATCH --time=${TIME}
#SBATCH --job-name=LSM_${tag}
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${NUMCORES}
#SBATCH --mem=${MEMORY}
#SBATCH --partition=${PARTITION}
#SBATCH -A ${ACCOUNT}
#SBATCH -o native-lsm-${tag}-%j.out
#SBATCH -e native-lsm-${tag}-%j.err

set -euo pipefail

echo "START: \$(date)"
echo "HOST:  \$(hostname)"
echo "INPUT: ${Q_DATA}"
echo "OUT:   ${Q_OUT}"
echo "CPUS:  \${SLURM_CPUS_PER_TASK:-${NUMCORES}}"

${Q_BIN} \
  ${Q_DATA} \
  ${ALPHA} \
  ${Q_OUT} \
  --threads \${SLURM_CPUS_PER_TASK:-${NUMCORES}} \
  --subset-mode ${SUBSET_MODE} \
  --max-exact-levels ${MAX_EXACT_LEVELS} \
  --fast-levels ${FAST_LEVELS}

test -f ${Q_OUT}/meta.txt
echo "END:   \$(date)"
EOF

chmod +x "$SBATCH_FILE"
echo "Created $SBATCH_FILE"

if [[ "$SUBMIT_JOB" == true ]]; then
  sbatch_out="$(sbatch "$SBATCH_FILE")"
  jobid="$(awk '{print $4}' <<< "$sbatch_out")"
  [[ -n "$jobid" ]] || { echo "sbatch did not return a job id: $sbatch_out" >&2; exit 1; }
  echo "Submitted $DATAFRAME -> $OUTPUT as job $jobid"
  echo "$(date): input=$DATAFRAME output=$OUTPUT job=$jobid sbatch=$SBATCH_FILE" >> native_lsm_job_submission.log
fi
