#!/usr/bin/env python3
"""Build and run post-#120 exact-construction cost attribution."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks" / "post120_exact_construction_probe.d"


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
    derived = []
    sink = None

    for line in text.splitlines():
        fields = line.split(",")

        if not fields:
            continue

        if fields[0] == "sizeof" and len(fields) == 3:
            sizes[fields[1]] = int(fields[2])

        elif fields[0] == "summary" and len(fields) == 6:
            summaries.append({
                "scalar": fields[1],
                "case": fields[2],
                "operation": fields[3],
                "median_ns": float(fields[4]),
                "proper_count": int(fields[5]),
            })

        elif fields[0] == "derived" and len(fields) == 13:
            derived.append({
                "scalar": fields[1],
                "case": fields[2],
                "edge_decode_net_ns": float(fields[3]),
                "determinant_net_ns": float(fields[4]),
                "weighted_build_net_ns": float(fields[5]),
                "full_prepared_both_net_ns": float(fields[6]),
                "full_prepared_first_net_ns": float(fields[7]),
                "full_decode_delta_ns": float(fields[8]),
                "component_sum_ns": float(fields[9]),
                "full_prepared_first_net_ns_per_proper": float(fields[10]),
                "determinant_net_ns_per_proper": float(fields[11]),
                "weighted_build_net_ns_per_proper": float(fields[12]),
            })

        elif fields[0] == "sink" and len(fields) == 2:
            sink = int(fields[1])

    expected_sizes = {
        "PreparedExactSegment",
        "SignedDyadicProduct",
        "ExactProperIntersection",
    }

    if set(sizes) != expected_sizes:
        raise RuntimeError(
            "missing size records: got " + repr(sizes)
        )

    if len(summaries) != 4 * 3 * 8:
        raise RuntimeError(
            f"expected 96 summary rows, got {len(summaries)}"
        )

    if len(derived) != 4 * 3:
        raise RuntimeError(
            f"expected 12 derived rows, got {len(derived)}"
        )

    if sink is None:
        raise RuntimeError("missing benchmark sink")

    return sizes, summaries, derived, sink


def maybe_disassemble(binary, destination):
    objdump = shutil.which("objdump")

    if not objdump:
        return None

    completed = subprocess.run(
        [objdump, "-drwC", str(binary)],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )

    destination.write_text(
        completed.stdout + completed.stderr
    )

    return completed.returncode


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

    if dirty:
        parser.error(
            "source/benchmarks/tools differ from HEAD; "
            "qualifying evidence requires a clean checkout"
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
        "purpose": (
            "post-#120 exact-construction cost attribution: edge decode, "
            "exact determinants, weighted rational build, and full prepared crossing"
        ),
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
            "Mechanism attribution only; this is not an end-to-end production performance verdict.",
            "Dense fixtures reuse the established synthetic segment/polygon comb corpus.",
            "The query is already prepared, matching the #120 production hot path.",
            "Prepared-edge and determinant read baselines are subtracted to reduce hash/carrier-read cost.",
            "Subtracted component costs are attribution estimates and need not sum exactly because compiler source shape and instruction overlap differ.",
            "No CPU frequency/turbo control is imposed.",
            "Any production change still requires an independent controlled end-to-end ABBA qualification.",
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

            compiler_record["objdump_status"] = maybe_disassemble(
                binary,
                out / ("objdump-" + label + ".txt"),
            )
            save()

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

            sizes, summaries, derived, sink = parse_output(
                run.stdout
            )

            record["runs"].append({
                "compiler": label,
                "sizes": sizes,
                "summaries": summaries,
                "derived": derived,
                "sink": sink,
                "status": "passed",
            })
            save()

        size_sets = {
            (
                run["sizes"]["PreparedExactSegment"],
                run["sizes"]["SignedDyadicProduct"],
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
