#!/usr/bin/env python3
"""Build an instrumented static GEOS 3.13.1 and record work attribution.

The generated GEOS build is diagnostic only.  Its timings are not a replacement
for benchmarks/segment-polygon/reference/run_native_comparison.py.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REFERENCE = HERE.parent
ROOT = HERE.parents[3]
EXPECTED_GEOS_COMMIT = "431568d6e311e0bbfb057b4ec3d44d0d3ba3335f"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture(command, cwd=ROOT) -> str:
    return subprocess.check_output(command, cwd=cwd, text=True)


def load_native_prepare():
    path = REFERENCE / "run_native_comparison.py"
    spec = importlib.util.spec_from_file_location("geo_d_native_compare", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load native comparison helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.prepare


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cxx", default="g++")
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--iterations", type=int, default=50)
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 1, 12))
    parser.add_argument("--allow-dirty", action="store_true")
    parser.add_argument("--notes", default="")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if not 1 <= args.iterations <= 100000:
        parser.error("iterations must be in [1, 100000]")
    if not 1 <= args.jobs <= 128:
        parser.error("jobs must be in [1, 128]")

    cxx = shutil.which(args.cxx)
    cmake = shutil.which("cmake")
    git = shutil.which("git")
    python = sys.executable

    if not cxx or not cmake or not git:
        parser.error("git, cmake and the selected C++ compiler are required")

    if args.cpu is not None:
        allowed = os.sched_getaffinity(0)
        if args.cpu not in allowed:
            parser.error(f"CPU {args.cpu} is outside allowed affinity {sorted(allowed)}")
        os.sched_setaffinity(0, {args.cpu})

    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    work = out / "work"
    source = work / "geos-source"
    geos_build = work / "geos-build"
    geos_install = work / "geos-install"
    driver_build = work / "driver-build"

    geo_status = capture(["git", "status", "--short"])
    dirty = bool(geo_status.strip())
    if dirty and not args.allow_dirty:
        parser.error("geo-d checkout is dirty; use --allow-dirty for diagnostics only")

    metadata = {
        "status": "incomplete",
        "purpose": "geos-work-attribution",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "geo_d_commit": capture(["git", "rev-parse", "HEAD"]).strip(),
        "geo_d_dirty": dirty,
        "geo_d_status": geo_status.splitlines(),
        "geos_version": "3.13.1",
        "geos_expected_commit": EXPECTED_GEOS_COMMIT,
        "platform": platform.platform(),
        "affinity": sorted(os.sched_getaffinity(0)),
        "notes": args.notes,
        "iterations": args.iterations,
        "jobs": args.jobs,
        "commands": [],
        "cxx": cxx,
        "cxx_version": capture([cxx, "--version"]),
        "cmake": cmake,
        "cmake_version": capture([cmake, "--version"]),
        "probe_driver_sha256": sha(HERE / "geos_work_probe.cpp"),
        "patcher_sha256": sha(HERE / "apply_geos_work_probe.py"),
        "analyzer_sha256": sha(HERE / "analyze_geos_work_probe.py"),
        "limitations": [
            "Research-only GEOS source instrumentation changes execution cost.",
            "Stage timings are mechanism evidence and must not replace uninstrumented wall-clock comparison.",
            "GEOS retains weaker binary64/construction semantics and only the pre-admitted 87 fixtures.",
            "Static linking is used so the diagnostic inline counter object is shared with the probe executable.",
        ],
    }

    def save() -> None:
        (out / "metadata.json").write_text(
            json.dumps(metadata, indent=2, sort_keys=True) + "\n"
        )

    def logged(command, name, cwd=ROOT, env=None) -> subprocess.CompletedProcess:
        command = [str(item) for item in command]
        metadata["commands"].append({
            "name": name,
            "cwd": str(cwd),
            "command": command,
        })
        save()

        result = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        (out / f"{name}.stdout").write_text(result.stdout)
        (out / f"{name}.stderr").write_text(result.stderr)

        if result.returncode:
            raise RuntimeError(
                f"{name} failed with status {result.returncode}; "
                f"see {out / (name + '.stderr')}"
            )

        return result

    save()

    try:
        logged(
            [
                git,
                "clone",
                "--quiet",
                "--depth",
                "1",
                "--branch",
                "3.13.1",
                "https://github.com/libgeos/geos.git",
                source,
            ],
            "geos-clone",
        )

        actual_geos_commit = capture(
            [git, "-C", str(source), "rev-parse", "HEAD"]
        ).strip()
        metadata["geos_commit"] = actual_geos_commit
        if actual_geos_commit != EXPECTED_GEOS_COMMIT:
            raise RuntimeError(
                f"GEOS tag commit mismatch: expected {EXPECTED_GEOS_COMMIT}, "
                f"got {actual_geos_commit}"
            )

        logged(
            [python, HERE / "apply_geos_work_probe.py", source],
            "geos-instrument",
        )
        logged(
            [git, "-C", str(source), "diff", "--check"],
            "geos-diff-check",
        )

        geos_patch = capture(
            [git, "-C", str(source), "diff", "--binary"],
            cwd=ROOT,
        )
        (out / "geos-instrumentation.patch").write_text(geos_patch)
        shutil.copyfile(
            source / "include/geos/diagnostic/GeoDWorkProbe.h",
            out / "GeoDWorkProbe.h",
        )

        logged(
            [
                cmake,
                "-S", source,
                "-B", geos_build,
                "-DCMAKE_BUILD_TYPE=Release",
                "-DBUILD_SHARED_LIBS=OFF",
                "-DBUILD_TESTING=OFF",
                "-DBUILD_BENCHMARKS=OFF",
                "-DGEOS_BUILD_DEVELOPER=OFF",
                f"-DCMAKE_CXX_COMPILER={cxx}",
                f"-DCMAKE_INSTALL_PREFIX={geos_install}",
            ],
            "geos-configure",
        )

        logged(
            [cmake, "--build", geos_build, "--parallel", str(args.jobs)],
            "geos-build",
        )
        logged(
            [cmake, "--install", geos_build],
            "geos-install",
        )

        corpus_path = REFERENCE / "results/corpus.json"
        assessment_path = REFERENCE / "results/geos-3.13.1.json"
        if not corpus_path.is_file() or not assessment_path.is_file():
            raise RuntimeError("retained corpus/GEOS assessment is missing")

        prepare = load_native_prepare()
        _, admitted = prepare(corpus_path, assessment_path, out)
        if len(admitted) != 87:
            raise RuntimeError("native admission set changed")

        driver_source_dir = work / "driver-source"
        driver_source_dir.mkdir(parents=True)
        cmake_lists = driver_source_dir / "CMakeLists.txt"
        cmake_lists.write_text(
            "cmake_minimum_required(VERSION 3.16)\n"
            "project(geo_d_geos_work_probe LANGUAGES CXX)\n"
            "set(CMAKE_CXX_STANDARD 17)\n"
            "set(CMAKE_CXX_STANDARD_REQUIRED ON)\n"
            "find_package(GEOS 3.13.1 EXACT CONFIG REQUIRED)\n"
            f"add_executable(geos-work-probe {json.dumps(str(HERE / 'geos_work_probe.cpp'))})\n"
            f"target_include_directories(geos-work-probe PRIVATE {json.dumps(str(out))})\n"
            "target_compile_options(geos-work-probe PRIVATE -Wall -Wextra -Werror)\n"
            "target_link_libraries(geos-work-probe PRIVATE GEOS::geos_c)\n"
        )

        logged(
            [
                cmake,
                "-S", driver_source_dir,
                "-B", driver_build,
                "-DCMAKE_BUILD_TYPE=Release",
                f"-DCMAKE_CXX_COMPILER={cxx}",
                f"-DCMAKE_PREFIX_PATH={geos_install}",
            ],
            "driver-configure",
        )
        logged(
            [cmake, "--build", driver_build, "--parallel", str(args.jobs)],
            "driver-build",
        )

        probe = driver_build / "geos-work-probe"
        if not probe.is_file():
            candidates = list(driver_build.rglob("geos-work-probe"))
            if len(candidates) != 1:
                raise RuntimeError("cannot locate geos-work-probe executable")
            probe = candidates[0]

        result = logged(
            [probe, f"--iterations={args.iterations}"],
            "probe",
        )
        (out / "probe.stdout").write_text(result.stdout)
        (out / "probe.stderr").write_text(result.stderr)

        logged(
            [
                python,
                HERE / "analyze_geos_work_probe.py",
                out / "probe.stdout",
                "--json", out / "summary.json",
                "--markdown", out / "summary.md",
            ],
            "probe-audit",
        )

        metadata["native_corpus_sha256"] = sha(out / "native_corpus.hpp")
        metadata["admission_sha256"] = sha(out / "admission.json")
        metadata["instrumentation_patch_sha256"] = sha(out / "geos-instrumentation.patch")
        metadata["summary_sha256"] = sha(out / "summary.json")
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
