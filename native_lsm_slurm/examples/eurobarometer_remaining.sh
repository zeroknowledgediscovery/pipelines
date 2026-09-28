#!/usr/bin/env bash
set -euo pipefail

# Run this script FROM:
#   Dropbox/ZED/Research/MAGICS_research/survey/data/eurobarometer
#
# Default:
#   build remaining_eurobarometer.txt from ZA*.csv files whose sibling
#   native-LSM directory does not contain meta.txt.
#
# Optional upload to MCC:
#   MCP_TARGET=/scratch/ich248/eurobarometer ./eurobarometer_remaining.sh
#
# `mcp` comes from zeroknowledgediscovery/bash_utils:
#   mcp put <local_path> <remote_dest>

MANIFEST="${MANIFEST:-remaining_eurobarometer.txt}"
MCP_TARGET="${MCP_TARGET:-}"
EXPECTED_REMAINING="${EXPECTED_REMAINING:-97}"

: > "$MANIFEST"

shopt -s nullglob
for csv in ZA*.csv; do
  [[ "$csv" == *.csv.gcs ]] && continue
  modeldir="${csv%.csv}"

  if [[ ! -f "$modeldir/meta.txt" ]]; then
    printf '%s\n' "$csv" >> "$MANIFEST"
  fi
done

count="$(wc -l < "$MANIFEST" | tr -d ' ')"
echo "Remaining Eurobarometer CSVs: $count"
echo "Manifest: $MANIFEST"

if [[ "$count" != "$EXPECTED_REMAINING" ]]; then
  echo "NOTE: expected $EXPECTED_REMAINING based on the 2026-09-27 audit; the folder state may have changed."
fi

if [[ -n "$MCP_TARGET" ]]; then
  command -v mcp >/dev/null 2>&1 || {
    echo "mcp not found in PATH. Install/copy it from zeroknowledgediscovery/bash_utils." >&2
    exit 2
  }

  echo "Uploading $count CSVs to: $MCP_TARGET"
  while IFS= read -r csv; do
    echo "mcp put $csv $MCP_TARGET"
    mcp put "$csv" "$MCP_TARGET"
  done < "$MANIFEST"

  mcp put "$MANIFEST" "$MCP_TARGET"
  echo "Upload complete."
else
  cat <<EOF

No files uploaded.

To also copy the remaining CSVs and manifest to MCC:

  MCP_TARGET=/scratch/ich248/eurobarometer $0

Equivalent one-file command:

  mcp put ZA3939_v1-0-1.csv /scratch/ich248/eurobarometer
EOF
fi
