#!/usr/bin/env python3
"""Compare normal vs separately linked boundary-specialization placement."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SPECIAL_MODULE = "geo.internal.segment_polygon_clip_p1_boundary_specialized"
SPECIAL_PATH = Path("source/geo/internal/segment_polygon_clip_p1_boundary_specialized.d")


def run(cmd, cwd=None, check=True):
    p = subprocess.run(
        cmd,
        cwd=ROOT if cwd is None else cwd,
        text=True,
        capture_output=True,
    )
    if check and p.returncode:
        raise RuntimeError("command failed: " + repr(cmd) + "\n" + p.stdout + p.stderr)
    return p


def capture(cmd, cwd=None):
    return run(cmd, cwd=cwd).stdout


def git(*args):
    return capture(["git", "-C", str(ROOT), *args]).strip()


def compiler_kind(path):
    return "ldc" if Path(path).name.startswith("ldc") else "dmd"


def tool(name):
    p = shutil.which(name)
    if not p:
        raise RuntimeError("required tool not found: " + name)
    return p


def imports(source_root, compiler):
    return capture(
        [
            "python3",
            str(source_root / "tools" / "dub-import-paths.py"),
            "--compiler=" + compiler,
        ],
        cwd=source_root,
    ).splitlines()


def release_flags(compiler):
    kind = compiler_kind(compiler)
    flags = ["-O3", "-release"] if kind == "ldc" else ["-O", "-inline", "-release"]
    flags.append("-boundscheck=safeonly")
    return flags


def build_normal(source_root, compiler, outdir):
    imps = imports(source_root, compiler)
    flags = release_flags(compiler)
    binary = outdir / "benchmark"
    cmd = [
        compiler,
        "-i",
        *["-I" + p for p in imps],
        str(source_root / "benchmarks" / "segment_polygon_bench.d"),
        *flags,
        "-of=" + str(binary),
    ]
    p = run(cmd, cwd=outdir, check=False)
    (outdir / "build.stdout").write_text(p.stdout)
    (outdir / "build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("normal build failed")
    return binary, cmd


def build_external_special(source_root, compiler, outdir):
    imps = imports(source_root, compiler)
    flags = release_flags(compiler)
    special_obj = outdir / "boundary-specialized.o"

    # Compile only the specialized module into its own object. Imported
    # dependencies remain link-time dependencies except template instances
    # required by this module.
    special_cmd = [
        compiler,
        "-c",
        *["-I" + p for p in imps],
        str(source_root / SPECIAL_PATH),
        *flags,
        "-of=" + str(special_obj),
    ]
    p = run(special_cmd, cwd=outdir, check=False)
    (outdir / "special-build.stdout").write_text(p.stdout)
    (outdir / "special-build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("special object build failed")

    binary = outdir / "benchmark"

    # Compile all ordinary imported modules, but deliberately exclude the
    # specialized module from -i auto-compilation. Link its object last.
    link_cmd = [
        compiler,
        "-i",
        "-i=-" + SPECIAL_MODULE,
        *["-I" + p for p in imps],
        str(source_root / "benchmarks" / "segment_polygon_bench.d"),
        *flags,
        str(special_obj),
        "-of=" + str(binary),
    ]
    p = run(link_cmd, cwd=outdir, check=False)
    (outdir / "link.stdout").write_text(p.stdout)
    (outdir / "link.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("external-specialization link failed")

    return binary, special_obj, special_cmd, link_cmd


def demangle(name):
    p = run([tool("c++filt"), "-s", "dlang", name], check=False)
    return p.stdout.strip() if p.returncode == 0 and p.stdout.strip() else name


def symbol_table(binary):
    txt = capture([tool("readelf"), "-Ws", "--wide", str(binary)])
    pat = re.compile(
        r"^\s*\d+:\s+([0-9a-fA-F]+)\s+(\d+)\s+"
        r"(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$"
    )
    rows = []
    for line in txt.splitlines():
        m = pat.match(line)
        if not m:
            continue
        value, size, stype, bind, vis, ndx, name = m.groups()
        if stype != "FUNC":
            continue
        d = demangle(name)
        if any(x in d for x in (
            "trySegmentPolygonClipP1Internal",
            "trySegmentPolygonClipP1BoundarySpecializedInternal",
            "trySegmentPolygonClipP1DispatchedInternal",
            "clipSegmentToPolygon",
        )):
            rows.append({
                "name": name,
                "demangled": d,
                "address": int(value, 16),
                "size": int(size),
                "bind": bind,
                "section_index": ndx,
            })
    rows.sort(key=lambda x: (x["address"], x["name"]))
    return txt, rows


def capture_codegen(binary, outdir):
    symtxt, syms = symbol_table(binary)
    (outdir / "readelf-symbols.txt").write_text(symtxt)
    (outdir / "readelf-sections.txt").write_text(
        capture([tool("readelf"), "-SW", str(binary)])
    )
    (outdir / "size-sections.txt").write_text(
        capture([tool("size"), "-A", "-x", str(binary)])
    )
    (outdir / "nm-address.txt").write_text(
        capture([tool("nm"), "-anS", str(binary)])
    )
    return syms


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--control", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--compiler", required=True)
    ap.add_argument("--output", type=Path, required=True)
    a = ap.parse_args()

    compiler = shutil.which(a.compiler)
    if not compiler:
        ap.error("compiler not found: " + a.compiler)
    compiler = str(Path(compiler).resolve())

    rev = {
        "control": git("rev-parse", "--verify", a.control + "^{commit}"),
        "candidate": git("rev-parse", "--verify", a.candidate + "^{commit}"),
    }
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)

    record = {
        "format": 1,
        "status": "incomplete",
        "purpose": "outer-specialization-external-object-placement",
        "compiler": compiler,
        "compiler_version": capture([compiler, "--version"]),
        "revisions": rev,
        "builds": {},
    }

    with tempfile.TemporaryDirectory(prefix="geo-d-external-special-") as tmp:
        wts = {}
        try:
            for label, sha in rev.items():
                wt = Path(tmp) / label
                git("worktree", "add", "--detach", str(wt), sha)
                wts[label] = wt

            # Control build (forced selector -> baseline trampolines).
            bd = out / "control-normal"
            bd.mkdir()
            binary, cmd = build_normal(wts["control"], compiler, bd)
            record["builds"]["control-normal"] = {
                "command": cmd,
                "binary_size": binary.stat().st_size,
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "symbols": capture_codegen(binary, bd),
            }

            # Real specialization with ordinary -i compilation.
            bd = out / "candidate-normal"
            bd.mkdir()
            binary, cmd = build_normal(wts["candidate"], compiler, bd)
            record["builds"]["candidate-normal"] = {
                "command": cmd,
                "binary_size": binary.stat().st_size,
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "symbols": capture_codegen(binary, bd),
            }

            # Same source candidate, but specialized module compiled separately
            # and linked after all ordinary auto-compiled modules.
            bd = out / "candidate-external-special"
            bd.mkdir()
            binary, special_obj, special_cmd, link_cmd = build_external_special(
                wts["candidate"], compiler, bd
            )
            record["builds"]["candidate-external-special"] = {
                "special_command": special_cmd,
                "link_command": link_cmd,
                "special_object_size": special_obj.stat().st_size,
                "special_object_sha256": hashlib.sha256(special_obj.read_bytes()).hexdigest(),
                "binary_size": binary.stat().st_size,
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "symbols": capture_codegen(binary, bd),
            }

            record["status"] = "passed"
        finally:
            for wt in wts.values():
                git("worktree", "remove", "--force", str(wt))
            (out / "summary.json").write_text(json.dumps(record, indent=2) + "\n")

    print(out)


if __name__ == "__main__":
    main()
