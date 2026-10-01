#!/usr/bin/env python3
"""Build, preflight and record public segment/polygon measurements."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def capture(args, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"command failed: {args!r}\n{result.stdout}{result.stderr}")
    return result.stdout


def read_optional(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", default="dmd")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--cpu", type=int, help="pin this process and its children to an allowed CPU")
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--iterations", type=int, default=0, help="0 calibrates each case/operation independently")
    parser.add_argument("--target-ms", type=int, default=20)
    parser.add_argument("--check", action="store_true", help="debug and release semantic preflight only")
    parser.add_argument("--smoke", action="store_true", help="two iterations, one round; not performance evidence")
    parser.add_argument("--allow-dirty", action="store_true", help="diagnostic runs only; save tracked diff")
    args = parser.parse_args()
    if not (1 <= args.rounds <= 100 and 0 <= args.iterations <= 10_000_000
            and 1 <= args.target_ms <= 60_000):
        parser.error("invalid measurement limits")
    if args.check and args.smoke:
        parser.error("--check and --smoke are mutually exclusive")
    compiler = shutil.which(args.compiler)
    if not compiler or not shutil.which("dub"):
        parser.error("compiler and dub must be available (put the selected toolchain on PATH)")
    compiler = str(Path(compiler).resolve())
    kind = "ldc" if Path(compiler).name.startswith("ldc") else "dmd"
    if kind == "dmd" and Path(compiler).name != "dmd":
        parser.error("supported compilers: dmd and ldc2")
    tracked_diff = capture(["git", "diff", "HEAD", "--binary"])
    untracked = capture(["git", "ls-files", "--others", "--exclude-standard", "benchmarks", "source", "tools"])
    dirty = bool(tracked_diff or untracked)
    if dirty and not args.allow_dirty:
        parser.error("tracked or benchmark/source/tool files differ from HEAD; use --allow-dirty for diagnostics")
    allowed = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None
    if args.cpu is not None:
        if allowed is None or args.cpu not in allowed:
            parser.error("requested CPU is not in the current allowed affinity set")
        os.sched_setaffinity(0, {args.cpu})
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = (args.output or ROOT / "build" / "segment-polygon" / f"{stamp}-{kind}").resolve()
    out.mkdir(parents=True, exist_ok=False)
    metadata = {
        "format": 1, "started_utc": stamp, "status": "incomplete",
        "purpose": "semantic-check" if args.check else "smoke" if args.smoke else "measurement",
        "commit": capture(["git", "rev-parse", "HEAD"]).strip(),
        "tree": capture(["git", "rev-parse", "HEAD^{tree}"]).strip(),
        "dirty": dirty, "untracked_relevant_files": untracked.splitlines(),
        "compiler_path": compiler, "compiler_version": capture([compiler, "--version"]),
        "dub_version": capture(["dub", "--version"]), "platform": platform.platform(),
        "cpuinfo": read_optional("/proc/cpuinfo"), "loadavg": read_optional("/proc/loadavg"),
        "affinity": sorted(os.sched_getaffinity(0)) if allowed is not None else None,
        "frequency_controls": {}, "commands": [],
        "runtime_environment": {key: os.environ.get(key) for key in ("DRT_GCOPT", "DFLAGS", "LDC_DFLAGS", "DUB_OPTIONS")},
        "gc_policy": "automatic GC enabled; explicit collection outside each timed round",
        "limitations": ["No frequency control is imposed by this harness.",
                        "Shared/virtualized hosts do not establish release performance.",
                        "GC bytes are current-thread runtime accounting, not allocation-call counts or peak memory."]
    }
    cpus = metadata["affinity"] or []
    for cpu in cpus:
        metadata["frequency_controls"][str(cpu)] = {
            key: read_optional(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/{key}")
            for key in ("scaling_governor", "scaling_min_freq", "scaling_max_freq")
        }
    meta_path = out / "metadata.json"

    def save():
        meta_path.write_text(json.dumps(metadata, indent=2) + "\n")

    def run_logged(command, name):
        metadata["commands"].append(command)
        save()
        result = subprocess.run(command, cwd=out, text=True, capture_output=True)
        (out / (name + ".stdout")).write_text(result.stdout)
        (out / (name + ".stderr")).write_text(result.stderr)
        if result.returncode:
            raise RuntimeError(f"{name} failed; see {out}\n{result.stderr[-3000:]}")
        return result.stdout

    save()
    try:
        (out / "tracked.patch").write_text(tracked_diff)
        source = ROOT / "benchmarks" / "segment_polygon_bench.d"
        # Snapshot the executed source even when it is not yet tracked.
        (out / "segment_polygon_bench.d").write_bytes(source.read_bytes())
        metadata["benchmark_sha256"] = hashlib.sha256(source.read_bytes()).hexdigest()
        imports = capture(["python3", str(ROOT / "tools" / "dub-import-paths.py"),
                           "--compiler=" + compiler]).splitlines()
        metadata["import_paths"] = imports
        (out / "dub-describe.json").write_text(capture(["dub", "describe", "--compiler=" + compiler]))
        common = [compiler, "-i", *["-I" + path for path in imports], str(source)]
        release = ["-O3", "-release", "-boundscheck=off"] if kind == "ldc" else ["-O", "-inline", "-release", "-boundscheck=off"]
        metadata["release_flags"] = release
        debug_bin, release_bin = out / "preflight", out / "benchmark"
        run_logged(common + ["-g", "-of=" + str(debug_bin)], "build-debug")
        print(run_logged([str(debug_bin), "--check"], "preflight-debug"), end="", flush=True)
        run_logged(common + release + ["-of=" + str(release_bin)], "build-release")
        print(run_logged([str(release_bin), "--check"], "preflight-release"), end="", flush=True)
        if not args.check:
            options = ["--iterations=2", "--rounds=1"] if args.smoke else [
                f"--rounds={args.rounds}", f"--iterations={args.iterations}", f"--target-ms={args.target_ms}"]
            run_logged([str(release_bin), *options], "samples")
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
