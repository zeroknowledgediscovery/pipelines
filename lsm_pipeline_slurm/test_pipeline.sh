#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

CSV="${1:-test_year2017_2018.csv}"
OUT="test_output"
MANIFEST="$OUT/test_manifest.json"
ASSEMBLED="$OUT/test_assembled.qnet"

python3 - <<'PY'
try:
    import quasinet.qnet
except Exception as e:
    raise SystemExit(
        "TEST REQUIRES quasinet in the active Python environment. "
        "Activate the MCC/conda environment first.\n" + repr(e)
    )
PY

rm -rf "$OUT"
mkdir -p "$OUT/models"

echo "=== 0. Verify sampled all-empty columns are removed ==="
python3 - "$OUT" <<'PY'
import os
import sys
import pandas as pd
from lsm_common import load_dataframe

out = sys.argv[1]
path = os.path.join(out, "empty_column_regression.csv")

# Construct a column that is non-empty somewhere in the full dataset but is
# guaranteed to be empty in the deterministic sampled training subset.
df = pd.DataFrame({
    "good": ["a" if i % 2 == 0 else "b" for i in range(20)],
    "always_empty": [""] * 20,
    "whitespace_only": ["   "] * 20,
    "sparse": [""] * 20,
}, index=[f"id{i}" for i in range(20)])

selected = set(df.sample(n=5, random_state=7).index)
nonselected = next(i for i in df.index if i not in selected)
df.loc[nonselected, "sparse"] = "present_only_outside_training_sample"
df.to_csv(path, index_label="respondent")

loaded = load_dataframe(path, k=1, samples=5, seed=7)
assert "good" in loaded.columns
assert "always_empty" not in loaded.columns
assert "whitespace_only" not in loaded.columns
assert "sparse" not in loaded.columns
assert len(loaded) == 5
print("PASS: columns empty in the actual sampled training dataframe are removed")
PY

echo "=== 1. Generate partial models locally ==="
./run.sh -d "$CSV" -w 4 -o "$OUT/models" -p qmodel -c 2 -a 0.2 -s 120 -k 1 -r 7 -M "$MANIFEST" -L

echo "=== 2. Verify every partial model ==="
python3 ./check_models.py -M "$MANIFEST" --write-retry "$OUT/retry_missing.sh"

echo "=== 3. Assemble and verify serialized full model ==="
python3 ./assemble.py -M "$MANIFEST" -o "$ASSEMBLED"

echo "=== 4. Final independent check ==="
python3 - "$MANIFEST" "$ASSEMBLED.gz" <<'PY'
import json, sys
from quasinet.qnet import load_qnet
m=json.load(open(sys.argv[1]))
q=load_qnet(sys.argv[2], gz=True)
keys=sorted(q.estimators_.keys())
expected=list(range(m['feature_count']))
assert keys == expected, (keys, expected)
assert list(map(str,q.feature_names)) == m['feature_names']
print('PASS: assembled model contains', len(keys), 'globally indexed estimators')
PY

echo "ALL TESTS PASSED"
