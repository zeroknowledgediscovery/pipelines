#!/usr/bin/env python3
"""Shared utilities for partial Qnet/LSM training and assembly."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd


def load_dataframe(path: str, k: int = 1, samples: int = 0, seed: int = 42) -> pd.DataFrame:
    """Load the training CSV exactly the same way for every partial job.

    The first CSV column is treated as the row index. Literal ``None`` values
    are converted to empty strings. If ``samples`` is non-zero, the deterministic
    training sample is selected *before* column filtering. Columns with fewer
    than ``k`` unique non-empty values in the actual training sample are then
    removed. This guarantees that an all-empty column cannot reach Qnet.fit().
    """
    df = (
        pd.read_csv(path, keep_default_na=False, index_col=0, low_memory=False)
        .replace("None", "")
        .astype(str)
    )

    # Select the exact training rows first. A column that has observations in the
    # full dataset can still be completely empty in a sampled training subset.
    # Filtering before sampling therefore allowed all-empty columns to reach
    # Qnet.fit(). Every partial job uses the same seed, so it gets the same rows.
    if samples and samples > 0:
        if samples > len(df):
            raise ValueError(
                f"Requested samples ({samples}) exceeds dataset size ({len(df)})"
            )
        df = df.sample(n=samples, random_state=seed)

    # Treat whitespace-only cells as empty without otherwise altering category
    # labels. Then retain only columns with enough distinct non-empty values in
    # the actual training dataframe.
    for c in df.columns:
        whitespace_only = df[c].str.strip().eq("")
        if whitespace_only.any():
            df.loc[whitespace_only, c] = ""

    keep_cols = [
        c for c in df.columns
        if df[c].replace("", np.nan).nunique(dropna=True) >= k
    ]
    dropped_cols = [c for c in df.columns if c not in keep_cols]
    if dropped_cols:
        print(
            f"Dropped {len(dropped_cols)} column(s) with fewer than {k} "
            f"unique non-empty value(s): {dropped_cols[:20]}"
            + (" ..." if len(dropped_cols) > 20 else "")
        )
    df = df.loc[:, keep_cols]

    if df.shape[1] == 0:
        raise ValueError("No columns remain after filtering")

    # Defensive check: Qnet rejects any feature whose training values are all
    # empty strings. This should be impossible after the filtering above.
    all_empty = [c for c in df.columns if df[c].eq("").all()]
    if all_empty:
        raise RuntimeError(
            "Internal preprocessing error: all-empty columns remain: "
            + ", ".join(map(str, all_empty[:20]))
        )

    return df


def feature_hash(feature_names: Iterable[str]) -> str:
    payload = json.dumps(list(map(str, feature_names)), separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def ranges_for(n_features: int, step: int):
    if step <= 0:
        raise ValueError("step must be > 0")
    return [(b, min(b + step, n_features)) for b in range(0, n_features, step)]


def model_stem(prefix: str, beg: int | None = None, end: int | None = None) -> str:
    """Return the filename passed to save_qnet (which appends .gz itself)."""
    prefix = str(prefix)
    if prefix.endswith(".gz"):
        prefix = prefix[:-3]
    if prefix.endswith(".qnet"):
        prefix = prefix[:-5]
    if beg is None and end is None:
        return prefix + ".qnet"
    if beg is None or end is None:
        raise ValueError("beg and end must be supplied together")
    return f"{prefix}{beg}-{end}.qnet"


def model_file(prefix: str, beg: int | None = None, end: int | None = None) -> str:
    return model_stem(prefix, beg, end) + ".gz"


def qnet_save_stem(path: str) -> str:
    """Normalize a requested output path to the stem expected by save_qnet."""
    path = str(path)
    if path.endswith(".gz"):
        path = path[:-3]
    return path


def load_manifest(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        m = json.load(f)
    required = ["datafile", "feature_count", "feature_names", "ranges", "model_prefix"]
    missing = [k for k in required if k not in m]
    if missing:
        raise ValueError(f"Manifest missing fields: {missing}")
    return m


def estimator_keys(model) -> list[int]:
    if not hasattr(model, "estimators_"):
        raise ValueError("Model has no estimators_ attribute")
    return sorted(int(x) for x in model.estimators_.keys())
