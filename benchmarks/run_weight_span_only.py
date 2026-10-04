#!/usr/bin/env python3
"""Build and run weighted-build span-width matrix research."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks" / "weight_span_only_probe.d"


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
    spans = []
    summaries = []
    derived = []
    sink = None

    for line in text.splitlines():
        fields = line.split(",")

        if not fields:
            continue

        if fields[0] == "span" and len(fields) == 7:
            spans.append({
                "scalar": fields[1],
                "case": fields[2],
                "kind": fields[3],
                "width_min": int(fields[4]),
                "width_max": int(fields[5]),
                "average_width": float(fields[6]),
            })

        elif fields[0] == "summary" and len(fields) == 5:
            summaries.append({
                "scalar": fields[1],
                "case": fields[2],
                "operation": fields[3],
                "median_ns": float(fields[4]),
            })

        elif fields[0] == "derived" and len(fields) == 10:
            derived.append({
                "scalar": fields[1],
                "case": fields[2],
                "current_net_ns": float(fields[3]),
                "weight_only_net_ns": float(fields[4]),
                "span_only_net_ns": float(fields[5]),
                "span_nonzero_net_ns": float(fields[6]),
                "current_over_weight_only": float(fields[7]),
                "current_over_span_only": float(fields[8]),
                "current_over_span_nonzero": float(fields[9]),
            })

        elif fields[0] == "sink" and len(fields) == 2:
            sink = int(fields[1])

    if len(spans) != 22:
        raise RuntimeError(
            f"expected 22 span rows, got {len(spans)}"
        )

    if len(summaries) != 55:
        raise RuntimeError(
            f"expected 55 summary rows, got {len(summaries)}"
        )

    if len(derived) != 11:
        raise RuntimeError(
            f"expected 11 derived rows, got {len(derived)}"
        )

    if sink is None:
        raise RuntimeError("missing benchmark sink")

    return spans, summaries, derived, sink


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
            "weighted-build span-width matrix across compact through wide "
            "exact determinant carriers"
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
            "Mechanism evidence only; this is not an end-to-end production verdict.",
            "Axis-aligned strict crossings are chosen to generate controlled exact active-span widths.",
            "The query is prepared and determinant pairs are precomputed so timing isolates the weighted rational build.",
            "weight-only does not cache query spans; it discovers query-coordinate spans inside each multiply while reusing only determinant-weight spans.",
            "span-only preserves product zero scans; span-nonzero additionally uses the established strict-crossing nonzero-weight invariant.",
            "Fixed-width result carriers and base-2^32 schoolbook multiplication are unchanged.",
            "Any production change requires an independent end-to-end ABBA qualification.",
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

            spans, summaries, derived, sink = parse_output(
                run.stdout
            )

            record["runs"].append({
                "compiler": label,
                "spans": spans,
                "summaries": summaries,
                "derived": derived,
                "sink": sink,
                "status": "passed",
            })
            save()

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
