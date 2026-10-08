#!/usr/bin/env python3
"""Build base/candidate segment-polygon binaries and capture codegen evidence."""

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


def git(*args):
    return run(["git", "-C", str(ROOT), *args]).stdout.strip()


def capture(cmd, cwd=None):
    return run(cmd, cwd=cwd).stdout


def compiler_kind(path):
    return "ldc" if Path(path).name.startswith("ldc") else "dmd"


def build_binary(source_root, compiler, outdir):
    imports = capture(
        [
            "python3",
            str(source_root / "tools" / "dub-import-paths.py"),
            "--compiler=" + compiler,
        ],
        cwd=source_root,
    ).splitlines()

    source = source_root / "benchmarks" / "segment_polygon_bench.d"
    binary = outdir / "segment-polygon-bench"
    kind = compiler_kind(compiler)

    flags = ["-O3", "-release"] if kind == "ldc" else ["-O", "-inline", "-release"]
    flags.append("-boundscheck=safeonly")

    cmd = [
        compiler,
        "-i",
        *["-I" + path for path in imports],
        str(source),
        *flags,
        "-of=" + str(binary),
    ]
    p = run(cmd, cwd=outdir, check=False)
    (outdir / "build.stdout").write_text(p.stdout)
    (outdir / "build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("build failed: " + str(outdir))

    return binary, cmd, flags, imports


def tool(name):
    path = shutil.which(name)
    if not path:
        raise RuntimeError("required tool not found: " + name)
    return path


def demangle(name, cxxfilt):
    p = run([cxxfilt, "-s", "dlang", name], check=False)
    if p.returncode:
        return name
    result = p.stdout.strip()
    return result or name


def read_symbols(binary, cxxfilt):
    out = capture([tool("readelf"), "-Ws", "--wide", str(binary)])
    symbols = []
    pattern = re.compile(
        r"^\s*\d+:\s+([0-9a-fA-F]+)\s+(\d+)\s+"
        r"(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$"
    )

    for line in out.splitlines():
        m = pattern.match(line)
        if not m:
            continue
        value, size, stype, bind, vis, ndx, name = m.groups()
        if name in ("", "0"):
            continue
        symbols.append(
            {
                "name": name,
                "demangled": demangle(name, cxxfilt),
                "value": int(value, 16),
                "size": int(size),
                "type": stype,
                "bind": bind,
                "visibility": vis,
                "section_index": ndx,
            }
        )
    return out, symbols


def relevant_symbol(symbol):
    text = symbol["demangled"] + " " + symbol["name"]
    needles = (
        "geo.internal.segment_polygon_clip_p1",
        "trySegmentPolygonClipP1Internal",
        "finishSegmentPolygonClipP1Internal",
        "applySmallBoundaryProvenanceSecondPass",
        "segment_polygon_bench",
        "runSelected",
        "clipping",
        "relationship",
    )
    return symbol["type"] == "FUNC" and any(n in text for n in needles)


def write_codegen(binary, outdir):
    cxxfilt = tool("c++filt")
    readelf_text, symbols = read_symbols(binary, cxxfilt)
    relevant = [s for s in symbols if relevant_symbol(s)]
    relevant.sort(key=lambda s: (s["value"], s["name"]))

    (outdir / "readelf-sections.txt").write_text(
        capture([tool("readelf"), "-SW", str(binary)])
    )
    (outdir / "readelf-program-headers.txt").write_text(
        capture([tool("readelf"), "-lW", str(binary)])
    )
    (outdir / "readelf-symbols.txt").write_text(readelf_text)
    (outdir / "size-sections.txt").write_text(
        capture([tool("size"), "-A", "-x", str(binary)])
    )
    (outdir / "nm-address.txt").write_text(
        capture([tool("nm"), "-anS", str(binary)])
    )
    (outdir / "nm-size.txt").write_text(
        capture([tool("nm"), "-S", "--size-sort", str(binary)])
    )

    with (outdir / "relevant-symbols.tsv").open("w") as f:
        f.write("address\tsize\ttype\tbind\tname\tdemangled\n")
        for s in relevant:
            f.write(
                f'{s["value"]:016x}\t{s["size"]}\t{s["type"]}\t{s["bind"]}'
                f'\t{s["name"]}\t{s["demangled"]}\n'
            )

    disdir = outdir / "disassembly"
    disdir.mkdir()
    disassembled = []
    for i, s in enumerate(relevant):
        safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", s["demangled"])[:120]
        target = disdir / f"{i:03d}-{safe}.txt"
        p = run(
            [
                tool("objdump"),
                "-drw",
                "--no-show-raw-insn",
                "--disassemble=" + s["name"],
                str(binary),
            ],
            check=False,
        )
        target.write_text(p.stdout + p.stderr)
        disassembled.append(
            {
                "name": s["name"],
                "demangled": s["demangled"],
                "path": str(target.relative_to(outdir)),
                "returncode": p.returncode,
            }
        )

    return relevant, disassembled


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--compiler", required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()

    compiler = shutil.which(args.compiler)
    if not compiler:
        ap.error("compiler not found: " + args.compiler)
    compiler = str(Path(compiler).resolve())

    base = git("rev-parse", "--verify", args.base + "^{commit}")
    candidate = git("rev-parse", "--verify", args.candidate + "^{commit}")

    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)

    record = {
        "format": 1,
        "status": "incomplete",
        "purpose": "segment-polygon-codegen-compare",
        "base": base,
        "candidate": candidate,
        "compiler": compiler,
        "compiler_version": capture([compiler, "--version"]),
        "tool_versions": {
            name: capture([tool(name), "--version"]).splitlines()[0]
            for name in ("readelf", "objdump", "nm", "size", "c++filt")
        },
        "builds": {},
    }

    with tempfile.TemporaryDirectory(prefix="geo-d-codegen-") as tmp:
        worktrees = {}
        try:
            for label, sha in (("base", base), ("candidate", candidate)):
                wt = Path(tmp) / label
                git("worktree", "add", "--detach", str(wt), sha)
                worktrees[label] = wt

            for label in ("base", "candidate"):
                bd = out / label
                bd.mkdir()
                binary, cmd, flags, imports = build_binary(
                    worktrees[label], compiler, bd
                )
                relevant, disassembled = write_codegen(binary, bd)
                record["builds"][label] = {
                    "revision": base if label == "base" else candidate,
                    "command": cmd,
                    "release_flags": flags,
                    "import_paths": imports,
                    "binary_size": binary.stat().st_size,
                    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                    "relevant_symbols": relevant,
                    "disassembly": disassembled,
                }
                (out / "summary.json").write_text(
                    json.dumps(record, indent=2) + "\n"
                )

            record["status"] = "passed"
        finally:
            for wt in worktrees.values():
                git("worktree", "remove", "--force", str(wt))
            (out / "summary.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )

    print(out)


if __name__ == "__main__":
    main()
