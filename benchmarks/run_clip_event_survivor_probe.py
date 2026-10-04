#!/usr/bin/env python3
"""Build and run deterministic clipping event survivor census."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks" / "clip_event_survivor_probe.d"


def capture(command):
    return subprocess.check_output(command, cwd=ROOT, text=True)


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
            "-version=GeoResearchClipEventCensus",
            "-i",
        ]
    else:
        flags = [
            "-O3",
            "-release",
            "-boundscheck=safeonly",
            "--d-version=GeoResearchClipEventCensus",
            "-i",
        ]

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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    compiler = shutil.which(args.compiler)
    if not compiler:
        parser.error(args.compiler + " not found")

    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)

    binary = out / "probe"
    command, build = compile_probe(compiler, binary)

    (out / "compile-command.txt").write_text(
        " ".join(command) + "\n"
    )
    (out / "build.stdout").write_text(build.stdout)
    (out / "build.stderr").write_text(build.stderr)

    if build.returncode:
        sys.stderr.write(build.stdout)
        sys.stderr.write(build.stderr)
        raise SystemExit(build.returncode)

    run = subprocess.run(
        [str(binary)],
        cwd=out,
        text=True,
        capture_output=True,
    )

    (out / "run.stdout").write_text(run.stdout)
    (out / "run.stderr").write_text(run.stderr)

    if run.returncode:
        sys.stderr.write(run.stdout)
        sys.stderr.write(run.stderr)
        raise SystemExit(run.returncode)

    sys.stdout.write(run.stdout)


if __name__ == "__main__":
    main()
