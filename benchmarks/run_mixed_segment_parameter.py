#!/usr/bin/env python3
"""Build and run lazy exact segment-parameter research."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks" / "mixed_segment_parameter_probe.d"


def capture(command):
    return subprocess.check_output(command, cwd=ROOT, text=True)


def compile_probe(compiler, output):
    import_paths = capture([
        "python3",
        str(ROOT / "tools" / "dub-import-paths.py"),
        "--compiler=" + compiler,
    ]).splitlines()

    if Path(compiler).name == "dmd":
        flags = ["-O", "-inline", "-release", "-boundscheck=safeonly", "-i"]
    else:
        flags = ["-O3", "-release", "-boundscheck=safeonly", "-i"]

    command = [
        compiler,
        *flags,
        *["-I" + path for path in import_paths],
        "-of=" + str(output),
        str(SOURCE),
    ]

    return command, subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
    )


def parse_output(text):
    layouts = {}
    summaries = []
    derived = []
    sink = None

    for line in text.splitlines():
        fields = line.split(",")

        if fields[0] == "layout" and len(fields) == 3:
            layouts[fields[1]] = int(fields[2])

        elif fields[0] == "summary" and len(fields) == 5:
            summaries.append({
                "scalar": fields[1],
                "case": fields[2],
                "operation": fields[3],
                "median_ns": float(fields[4]),
            })

        elif fields[0] == "derived" and len(fields) == 7:
            derived.append({
                "scalar": fields[1],
                "case": fields[2],
                "current_ns": float(fields[3]),
                "parameter_ns": float(fields[4]),
                "ratio": float(fields[5]),
                "check": int(fields[6]),
            })

        elif fields[0] == "sink" and len(fields) == 2:
            sink = int(fields[1])

    if len(layouts) != 2:
        raise RuntimeError(f"expected 2 layout rows, got {len(layouts)}")

    if len(summaries) != 16:
        raise RuntimeError(f"expected 16 summaries, got {len(summaries)}")

    if len(derived) != 8:
        raise RuntimeError(f"expected 8 derived rows, got {len(derived)}")

    if sink is None:
        raise RuntimeError("missing sink")

    return layouts, summaries, derived, sink


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cpu", type=int, default=0)
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--target-ms", type=int, default=50)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compiler", action="append", dest="compilers")
    args = parser.parse_args()

    if args.cpu not in os.sched_getaffinity(0):
        parser.error("CPU outside allowed affinity")

    os.sched_setaffinity(0, {args.cpu})

    dirty = bool(capture([
        "git", "status", "--porcelain", "--",
        "source", "benchmarks", "tools",
    ]))

    if dirty:
        parser.error("source/benchmarks/tools differ from HEAD")

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
            "compare eager exact Cartesian proper-crossing events against "
            "exact source-segment parameter events"
        ),
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "commit": capture(["git", "rev-parse", "HEAD"]).strip(),
        "dirty": dirty,
        "cpu": args.cpu,
        "rounds": args.rounds,
        "target_ms": args.target_ms,
        "probe_source": str(SOURCE.relative_to(ROOT)),
        "compilers": [],
        "runs": [],
        "limitations": [
            "Research mechanism evidence only; not an end-to-end production verdict.",
            "This probe mixes represented source endpoints, represented touch/overlap-style points and strict proper crossings.",
            "Deliberate duplicate positions exercise equality/dedup across representation kinds.",
            "Every current-vs-parameter event pair is order-preflighted before timing.",
            "All event kinds are expressed in one exact source-parameter rational domain.",
            "Any production change requires full mixed-event correctness and clipping ABBA.",
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

            command, completed = compile_probe(compiler, binary)

            (out / ("build-" + label + ".stdout")).write_text(completed.stdout)
            (out / ("build-" + label + ".stderr")).write_text(completed.stderr)

            record["compilers"].append({
                "label": label,
                "path": compiler,
                "version": capture([compiler, "--version"]),
                "compile_command": command,
                "build_status": completed.returncode,
            })
            save()

            if completed.returncode:
                sys.stderr.write(completed.stdout)
                sys.stderr.write(completed.stderr)
                raise RuntimeError("build failed for " + label)

            run = subprocess.run(
                [str(binary), str(args.rounds), str(args.target_ms)],
                cwd=out,
                text=True,
                capture_output=True,
            )

            (out / ("run-" + label + ".stdout")).write_text(run.stdout)
            (out / ("run-" + label + ".stderr")).write_text(run.stderr)

            if run.returncode:
                sys.stderr.write(run.stdout)
                sys.stderr.write(run.stderr)
                raise RuntimeError("probe failed for " + label)

            layouts, summaries, derived, sink = parse_output(run.stdout)

            record["runs"].append({
                "compiler": label,
                "layouts": layouts,
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
