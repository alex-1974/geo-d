#!/usr/bin/env python3
"""Build and run research-only boundary clipping attribution."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "boundary_clipping_attribution.d"
CASES = [
    "crossing",
    "boundary-only",
    "boundary-overlap",
    "dense-4",
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


def compiler_kind(path):
    return "ldc" if Path(path).name.startswith("ldc") else "dmd"


def build(compiler_name, out):
    compiler = shutil.which(compiler_name)
    if not compiler:
        raise RuntimeError("compiler not found: " + compiler_name)

    imports = capture(
        [
            "python3",
            str(ROOT / "tools" / "dub-import-paths.py"),
            "--compiler=" + compiler,
        ]
    ).splitlines()

    kind = compiler_kind(compiler)

    if kind == "ldc":
        flags = [
            "-O3",
            "-release",
            "-boundscheck=safeonly",
            "--d-version=GeoBoundaryAttribution",
        ]
    else:
        flags = [
            "-O",
            "-inline",
            "-release",
            "-boundscheck=safeonly",
            "-version=GeoBoundaryAttribution",
        ]

    binary = out / "boundary-clipping-attribution"

    cmd = [
        compiler,
        "-i",
        *["-I" + p for p in imports],
        str(BENCH),
        *flags,
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
            "build failed for "
            + compiler_name
            + "\nstdout:\n"
            + p.stdout
            + "\nstderr:\n"
            + p.stderr
        )

    return {
        "compiler": compiler_name,
        "path": compiler,
        "kind": kind,
        "version": capture([compiler, "--version"]),
        "binary": str(binary),
        "binary_sha256": hashlib.sha256(
            binary.read_bytes()
        ).hexdigest(),
        "command": cmd,
    }


def run_case(binary, compiler, scalar, case, rounds, iterations, out):
    dest = out / "runs" / compiler / scalar / case
    dest.mkdir(parents=True, exist_ok=False)

    cmd = [
        binary,
        scalar,
        case,
        str(rounds),
        str(iterations),
    ]

    stdout_path = dest / "samples.stdout"
    stderr_path = dest / "samples.stderr"
    (dest / "command.json").write_text(
        json.dumps(cmd, indent=2) + "\n"
    )

    with stdout_path.open("w") as stdout_file, stderr_path.open("w") as stderr_file:
        p = subprocess.run(
            cmd,
            cwd=dest,
            text=True,
            stdout=stdout_file,
            stderr=stderr_file,
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
        "compiler": compiler,
        "scalar": scalar,
        "case": case,
        "stdout": str(stdout_path),
        "stderr": str(stderr_path),
        "command": cmd,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--compiler",
        action="append",
        choices=["dmd", "ldc2"],
    )
    ap.add_argument("--cpu", type=int, default=0)
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--iterations", type=int, default=1000)
    ap.add_argument("--notes", default="")
    ap.add_argument("--allow-dirty", action="store_true")
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()

    compilers = args.compiler or ["dmd", "ldc2"]

    allowed = os.sched_getaffinity(0)
    if args.cpu not in allowed:
        ap.error(
            "CPU "
            + str(args.cpu)
            + " not in allowed affinity "
            + repr(sorted(allowed))
        )

    os.sched_setaffinity(0, {args.cpu})

    head = git("rev-parse", "HEAD")
    branch = git("branch", "--show-current")
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
            "post157-boundary-attribution-" + stamp
        )
    ).resolve()

    out.mkdir(parents=True, exist_ok=False)

    record = {
        "format": 1,
        "status": "incomplete",
        "purpose": "post157-boundary-clipping-attribution",
        "head": head,
        "branch": branch,
        "dirty": bool(dirty_lines),
        "dirty_lines": dirty_lines,
        "cpu": args.cpu,
        "allowed_affinity": sorted(allowed),
        "rounds": args.rounds,
        "iterations": args.iterations,
        "cases": CASES,
        "notes": args.notes,
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "builds": [],
        "runs": [],
        "limitations": [
            "Research-only internal clock instrumentation perturbs absolute wall time.",
            "Use stage shares and work counters as diagnostic evidence only.",
            "Any production candidate requires independent non-instrumented ABBA.",
        ],
    }

    try:
        for compiler_name in compilers:
            build_dir = out / "build" / compiler_name
            build_dir.mkdir(parents=True, exist_ok=False)

            info = build(
                compiler_name,
                build_dir,
            )

            record["builds"].append(info)
            binary = info["binary"]

            for scalar in [
                "int",
                "long",
                "float",
                "double",
            ]:
                for case in CASES:
                    print(
                        "[measure]",
                        compiler_name,
                        scalar,
                        case,
                        flush=True,
                    )

                    record["runs"].append(
                        run_case(
                            binary,
                            compiler_name,
                            scalar,
                            case,
                            args.rounds,
                            args.iterations,
                            out,
                        )
                    )

                    (out / "record.json").write_text(
                        json.dumps(record, indent=2)
                        + "\n"
                    )

        record["status"] = "passed"
    finally:
        record["finished_utc"] = (
            datetime.now(timezone.utc).isoformat()
        )
        (out / "record.json").write_text(
            json.dumps(record, indent=2)
            + "\n"
        )

    print("attribution record:", out)


if __name__ == "__main__":
    main()
