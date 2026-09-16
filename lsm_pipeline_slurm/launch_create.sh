#!/bin/bash
set -euo pipefail

TIME="5:10:00"
MEMORY="200g"
NUMCORES=1
DATAFRAME=""
BEG=""
END=""
ALPHA=0.2
SAMPLES=0
K=1
OUTPUT="qmodel"
SEED=42
PARTITION="short"
ACCOUNT="coa_ich248_uksr"
CONDAENVPATH="/project/ich248_uksr/IXC/condaenv"
SUBMIT_JOB=false

usage() {
  echo "Usage: $0 -d csv [-b beg -e end] [-t time] [-m mem] [-c cores] [-a alpha] [-s samples] [-k min_unique] [-o model_prefix] [-r seed] [-p partition] [-A account] [-E conda_env] [-l]"
}

while getopts ":t:m:c:b:d:e:a:s:k:o:r:p:A:E:lh" opt; do
  case "$opt" in
    t) TIME="$OPTARG" ;;
    m) MEMORY="$OPTARG" ;;
    c) NUMCORES="$OPTARG" ;;
    b) BEG="$OPTARG" ;;
    d) DATAFRAME="$OPTARG" ;;
    e) END="$OPTARG" ;;
    a) ALPHA="$OPTARG" ;;
    s) SAMPLES="$OPTARG" ;;
    k) K="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    r) SEED="$OPTARG" ;;
    p) PARTITION="$OPTARG" ;;
    A) ACCOUNT="$OPTARG" ;;
    E) CONDAENVPATH="$OPTARG" ;;
    l) SUBMIT_JOB=true ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage; exit 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
  esac
done

if [[ -z "$DATAFRAME" ]]; then
  echo "Error: -d CSV is required" >&2
  exit 2
fi
if [[ -n "$BEG" && -z "$END" ]] || [[ -z "$BEG" && -n "$END" ]]; then
  echo "Error: -b and -e must be supplied together" >&2
  exit 2
fi

if [[ -n "$BEG" ]]; then
  RANGE_ARGS=(-b "$BEG" -e "$END")
  TAG="${BEG}_${END}"
else
  RANGE_ARGS=()
  TAG="all"
fi

SBATCH_FILE="submit_job_${TAG}.sbatch"
# Shell-escape paths/values once before embedding them in the generated job.
printf -v Q_DATA '%q' "$DATAFRAME"
printf -v Q_OUT '%q' "$OUTPUT"
printf -v Q_ENV '%q' "$CONDAENVPATH"
printf -v Q_RANGE '%q ' "${RANGE_ARGS[@]}"

cat > "$SBATCH_FILE" <<EOF
#!/bin/bash
#SBATCH --time=${TIME}
#SBATCH --job-name=Qnet_${TAG}
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${NUMCORES}
#SBATCH --mem=${MEMORY}
#SBATCH --partition=${PARTITION}
#SBATCH -e qrun-${TAG}-%j.err
#SBATCH -o qrun-${TAG}-%j.out
#SBATCH -A ${ACCOUNT}
set -euo pipefail

module load ccs/Miniforge3
source activate
conda activate ${Q_ENV}

date
python3 ./createLSM.py -f ${Q_DATA} ${Q_RANGE} -njobs ${NUMCORES} -a ${ALPHA} -samples ${SAMPLES} -k ${K} --seed ${SEED} -o ${Q_OUT}
date
EOF

echo "Created $SBATCH_FILE"
if [[ "$SUBMIT_JOB" == true ]]; then
  SBATCH_OUTPUT=$(sbatch "$SBATCH_FILE")
  JOBID=$(awk '{print $4}' <<< "$SBATCH_OUTPUT")
  if [[ -z "$JOBID" ]]; then
    echo "sbatch did not return a job id: $SBATCH_OUTPUT" >&2
    exit 1
  fi
  echo "Submitted $TAG as job $JOBID"
  echo "$(date): range=$TAG job=$JOBID sbatch=$SBATCH_FILE" >> job_submission.log
fi
