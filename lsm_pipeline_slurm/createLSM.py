#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
import numpy as np

from quasinet.qnet import Qnet, save_qnet
from lsm_common import load_dataframe, model_stem, feature_hash

sys.setrecursionlimit(20000)


def build_parser():
    p = argparse.ArgumentParser(
        description="Train a complete or partial Qnet/LSM from CSV. Ranges are [begin,end)."
    )
    p.add_argument("-f", "--file", "-file", dest="file", required=True, help="Input CSV")
    p.add_argument("-b", "--beg", "-begin", dest="beg", type=int, default=None,
                   help="Beginning estimator/column index, inclusive")
    p.add_argument("-e", "--end", "-end", dest="end", type=int, default=None,
                   help="Ending estimator/column index, exclusive")
    p.add_argument("-samples", dest="samples", type=int, default=0,
                   help="Number of training rows to sample; 0 uses all")
    p.add_argument("-k", type=int, default=1,
                   help="Minimum unique non-empty values required to retain a column")
    p.add_argument("-a", "--alpha", "-alpha", dest="alpha", type=float, default=0.15)
    p.add_argument("-njobs", dest="njobs", type=int, default=1)
    p.add_argument("-o", "--output", "-prefix", dest="output", default="qmodel",
                   help="Output prefix. Partial jobs automatically append begin-end.qnet.gz")
    p.add_argument("--seed", type=int, default=42)
    return p


def main():
    parser = build_parser()
    args = parser.parse_args()

    if (args.beg is None) != (args.end is None):
        parser.error("-b/--beg and -e/--end must be specified together")

    np.random.seed(args.seed)
    print("Loading:", args.file)
    df = load_dataframe(args.file, k=args.k, samples=args.samples, seed=args.seed)
    feature_names = np.asarray(df.columns.astype(str), dtype=str)
    X = df.to_numpy().astype(str)
    n_features = X.shape[1]

    if args.beg is None:
        fit_index = None
        expected_keys = list(range(n_features))
        out_stem = model_stem(args.output)
        print(f"Training all {n_features} estimators")
    else:
        if args.beg < 0 or args.end > n_features or args.beg >= args.end:
            raise ValueError(
                f"Invalid estimator range [{args.beg},{args.end}) for {n_features} features"
            )
        fit_index = np.arange(args.beg, args.end, dtype=int)
        expected_keys = fit_index.tolist()
        out_stem = model_stem(args.output, args.beg, args.end)
        print(f"Training estimators [{args.beg},{args.end}) of {n_features}")

    os.makedirs(os.path.dirname(os.path.abspath(out_stem)), exist_ok=True)

    model = Qnet(
        feature_names=feature_names,
        alpha=args.alpha,
        n_jobs=args.njobs,
        random_state=args.seed,
    )
    model.fit(X, index_array=fit_index)

    actual_keys = sorted(int(k) for k in model.estimators_.keys())
    if actual_keys != expected_keys:
        raise RuntimeError(
            f"Qnet fit returned estimator keys {actual_keys[:10]}...; "
            f"expected exactly [{expected_keys[0] if expected_keys else '-'}, "
            f"{expected_keys[-1] if expected_keys else '-'}]"
        )

    # Metadata used by checker/assembler. Estimator keys themselves remain global.
    model.training_index = df.index.to_numpy()
    model.training_column_beg = 0 if args.beg is None else args.beg
    model.training_column_end = n_features if args.end is None else args.end
    model.training_column_index = np.asarray(expected_keys, dtype=int)
    model.training_feature_count = n_features
    model.training_feature_hash = feature_hash(feature_names)
    model.training_source_file = os.path.abspath(args.file)
    model.training_filter_k = args.k
    model.training_samples = args.samples
    model.training_seed = args.seed

    print("Saving:", out_stem + ".gz")
    save_qnet(model, out_stem, low_mem=True, gz=True)
    print("DONE")


if __name__ == "__main__":
    main()
