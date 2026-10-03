#!/usr/bin/env python3
"""Build and run the dense exact-crossing cost probe under baseline D compilers."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks" / "dense_exact_crossing_cost.d"


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
    sizes = {}
    summaries = []

    for line in text.splitlines():
        fields = line.split(",")

        if not fields:
            continue

        if fields[0] == "sizeof" and len(fields) == 3:
            sizes[fields[1]] = int(fields[2])
        elif fields[0] == "summary" and len(fields) == 8:
            summaries.append({
                "scalar": fields[1],
                "case": fields[2],
                "operation": fields[3],
                "median_ns": float(fields[4]),
                "per_proper_ns": float(fields[5]),
                "edge_count": int(fields[6]),
                "proper_count": int(fields[7]),
            })

    expected = 4 * 3 * 3

    if len(summaries) != expected:
        raise RuntimeError(
            f"expected {expected} summaries, got {len(summaries)}"
        )

    derived = []

    keyed = {
        (r["scalar"], r["case"], r["operation"]): r
        for r in summaries
    }

    for scalar in ["int", "long", "float", "double"]:
        for case in ["dense-4", "dense-16", "dense-64"]:
            carrier = keyed[(scalar, case, "carrier-read")]
            exact = keyed[(scalar, case, "exact-construction")]
            contact = keyed[(scalar, case, "contact-classification")]

            net = exact["median_ns"] - carrier["median_ns"]
            per_proper = (
                net / exact["proper_count"]
                if exact["proper_count"]
                else 0.0
            )

            derived.append({
                "scalar": scalar,
                "case": case,
                "edge_count": exact["edge_count"],
                "proper_count": exact["proper_count"],
                "carrier_read_median_ns": carrier["median_ns"],
                "exact_construction_median_ns": exact["median_ns"],
                "exact_construction_net_ns": net,
                "exact_construction_net_per_proper_ns": per_proper,
                "contact_classification_median_ns": contact["median_ns"],
            })

    return sizes, summaries, derived


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

    compilers = []

    requested = args.compilers or ["dmd", "ldc2"]

    for name in requested:
        path = shutil.which(name)

        if not path:
            parser.error(name + " not found")

        compilers.append(path)

    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)

    record = {
        "status": "incomplete",
        "purpose": "dense exact-crossing construction cost attribution",
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
            "This is mechanism attribution, not an end-to-end optimization result.",
            "Exact construction net time subtracts a precomputed-carrier hash/read replay from a construct-and-hash replay.",
            "The subtraction estimates construction work while retaining the same full-carrier consumption in both paths.",
            "No CPU frequency or turbo control is imposed.",
            "A production optimization still requires controlled end-to-end ABBA qualification.",
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

            sizes, summaries, derived = parse_output(
                run.stdout
            )

            record["runs"].append({
                "compiler": label,
                "compiler_version": version,
                "build_command": command,
                "sizes": sizes,
                "summaries": summaries,
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
            "ExactProperIntersection.sizeof",
            run["sizes"].get(
                "ExactProperIntersection"
            ),
            "ExactOverlayPoint.sizeof",
            run["sizes"].get(
                "ExactOverlayPoint"
            ),
        )

        for row in run["derived"]:
            print(
                run["compiler"],
                row["scalar"],
                row["case"],
                "proper",
                row["proper_count"],
                "net_exact_ns",
                f'{row["exact_construction_net_ns"]:.1f}',
                "net_per_proper_ns",
                f'{row["exact_construction_net_per_proper_ns"]:.1f}',
                "contact_ns",
                f'{row["contact_classification_median_ns"]:.1f}',
            )

    print("record:", out)


if __name__ == "__main__":
    main()
