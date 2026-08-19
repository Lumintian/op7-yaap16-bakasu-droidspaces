#!/usr/bin/env python3
"""Reject final config changes outside the explicit ReSuki/devtmpfs allowlist."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_config(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        if raw.startswith("CONFIG_") and "=" in raw:
            key, value = raw.split("=", 1)
            values[key] = value
        elif raw.startswith("# CONFIG_") and raw.endswith(" is not set"):
            key = raw.split()[1]
            values[key] = "n"
    return values


def allowed(key: str) -> bool:
    return key.startswith("CONFIG_KSU") or key in {
        "CONFIG_DEVTMPFS",
        "CONFIG_DEVTMPFS_MOUNT",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("final", type=Path)
    args = parser.parse_args()

    baseline = parse_config(args.baseline)
    final = parse_config(args.final)
    changed = {
        key: (baseline.get(key, "<absent>"), final.get(key, "<absent>"))
        for key in sorted(baseline.keys() | final.keys())
        if baseline.get(key) != final.get(key)
    }
    unexpected = {key: values for key, values in changed.items() if not allowed(key)}

    print(f"config changes: {len(changed)}; allowlisted: {len(changed) - len(unexpected)}")
    for key, (before, after) in unexpected.items():
        print(f"UNEXPECTED {key}: {before} -> {after}")

    if unexpected:
        return 1
    print("CONFIG_DIFF_ALLOWLIST=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
