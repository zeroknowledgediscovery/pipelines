#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone

from lsm_common import load_dataframe, ranges_for, model_file, feature_hash


def main():
    p = argparse.ArgumentParser(description="Create a manifest for partial Qnet jobs")
    p.add_argument("-f", "--file", required=True)
    p.add_argument("--step", type=int, default=50)
    p.add_argument("--model-dir", default="models")
    p.add_argument("--prefix", default="qmodel")
    p.add_argument("-k", type=int, default=1)
    p.add_argument("-a", "--alpha", type=float, default=0.2)
    p.add_argument("-samples", type=int, default=0)
    p.add_argument("-njobs", type=int, default=20)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("-o", "--output", default="model_manifest.json")
    args = p.parse_args()

    # No sampling is needed merely to determine the feature set/count.
    df = load_dataframe(args.file, k=args.k, samples=0, seed=args.seed)
    names = [str(x) for x in df.columns]
    n = len(names)

    model_dir = os.path.abspath(args.model_dir)
    os.makedirs(model_dir, exist_ok=True)
    prefix_path = os.path.join(model_dir, args.prefix)
    rs = ranges_for(n, args.step)

    manifest = {
        "schema_version": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "datafile": os.path.abspath(args.file),
        "feature_count": n,
        "feature_names": names,
        "feature_names_sha256": feature_hash(names),
        "step": args.step,
        "model_dir": model_dir,
        "model_prefix": prefix_path,
        "prefix_name": args.prefix,
        "k": args.k,
        "alpha": args.alpha,
        "samples": args.samples,
        "njobs": args.njobs,
        "seed": args.seed,
        "ranges": [
            {"begin": b, "end": e, "model_file": model_file(prefix_path, b, e)}
            for b, e in rs
        ],
    }

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print(f"Manifest: {args.output}")
    print(f"Features: {n}")
    print(f"Chunks: {len(rs)}")
    for b, e in rs:
        print(f"{b}\t{e}\t{model_file(prefix_path, b, e)}")


if __name__ == "__main__":
    main()
