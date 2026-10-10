#!/usr/bin/env python3
"""Run research-only post-#166 LDC double boundary attribution."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "double_boundary_attribution.d"
CASES = [
    "boundary-only",
    "boundary-overlap",
    "crossing",
    "dense-4",
    "concave-u",
    "hole",
]


def git(*args):
    return subprocess.check_output(
        ["git", "-C", str(ROOT), *args],
        text=True,
    ).strip()


def capture(cmd, cwd=ROOT):
    p = subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        capture_output=True,
    )
    if p.returncode:
        raise RuntimeError(
            "command failed: "
            + repr(cmd)
            + "\n"
            + p.stdout
            + p.stderr
        )
    return p.stdout


def build(out):
    compiler = shutil.which("ldc2")
    if not compiler:
        raise RuntimeError("compiler not found: ldc2")

    imports = capture(
        [
            "python3",
            str(ROOT / "tools" / "dub-import-paths.py"),
            "--compiler=" + compiler,
        ]
    ).splitlines()

    binary = out / "double-boundary-attribution"
    cmd = [
        compiler,
        "-i",
        *["-I" + p for p in imports],
        str(BENCH),
        "-O3",
        "-release",
        "-boundscheck=safeonly",
        "--d-version=GeoDoubleBoundaryAttribution",
        "-of=" + str(binary),
    ]

    p = subprocess.run(
        cmd,
        cwd=out,
        text=True,
        capture_output=True,
    )

    (out / "build.stdout").write_text(p.stdout)
    (out / "build.stderr").write_text(p.stderr)
    (out / "build.command.json").write_text(
        json.dumps(cmd, indent=2) + "\n"
    )

    if p.returncode:
        raise RuntimeError(
            "build failed\nstdout:\n"
            + p.stdout
            + "\nstderr:\n"
            + p.stderr
        )

    return {
        "compiler": compiler,
        "compiler_version": capture([compiler, "--version"]),
        "binary": str(binary),
        "binary_sha256": hashlib.sha256(
            binary.read_bytes()
        ).hexdigest(),
        "command": cmd,
    }


def run_case(binary, case, rounds, iterations, out):
    dest = out / "runs" / case
    dest.mkdir(parents=True, exist_ok=False)

    cmd = [
        binary,
        case,
        str(rounds),
        str(iterations),
    ]

    stdout_path = dest / "samples.stdout"
    stderr_path = dest / "samples.stderr"

    with stdout_path.open("w") as so, stderr_path.open("w") as se:
        p = subprocess.run(
            cmd,
            cwd=dest,
            text=True,
            stdout=so,
            stderr=se,
        )

    if p.returncode:
        raise RuntimeError(
            "measurement failed: "
            + str(dest)
            + "\n"
            + stdout_path.read_text()
            + stderr_path.read_text()
        )

    return {
        "case": case,
        "stdout": str(stdout_path),
        "stderr": str(stderr_path),
        "command": cmd,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cpu", type=int, default=6)
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--iterations", type=int, default=1000)
    ap.add_argument("--notes", default="")
    ap.add_argument("--allow-dirty", action="store_true")
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()

    allowed = os.sched_getaffinity(0)
    if args.cpu not in allowed:
        ap.error(
            "CPU "
            + str(args.cpu)
            + " not in allowed affinity "
            + repr(sorted(allowed))
        )

    os.sched_setaffinity(0, {args.cpu})

    dirty_lines = git(
        "status",
        "--porcelain",
        "--untracked-files=normal",
        "--",
        "source",
        "benchmarks",
        ".github/workflows",
    ).splitlines()

    if dirty_lines and not args.allow_dirty:
        raise RuntimeError(
            "research source is dirty:\n"
            + "\n".join(dirty_lines)
        )

    stamp = datetime.now(timezone.utc).strftime(
        "%Y%m%dT%H%M%S%fZ"
    )

    out = (
        args.output
        or ROOT / "build" / (
            "post166-double-boundary-attribution-" + stamp
        )
    ).resolve()

    out.mkdir(parents=True, exist_ok=False)

    record = {
        "format": 1,
        "status": "incomplete",
        "purpose": "post166-ldc-double-boundary-attribution",
        "head": git("rev-parse", "HEAD"),
        "branch": git("branch", "--show-current"),
        "dirty": bool(dirty_lines),
        "dirty_lines": dirty_lines,
        "cpu": args.cpu,
        "allowed_affinity": sorted(allowed),
        "rounds": args.rounds,
        "iterations": args.iterations,
        "cases": CASES,
        "notes": args.notes,
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "build": None,
        "runs": [],
        "limitations": [
            "Research-only internal clock instrumentation perturbs absolute wall time.",
            "Use stage shares and work counters as diagnostic evidence only.",
            "Only LDC double is measured because #167 targets the remaining LDC double gap.",
            "Any production candidate requires independent non-instrumented codegen and ABBA gates.",
        ],
    }

    try:
        build_dir = out / "build"
        build_dir.mkdir(parents=True, exist_ok=False)
        info = build(build_dir)
        record["build"] = info

        for case in CASES:
            print("[measure]", case, flush=True)
            record["runs"].append(
                run_case(
                    info["binary"],
                    case,
                    args.rounds,
                    args.iterations,
                    out,
                )
            )
            (out / "record.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )

        record["status"] = "passed"
    finally:
        record["finished_utc"] = (
            datetime.now(timezone.utc).isoformat()
        )
        (out / "record.json").write_text(
            json.dumps(record, indent=2) + "\n"
        )

    print("attribution record:", out)


if __name__ == "__main__":
    main()
