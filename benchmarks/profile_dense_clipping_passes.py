#!/usr/bin/env python3
"""Attribute dense segment/polygon clipping work by production pass."""

import argparse, json, os, shutil, subprocess
from datetime import datetime, timezone
from pathlib import Path

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

        writefln("profile_case,%s,%s,%s,%s",
            T.stringof, c.name, iterations, benchmarkSink);
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
    "first_pair_calls": "profileNodingPairCall",
    "first_none": "profileNodingNone",
    "first_touch": "profileNodingTouch",
    "first_proper": "profileNodingProperCrossing",
    "first_overlap": "profileNodingOverlap",
    "second_contact_calls": "profileSecondContactCall",
    "second_none": "profileSecondNone",
    "second_touch": "profileSecondTouch",
    "second_proper": "profileSecondProperCrossing",
    "second_overlap": "profileSecondOverlap",
    "second_proper_constructions": "profileSecondProperConstruction",
    "vertex_contact_calls": "profileVertexContactCall",
    "find_event_calls": "profileFindExactEventCall",
    "point_classification_fallbacks": "profilePointClassificationFallback",
}


def capture(cmd, cwd=ROOT):
    return subprocess.check_output(cmd, cwd=cwd, text=True)


def calls(path, needle):
    for line in path.read_text().splitlines():
        if needle in line:
            fields = line.split()
            if fields and fields[0].isdigit():
                return int(fields[0])
    return 0


def run(binary, cwd, scalar, case, iterations):
    cwd.mkdir()
    subprocess.run(
        [str(binary), scalar, case, str(iterations)],
        cwd=cwd,
        check=True,
        stdout=(cwd / "stdout.txt").open("w"),
        stderr=(cwd / "stderr.txt").open("w"),
    )

    trace = cwd / "trace.log"

    if not trace.is_file():
        raise RuntimeError("missing trace.log")

    return {
        name: calls(trace, helper)
        for name, helper in HELPERS.items()
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cpu", type=int, default=0)
    ap.add_argument("--iterations", type=int, default=200)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()

    if args.cpu not in os.sched_getaffinity(0):
        ap.error("CPU not allowed")

    os.sched_setaffinity(0, {args.cpu})

    dmd = shutil.which("dmd")

    if not dmd:
        ap.error("dmd not found")

    out = (
        args.output
        or ROOT / "build" /
        ("dense-pass-attribution-" +
         datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    ).resolve()

    out.mkdir(parents=True)

    source = (ROOT / "benchmarks/segment_polygon_bench.d").read_text()
    marker = "void main(string[] args)"

    if source.count(marker) != 1:
        raise RuntimeError("benchmark main changed")

    driver = out / "segment_polygon_bench.d"
    driver.write_text(source[:source.index(marker)] + DRIVER_MAIN)

    imports = capture([
        "python3",
        str(ROOT / "tools/dub-import-paths.py"),
        "--compiler=" + dmd,
    ]).splitlines()

    binary = out / "profile"

    subprocess.run([
        dmd,
        "-O",
        "-inline",
        "-release",
        "-boundscheck=safeonly",
        "-profile",
        "-i",
        *["-I" + path for path in imports],
        "-of=" + str(binary),
        str(driver),
    ], cwd=out, check=True)

    rows = []

    cases = [
        "crossing",
        "sparse-16",
        "sparse-64",
        "dense-4",
        "dense-16",
        "dense-64",
    ]

    for scalar in ["int", "long", "float", "double"]:
        for case in cases:
            baseline = run(
                binary,
                out / f"{scalar}-{case}-base",
                scalar,
                case,
                0,
            )

            measured = run(
                binary,
                out / f"{scalar}-{case}-measured",
                scalar,
                case,
                args.iterations,
            )

            counts = {
                key: measured[key] - baseline[key]
                for key in HELPERS
            }

            row = {
                "scalar": scalar,
                "case": case,
                "iterations": args.iterations,
                **counts,
            }

            if args.iterations:
                row["per_iteration"] = {
                    key: value / args.iterations
                    for key, value in counts.items()
                }

            rows.append(row)

    record = {
        "status": "passed",
        "purpose": "dense clipping pass attribution",
        "commit": capture(["git", "rev-parse", "HEAD"]).strip(),
        "dirty": bool(capture([
            "git", "status", "--porcelain", "--",
            "source", "benchmarks", "tools",
        ])),
        "compiler": capture([dmd, "--version"]),
        "cpu": args.cpu,
        "iterations": args.iterations,
        "rows": rows,
        "limitations": [
            "DMD -profile call counts are mechanism evidence only, not latency evidence.",
            "A zero-iteration process is subtracted per scalar/fixture to remove preflight calls.",
            "Research-only no-inline no-op markers identify production call sites without changing geometry semantics.",
            "Counts do not by themselves establish which duplicated work is latency-dominant.",
        ],
    }

    (out / "dense-pass-attribution.json").write_text(
        json.dumps(record, indent=2) + "\n"
    )

    print(json.dumps(rows, indent=2))
    print("record:", out)


if __name__ == "__main__":
    main()
