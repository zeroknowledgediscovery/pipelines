#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
import numpy as np

from lsm_common import load_manifest, estimator_keys, feature_hash, qnet_save_stem


def main():
    p = argparse.ArgumentParser(description="Assemble verified partial Qnets into one complete Qnet")
    p.add_argument("-M", "--manifest", default="model_manifest.json")
    p.add_argument("-o", "--output", default="assembled.qnet",
                   help="Output model; .gz is appended by save_qnet if needed")
    args = p.parse_args()

    try:
        from quasinet.qnet import load_qnet, save_qnet
    except Exception as e:
        raise RuntimeError("Activate the quasinet environment before assembly") from e

    m = load_manifest(args.manifest)
    expected_all = list(range(m["feature_count"]))
    base = None
    reference_training_index = None

    for i, r in enumerate(m["ranges"]):
        path = r["model_file"]
        if not os.path.isfile(path):
            raise FileNotFoundError(
                f"Missing partial model {path}. Run check_models.py and retry missing jobs first."
            )
        part = load_qnet(path, gz=True)

        names = [str(x) for x in part.feature_names]
        if names != m["feature_names"] or feature_hash(names) != m["feature_names_sha256"]:
            raise ValueError(f"Feature mismatch in {path}")

        expected = list(range(r["begin"], r["end"]))
        keys = estimator_keys(part)
        if keys != expected:
            raise ValueError(f"Wrong estimator keys in {path}: expected [{r['begin']},{r['end']})")

        ti = getattr(part, "training_index", None)
        if reference_training_index is None and ti is not None:
            reference_training_index = np.asarray(ti)
        elif ti is not None and reference_training_index is not None:
            if not np.array_equal(reference_training_index, np.asarray(ti)):
                raise ValueError(f"training_index differs in {path}; chunks were not trained on identical rows")

        if base is None:
            base = part
        else:
            # Global estimator keys were preserved by fit(index_array=...).
            # Directly merge dictionaries; this is exactly what Qnet.mix ultimately does.
            overlap = set(base.estimators_).intersection(part.estimators_)
            if overlap:
                raise ValueError(f"Overlapping estimator keys in {path}: {sorted(overlap)[:10]}")
            base.estimators_.update(part.estimators_)
            if hasattr(base, "col_to_non_leaf_nodes"):
                delattr(base, "col_to_non_leaf_nodes")

        print(f"Added [{r['begin']},{r['end']}) from {path}")

    if base is None:
        raise RuntimeError("Manifest contains no model ranges")

    final_keys = estimator_keys(base)
    if final_keys != expected_all:
        missing = sorted(set(expected_all) - set(final_keys))
        extra = sorted(set(final_keys) - set(expected_all))
        raise RuntimeError(f"Assembly incomplete. missing={missing[:20]} extra={extra[:20]}")

    base.training_column_beg = 0
    base.training_column_end = m["feature_count"]
    base.training_column_index = np.asarray(expected_all, dtype=int)
    base.training_feature_count = m["feature_count"]
    base.training_feature_hash = m["feature_names_sha256"]
    base.assembled_from = [r["model_file"] for r in m["ranges"]]
    base.mixed = False

    out_stem = qnet_save_stem(args.output)
    os.makedirs(os.path.dirname(os.path.abspath(out_stem)), exist_ok=True)
    save_qnet(base, out_stem, low_mem=True, gz=True)
    out_file = out_stem + ".gz"

    # Reload and verify the serialized product, not just the in-memory object.
    final = load_qnet(out_file, gz=True)
    if estimator_keys(final) != expected_all:
        raise RuntimeError("Serialized assembled model failed estimator completeness check")
    if [str(x) for x in final.feature_names] != m["feature_names"]:
        raise RuntimeError("Serialized assembled model failed feature-name check")

    print(f"ASSEMBLY COMPLETE: {out_file}")
    print(f"Estimators: {len(final.estimators_)}")


if __name__ == "__main__":
    main()
