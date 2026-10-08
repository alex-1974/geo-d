#!/usr/bin/env python3
"""Compare normal outer specialization with a static ABI-bridge object layout."""

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
BRIDGE_MODULE = "geo.internal.segment_polygon_clip_p1_boundary_static_bridge"
SPECIAL_PATH = Path("source/geo/internal/segment_polygon_clip_p1_boundary_specialized.d")
BRIDGE_PATH = Path("source/geo/internal/segment_polygon_clip_p1_boundary_static_bridge.d")
BRIDGE_DI_PATH = Path("source/geo/internal/segment_polygon_clip_p1_boundary_static_bridge.di")


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


def release_flags(compiler):
    flags = ["-O3", "-release"] if compiler_kind(compiler) == "ldc" else ["-O", "-inline", "-release"]
    flags.append("-boundscheck=safeonly")
    return flags


def imports(source_root, compiler):
    return capture(
        [
            "python3",
            str(source_root / "tools" / "dub-import-paths.py"),
            "--compiler=" + compiler,
        ],
        cwd=source_root,
    ).splitlines()


def tool(name):
    p = shutil.which(name)
    if not p:
        raise RuntimeError("required tool not found: " + name)
    return p


def demangle(name):
    p = run([tool("c++filt"), "-s", "dlang", name], check=False)
    return p.stdout.strip() if p.returncode == 0 and p.stdout.strip() else name


def bridge_source():
    wrappers = []
    for scalar in ("int", "long", "float", "double"):
        wrappers.append(f'''
package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!{scalar} query,
    scope Polygon2View!{scalar} polygon,
    out SegmentPolygonClipOwnedResultInternal owned
)
    @safe
{{
    return trySegmentPolygonClipP1BoundarySpecializedInternal(
        query,
        polygon,
        owned
    );
}}
''')
    return '''module geo.internal.segment_polygon_clip_p1_boundary_static_bridge;

import geo.internal.segment_polygon_clip_p1 :
    SegmentPolygonClipInternalStatus;

import geo.internal.segment_polygon_clip_p1_boundary_specialized :
    trySegmentPolygonClipP1BoundarySpecializedInternal;

import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;

import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;

''' + "\n".join(wrappers)


def bridge_interface():
    decls = []
    for scalar in ("int", "long", "float", "double"):
        decls.append(f'''
package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!{scalar},
    scope Polygon2View!{scalar},
    out SegmentPolygonClipOwnedResultInternal
)
    @safe;
''')
    return '''module geo.internal.segment_polygon_clip_p1_boundary_static_bridge;

import geo.internal.segment_polygon_clip_p1 :
    SegmentPolygonClipInternalStatus;

import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;

import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;

''' + "\n".join(decls)


def patch_candidate(source_root):
    bridge = source_root / BRIDGE_PATH
    bridge_di = source_root / BRIDGE_DI_PATH
    bridge.write_text(bridge_source())
    bridge_di.write_text(bridge_interface())

    dispatcher_path = (
        source_root / "source/geo/internal/segment_polygon_clip_p1_dispatch.d"
    )
    dispatcher = dispatcher_path.read_text()

    old_import = '''import geo.internal.segment_polygon_clip_p1_boundary_specialized :
    trySegmentPolygonClipP1BoundarySpecializedInternal;
'''
    new_import = '''import geo.internal.segment_polygon_clip_p1_boundary_static_bridge :
    trySegmentPolygonClipP1BoundaryStaticInternal;
'''
    if old_import not in dispatcher:
        raise RuntimeError("dispatcher specialized import anchor missing")
    dispatcher = dispatcher.replace(old_import, new_import)
    dispatcher = dispatcher.replace(
        "trySegmentPolygonClipP1BoundarySpecializedInternal(",
        "trySegmentPolygonClipP1BoundaryStaticInternal(",
    )
    dispatcher_path.write_text(dispatcher)


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
        raise RuntimeError("normal build failed\n" + p.stdout + p.stderr)
    return binary, cmd


def build_static_bridge(source_root, compiler, outdir):
    imps = imports(source_root, compiler)
    flags = release_flags(compiler)
    patch_candidate(source_root)

    special_obj = outdir / "boundary-specialized.o"
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
        raise RuntimeError("special object build failed\n" + p.stdout + p.stderr)

    bridge_obj = outdir / "boundary-static-bridge.o"
    bridge_cmd = [
        compiler,
        "-c",
        *["-I" + p for p in imps],
        str(source_root / BRIDGE_PATH),
        *flags,
        "-of=" + str(bridge_obj),
    ]
    p = run(bridge_cmd, cwd=outdir, check=False)
    (outdir / "bridge-build.stdout").write_text(p.stdout)
    (outdir / "bridge-build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("bridge object build failed\n" + p.stdout + p.stderr)

    # Sanity: specialized template instantiations must exist in the bridge
    # object, not depend on main-module instantiation.
    bridge_symbols = capture([tool("nm"), "-S", str(bridge_obj)], outdir)
    if "trySegmentPolygonClipP1BoundarySpecializedInternal" not in bridge_symbols:
        raise RuntimeError("bridge object does not contain specialized template instantiations")

    binary = outdir / "benchmark"
    link_cmd = [
        compiler,
        "-i",
        "-i=-" + BRIDGE_MODULE,
        "-i=-" + SPECIAL_MODULE,
        *["-I" + p for p in imps],
        str(source_root / "benchmarks" / "segment_polygon_bench.d"),
        *flags,
        str(bridge_obj),
        str(special_obj),
        "-of=" + str(binary),
    ]
    p = run(link_cmd, cwd=outdir, check=False)
    (outdir / "link.stdout").write_text(p.stdout)
    (outdir / "link.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("static bridge link failed\n" + p.stdout + p.stderr)

    smoke = run([str(binary), "--check"], cwd=outdir, check=False)
    (outdir / "smoke.stdout").write_text(smoke.stdout)
    (outdir / "smoke.stderr").write_text(smoke.stderr)
    if smoke.returncode:
        raise RuntimeError("static bridge semantic smoke failed\n" + smoke.stdout + smoke.stderr)

    return binary, special_obj, bridge_obj, special_cmd, bridge_cmd, link_cmd


def symbol_rows(binary):
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
            "trySegmentPolygonClipP1BoundaryStaticInternal",
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
    symtxt, rows = symbol_rows(binary)
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
    return rows


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
        "purpose": "outer-specialization-static-abi-bridge-placement",
        "compiler": compiler,
        "compiler_version": capture([compiler, "--version"]),
        "revisions": rev,
        "builds": {},
    }

    with tempfile.TemporaryDirectory(prefix="geo-d-static-bridge-") as tmp:
        wts = {}
        try:
            for label, sha in rev.items():
                wt = Path(tmp) / label
                git("worktree", "add", "--detach", str(wt), sha)
                wts[label] = wt

            bd = out / "control-normal"
            bd.mkdir()
            binary, cmd = build_normal(wts["control"], compiler, bd)
            record["builds"]["control-normal"] = {
                "command": cmd,
                "binary_size": binary.stat().st_size,
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "symbols": capture_codegen(binary, bd),
            }

            bd = out / "candidate-normal"
            bd.mkdir()
            binary, cmd = build_normal(wts["candidate"], compiler, bd)
            record["builds"]["candidate-normal"] = {
                "command": cmd,
                "binary_size": binary.stat().st_size,
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "symbols": capture_codegen(binary, bd),
            }

            bd = out / "candidate-static-bridge"
            bd.mkdir()
            (
                binary,
                special_obj,
                bridge_obj,
                special_cmd,
                bridge_cmd,
                link_cmd,
            ) = build_static_bridge(wts["candidate"], compiler, bd)
            record["builds"]["candidate-static-bridge"] = {
                "special_command": special_cmd,
                "bridge_command": bridge_cmd,
                "link_command": link_cmd,
                "special_object_size": special_obj.stat().st_size,
                "bridge_object_size": bridge_obj.stat().st_size,
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
