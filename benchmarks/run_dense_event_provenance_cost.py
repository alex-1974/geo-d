#!/usr/bin/env python3
"""Build and run the dense exact-event lookup-vs-provenance probe."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks" / "dense_event_provenance_cost_probe.d"


def capture(command, cwd=ROOT):
    return subprocess.check_output(command, cwd=cwd, text=True)


def compile_probe(compiler, output):
    import_paths = capture([
        "python3",
        str(ROOT / "tools" / "dub-import-paths.py"),
        "--compiler=" + compiler,
    ]).splitlines()

    if Path(compiler).name == "dmd":
        flags = [
            "-O",
            "-inline",
            "-release",
            "-boundscheck=safeonly",
            "-i",
        ]
    else:
        flags = [
            "-O3",
            "-release",
            "-boundscheck=safeonly",
            "-i",
        ]

    command = [
        compiler,
        *flags,
        *["-I" + path for path in import_paths],
        "-of=" + str(output),
        str(SOURCE),
    ]

    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
    )

    return command, completed


def parse_output(text):
    rows = []
    derived = []
    size = None

    for line in text.splitlines():
        fields = line.split(",")

        if not fields:
            continue

        if fields[0] == "sizeof" and len(fields) == 3:
            size = int(fields[2])
        elif fields[0] == "summary" and len(fields) == 7:
            rows.append({
                "scalar": fields[1],
                "case": fields[2],
                "operation": fields[3],
                "median_ns": float(fields[4]),
                "event_count": int(fields[5]),
                "proper_count": int(fields[6]),
            })
        elif fields[0] == "derived" and len(fields) == 7:
            derived.append({
                "scalar": fields[1],
                "case": fields[2],
                "lookup_median_ns": float(fields[3]),
                "direct_index_median_ns": float(fields[4]),
                "lookup_net_ns": float(fields[5]),
                "lookup_net_per_proper_ns": float(fields[6]),
            })

    if size is None:
        raise RuntimeError("missing ExactOverlayPoint sizeof")

    if len(rows) != 4 * 3 * 2:
        raise RuntimeError(
            f"expected 24 summary rows, got {len(rows)}"
        )

    if len(derived) != 4 * 3:
        raise RuntimeError(
            f"expected 12 derived rows, got {len(derived)}"
        )

    return size, rows, derived


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cpu", type=int, default=0)
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--target-ms", type=int, default=50)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--compiler",
        action="append",
        dest="compilers",
        help="compiler executable/name; repeat for multiple compilers",
    )
    args = parser.parse_args()

    if args.cpu not in os.sched_getaffinity(0):
        parser.error("CPU outside allowed affinity")

    os.sched_setaffinity(0, {args.cpu})

    requested = args.compilers or ["dmd", "ldc2"]
    compilers = []

    for name in requested:
        path = shutil.which(name)

        if not path:
            parser.error(name + " not found")

        compilers.append(path)

    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)

    record = {
        "status": "incomplete",
        "purpose": "dense exact-event lookup-vs-provenance attribution",
        "commit": capture(["git", "rev-parse", "HEAD"]).strip(),
        "dirty": bool(capture([
            "git",
            "status",
            "--porcelain",
            "--",
            "source",
            "benchmarks",
            "tools",
        ])),
        "cpu": args.cpu,
        "rounds": args.rounds,
        "target_ms": args.target_ms,
        "runs": [],
        "limitations": [
            "This is mechanism evidence, not an end-to-end production optimization result.",
            "The lookup replay uses the current >=9-event equal-denominator-preferred binary-search comparator.",
            "The direct-index replay consumes the same resolved events through precomputed compact size_t indices.",
            "The net difference estimates lookup overhead after #107, not first-pass provenance construction cost.",
            "Second-pass exact-construction cost is measured separately by evidence PR #106.",
            "A production change still requires controlled end-to-end ABBA qualification.",
            "No CPU frequency or turbo control is imposed.",
        ],
    }

    try:
        for compiler in compilers:
            label = Path(compiler).name
            binary = out / ("probe-" + label)

            command, completed = compile_probe(
                compiler,
                binary,
            )

            (out / ("build-" + label + ".stdout")).write_text(
                completed.stdout
            )

            (out / ("build-" + label + ".stderr")).write_text(
                completed.stderr
            )

            if completed.returncode:
                sys.stderr.write(completed.stdout)
                sys.stderr.write(completed.stderr)
                raise RuntimeError(
                    "build failed for " + label
                )

            version = capture([
                compiler,
                "--version",
            ])

            run = subprocess.run(
                [
                    str(binary),
                    str(args.rounds),
                    str(args.target_ms),
                ],
                cwd=out,
                text=True,
                capture_output=True,
            )

            (out / ("run-" + label + ".stdout")).write_text(
                run.stdout
            )

            (out / ("run-" + label + ".stderr")).write_text(
                run.stderr
            )

            if run.returncode:
                sys.stderr.write(run.stdout)
                sys.stderr.write(run.stderr)
                raise RuntimeError(
                    "probe failed for " + label
                )

            carrier_size, rows, derived = parse_output(
                run.stdout
            )

            record["runs"].append({
                "compiler": label,
                "compiler_version": version,
                "build_command": command,
                "carrier_size": carrier_size,
                "summaries": rows,
                "derived": derived,
            })

        record["status"] = "passed"
    finally:
        record["finished_utc"] = (
            datetime.now(timezone.utc).isoformat()
        )

        (out / "record.json").write_text(
            json.dumps(record, indent=2) + "\n"
        )

    for run in record["runs"]:
        print(
            "compiler",
            run["compiler"],
            "ExactOverlayPoint.sizeof",
            run["carrier_size"],
        )

        for row in run["derived"]:
            print(
                run["compiler"],
                row["scalar"],
                row["case"],
                "lookup_ns",
                f'{row["lookup_median_ns"]:.1f}',
                "direct_ns",
                f'{row["direct_index_median_ns"]:.1f}',
                "net_lookup_ns",
                f'{row["lookup_net_ns"]:.1f}',
                "net_per_proper_ns",
                f'{row["lookup_net_per_proper_ns"]:.1f}',
            )

    print("record:", out)


if __name__ == "__main__":
    main()
