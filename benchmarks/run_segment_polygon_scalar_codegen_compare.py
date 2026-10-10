#!/usr/bin/env python3
"""Capture codegen for one scalar instantiation per benchmark binary."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]

DRIVER = r'''
void main(string[] args)
{
    bool checkOnly;
    size_t rounds = 1, iterations = 1;
    long target = 1;

    foreach (arg; args[1 .. $])
    {
        if (arg == "--check") checkOnly = true;
        else enforce(false, "unknown option: " ~ arg);
    }

    writeln("fixture_header,scalar,case,edges,expected_fact_bits,expected_status,expected_components");
    writeln("sample_header,scalar,case,operation,edges,expected_components,round,iterations,warmup,elapsed_ns,gc_bytes,gc_collections");
    writeln("summary_header,scalar,case,operation,min_ns_per_op,median_ns_per_op,max_ns_per_op");
    run!SCALAR_TYPE(checkOnly, rounds, iterations, target);
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


def tool(name):
    p = shutil.which(name)
    if not p:
        raise RuntimeError("required tool not found: " + name)
    return p


def demangle(name):
    p = run([tool("c++filt"), "-s", "dlang", name], check=False)
    return p.stdout.strip() if p.returncode == 0 and p.stdout.strip() else name


def build(source_root, compiler_name, scalar, outdir):
    compiler = shutil.which(compiler_name)
    if not compiler:
        raise RuntimeError("compiler not found: " + compiler_name)

    source = (source_root / "benchmarks" / "segment_polygon_bench.d").read_text()
    marker = "void main(string[] args)"
    if source.count(marker) != 1:
        raise RuntimeError("benchmark main changed")

    driver = outdir / ("segment_polygon_codegen_" + scalar + ".d")
    driver.write_text(
        source[:source.index(marker)] +
        DRIVER.replace("SCALAR_TYPE", scalar)
    )

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
    flags = ["-O3", "-release"] if kind == "ldc" else ["-O", "-inline", "-release"]
    flags.append("-boundscheck=safeonly")

    cmd = [
        compiler,
        "-i",
        *["-I" + p for p in imports],
        str(driver),
        *flags,
        "-of=" + str(binary),
    ]
    p = run(cmd, cwd=outdir, check=False)
    (outdir / "build.stdout").write_text(p.stdout)
    (outdir / "build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError(
            "build failed: " + str(outdir) + "\n" + p.stdout + p.stderr
        )

    return binary, compiler, flags, cmd


def symbols(binary):
    txt = capture([tool("readelf"), "-Ws", "--wide", str(binary)])
    pat = re.compile(
        r"^\s*\d+:\s+([0-9a-fA-F]+)\s+(\d+)\s+"
        r"(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$"
    )
    out = []
    for line in txt.splitlines():
        m = pat.match(line)
        if not m:
            continue
        value, size, stype, bind, vis, ndx, name = m.groups()
        d = demangle(name)
        if stype != "FUNC":
            continue
        if any(x in d for x in (
            "geo.internal.segment_polygon_clip_p1",
            "segment_polygon_bench",
            "clipping",
            "relationship",
            "run(",
        )):
            out.append({
                "name": name,
                "demangled": d,
                "address": int(value, 16),
                "size": int(size),
                "bind": bind,
                "section_index": ndx,
            })
    out.sort(key=lambda x: (x["address"], x["name"]))
    return txt, out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--compiler", required=True)
    ap.add_argument("--scalar", choices=["int", "long", "float", "double"], required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()

    base = git("rev-parse", "--verify", args.base + "^{commit}")
    candidate = git("rev-parse", "--verify", args.candidate + "^{commit}")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)

    record = {
        "format": 1,
        "status": "incomplete",
        "purpose": "segment-polygon-scalar-codegen-compare",
        "base": base,
        "candidate": candidate,
        "compiler_requested": args.compiler,
        "scalar": args.scalar,
        "builds": {},
    }

    with tempfile.TemporaryDirectory(prefix="geo-d-scalar-codegen-") as tmp:
        wts = {}
        try:
            for label, sha in (("base", base), ("candidate", candidate)):
                wt = Path(tmp) / label
                git("worktree", "add", "--detach", str(wt), sha)
                wts[label] = wt

            for label in ("base", "candidate"):
                bd = out / label
                bd.mkdir()
                binary, compiler, flags, cmd = build(
                    wts[label], args.compiler, args.scalar, bd
                )
                symtxt, syms = symbols(binary)
                (bd / "readelf-symbols.txt").write_text(symtxt)
                (bd / "readelf-sections.txt").write_text(
                    capture([tool("readelf"), "-SW", str(binary)])
                )
                (bd / "size-sections.txt").write_text(
                    capture([tool("size"), "-A", "-x", str(binary)])
                )
                (bd / "nm-size.txt").write_text(
                    capture([tool("nm"), "-S", "--size-sort", str(binary)])
                )

                dis = bd / "disassembly"
                dis.mkdir()
                for i, s in enumerate(syms):
                    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", s["demangled"])[:120]
                    p = run([
                        tool("objdump"),
                        "-drw",
                        "--no-show-raw-insn",
                        "--disassemble=" + s["name"],
                        str(binary),
                    ], check=False)
                    (dis / f"{i:03d}-{safe}.txt").write_text(p.stdout + p.stderr)

                record["builds"][label] = {
                    "revision": base if label == "base" else candidate,
                    "compiler": compiler,
                    "compiler_version": capture([compiler, "--version"]),
                    "release_flags": flags,
                    "command": cmd,
                    "binary_size": binary.stat().st_size,
                    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                    "symbols": syms,
                }
                (out / "summary.json").write_text(
                    json.dumps(record, indent=2) + "\n"
                )
            record["status"] = "passed"
        finally:
            for wt in wts.values():
                git("worktree", "remove", "--force", str(wt))
            (out / "summary.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )

    print(out)


if __name__ == "__main__":
    main()
