#!/usr/bin/env python3
"""Build and run the exact-event active-span/comparator research probe."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks" / "exact_event_active_span_probe.d"


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
    spans = []
    summaries = []
    derived = []
    sink = None

    for line in text.splitlines():
        fields = line.split(",")

        if not fields:
            continue

        if fields[0] == "sizeof" and len(fields) == 3:
            sizes[fields[1]] = int(fields[2])

        elif fields[0] == "span" and len(fields) == 14:
            spans.append({
                "scalar": fields[1],
                "case": fields[2],
                "kind": fields[3],
                "event_count": int(fields[4]),
                "x_first_min": int(fields[5]),
                "x_end_max": int(fields[6]),
                "x_avg_width": float(fields[7]),
                "y_first_min": int(fields[8]),
                "y_end_max": int(fields[9]),
                "y_avg_width": float(fields[10]),
                "d_first_min": int(fields[11]),
                "d_end_max": int(fields[12]),
                "d_avg_width": float(fields[13]),
            })

        elif fields[0] == "summary" and len(fields) == 7:
            summaries.append({
                "scalar": fields[1],
                "case": fields[2],
                "operation": fields[3],
                "median_ns": float(fields[4]),
                "event_count": int(fields[5]),
                "proper_count": int(fields[6]),
            })

        elif fields[0] == "derived" and len(fields) == 8:
            derived.append({
                "scalar": fields[1],
                "case": fields[2],
                "known_construction_net_ns": float(fields[3]),
                "known_construction_net_ns_per_proper": float(fields[4]),
                "current_index_sort_ns": float(fields[5]),
                "bounded_index_sort_ns": float(fields[6]),
                "current_over_bounded": float(fields[7]),
            })

        elif fields[0] == "sink" and len(fields) == 2:
            sink = int(fields[1])

    expected_sizes = {
        "ExactOverlayPoint",
        "ExactProperIntersection",
    }

    if set(sizes) != expected_sizes:
        raise RuntimeError(
            "missing size records: got " + repr(sizes)
        )

    if len(spans) != 4 * 3 * 4:
        raise RuntimeError(
            f"expected 48 span rows, got {len(spans)}"
        )

    if len(summaries) != 4 * 3 * 4:
        raise RuntimeError(
            f"expected 48 summary rows, got {len(summaries)}"
        )

    if len(derived) != 4 * 3:
        raise RuntimeError(
            f"expected 12 derived rows, got {len(derived)}"
        )

    if sink is None:
        raise RuntimeError("missing benchmark sink")

    return sizes, spans, summaries, derived, sink


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
    parser.add_argument("--allow-dirty", action="store_true")
    args = parser.parse_args()

    if not 1 <= args.rounds <= 100:
        parser.error("rounds must be in [1, 100]")

    if not 1 <= args.target_ms <= 60000:
        parser.error("target-ms must be in [1, 60000]")

    if args.cpu not in os.sched_getaffinity(0):
        parser.error("CPU outside allowed affinity")

    os.sched_setaffinity(0, {args.cpu})

    dirty = bool(capture([
        "git",
        "status",
        "--porcelain",
        "--",
        "source",
        "benchmarks",
        "tools",
    ]))

    if dirty and not args.allow_dirty:
        parser.error(
            "source/benchmarks/tools differ from HEAD; "
            "--allow-dirty is diagnostic only"
        )

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
        "purpose": "exact-event active-span and bounded-comparator mechanism attribution",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "commit": capture(["git", "rev-parse", "HEAD"]).strip(),
        "dirty": dirty,
        "cpu": args.cpu,
        "affinity": sorted(os.sched_getaffinity(0)),
        "rounds": args.rounds,
        "target_ms": args.target_ms,
        "probe_source": str(SOURCE.relative_to(ROOT)),
        "compilers": [],
        "runs": [],
        "limitations": [
            "Mechanism evidence only; this is not an end-to-end production performance verdict.",
            "Dense fixtures are synthetic current segment/polygon comb fixtures.",
            "The bounded comparator caches active high-limb ends outside the timed sort.",
            "The bounded comparator uses the production comparator for unequal denominators.",
            "A production change requires independent controlled end-to-end ABBA qualification.",
            "No CPU frequency/turbo control is imposed.",
        ],
    }

    def save():
        (out / "record.json").write_text(
            json.dumps(record, indent=2, sort_keys=True) + "\n"
        )

    save()

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

            compiler_record = {
                "label": label,
                "path": compiler,
                "version": capture([compiler, "--version"]),
                "compile_command": command,
                "build_status": completed.returncode,
            }

            record["compilers"].append(compiler_record)
            save()

            if completed.returncode:
                sys.stderr.write(completed.stdout)
                sys.stderr.write(completed.stderr)
                raise RuntimeError(
                    "build failed for " + label
                )

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

            sizes, spans, summaries, derived, sink = parse_output(
                run.stdout
            )

            record["runs"].append({
                "compiler": label,
                "sizes": sizes,
                "spans": spans,
                "summaries": summaries,
                "derived": derived,
                "sink": sink,
                "status": "passed",
            })
            save()

        size_sets = {
            (
                run["sizes"]["ExactOverlayPoint"],
                run["sizes"]["ExactProperIntersection"],
            )
            for run in record["runs"]
        }

        if len(size_sets) != 1:
            raise RuntimeError(
                "carrier sizes differ between compilers"
            )

        record["status"] = "passed"

    except Exception:
        record["status"] = "failed"
        raise

    finally:
        record["finished_utc"] = datetime.now(timezone.utc).isoformat()
        save()
        print("record:", out, flush=True)


if __name__ == "__main__":
    main()
