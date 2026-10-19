#!/usr/bin/env python3
"""Measure constant-time denominator signature rejection coverage.

Research instrumentation only. DMD -profile changes code generation and runtime
cost; call counts are mechanism evidence, never latency evidence.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

DRIVER_MAIN = r'''
private void profileOne(T)(string caseName, size_t iterations)
{
    auto cases = corpus!T();

    foreach (ref c; cases)
    {
        if (c.name != caseName)
            continue;

        preflight(c);

        ulong sink;

        foreach (i; 0 .. iterations)
            sink = sink * 1_000_033UL + clipping(c, i);

        benchmarkSink = sink;

        writefln(
            "profile_case,%s,%s,%s,%s",
            T.stringof,
            c.name,
            iterations,
            benchmarkSink
        );

        return;
    }

    enforce(false, "unknown profile case");
}

void main(string[] args)
{
    enforce(args.length == 4);

    const scalar = args[1];
    const caseName = args[2];
    const iterations = args[3].to!size_t;

    if (scalar == "int")
        profileOne!int(caseName, iterations);
    else if (scalar == "long")
        profileOne!long(caseName, iterations);
    else if (scalar == "float")
        profileOne!float(caseName, iterations);
    else if (scalar == "double")
        profileOne!double(caseName, iterations);
    else
        enforce(false, "unknown scalar");
}
'''

HELPERS = {
    "limb67": "signatureRejectLimb67",
    "band66_68": "signatureRejectBand66To68",
    "five_samples": "signatureRejectFiveSamples",
    "nine_samples": "signatureRejectNineSamples",
    "needs_full_scan": "signatureNeedsFullScan",
}


def capture(command):
    return subprocess.check_output(command, cwd=ROOT, text=True)


def trace_calls(path, needle):
    for line in path.read_text().splitlines():
        if needle not in line:
            continue
        fields = line.split()
        if fields and fields[0].isdigit():
            return int(fields[0])
    return 0


def run_profile(binary, cwd, scalar, case, iterations):
    cwd.mkdir()
    proc = subprocess.run(
        [str(binary), scalar, case, str(iterations)],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    (cwd / "stdout.txt").write_text(proc.stdout)
    (cwd / "stderr.txt").write_text(proc.stderr)
    trace = cwd / "trace.log"
    if not trace.is_file():
        raise RuntimeError("DMD did not emit trace.log")
    return {name: trace_calls(trace, symbol) for name, symbol in HELPERS.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cpu", type=int, default=0)
    parser.add_argument("--iterations", type=int, default=200)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    if args.iterations <= 0:
        parser.error("--iterations must be positive")

    if not hasattr(os, "sched_getaffinity") or args.cpu not in os.sched_getaffinity(0):
        parser.error("--cpu must be an allowed Linux CPU")

    os.sched_setaffinity(0, {args.cpu})

    compiler = shutil.which("dmd")
    if not compiler:
        parser.error("dmd not found")

    version = capture([compiler, "--version"])
    if "DMD" not in version:
        parser.error("this instrumentation runner requires DMD")

    out = (
        args.output
        or ROOT / "build" / (
            "denominator-signature-"
            + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        )
    ).resolve()
    out.mkdir(parents=True, exist_ok=False)

    source = (ROOT / "benchmarks/segment_polygon_bench.d").read_text()
    marker = "void main(string[] args)"
    if source.count(marker) != 1:
        raise RuntimeError("benchmark main changed; inspect driver derivation")

    driver = out / "segment_polygon_bench.d"
    driver.write_text(source[:source.index(marker)] + DRIVER_MAIN)

    imports = capture([
        "python3",
        str(ROOT / "tools/dub-import-paths.py"),
        "--compiler=" + compiler,
    ]).splitlines()

    binary = out / "profile"
    build = [
        compiler,
        "-O",
        "-inline",
        "-release",
        "-boundscheck=safeonly",
        "-profile",
        "-i",
        *["-I" + path for path in imports],
        "-of=" + str(binary),
        str(driver),
    ]

    proc = subprocess.run(
        build,
        cwd=out,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    (out / "build.stdout").write_text(proc.stdout)
    (out / "build.stderr").write_text(proc.stderr)

    scalars = ["int", "long", "float", "double"]
    cases = [
        "crossing",
        "sparse-4",
        "sparse-16",
        "sparse-64",
        "dense-4",
        "dense-16",
        "dense-64",
    ]

    rows = []

    for scalar in scalars:
        for case in cases:
            baseline = run_profile(
                binary,
                out / (scalar + "-" + case + "-baseline"),
                scalar,
                case,
                0,
            )
            measured = run_profile(
                binary,
                out / (scalar + "-" + case + "-measured"),
                scalar,
                case,
                args.iterations,
            )

            counts = {
                key: measured[key] - baseline[key]
                for key in HELPERS
            }

            if any(value < 0 for value in counts.values()):
                raise RuntimeError("negative baseline-adjusted call count")

            distinct = counts["nine_samples"] + counts["needs_full_scan"]

            rows.append({
                "scalar": scalar,
                "case": case,
                "iterations": args.iterations,
                "distinct_denominator_pairs": distinct,
                **counts,
                "limb67_reject_rate": (
                    counts["limb67"] / distinct if distinct else None
                ),
                "band66_68_reject_rate": (
                    counts["band66_68"] / distinct if distinct else None
                ),
                "five_sample_reject_rate": (
                    counts["five_samples"] / distinct if distinct else None
                ),
                "nine_sample_reject_rate": (
                    counts["nine_samples"] / distinct if distinct else None
                ),
            })

    record = {
        "format": 1,
        "purpose": "exact-denominator-signature-coverage",
        "status": "passed",
        "commit": capture(["git", "rev-parse", "HEAD"]).strip(),
        "tree": capture(["git", "rev-parse", "HEAD^{tree}"]).strip(),
        "dirty": bool(capture([
            "git", "status", "--porcelain", "--", "source", "benchmarks", "tools"
        ])),
        "compiler_version": version,
        "cpu": args.cpu,
        "iterations": args.iterations,
        "driver_sha256": hashlib.sha256(driver.read_bytes()).hexdigest(),
        "rows": rows,
        "limitations": [
            "DMD -profile changes code generation and runtime cost.",
            "Call counts are mechanism evidence only, not latency evidence.",
            "A zero-iteration process is subtracted per scalar/fixture so preflight calls are excluded.",
            "Signatures are rejection filters only; a match never proves denominator equality.",
        ],
    }

    (out / "signature-coverage.json").write_text(
        json.dumps(record, indent=2) + "\n"
    )

    print(json.dumps(rows, indent=2))
    print("record:", out)


if __name__ == "__main__":
    main()
