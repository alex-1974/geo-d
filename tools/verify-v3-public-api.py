#!/usr/bin/env python3
"""Verify the frozen geo-d v3 public API inventory."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


EXPECTED = {
    "package exports": "67",
    "top-level declarations": "81",
    "public aggregate members": "96",
    "private aggregate members": "22",
    "enum members": "39",
    "relocated reflection matches": "4",
    "total audit declarations": "216",
    "surface sha256": "b55433799612df97eb11996a18e69acffe877807f130b86f09149511c03e4a50",
}


def parse_summary(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^([^:]+):\s+(.+)$", line)
        if match:
            values[match.group(1).strip()] = match.group(2).strip()
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="build/v3-api-check")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    out_dir = root / args.out_dir
    command = [
        sys.executable,
        str(root / "tools/audit-public-api.py"),
        "--out-dir",
        str(out_dir),
    ]
    subprocess.run(command, cwd=root, check=True)

    actual = parse_summary(out_dir / "summary.txt")
    failures = []
    for key, expected in EXPECTED.items():
        if actual.get(key) != expected:
            failures.append(
                f"{key}: expected {expected!r}, got {actual.get(key)!r}"
            )

    if failures:
        print("V3 public API audit FAILED", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print("V3 public API audit PASS: 67 exports, 216 declarations, 0 unresolved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
