#!/usr/bin/env python3
"""Prebuild pinned base/candidate binaries and ABBA the prepared known-crossing exact kernel."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

PROBE = r'''
module geo.internal.known_crossing_exact_abba_probe;

import geo.internal.intersection_exact :
    ExactProperIntersection,
    exactProperIntersectionsEqual,
    prepareExactSegment,
    properIntersectionExactKnownCrossing,
    properIntersectionExactKnownCrossingPreparedFirst;
import geo.point : Point2;
import geo.segment : Segment2;

import std.algorithm.sorting : sort;
import std.conv : to;
import std.datetime.stopwatch : StopWatch;
import std.exception : enforce;
import std.stdio : writefln;

alias P = Point2!double;
alias S = Segment2!double;

__gshared ulong benchmarkSink;
__gshared typeof(prepareExactSegment(first)) preparedFirstValue;

private S first =
    S(P(1_000_000.0, 1_000_000.0),
      P(1_000_100.0, 1_000_100.0));

private S[8] seconds = [
    S(P(1_000_000.0, 1_000_100.0),
      P(1_000_100.0, 1_000_000.0)),
    S(P(1_000_010.0, 1_000_100.0),
      P(1_000_090.0, 1_000_000.0)),
    S(P(1_000_000.0, 1_000_090.0),
      P(1_000_100.0, 1_000_010.0)),
    S(P(1_000_020.0, 1_000_100.0),
      P(1_000_080.0, 1_000_000.0)),
    S(P(1_000_000.25, 1_000_099.75),
      P(1_000_099.75, 1_000_000.25)),
    S(P(1_000_012.5, 1_000_100.0),
      P(1_000_087.5, 1_000_000.0)),
    S(P(1_000_000.0, 1_000_075.5),
      P(1_000_100.0, 1_000_024.5)),
    S(P(1_000_031.25, 1_000_100.0),
      P(1_000_068.75, 1_000_000.0))
];

private ulong mix(ulong value, ulong part)
{
    return (value * 0x100000001b3UL) ^ part;
}

private ulong fingerprintMagnitude(M)(ref const M value)
{
    ulong result = 0xcbf29ce484222325UL;
    foreach (limb; value.limb)
        result = mix(result, limb);
    return result;
}

private ulong fingerprint(ref const ExactProperIntersection value)
{
    ulong result = cast(ulong)(value.xNumerator.sign + 1);
    result = mix(result, fingerprintMagnitude(value.xNumerator.magnitude));
    result = mix(result, cast(ulong)(value.yNumerator.sign + 1));
    result = mix(result, fingerprintMagnitude(value.yNumerator.magnitude));
    result = mix(result, fingerprintMagnitude(value.denominator));
    return result;
}

pragma(inline, false)
private ulong control(size_t i)
{
    const auto prepared = prepareExactSegment(seconds[i & 7]);
    ulong result = cast(ulong)(prepared.aX.sign + prepared.aY.sign +
        prepared.bX.sign + prepared.bY.sign + 4);
    result = mix(result, prepared.aX.magnitude.limb[33]);
    result = mix(result, prepared.aY.magnitude.limb[33]);
    result = mix(result, prepared.bX.magnitude.limb[33]);
    result = mix(result, prepared.bY.magnitude.limb[33]);
    return result;
}

pragma(inline, false)
private ulong exactConstruction(size_t i)
{
    ExactProperIntersection result;
    properIntersectionExactKnownCrossingPreparedFirst(
        preparedFirstValue,
        seconds[i & 7],
        result
    );
    return fingerprint(result);
}

private void preflight()
{
    preparedFirstValue = prepareExactSegment(first);

    foreach (ref second; seconds)
    {
        ExactProperIntersection reference;
        ExactProperIntersection candidate;

        properIntersectionExactKnownCrossing(
            first,
            second,
            reference
        );

        properIntersectionExactKnownCrossingPreparedFirst(
            preparedFirstValue,
            second,
            candidate
        );

        assert(exactProperIntersectionsEqual(reference, candidate));
        assert(reference.denominator.limb == candidate.denominator.limb);
        assert(reference.xNumerator.sign == candidate.xNumerator.sign);
        assert(reference.xNumerator.magnitude.limb ==
            candidate.xNumerator.magnitude.limb);
        assert(reference.yNumerator.sign == candidate.yNumerator.sign);
        assert(reference.yNumerator.magnitude.limb ==
            candidate.yNumerator.magnitude.limb);
    }
}

private void measure(alias operation)(
    string name,
    size_t rounds,
    size_t fixedIterations,
    long targetMilliseconds
)
{
    size_t iterations = fixedIterations ? fixedIterations : 1;
    ulong sink = 1;

    if (!fixedIterations)
    {
        while (true)
        {
            StopWatch calibration;
            calibration.start();
            foreach (i; 0 .. iterations)
                sink = mix(sink, operation(i));
            calibration.stop();

            if (calibration.peek.total!"msecs" >= targetMilliseconds ||
                iterations >= 1_048_576)
                break;

            iterations *= 2;
        }
    }

    const size_t warmup = iterations / 10 + 1;
    foreach (i; 0 .. warmup)
        sink = mix(sink, operation(i));

    double[] timings = new double[rounds];

    foreach (round; 0 .. rounds)
    {
        StopWatch watch;
        watch.start();

        foreach (i; 0 .. iterations)
            sink = mix(sink, operation(i));

        watch.stop();

        const auto elapsed = watch.peek.total!"nsecs";
        timings[round] = cast(double) elapsed / iterations;

        writefln(
            "sample,%s,%s,%s,%s",
            name,
            round,
            iterations,
            elapsed
        );
    }

    sort(timings);

    const double median =
        (timings[(rounds - 1) / 2] + timings[rounds / 2]) / 2;

    writefln(
        "summary,%s,%.3f,%.3f,%.3f",
        name,
        timings[0],
        median,
        timings[$ - 1]
    );

    benchmarkSink = mix(benchmarkSink, sink);
}

void main(string[] args)
{
    enforce(args.length == 5);

    const operation = args[1];
    const rounds = args[2].to!size_t;
    const iterations = args[3].to!size_t;
    const target = args[4].to!long;

    preflight();
    writefln("preflight,8,PASS");

    if (operation == "control")
        measure!control("control", rounds, iterations, target);
    else if (operation == "exact")
        measure!exactConstruction("exact", rounds, iterations, target);
    else
        enforce(false, "unknown operation");

    writefln("sink,%s", benchmarkSink);
}
'''


def git(*args):
    return subprocess.check_output(
        ["git", "-C", str(ROOT), *args],
        text=True
    ).strip()


def capture(cmd, cwd):
    p = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if p.returncode:
        raise RuntimeError(
            "command failed: " + repr(cmd) + "\n" + p.stdout + p.stderr
        )
    return p.stdout


def build_binary(source_root, compiler_name, outdir):
    compiler = shutil.which(compiler_name)
    if not compiler:
        raise RuntimeError("compiler not found: " + compiler_name)

    driver = outdir / "known_crossing_exact_abba_probe.d"
    driver.write_text(PROBE)

    imports = capture(
        [
            "python3",
            str(source_root / "tools/dub-import-paths.py"),
            "--compiler=" + compiler,
        ],
        source_root,
    ).splitlines()

    binary = outdir / "benchmark"
    kind = "ldc" if Path(compiler).name.startswith("ldc") else "dmd"
    release = ["-O3", "-release"] if kind == "ldc" else [
        "-O", "-inline", "-release"
    ]
    release.append("-boundscheck=safeonly")

    cmd = [
        compiler,
        "-i",
        *["-I" + p for p in imports],
        str(driver),
        *release,
        "-of=" + str(binary),
    ]

    p = subprocess.run(cmd, cwd=outdir, text=True, capture_output=True)
    (outdir / "build.stdout").write_text(p.stdout)
    (outdir / "build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("build failed: " + str(outdir))

    return binary, capture([compiler, "--version"], source_root)


def run_one(binary, outdir, operation, rounds, target_ms):
    outdir.mkdir(parents=True, exist_ok=False)
    cmd = [str(binary), operation, str(rounds), "0", str(target_ms)]
    p = subprocess.run(cmd, cwd=outdir, text=True, capture_output=True)
    (outdir / "samples.stdout").write_text(p.stdout)
    (outdir / "samples.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("measurement failed: " + str(outdir))
    if "preflight,8,PASS" not in p.stdout:
        raise RuntimeError("preflight missing: " + str(outdir))
    return cmd


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--base",
        default="7f9237f7c4be993b7ac987a46f40d05bde8355c8",
    )
    ap.add_argument(
        "--candidate",
        default="c72a9b9511d3183eb7f29d5aa9179214647c9765",
    )
    ap.add_argument("--cpu", type=int, default=0)
    ap.add_argument("--cycles", type=int, default=5)
    ap.add_argument("--rounds", type=int, default=9)
    ap.add_argument("--target-ms", type=int, default=75)
    ap.add_argument("--output", type=Path)
    a = ap.parse_args()

    if a.cpu not in os.sched_getaffinity(0):
        ap.error("CPU not allowed")
    os.sched_setaffinity(0, {a.cpu})

    revisions = {
        "base": git("rev-parse", "--verify", a.base + "^{commit}"),
        "candidate": git(
            "rev-parse", "--verify", a.candidate + "^{commit}"
        ),
    }

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = (
        a.output or
        ROOT / "build" / ("known-crossing-exact-abba-" + stamp)
    ).resolve()
    out.mkdir(parents=True, exist_ok=False)

    record = {
        "format": 1,
        "status": "incomplete",
        "purpose": "prepared-known-crossing-exact-abba",
        "revisions": revisions,
        "cpu": a.cpu,
        "cycles": a.cycles,
        "rounds": a.rounds,
        "target_ms": a.target_ms,
        "runs": [],
        "builds": [],
        "limitations": [
            "No frequency/turbo control imposed.",
            "Binaries are built once before timing.",
            "prepareExactSegment is retained as an unaffected control.",
            "Eight strict double-precision crossings use translated positive coordinates to exercise same-sign coordinate subtraction.",
        ],
    }

    with tempfile.TemporaryDirectory(
        prefix="geo-d-known-crossing-exact-"
    ) as tmp:
        worktrees = {}
        binaries = {}
        try:
            for label, sha in revisions.items():
                path = Path(tmp) / label
                git("worktree", "add", "--detach", str(path), sha)
                worktrees[label] = path

            for compiler in ("dmd", "ldc2"):
                for label in ("base", "candidate"):
                    dest = out / "build" / compiler / label
                    dest.mkdir(parents=True, exist_ok=False)
                    binary, version = build_binary(
                        worktrees[label], compiler, dest
                    )
                    binaries[(compiler, label)] = binary
                    record["builds"].append({
                        "compiler": compiler,
                        "label": label,
                        "revision": revisions[label],
                        "compiler_version": version,
                        "binary_sha256": hashlib.sha256(
                            binary.read_bytes()
                        ).hexdigest(),
                    })

            for compiler in ("dmd", "ldc2"):
                for label in ("base", "candidate"):
                    warm = out / "warmup" / compiler / label
                    run_one(
                        binaries[(compiler, label)],
                        warm,
                        "exact",
                        3,
                        25,
                    )

                for operation in ("control", "exact"):
                    for cycle in range(a.cycles):
                        order = (
                            ["base", "candidate", "candidate", "base"]
                            if cycle % 2 == 0
                            else ["candidate", "base", "base", "candidate"]
                        )
                        for position, label in enumerate(order):
                            name = (
                                f"{compiler}-{operation}-"
                                f"c{cycle}-p{position}-{label}"
                            )
                            dest = out / "runs" / name
                            cmd = run_one(
                                binaries[(compiler, label)],
                                dest,
                                operation,
                                a.rounds,
                                a.target_ms,
                            )
                            record["runs"].append({
                                "name": name,
                                "compiler": compiler,
                                "operation": operation,
                                "cycle": cycle,
                                "position": position,
                                "label": label,
                                "revision": revisions[label],
                                "command": cmd,
                            })
                            (out / "comparison.json").write_text(
                                json.dumps(record, indent=2) + "\n"
                            )

            record["status"] = "passed"
        finally:
            for path in worktrees.values():
                git("worktree", "remove", "--force", str(path))

            record["finished_utc"] = datetime.now(
                timezone.utc
            ).isoformat()
            (out / "comparison.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )

    print("comparison record:", out)


if __name__ == "__main__":
    main()
