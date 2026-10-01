#!/usr/bin/env python3
"""Preflight and record serial D/native-GEOS AB/BA comparisons (weaker GEOS contract)."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def capture(command):
    return subprocess.check_output(command, cwd=ROOT, text=True)


def bits(value):
    return struct.unpack("=Q", struct.pack("=d", float(value)))[0]


def prepare(corpus_path, assessment_path, output):
    cases = json.loads(corpus_path.read_text())
    report = json.loads(assessment_path.read_text())
    if report["corpus_sha256"] != sha(corpus_path) or report["geos"] != "3.13.1":
        raise RuntimeError("assessment/corpus mismatch")
    identities = {(c["scalar"], c["case"]) for c in cases}
    if len(cases) != 92 or len(identities) != 92:
        raise RuntimeError("expected 92 unique corpus fixtures")
    records = report["records"]
    record_ids = {(r["scalar"], r["case"], r["reverse"]) for r in records}
    if len(records) != 184 or record_ids != {(s, n, d) for s, n in identities for d in (False, True)}:
        raise RuntimeError("assessment must cover both directions of every fixture")
    admitted = {key for key in identities if all(
        r["assessment"] == "matches_after_adapter" for r in records
        if (r["scalar"], r["case"]) == key)}
    if len(admitted) != 87:
        raise RuntimeError("expected pinned 87-fixture admission set")
    excluded = [r for r in records if (r["scalar"], r["case"]) not in admitted]
    (output / "admission.json").write_text(json.dumps({
        "admitted": sorted(admitted), "excluded_records": excluded,
        "policy": "both directions match pinned untimed assessment; native preflight still required"
    }, indent=2) + "\n")

    def point(p, encoding):
        values = [bits(v) for v in p] if encoding == "integer" else p
        return "bp(" + ",".join(str(v) + "ULL" for v in values) + ")"

    rows = []
    for c in cases:
        if (c["scalar"], c["case"]) not in admitted:
            continue
        if c["expected_status"] != "success":
            raise RuntimeError("failed-construction case cannot be admitted")
        encoding = c["coordinate_encoding"]
        if encoding == "integer" and any(int(float(v)) != v
                for p in [*c["query"], *[p for ring in c["rings"] for p in ring]] for v in p):
            raise RuntimeError("lossy integral input cannot be admitted")
        rings = "{" + ",".join("{" + ",".join(point(p, encoding) for p in ring) + "}"
                                for ring in c["rings"]) + "}"
        query = "{" + ",".join(point(p, encoding) for p in c["query"]) + "}"
        expected = "{" + ",".join("{" + ",".join(point(p, "binary64-bits") for p in s) + "}"
                                   for s in c["expected_segments_binary64_bits"]) + "}"
        rows.append("{" + ",".join((json.dumps(c["scalar"]), json.dumps(c["case"]), rings,
                                     query, expected, str(c["edges"]))) + "}")
    (output / "native_corpus.hpp").write_text(
        "// Generated from shared corpus; input construction is outside timing.\n"
        "std::vector<Fixture> corpus() { return {\n" + ",\n".join(rows) + "\n}; }\n")
    return cases, admitted


def summaries(text, admitted, expected_cases, rounds, smoke=False):
    rows = [line.split(",") for line in text.splitlines()]
    checksum = [r for r in rows if r[0] in ("checksum", "sink")]
    samples = [r for r in rows if r[0] == "sample" and r[3] == "clipping"]
    result = [r for r in rows if r[0] == "summary" and r[3] == "clipping"]
    if len(checksum) != 1 or len(result) != expected_cases or len(samples) != expected_cases * rounds:
        raise RuntimeError("incomplete sample/summary/checksum record")
    counts = Counter((r[1], r[2]) for r in samples)
    values = {(r[1], r[2]): float(r[5]) for r in result}
    if len(values) != expected_cases or any(counts[k] != rounds for k in values):
        raise RuntimeError("duplicate or missing case samples")
    for key in values:
        if {int(r[6]) for r in samples if (r[1], r[2]) == key} != set(range(rounds)):
            raise RuntimeError("duplicate/missing timed round")
    if any(not math.isfinite(v) or v < 0 or (v == 0 and not smoke) for v in values.values()):
        raise RuntimeError("invalid median (zero allowed only in smoke)")
    if not admitted <= values.keys():
        raise RuntimeError("missing admitted fixture")
    return {key: values[key] for key in admitted}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", action="append", required=True, help="dmd/ldc2; repeat for both")
    parser.add_argument("--cxx", default="g++")
    parser.add_argument("--geos-header", type=Path, required=True, help="configured GEOS 3.13.1 geos_c.h")
    parser.add_argument("--geos-library", type=Path, required=True, help="exact native libgeos_c shared library")
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--target-ms", type=int, default=20)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--allow-dirty", action="store_true", help="diagnostics only")
    parser.add_argument("--notes", default="", help="power/turbo/background workload attestations")
    parser.add_argument("--output", type=Path, required=True, help="new record directory")
    args = parser.parse_args()
    if not 1 <= args.rounds <= 100 or not 1 <= args.target_ms <= 60000:
        parser.error("invalid measurement limits")
    compilers = [shutil.which(c) for c in args.compiler]
    cxx = shutil.which(args.cxx)
    if not all(compilers) or not cxx:
        parser.error("D and C++ compilers must be available")
    if len(set(compilers)) != len(compilers):
        parser.error("duplicate compiler")
    header, library = args.geos_header.resolve(), args.geos_library.resolve()
    if not header.is_file() or not library.is_file():
        parser.error("GEOS header/library must exist")
    patch = capture(["git", "diff", "HEAD", "--binary"])
    untracked = capture(["git", "ls-files", "--others", "--exclude-standard", "benchmarks", "source", "tools"])
    dirty = bool(patch or untracked)
    if dirty and not args.allow_dirty:
        parser.error("source differs from HEAD; --allow-dirty permits diagnostics only")
    if args.cpu is not None:
        if args.cpu not in os.sched_getaffinity(0):
            parser.error("CPU outside allowed affinity")
        os.sched_setaffinity(0, {args.cpu})
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = HERE / "geos_native_bench.cpp"
    corpus_path, assessment_path = HERE / "results/corpus.json", HERE / "results/geos-3.13.1.json"
    metadata = {"status": "incomplete", "purpose": "smoke" if args.smoke else "comparison",
                "started_utc": datetime.now(timezone.utc).isoformat(),
                "source_commit": capture(["git", "rev-parse", "HEAD"]).strip(),
                "dirty": dirty, "untracked_relevant_files": untracked.splitlines(),
                "platform": platform.platform(), "affinity": sorted(os.sched_getaffinity(0)),
                "notes": args.notes, "commands": [], "runs": [],
                "cxx_version": capture([cxx, "--version"]), "cxx_flags": ["-std=c++17", "-O3"],
                "geos_header": str(header), "geos_header_sha256": sha(header),
                "geos_library": str(library), "geos_library_sha256": sha(library),
                "runner_sha256": sha(__file__), "cpp_sha256": sha(source),
                "corpus_sha256": sha(corpus_path), "assessment_sha256": sha(assessment_path),
                "limitations": ["GEOS has weaker numerical/construction semantics; admitted subset only.",
                    "No frequency control imposed; shared-host measurements are diagnostic only.",
                    "C++ releases per call; D automatic GC remains enabled with collection outside rounds.",
                    "Native allocation counts/bytes are not instrumented; NA is not zero."]}
    metadata["frequency_controls"] = {}
    for cpu in metadata["affinity"]:
        controls = {}
        for key in ("scaling_governor", "scaling_min_freq", "scaling_max_freq"):
            path = Path(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/{key}")
            controls[key] = path.read_text().strip() if path.is_file() else None
        metadata["frequency_controls"][str(cpu)] = controls

    def save():
        (out / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")

    def logged(command, name):
        metadata["commands"].append(command)
        save()
        r = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
        (out / (name + ".stdout")).write_text(r.stdout)
        (out / (name + ".stderr")).write_text(r.stderr)
        if r.returncode:
            raise RuntimeError(f"{name} failed; see {out}: {r.stderr[-1500:]}")
        return r.stdout

    save()
    try:
        for path in (source, Path(__file__), corpus_path, assessment_path):
            shutil.copyfile(path, out / path.name)
        shutil.copyfile(header, out / "geos_c.h")
        export_header = header.parent / "geos/export.h"
        if export_header.is_file():
            (out / "geos").mkdir()
            shutil.copyfile(export_header, out / "geos/export.h")
            metadata["geos_export_header_sha256"] = sha(export_header)
        (out / "tracked.patch").write_text(patch)
        cases, admitted = prepare(corpus_path, assessment_path, out)
        metadata["native_corpus_sha256"] = sha(out / "native_corpus.hpp")
        common = [cxx, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-I" + str(out),
                  "-I" + str(header.parent),
                  str(out / source.name), str(library),
                  "-Wl,--disable-new-dtags,-rpath," + str(library.parent)]
        debug, binary = out / "native-debug", out / "native"
        logged(common + ["-g", "-o", str(debug)], "native-build-debug")
        logged(common + ["-O3", "-o", str(binary)], "native-build-release")
        for exe, name in ((debug, "native-preflight-debug"), (binary, "native-preflight-release")):
            text = logged([str(exe), "--check"], name)
            if "preflight,native,87,174,PASS" not in text:
                raise RuntimeError("missing native preflight completion")
        metadata["native_linked_libraries"] = logged(["ldd", str(binary)], "native-ldd")
        metadata["linked_library_sha256"] = {p: sha(p) for p in
            sorted(set(re.findall(r"(/[^\s]+)", metadata["native_linked_libraries"])))
            if Path(p).is_file()}
        rounds = 1 if args.smoke else args.rounds
        native_options = ["--iterations=2", "--rounds=1"] if args.smoke else [
            f"--rounds={rounds}", f"--target-ms={args.target_ms}"]
        pairs = []
        for index, compiler in enumerate(compilers):
            prefix = f"compiler-{index}"
            child_args = [sys.executable, str(ROOT / "benchmarks/run_segment_polygon.py"),
                          "--compiler=" + compiler, "--boundscheck=safeonly"]
            if args.allow_dirty: child_args.append("--allow-dirty")
            if args.cpu is not None: child_args.append(f"--cpu={args.cpu}")
            check_dir = out / (prefix + "-check")
            logged(child_args + ["--check", "--output=" + str(check_dir)], prefix + "-check")
            child_meta = json.loads((check_dir / "metadata.json").read_text())
            if child_meta["status"] != "passed":
                raise RuntimeError("incomplete D preflight")
            for exe in ("preflight", "benchmark"):
                exported = logged([str(check_dir / exe), "--export-corpus"], prefix + "-export-" + exe)
                if json.loads(exported) != cases:
                    raise RuntimeError("fresh D export differs from retained shared corpus")
            for block, order in enumerate((("d", "native"), ("native", "d"))):
                values = {}
                for implementation in order:
                    name = f"{prefix}-block-{block}-{implementation}"
                    if implementation == "native":
                        text = logged([str(binary), *native_options], name)
                        values[implementation] = summaries(text, admitted, 87, rounds, args.smoke)
                    else:
                        child_dir = out / name
                        options = ["--smoke"] if args.smoke else [f"--rounds={rounds}", f"--target-ms={args.target_ms}"]
                        logged(child_args + options + ["--output=" + str(child_dir)], name)
                        m = json.loads((child_dir / "metadata.json").read_text())
                        if m["status"] != "passed" or m["commit"] != metadata["source_commit"]:
                            raise RuntimeError("incomplete/mismatched D record")
                        values[implementation] = summaries((child_dir / "samples.stdout").read_text(), admitted, 92, rounds, args.smoke)
                    metadata["runs"].append({"compiler": compiler, "block": block,
                                             "implementation": implementation, "record": name, "status": "passed"})
                    save()
                for scalar, case in sorted(admitted):
                    d, native = values["d"][(scalar, case)], values["native"][(scalar, case)]
                    pairs.append({"compiler": compiler, "block": block, "order": list(order),
                                  "scalar": scalar, "case": case, "d_median_ns": d,
                                  "native_median_ns": native, "d_over_native": None if args.smoke else d / native})
        (out / "comparison.json").write_text(json.dumps({"purpose": metadata["purpose"],
            "warning": "subset with weaker GEOS semantics; smoke is not performance evidence",
            "pairs": pairs}, indent=2) + "\n")
        metadata["status"] = "passed"
    except Exception:
        metadata["status"] = "failed"
        raise
    finally:
        metadata["finished_utc"] = datetime.now(timezone.utc).isoformat()
        save()
        print(f"record: {out}", flush=True)


if __name__ == "__main__":
    main()
