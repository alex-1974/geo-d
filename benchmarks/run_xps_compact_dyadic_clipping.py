#!/usr/bin/env python3
"""Qualify the compact-dyadic research fast path in real clipping workloads."""

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tarfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks" / "segment_polygon_bench.d"
HARNESS = Path(__file__).resolve()
COMPACT_SOURCE = ROOT / "source" / "geo" / "internal" / "dyadic_compact_research.d"
INTERSECTION_SOURCE = ROOT / "source" / "geo" / "internal" / "intersection_exact.d"

WORKLOADS = [
    "exterior",
    "crossing",
    "sparse-64",
    "sparse-256",
    "dense-64",
    "dense-256",
    "subnormal",
    "large-finite",
]


def capture(args, cwd=ROOT):
    result = subprocess.run(
        args,
        cwd=cwd,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise RuntimeError(
            f"command failed: {args!r}\n"
            f"{result.stdout}{result.stderr}"
        )
    return result.stdout


def run_logged(args, stdout_path, stderr_path, cwd=ROOT):
    result = subprocess.run(
        args,
        cwd=cwd,
        text=True,
        capture_output=True,
    )
    stdout_path.write_text(result.stdout)
    stderr_path.write_text(result.stderr)
    if result.returncode:
        tail = (result.stdout + result.stderr)[-5000:]
        raise RuntimeError(
            f"command failed: {args!r}\n{tail}"
        )
    return result.stdout


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def compiler_kind(path):
    name = Path(path).name
    return "ldc" if name.startswith("ldc") else "dmd"


def build(
    compiler,
    imports,
    output,
    candidate,
    log_dir,
):
    kind = compiler_kind(compiler)
    args = [
        compiler,
        "-i",
        *["-I" + path for path in imports],
        str(SOURCE),
    ]

    if kind == "dmd":
        args += [
            "-O",
            "-inline",
            "-release",
            "-boundscheck=safeonly",
        ]
        if candidate:
            args.append(
                "-version=GeoResearchCompactDyadic"
            )
    else:
        args += [
            "-O3",
            "-release",
            "-boundscheck=safeonly",
        ]
        if candidate:
            args.append(
                "--d-version=GeoResearchCompactDyadic"
            )

    args.append("-of=" + str(output))

    label = "candidate" if candidate else "baseline"
    run_logged(
        args,
        log_dir / f"build-{label}.stdout",
        log_dir / f"build-{label}.stderr",
    )

    (log_dir / f"{label}.sha256").write_text(
        sha256(output) + "\n"
    )

    return args


def parse_summaries(text):
    records = []
    for line in text.splitlines():
        if not line.startswith("summary,"):
            continue
        fields = line.split(",")
        if len(fields) != 7:
            raise RuntimeError(
                "unexpected summary line: " + line
            )
        records.append(
            {
                "scalar": fields[1],
                "case": fields[2],
                "operation": fields[3],
                "min_ns": float(fields[4]),
                "median_ns": float(fields[5]),
                "max_ns": float(fields[6]),
            }
        )
    return records


def grouped_median(values):
    return statistics.median(values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expected_head")
    parser.add_argument("--cpu", type=int, default=0)
    parser.add_argument("--cycles", type=int, default=6)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--target-ms", type=int, default=15)
    args = parser.parse_args()

    if not 1 <= args.cycles <= 20:
        parser.error("--cycles must be 1..20")
    if not 1 <= args.rounds <= 20:
        parser.error("--rounds must be 1..20")
    if not 1 <= args.target_ms <= 1000:
        parser.error("--target-ms must be 1..1000")

    actual_head = capture(
        ["git", "rev-parse", "HEAD"]
    ).strip()

    if actual_head != args.expected_head:
        parser.error(
            f"expected HEAD {args.expected_head}, "
            f"got {actual_head}"
        )

    relevant_diff = capture(
        [
            "git",
            "status",
            "--porcelain",
            "--",
            "benchmarks",
            "source",
            "tools",
        ]
    )

    if relevant_diff:
        parser.error(
            "benchmark/source/tool tree is dirty:\n" +
            relevant_diff
        )

    if hasattr(os, "sched_getaffinity"):
        allowed = sorted(os.sched_getaffinity(0))
        if args.cpu not in allowed:
            parser.error(
                f"CPU {args.cpu} not in allowed affinity "
                f"{allowed}"
            )
        os.sched_setaffinity(0, {args.cpu})
    else:
        allowed = None

    dmd = shutil.which("dmd")
    ldc = shutil.which("ldc2")
    dub = shutil.which("dub")

    if not dmd or not ldc or not dub:
        parser.error(
            "dmd, ldc2 and dub must be available on PATH"
        )

    stamp = datetime.now(
        timezone.utc
    ).strftime("%Y%m%dT%H%M%S%fZ")

    out = (
        ROOT /
        "build" /
        f"compact-dyadic-clipping-xps.{stamp}"
    )
    out.mkdir(parents=True)

    provenance = {
        "format": 1,
        "head": actual_head,
        "cpu": args.cpu,
        "allowed_affinity": allowed,
        "cycles": args.cycles,
        "rounds_per_invocation": args.rounds,
        "target_ms": args.target_ms,
        "workloads": WORKLOADS,
        "platform": platform.platform(),
        "uname": capture(["uname", "-a"]).strip(),
        "dmd": capture([dmd, "--version"]),
        "ldc": capture([ldc, "--version"]),
        "dub": capture([dub, "--version"]),
        "benchmark_sha256": sha256(SOURCE),
        "harness_sha256": sha256(HARNESS),
        "compact_source_sha256": sha256(COMPACT_SOURCE),
        "intersection_source_sha256": sha256(INTERSECTION_SOURCE),
        "candidate_version":
            "GeoResearchCompactDyadic",
        "boundscheck": "safeonly",
        "order":
            "ABBA on even cycles, BAAB on odd cycles",
        "limitations": [
            "Research-only versioned fast path; no production promotion.",
            "No CPU-frequency control is imposed.",
            "Relationship is an independent common-mode control; "
            "normalization is diagnostic and does not erase "
            "absolute clipping regressions.",
        ],
    }
    (out / "provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n"
    )

    shutil.copy2(
        SOURCE,
        out / "segment_polygon_bench.d",
    )
    shutil.copy2(
        HARNESS,
        out / HARNESS.name,
    )
    shutil.copy2(
        COMPACT_SOURCE,
        out / "dyadic_compact_research.d",
    )
    shutil.copy2(
        INTERSECTION_SOURCE,
        out / "intersection_exact.d",
    )
    (out / "git-status.txt").write_text(
        capture(["git", "status", "--short", "--branch"])
    )

    print("=== PROVENANCE ===", flush=True)
    print(
        json.dumps(
            {
                "head": actual_head,
                "cpu": args.cpu,
                "cycles": args.cycles,
                "rounds": args.rounds,
                "target_ms": args.target_ms,
                "workloads": WORKLOADS,
            },
            indent=2,
        ),
        flush=True,
    )

    print("\n=== UNIT TESTS DMD ===", flush=True)
    run_logged(
        [dub, "test", "--compiler=dmd", "--force"],
        out / "dub-test-dmd.stdout",
        out / "dub-test-dmd.stderr",
    )
    print("PASS", flush=True)

    print("\n=== UNIT TESTS LDC ===", flush=True)
    run_logged(
        [dub, "test", "--compiler=ldc2", "--force"],
        out / "dub-test-ldc.stdout",
        out / "dub-test-ldc.stderr",
    )
    print("PASS", flush=True)

    all_records = []
    all_paired = []

    only_arg = "--only=" + ",".join(WORKLOADS)

    for compiler in (dmd, ldc):
        kind = compiler_kind(compiler)
        compiler_dir = out / kind
        compiler_dir.mkdir()

        print(
            f"\n=== BUILD {kind.upper()} ===",
            flush=True,
        )

        imports = capture(
            [
                "python3",
                str(ROOT / "tools" / "dub-import-paths.py"),
                "--compiler=" + compiler,
            ]
        ).splitlines()

        (compiler_dir / "import-paths.txt").write_text(
            "\n".join(imports) + "\n"
        )

        baseline = compiler_dir / "baseline"
        candidate = compiler_dir / "candidate"

        baseline_command = build(
            compiler,
            imports,
            baseline,
            False,
            compiler_dir,
        )

        candidate_command = build(
            compiler,
            imports,
            candidate,
            True,
            compiler_dir,
        )

        (compiler_dir / "commands.json").write_text(
            json.dumps(
                {
                    "baseline": baseline_command,
                    "candidate": candidate_command,
                },
                indent=2,
            ) + "\n"
        )

        print(
            f"=== PREFLIGHT {kind.upper()} ===",
            flush=True,
        )

        common_check = [
            "--check",
            "--scalar=double",
            only_arg,
        ]

        run_logged(
            [str(baseline), *common_check],
            compiler_dir / "preflight-baseline.stdout",
            compiler_dir / "preflight-baseline.stderr",
        )

        run_logged(
            [str(candidate), *common_check],
            compiler_dir / "preflight-candidate.stdout",
            compiler_dir / "preflight-candidate.stderr",
        )

        census = run_logged(
            [
                str(candidate),
                "--compact-census",
                "--scalar=double",
                only_arg,
            ],
            compiler_dir / "compact-census.stdout",
            compiler_dir / "compact-census.stderr",
        )

        print(census, end="", flush=True)

        print(
            f"=== ABBA {kind.upper()} ===",
            flush=True,
        )

        by_cycle = {}

        for cycle in range(args.cycles):
            order = (
                ["baseline", "candidate", "candidate", "baseline"]
                if cycle % 2 == 0
                else ["candidate", "baseline", "baseline", "candidate"]
            )

            by_cycle[cycle] = {
                "baseline": {},
                "candidate": {},
            }

            for slot, variant in enumerate(order):
                binary = (
                    baseline
                    if variant == "baseline"
                    else candidate
                )

                run_dir = (
                    compiler_dir /
                    f"cycle-{cycle:02d}-slot-{slot}-{variant}"
                )
                run_dir.mkdir()

                stdout = run_logged(
                    [
                        str(binary),
                        f"--rounds={args.rounds}",
                        "--iterations=0",
                        f"--target-ms={args.target_ms}",
                        "--scalar=double",
                        only_arg,
                    ],
                    run_dir / "stdout",
                    run_dir / "stderr",
                )

                records = parse_summaries(stdout)
                if not records:
                    raise RuntimeError(
                        "measurement produced no summaries"
                    )

                for record in records:
                    row = {
                        "compiler": kind,
                        "cycle": cycle,
                        "slot": slot,
                        "variant": variant,
                        **record,
                    }
                    all_records.append(row)

                    key = (
                        record["case"],
                        record["operation"],
                    )

                    by_cycle[cycle][variant].setdefault(
                        key,
                        [],
                    ).append(
                        record["median_ns"]
                    )

            for case in WORKLOADS:
                def cycle_value(variant, operation):
                    values = by_cycle[cycle][variant].get(
                        (case, operation),
                        [],
                    )
                    if len(values) != 2:
                        raise RuntimeError(
                            "ABBA cycle did not produce two "
                            f"{variant}/{case}/{operation} values"
                        )
                    return statistics.mean(values)

                base_clip = cycle_value(
                    "baseline",
                    "clipping",
                )
                cand_clip = cycle_value(
                    "candidate",
                    "clipping",
                )
                base_rel = cycle_value(
                    "baseline",
                    "relationship",
                )
                cand_rel = cycle_value(
                    "candidate",
                    "relationship",
                )

                clip_delta = (
                    100.0 *
                    (cand_clip - base_clip) /
                    base_clip
                )
                rel_delta = (
                    100.0 *
                    (cand_rel - base_rel) /
                    base_rel
                )

                all_paired.append(
                    {
                        "compiler": kind,
                        "cycle": cycle,
                        "case": case,
                        "baseline_clipping_ns": base_clip,
                        "candidate_clipping_ns": cand_clip,
                        "clipping_delta_percent": clip_delta,
                        "baseline_relationship_ns": base_rel,
                        "candidate_relationship_ns": cand_rel,
                        "relationship_delta_percent": rel_delta,
                        "diagnostic_normalized_delta_percent":
                            clip_delta - rel_delta,
                    }
                )

    records_path = out / "records.csv"
    with records_path.open("w", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=list(all_records[0].keys()),
        )
        writer.writeheader()
        writer.writerows(all_records)

    paired_path = out / "paired.csv"
    with paired_path.open("w", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=list(all_paired[0].keys()),
        )
        writer.writeheader()
        writer.writerows(all_paired)

    aggregate = []

    for compiler in ("dmd", "ldc"):
        for case in WORKLOADS:
            rows = [
                row
                for row in all_paired
                if row["compiler"] == compiler
                and row["case"] == case
            ]
            if not rows:
                continue

            aggregate.append(
                {
                    "compiler": compiler,
                    "case": case,
                    "median_clipping_delta_percent":
                        grouped_median([
                            row["clipping_delta_percent"]
                            for row in rows
                        ]),
                    "median_relationship_delta_percent":
                        grouped_median([
                            row["relationship_delta_percent"]
                            for row in rows
                        ]),
                    "median_diagnostic_normalized_delta_percent":
                        grouped_median([
                            row[
                                "diagnostic_normalized_delta_percent"
                            ]
                            for row in rows
                        ]),
                    "min_clipping_delta_percent":
                        min(
                            row["clipping_delta_percent"]
                            for row in rows
                        ),
                    "max_clipping_delta_percent":
                        max(
                            row["clipping_delta_percent"]
                            for row in rows
                        ),
                }
            )

    aggregate_path = out / "aggregate.csv"
    with aggregate_path.open("w", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=list(aggregate[0].keys()),
        )
        writer.writeheader()
        writer.writerows(aggregate)

    print("\n=== AGGREGATE ===", flush=True)
    for row in aggregate:
        print(
            "aggregate,"
            f"{row['compiler']},"
            f"{row['case']},"
            f"{row['median_clipping_delta_percent']:.3f},"
            f"{row['median_relationship_delta_percent']:.3f},"
            f"{row['median_diagnostic_normalized_delta_percent']:.3f},"
            f"{row['min_clipping_delta_percent']:.3f},"
            f"{row['max_clipping_delta_percent']:.3f}",
            flush=True,
        )

    archive = out / "geo-compact-dyadic-clipping-xps.tar.gz"
    with tarfile.open(
        archive,
        "w:gz",
    ) as tar:
        for path in sorted(out.rglob("*")):
            if path == archive:
                continue
            if path.is_file() and path.name not in {
                "baseline",
                "candidate",
            }:
                tar.add(
                    path,
                    arcname=path.relative_to(out),
                )

    digest = sha256(archive)

    print(
        f"\nsha256 {digest}  {archive.name}",
        flush=True,
    )
    print(
        f"Archive: {archive}",
        flush=True,
    )


if __name__ == "__main__":
    main()
