#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shlex
import sys
import numpy as np

from lsm_common import load_manifest, estimator_keys, feature_hash


def import_qnet():
    try:
        from quasinet.qnet import load_qnet
        return load_qnet
    except Exception as e:
        raise RuntimeError(
            "Could not import quasinet.qnet. Activate the same quasinet environment used for training."
        ) from e


def inspect_model(path, beg, end, manifest, load_qnet):
    if not os.path.isfile(path):
        return False, "MISSING FILE"
    if os.path.getsize(path) == 0:
        return False, "ZERO-BYTE FILE"
    try:
        model = load_qnet(path, gz=True)
    except Exception as e:
        return False, f"LOAD FAILED: {type(e).__name__}: {e}"

    names = [str(x) for x in model.feature_names]
    if names != manifest["feature_names"]:
        return False, "FEATURE ORDER/NAMES MISMATCH"
    if feature_hash(names) != manifest["feature_names_sha256"]:
        return False, "FEATURE HASH MISMATCH"

    keys = estimator_keys(model)
    expected = list(range(beg, end))
    if keys != expected:
        return False, f"ESTIMATOR KEYS WRONG: got {keys[:5]}...{keys[-5:] if keys else []}, expected [{beg},{end})"

    mb = getattr(model, "training_column_beg", beg)
    me = getattr(model, "training_column_end", end)
    if int(mb) != beg or int(me) != end:
        return False, f"RANGE METADATA WRONG: [{mb},{me})"

    return True, "OK"


def retry_command(manifest, beg, end):
    q = shlex.quote
    return (
        f"./launch_create.sh -d {q(manifest['datafile'])} -b {beg} -e {end} "
        f"-c {manifest['njobs']} -a {manifest['alpha']} -s {manifest['samples']} "
        f"-k {manifest['k']} -r {manifest['seed']} -o {q(manifest['model_prefix'])} -l"
    )


def main():
    p = argparse.ArgumentParser(description="Verify every partial Qnet in a manifest")
    p.add_argument("-M", "--manifest", default="model_manifest.json")
    p.add_argument("--write-retry", default="retry_missing.sh",
                   help="Write commands to resubmit missing/corrupt chunks; empty disables")
    args = p.parse_args()

    manifest = load_manifest(args.manifest)
    load_qnet = import_qnet()
    bad = []

    print(f"Checking {len(manifest['ranges'])} chunks / {manifest['feature_count']} features")
    for r in manifest["ranges"]:
        ok, msg = inspect_model(r["model_file"], r["begin"], r["end"], manifest, load_qnet)
        tag = "OK " if ok else "BAD"
        print(f"{tag} [{r['begin']:>5},{r['end']:<5}) {msg}  {r['model_file']}")
        if not ok:
            bad.append(r)

    if bad:
        print(f"\nINCOMPLETE: {len(bad)} of {len(manifest['ranges'])} chunks are missing or invalid.")
        if args.write_retry:
            with open(args.write_retry, "w", encoding="utf-8") as f:
                f.write("#!/bin/bash\nset -euo pipefail\n")
                for r in bad:
                    f.write(retry_command(manifest, r["begin"], r["end"]) + "\n")
            os.chmod(args.write_retry, 0o755)
            print(f"Retry script written: {args.write_retry}")
        return 2

    print("\nCOMPLETE: every expected partial model is present and internally consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
