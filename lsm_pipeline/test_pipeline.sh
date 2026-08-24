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
