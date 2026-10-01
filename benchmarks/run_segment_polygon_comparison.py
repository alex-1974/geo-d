#!/usr/bin/env python3
"""Serial immutable-revision comparison; retain all records outside worktrees."""

import argparse
import hashlib
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="03f345acb6b922719108fd00b72bf105d20a8a21")
    parser.add_argument("--candidate", default="HEAD")
    parser.add_argument("--boundscheck", choices=["safeonly", "on", "off"], default="safeonly")
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--compiler", action="append", choices=["dmd", "ldc2"])
    parser.add_argument("--blocks", type=int, default=2, help="alternate base/candidate then candidate/base")
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--target-ms", type=int, default=20)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--notes", default="", help="power, governor, turbo and background-load controls")
    parser.add_argument("--smoke", action="store_true", help="runner validation only, not performance evidence")
    args = parser.parse_args()
    if not (1 <= args.blocks <= 10 and 1 <= args.rounds <= 100 and 1 <= args.target_ms <= 60_000):
        parser.error("invalid comparison limits")
    if not hasattr(os, "sched_getaffinity") or args.cpu not in os.sched_getaffinity(0):
        parser.error("--cpu must be an allowed Linux CPU")
    compilers = args.compiler or ["dmd", "ldc2"]
    for compiler in compilers:
        if not shutil.which(compiler):
            parser.error(f"compiler not found on PATH: {compiler}")
    if not shutil.which("dub"):
        parser.error("dub not found on PATH")
    revisions = {"base": git("rev-parse", "--verify", args.base + "^{commit}"),
                 "candidate": git("rev-parse", "--verify", args.candidate + "^{commit}")}
    if revisions["base"] == revisions["candidate"]:
        parser.error("base and candidate must differ")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output = (args.output or ROOT / "build" / ("segment-polygon-comparison-" + stamp)).resolve()
    output.mkdir(parents=True, exist_ok=False)
    runner = ROOT / "benchmarks/run_segment_polygon.py"
    record = {"format": 2, "purpose": "smoke" if args.smoke else "comparison",
              "status": "incomplete", "revisions": revisions, "cpu": args.cpu,
              "boundscheck": args.boundscheck,
              "comparison_runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "measurement_runner_sha256": hashlib.sha256(runner.read_bytes()).hexdigest(),
              "notes": args.notes, "runs": [], "started_utc": stamp}
    (output / "run_segment_polygon_comparison.py").write_bytes(Path(__file__).read_bytes())
    (output / "run_segment_polygon.py").write_bytes(runner.read_bytes())
    manifest = output / "comparison.json"

    def save():
        manifest.write_text(json.dumps(record, indent=2) + "\n")

    save()
    with tempfile.TemporaryDirectory(prefix="geo-d-segment-polygon-") as temporary:
        worktrees = {}
        try:
            for label, revision in revisions.items():
                path = Path(temporary) / label
                git("worktree", "add", "--detach", str(path), revision)
                worktrees[label] = path
                if not (path / "benchmarks/run_segment_polygon.py").is_file():
                    raise RuntimeError(f"{label} does not contain the benchmark runner")
            for compiler in compilers:
                for block in range(args.blocks):
                    order = ["base", "candidate"] if block % 2 == 0 else ["candidate", "base"]
                    for label in order:
                        name = f"{compiler}-block{block}-{label}"
                        # One recorded runner applies identical flags to both immutable sources,
                        # including historical revisions whose own runner disabled all checks.
                        command = ["python3", str(runner), "--source-root=" + str(worktrees[label]),
                                   "--boundscheck=" + args.boundscheck,
                                   "--compiler=" + compiler, "--cpu=" + str(args.cpu),
                                   "--output=" + str(output / name)]
                        command += ["--smoke"] if args.smoke else [
                            "--rounds=" + str(args.rounds), "--target-ms=" + str(args.target_ms)]
                        run = {"name": name, "revision": revisions[label], "command": command}
                        record["runs"].append(run)
                        save()
                        print(name, flush=True)
                        with (output / (name + ".log")).open("w") as log:
                            result = subprocess.run(command, cwd=worktrees[label], stdout=log,
                                                    stderr=subprocess.STDOUT)
                        run["returncode"] = result.returncode
                        save()
                        if result.returncode:
                            raise RuntimeError(f"{name} failed; see {output / (name + '.log')}")
                        metadata = json.loads((output / name / "metadata.json").read_text())
                        if not (metadata["status"] == "passed" and not metadata["dirty"]
                                and metadata["commit"] == revisions[label]
                                and metadata["boundscheck"] == args.boundscheck
                                and metadata["harness_sha256"] == record["measurement_runner_sha256"]
                                and "-boundscheck=" + args.boundscheck in metadata["release_flags"]):
                            raise RuntimeError(f"{name} has an incomplete or inconsistent measurement record")
                        run["record_verified"] = True
                        save()
            record["status"] = "passed"
        except Exception:
            record["status"] = "failed"
            raise
        finally:
            # Only disposable worktrees created by this run are removed.
            # All output and the manifest live outside them and are retained.
            for path in worktrees.values():
                git("worktree", "remove", "--force", str(path))
            record["finished_utc"] = datetime.now(timezone.utc).isoformat()
            save()
            print(f"comparison record: {output}", flush=True)


if __name__ == "__main__":
    main()
