#!/usr/bin/env python3
"""Build and run hybrid clipping dispatch probe."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmarks" / "hybrid_dispatch_probe.d"


def capture(command):
    return subprocess.check_output(command, cwd=ROOT, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    compiler = shutil.which(args.compiler)
    if not compiler:
        parser.error(args.compiler + " not found")

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
            "-version=GeoResearchHybridDispatchProbe",
            "-i",
        ]
    else:
        flags = [
            "-O3",
            "-release",
            "-boundscheck=safeonly",
            "--d-version=GeoResearchHybridDispatchProbe",
            "-i",
        ]

    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    binary = out / "probe"

    command = [
        compiler,
        *flags,
        *["-I" + path for path in import_paths],
        "-of=" + str(binary),
        str(SOURCE),
    ]

    build = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
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

    sys.stdout.write(run.stdout)

    if run.returncode:
        sys.stderr.write(run.stderr)
        raise SystemExit(run.returncode)


if __name__ == "__main__":
    main()
