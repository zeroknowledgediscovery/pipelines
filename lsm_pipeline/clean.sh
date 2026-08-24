#!/bin/bash
set -euo pipefail
DIR="${1:-models}"
if [[ "$DIR" == "/" || -z "$DIR" ]]; then
  echo "Refusing unsafe cleanup target: '$DIR'" >&2
  exit 2
fi
rm -f -- "$DIR"/qmodel*.qnet.gz
rm -f -- submit_job_*.sbatch qrun-*.err qrun-*.out retry_missing.sh job_submission.log
printf 'Cleaned generated model/job files under %s\n' "$DIR"
