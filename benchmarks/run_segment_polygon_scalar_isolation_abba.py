#!/usr/bin/env python3
"""ABBA diagnostic with one scalar instantiation per immutable benchmark binary."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[1]

DRIVER = r'''
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
        writefln("fixture,%s,%s,%s,%s,%s,%s", T.stringof, c.name,
            c.edges, c.expectedFacts, c.expectedStatus, c.expected.length);

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
    enforce(args.length == 5);

    const caseName = args[1];
    const rounds = args[2].to!size_t;
    const iterations = args[3].to!size_t;
    const target = args[4].to!long;

    writeln("fixture_header,scalar,case,edges,expected_fact_bits,expected_status,expected_components");
    writeln("sample_header,scalar,case,operation,edges,expected_components,round,iterations,warmup,elapsed_ns,gc_bytes,gc_collections");
    writeln("summary_header,scalar,case,operation,min_ns_per_op,median_ns_per_op,max_ns_per_op");

    runSelected!SCALAR_TYPE(caseName, rounds, iterations, target);
    writefln("sink,%s", benchmarkSink);
}
'''


def run(cmd, cwd=None, check=True):
    p = subprocess.run(
        cmd,
        cwd=ROOT if cwd is None else cwd,
        text=True,
        capture_output=True,
    )
    if check and p.returncode:
        raise RuntimeError(
            "command failed: " + repr(cmd) + "\n" + p.stdout + p.stderr
        )
    return p


def capture(cmd, cwd=None):
    return run(cmd, cwd=cwd).stdout


def git(*args):
    return capture(["git", "-C", str(ROOT), *args]).strip()


def build_binary(source_root, compiler_name, scalar, outdir):
    compiler = shutil.which(compiler_name)
    if not compiler:
        raise RuntimeError("compiler not found: " + compiler_name)

    source = (source_root / "benchmarks" / "segment_polygon_bench.d").read_text()
    marker = "void main(string[] args)"
    if source.count(marker) != 1:
        raise RuntimeError("benchmark main changed")

    driver = outdir / ("segment_polygon_" + scalar + ".d")
    generated = DRIVER.replace("SCALAR_TYPE", scalar)
    driver.write_text(source[:source.index(marker)] + generated)

    imports = capture(
        [
            "python3",
            str(source_root / "tools" / "dub-import-paths.py"),
            "--compiler=" + compiler,
        ],
        cwd=source_root,
    ).splitlines()

    binary = outdir / "benchmark"
    kind = "ldc" if Path(compiler).name.startswith("ldc") else "dmd"
    release = ["-O3", "-release"] if kind == "ldc" else ["-O", "-inline", "-release"]
    release.append("-boundscheck=safeonly")

    cmd = [
        compiler,
        "-i",
        *["-I" + p for p in imports],
        str(driver),
        *release,
        "-of=" + str(binary),
    ]
    p = run(cmd, cwd=outdir, check=False)
    (outdir / "build.stdout").write_text(p.stdout)
    (outdir / "build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("build failed: " + str(outdir))

    return binary, capture([compiler, "--version"], cwd=source_root), cmd


def run_one(binary, outdir, case_name, rounds, target_ms):
    outdir.mkdir(parents=True, exist_ok=False)
    cmd = [str(binary), case_name, str(rounds), "0", str(target_ms)]
    p = run(cmd, cwd=outdir, check=False)
    (outdir / "samples.stdout").write_text(p.stdout)
    (outdir / "samples.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("measurement failed: " + str(outdir))
    return cmd


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--cpu", type=int, default=0)
    ap.add_argument("--cycles", type=int, default=6)
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--target-ms", type=int, default=50)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()

    if args.cpu not in os.sched_getaffinity(0):
        ap.error("CPU not allowed")
    os.sched_setaffinity(0, {args.cpu})

    rev = {
        "base": git("rev-parse", "--verify", args.base + "^{commit}"),
        "candidate": git("rev-parse", "--verify", args.candidate + "^{commit}"),
    }

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = (
        args.output
        or ROOT / "build" / ("segment-polygon-scalar-isolation-" + stamp)
    ).resolve()
    out.mkdir(parents=True, exist_ok=False)

    record = {
        "format": 1,
        "status": "incomplete",
        "purpose": "segment-polygon-scalar-isolation-abba",
        "revisions": rev,
        "cpu": args.cpu,
        "cycles": args.cycles,
        "rounds": args.rounds,
        "target_ms": args.target_ms,
        "builds": [],
        "runs": [],
        "limitations": [
            "One scalar template instantiation per benchmark binary.",
            "No frequency/turbo control imposed.",
            "relationship remains the same-binary normalization control.",
            "This is a causal code-layout diagnostic, not a release benchmark.",
        ],
    }

    scalars = ["int", "long", "float", "double"]
    cases = [
        "exterior",
        "crossing",
        "dense-4",
        "boundary-only",
        "boundary-overlap",
        "degenerate-interior",
        "empty",
    ]

    with tempfile.TemporaryDirectory(prefix="geo-d-scalar-isolation-") as tmp:
        worktrees = {}
        binaries = {}
        try:
            for label, sha in rev.items():
                wt = Path(tmp) / label
                git("worktree", "add", "--detach", str(wt), sha)
                worktrees[label] = wt

            for compiler in ["dmd", "ldc2"]:
                for scalar in scalars:
                    for label in ["base", "candidate"]:
                        bd = out / "build" / compiler / scalar / label
                        bd.mkdir(parents=True, exist_ok=False)
                        binary, version, cmd = build_binary(
                            worktrees[label], compiler, scalar, bd
                        )
                        binaries[(compiler, scalar, label)] = binary
                        record["builds"].append(
                            {
                                "compiler": compiler,
                                "scalar": scalar,
                                "label": label,
                                "revision": rev[label],
                                "compiler_version": version,
                                "command": cmd,
                                "binary_size": binary.stat().st_size,
                                "binary_sha256": hashlib.sha256(
                                    binary.read_bytes()
                                ).hexdigest(),
                            }
                        )

                for scalar in scalars:
                    # Warm both immutable binaries before recorded pairs.
                    for label in ["base", "candidate"]:
                        warm = out / "warmup" / compiler / scalar / label
                        run_one(
                            binaries[(compiler, scalar, label)],
                            warm,
                            "crossing",
                            3,
                            20,
                        )

                    for case_name in cases:
                        for cycle in range(args.cycles):
                            order = (
                                ["base", "candidate", "candidate", "base"]
                                if cycle % 2 == 0
                                else ["candidate", "base", "base", "candidate"]
                            )
                            for pos, label in enumerate(order):
                                name = (
                                    f"{compiler}-{scalar}-{case_name}-"
                                    f"c{cycle}-p{pos}-{label}"
                                )
                                dest = out / "runs" / name
                                cmd = run_one(
                                    binaries[(compiler, scalar, label)],
                                    dest,
                                    case_name,
                                    args.rounds,
                                    args.target_ms,
                                )
                                record["runs"].append(
                                    {
                                        "name": name,
                                        "compiler": compiler,
                                        "scalar": scalar,
                                        "case": case_name,
                                        "cycle": cycle,
                                        "position": pos,
                                        "label": label,
                                        "revision": rev[label],
                                        "command": cmd,
                                    }
                                )
                                (out / "comparison.json").write_text(
                                    json.dumps(record, indent=2) + "\n"
                                )

            record["status"] = "passed"
        finally:
            for wt in worktrees.values():
                git("worktree", "remove", "--force", str(wt))
            record["finished_utc"] = datetime.now(timezone.utc).isoformat()
            (out / "comparison.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )

    print("comparison record:", out)


if __name__ == "__main__":
    main()
