#!/usr/bin/env python3
"""Record real LDC segment/polygon codegen for base and candidate revisions."""

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DRIVER_MAIN = r'''
private void runSelected(T)(
    string caseName,
    size_t rounds,
    size_t iterations,
    long target
)
{
    auto cases = corpus!T();

    foreach (ref c; cases)
    {
        if (c.name != caseName)
            continue;

        preflight(c);
        measure!(relationship!T)(
            c, "relationship", rounds, iterations, target);
        measure!(clipping!T)(
            c, "clipping", rounds, iterations, target);
        return;
    }

    enforce(false, "unknown case");
}

void main(string[] args)
{
    enforce(args.length == 6);

    const scalar = args[1];
    const caseName = args[2];
    const rounds = args[3].to!size_t;
    const iterations = args[4].to!size_t;
    const target = args[5].to!long;

    if (scalar == "double")
        runSelected!double(caseName, rounds, iterations, target);
    else
        enforce(false, "codegen recorder expects double");

    writefln("sink,%s", benchmarkSink);
}
'''


def git(*args):
    return subprocess.check_output(
        ["git", "-C", str(ROOT), *args],
        text=True
    ).strip()


def capture(cmd, cwd):
    p = subprocess.run(
        cmd, cwd=cwd, text=True, capture_output=True
    )
    if p.returncode:
        raise RuntimeError(
            "command failed: " + repr(cmd) +
            "\n" + p.stdout + p.stderr
        )
    return p.stdout


def write_command(path, cmd, cwd):
    p = subprocess.run(
        cmd, cwd=cwd, text=True, capture_output=True
    )
    path.write_text(p.stdout + p.stderr)
    if p.returncode:
        raise RuntimeError(
            "command failed: " + repr(cmd) +
            "\nsee " + str(path)
        )


def build_binary(source_root, outdir):
    compiler = shutil.which("ldc2")
    if not compiler:
        raise RuntimeError("ldc2 not found")

    source = (
        source_root / "benchmarks/segment_polygon_bench.d"
    ).read_text()

    marker = "void main(string[] args)"
    if source.count(marker) != 1:
        raise RuntimeError("benchmark main changed")

    driver = outdir / "segment_polygon_targeted.d"
    driver.write_text(
        source[:source.index(marker)] + DRIVER_MAIN
    )

    imports = capture(
        [
            "python3",
            str(source_root / "tools/dub-import-paths.py"),
            "--compiler=" + compiler,
        ],
        source_root,
    ).splitlines()

    binary = outdir / "benchmark"
    cmd = [
        compiler,
        "-i",
        *["-I" + p for p in imports],
        str(driver),
        "-O3",
        "-release",
        "-boundscheck=safeonly",
        "-of=" + str(binary),
    ]

    write_command(outdir / "build.log", cmd, outdir)
    return binary, cmd, capture([compiler, "--version"], source_root)


def record_binary(label, binary, outdir):
    run_cmd = [
        str(binary),
        "double",
        "dense-64",
        "1",
        "1",
        "1",
    ]
    write_command(outdir / "run.log", run_cmd, outdir)

    commands = {
        "nm-demangled.txt":
            ["nm", "-n", "-C", str(binary)],
        "nm-raw.txt":
            ["nm", "-n", str(binary)],
        "nm-size-demangled.txt":
            ["nm", "-S", "-n", "-C", str(binary)],
        "readelf-symbols.txt":
            ["readelf", "-Ws", str(binary)],
        "sections.txt":
            ["size", "-A", str(binary)],
        "full.asm":
            [
                "objdump",
                "-d",
                "-Mintel",
                "--no-show-raw-insn",
                "-C",
                str(binary),
            ],
    }

    for name, cmd in commands.items():
        write_command(outdir / name, cmd, outdir)

    symbols = (outdir / "nm-demangled.txt").read_text().splitlines()
    needles = (
        "subtractDyadicCoordinates",
        "compareCoordinateMagnitudeWithBound",
        "subtractCoordinateMagnitudeBoundedInto",
        "orientationDeterminantDyadicDecoded",
        "properIntersectionExactKnownCrossingPreparedFirst",
        "properIntersectionExactKnownCrossing",
        "clipping",
        "relationship",
    )
    selected = [
        line for line in symbols
        if any(needle in line for needle in needles)
    ]
    (outdir / "relevant-symbols.txt").write_text(
        "\n".join(selected) + "\n"
    )

    return {
        "label": label,
        "binary_sha256":
            hashlib.sha256(binary.read_bytes()).hexdigest(),
        "run_command": run_cmd,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--base",
        default="7f9237f7c4be993b7ac987a46f40d05bde8355c8",
    )
    ap.add_argument(
        "--candidate",
        default="38b0b095a0cfa232bc3609ba66927bc6b12a2516",
    )
    ap.add_argument("--output", type=Path)
    a = ap.parse_args()

    revisions = {
        "base": git("rev-parse", "--verify", a.base + "^{commit}"),
        "candidate":
            git("rev-parse", "--verify", a.candidate + "^{commit}"),
    }

    out = (
        a.output or
        ROOT / "build" / "bounded-coordinate-codegen"
    ).resolve()
    if out.exists():
        raise RuntimeError("output already exists: " + str(out))
    out.mkdir(parents=True)

    record = {
        "format": 1,
        "purpose": "real-segment-polygon-ldc-codegen",
        "revisions": revisions,
        "builds": [],
    }

    with tempfile.TemporaryDirectory(
        prefix="geo-d-bounded-codegen-"
    ) as tmp:
        worktrees = {}
        try:
            for label, sha in revisions.items():
                path = Path(tmp) / label
                git(
                    "worktree", "add", "--detach",
                    str(path), sha
                )
                worktrees[label] = path

            for label in ("base", "candidate"):
                dest = out / label
                dest.mkdir()
                binary, cmd, version = build_binary(
                    worktrees[label], dest
                )
                item = record_binary(
                    label, binary, dest
                )
                item["revision"] = revisions[label]
                item["compiler_version"] = version
                item["build_command"] = cmd
                record["builds"].append(item)

        finally:
            for path in worktrees.values():
                git(
                    "worktree", "remove",
                    "--force", str(path)
                )

    (out / "record.json").write_text(
        json.dumps(record, indent=2) + "\n"
    )
    print(out)


if __name__ == "__main__":
    main()
