#!/usr/bin/env python3
"""Verify that every explicit Kconfig fragment value survived olddefconfig."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line.startswith("CONFIG_") and "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            values[line.split()[1]] = "n"
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("fragment", type=Path)
    parser.add_argument("config", type=Path)
    args = parser.parse_args()

    requested = parse(args.fragment)
    actual = parse(args.config)
    mismatches = []
    for key, expected in requested.items():
        # In Kconfig, an invisible/omitted boolean has the same effective value as n.
        observed = actual.get(key, "n" if expected == "n" else "<absent>")
        if observed != expected:
            mismatches.append((key, expected, observed))

    for key, expected, observed in mismatches:
        print(f"FRAGMENT_MISMATCH {key}: requested {expected}, observed {observed}")
    if mismatches:
        return 1
    print(f"FRAGMENT_VERIFY=PASS entries={len(requested)} fragment={args.fragment.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
