#!/usr/bin/env python3
"""Verify native comparison completion, raw sample pairs and retained checksums."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from run_native_comparison import summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("record", type=Path)
    args = parser.parse_args()
    root = args.record.resolve()
    metadata = json.loads((root / "metadata.json").read_text())
    if metadata["status"] != "passed":
        raise RuntimeError("incomplete/failed parent record")
    manifest = root / "SHA256SUMS"
    if manifest.is_file():
        for line in manifest.read_text().splitlines():
            digest, relative = line.split("  ", 1)
            path = (root / relative).resolve()
            if not path.is_relative_to(root) or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise RuntimeError("retained checksum mismatch: " + relative)
    admitted = set(tuple(key) for key in json.loads((root / "admission.json").read_text())["admitted"])
    if len(admitted) != 87:
        raise RuntimeError("invalid admission count")
    rounds = {int(arg.split("=", 1)[1]) for cmd in metadata["commands"] for arg in cmd
              if arg.startswith("--rounds=")}
    if len(rounds) != 1:
        raise RuntimeError("missing/inconsistent round configuration")
    rounds = rounds.pop()
    smoke = metadata["purpose"] == "smoke"
    pairs = json.loads((root / "comparison.json").read_text())["pairs"]
    runs = metadata["runs"]
    compilers = {r["compiler"] for r in runs}
    if len(runs) != 4 * len(compilers) or len(pairs) != 174 * len(compilers):
        raise RuntimeError("incomplete compiler/block matrix")
    for compiler in compilers:
        for block, order in enumerate((['d', 'native'], ['native', 'd'])):
            children = [r for r in runs if r["compiler"] == compiler and r["block"] == block]
            if [r["implementation"] for r in children] != order or any(r["status"] != "passed" for r in children):
                raise RuntimeError("incomplete/wrong-order block")
            values = {}
            for child in children:
                name, implementation = child["record"], child["implementation"]
                if implementation == "d":
                    m = json.loads((root / name / "metadata.json").read_text())
                    if m["status"] != "passed" or m["commit"] != metadata["source_commit"] or m["boundscheck"] != "safeonly":
                        raise RuntimeError("invalid D child provenance")
                    text = (root / name / "samples.stdout").read_text()
                    count = 92
                else:
                    text = (root / (name + ".stdout")).read_text()
                    if "preflight,native,87,174,PASS" not in text:
                        raise RuntimeError("missing native semantic preflight")
                    count = 87
                values[implementation] = summaries(text, admitted, count, rounds, smoke)
            selected = [p for p in pairs if p["compiler"] == compiler and p["block"] == block]
            if len(selected) != 87 or {(p["scalar"], p["case"]) for p in selected} != admitted:
                raise RuntimeError("invalid paired fixture identities")
            for p in selected:
                key = p["scalar"], p["case"]
                d, native = values["d"][key], values["native"][key]
                if p["d_median_ns"] != d or p["native_median_ns"] != native or p["order"] != order:
                    raise RuntimeError("pair differs from raw summary")
                if smoke:
                    if p["d_over_native"] is not None: raise RuntimeError("smoke ratio forbidden")
                elif not math.isclose(p["d_over_native"], d / native, rel_tol=1e-12):
                    raise RuntimeError("ratio differs from raw summary")
    print(f"NATIVE RECORD PASS: {len(runs)} runs, {len(pairs)} pairs, {rounds} rounds; {metadata['source_commit']}")


if __name__ == "__main__":
    main()
