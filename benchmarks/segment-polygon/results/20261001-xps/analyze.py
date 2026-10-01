#!/usr/bin/env python3
"""Audit and summarize the retained eight-run XPS comparison without geometry code."""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from statistics import median


HERE = Path(__file__).resolve().parent


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=HERE / "raw")
    parser.add_argument("--output", type=Path, default=HERE / "comparison-analysis.json")
    args = parser.parse_args()
    manifest = json.loads((args.root / "comparison.json").read_text())
    require(manifest["status"] == "passed" and len(manifest["runs"]) == 8, "incomplete comparison")
    expected_preflight = [["preflight", "int", "22", "PASS"],
                          ["preflight", "long", "24", "PASS"],
                          ["preflight", "float", "23", "PASS"],
                          ["preflight", "double", "23", "PASS"]]
    samples = {}
    for run in manifest["runs"]:
        path = args.root / run["name"]
        metadata = json.loads((path / "metadata.json").read_text())
        require(run["returncode"] == 0 and metadata["status"] == "passed", run["name"] + " failed")
        require(not metadata["dirty"] and metadata["commit"] == run["revision"], "source mismatch")
        require(metadata["affinity"] == [0], "affinity mismatch")
        require("-boundscheck=off" in metadata["release_flags"], "unexpected historical flags")
        source = (path / "segment_polygon_bench.d").read_bytes()
        require(hashlib.sha256(source).hexdigest() == metadata["benchmark_sha256"], "source hash mismatch")
        require(not (path / "tracked.patch").read_bytes(), "tracked changes")
        for mode in ("debug", "release"):
            rows = csv.reader((path / f"preflight-{mode}.stdout").read_text().splitlines())
            require([r for r in rows if r and r[0] == "preflight"] == expected_preflight, "preflight mismatch")
        collected, summaries, sink = {}, {}, None
        for row in csv.reader((path / "samples.stdout").read_text().splitlines()):
            if not row:
                continue
            if row[0] == "sample":
                key = tuple(row[1:4])
                count = int(row[7])
                require(count > 0, "invalid iteration count")
                collected.setdefault(key, []).append({
                    "round": int(row[6]), "ns": int(row[9]) / count,
                    "gc_bytes": int(row[10]) / count,
                    "elapsed_ns": int(row[9]), "iterations": count})
            elif row[0] == "summary":
                summaries[tuple(row[1:4])] = float(row[5])
            elif row[0] == "sink":
                sink = int(row[1])
        require(len(collected) == 184 and collected.keys() == summaries.keys(), "missing workloads")
        require(sink is not None and sink != 0, "missing consumed checksum")
        for key, rows in collected.items():
            require(sorted(r["round"] for r in rows) == list(range(7)), "missing or duplicate rounds")
            require(abs(median(r["ns"] for r in rows) - summaries[key]) <= 0.00051, "summary mismatch")
            require(key[2] != "relationship" or all(r["gc_bytes"] == 0 for r in rows), "classifier allocation")
        samples[run["name"]] = collected
    output = []
    for compiler in ("dmd", "ldc2"):
        for key in sorted(samples[f"{compiler}-block0-base"]):
            measured = {label: [samples[f"{compiler}-block{i}-{label}"][key] for i in range(2)]
                        for label in ("base", "candidate")}
            medians = {label: [median(r["ns"] for r in rows) for rows in blocks]
                       for label, blocks in measured.items()}
            ratios = [medians["candidate"][i] / medians["base"][i] for i in range(2)]
            output.append({"compiler": compiler, "scalar": key[0], "case": key[1], "operation": key[2],
                           "base_ns": medians["base"], "candidate_ns": medians["candidate"],
                           "candidate_base_ratios": ratios,
                           "geomean_pair_ratio": math.sqrt(ratios[0] * ratios[1]),
                           "gc_bytes_per_call": {label: sorted({r["gc_bytes"] for rows in blocks for r in rows})
                                                 for label, blocks in measured.items()},
                           "sample_ranges_ns": {label: [[min(r["ns"] for r in rows), max(r["ns"] for r in rows)]
                                                        for rows in blocks] for label, blocks in measured.items()}})
    args.output.write_text(json.dumps(output, separators=(",", ":")) + "\n")
    print(f"AUDIT PASS: 8 runs, 10304 samples, {len(output)} comparisons; {args.output}")


if __name__ == "__main__":
    main()
