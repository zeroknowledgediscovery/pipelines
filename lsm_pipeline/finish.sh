#!/bin/bash
set -euo pipefail
MANIFEST="model_manifest.json"
OUTPUT="assembled.qnet"
RETRY="retry_missing.sh"
while getopts ":M:o:r:h" opt; do
  case "$opt" in
    M) MANIFEST="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    r) RETRY="$OPTARG" ;;
    h) echo "Usage: $0 [-M manifest] [-o assembled.qnet] [-r retry_missing.sh]"; exit 0 ;;
    \?) exit 2 ;;
  esac
done

if python3 ./check_models.py -M "$MANIFEST" --write-retry "$RETRY"; then
  python3 ./assemble.py -M "$MANIFEST" -o "$OUTPUT"
else
  echo "Assembly not attempted because one or more partial models are missing/corrupt." >&2
  echo "Run ./$RETRY to resubmit only the bad ranges, then run finish.sh again." >&2
  exit 2
fi
