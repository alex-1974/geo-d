#!/usr/bin/env python3
"""Place boundary-specialized P1 code in a shared object and inspect executable layout."""

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
BRIDGE_MODULE = "geo.internal.segment_polygon_clip_p1_boundary_shared_bridge"
BRIDGE_PATH = Path("source/geo/internal/segment_polygon_clip_p1_boundary_shared_bridge.d")
BRIDGE_DI_PATH = Path("source/geo/internal/segment_polygon_clip_p1_boundary_shared_bridge.di")


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
    kind = compiler_kind(compiler)
    flags = ["-O3", "-release"] if kind == "ldc" else ["-O", "-inline", "-release"]
    flags.append("-boundscheck=safeonly")
    return flags


def imports(source_root, compiler):
    return capture(
        ["python3", str(source_root / "tools" / "dub-import-paths.py"),
         "--compiler=" + compiler],
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


def capture_symbols(binary, outdir, prefix):
    txt = capture([tool("readelf"), "-Ws", "--wide", str(binary)])
    (outdir / (prefix + "-readelf-symbols.txt")).write_text(txt)
    (outdir / (prefix + "-readelf-sections.txt")).write_text(
        capture([tool("readelf"), "-SW", str(binary)])
    )
    (outdir / (prefix + "-size-sections.txt")).write_text(
        capture([tool("size"), "-A", "-x", str(binary)])
    )
    (outdir / (prefix + "-dynamic.txt")).write_text(
        capture([tool("readelf"), "-dW", str(binary)])
    )

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
    return rows


def build_control(source_root, compiler, outdir):
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
        raise RuntimeError("control build failed")
    return binary, cmd


def build_shared_isolated(source_root, compiler, outdir):
    imps = imports(source_root, compiler)
    flags = release_flags(compiler)

    bridge_source = r'''module geo.internal.segment_polygon_clip_p1_boundary_shared_bridge;

import geo.internal.segment_polygon_clip_p1 :
    SegmentPolygonClipInternalStatus;

import geo.internal.segment_polygon_clip_p1_boundary_specialized :
    trySegmentPolygonClipP1BoundarySpecializedInternal;

import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;

import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;


package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundarySharedInternal(
    Segment2!int query,
    scope Polygon2View!int polygon,
    out SegmentPolygonClipOwnedResultInternal owned
)
    @safe
{
    return trySegmentPolygonClipP1BoundarySpecializedInternal(
        query, polygon, owned
    );
}


package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundarySharedInternal(
    Segment2!long query,
    scope Polygon2View!long polygon,
    out SegmentPolygonClipOwnedResultInternal owned
)
    @safe
{
    return trySegmentPolygonClipP1BoundarySpecializedInternal(
        query, polygon, owned
    );
}


package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundarySharedInternal(
    Segment2!float query,
    scope Polygon2View!float polygon,
    out SegmentPolygonClipOwnedResultInternal owned
)
    @safe
{
    return trySegmentPolygonClipP1BoundarySpecializedInternal(
        query, polygon, owned
    );
}


package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundarySharedInternal(
    Segment2!double query,
    scope Polygon2View!double polygon,
    out SegmentPolygonClipOwnedResultInternal owned
)
    @safe
{
    return trySegmentPolygonClipP1BoundarySpecializedInternal(
        query, polygon, owned
    );
}
'''

    bridge_interface = r'''module geo.internal.segment_polygon_clip_p1_boundary_shared_bridge;

import geo.internal.segment_polygon_clip_p1 :
    SegmentPolygonClipInternalStatus;

import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;

import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;

package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundarySharedInternal(
    Segment2!int,
    scope Polygon2View!int,
    out SegmentPolygonClipOwnedResultInternal
) @safe;

package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundarySharedInternal(
    Segment2!long,
    scope Polygon2View!long,
    out SegmentPolygonClipOwnedResultInternal
) @safe;

package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundarySharedInternal(
    Segment2!float,
    scope Polygon2View!float,
    out SegmentPolygonClipOwnedResultInternal
) @safe;

package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundarySharedInternal(
    Segment2!double,
    scope Polygon2View!double,
    out SegmentPolygonClipOwnedResultInternal
) @safe;
'''

    bridge_path = source_root / BRIDGE_PATH
    bridge_di_path = source_root / BRIDGE_DI_PATH
    bridge_path.write_text(bridge_source)
    bridge_di_path.write_text(bridge_interface)

    # Patch only the temporary candidate worktree: dispatcher calls a
    # non-template bridge symbol. The qualified baseline P1 file is untouched.
    dispatcher_path = (
        source_root / "source/geo/internal/segment_polygon_clip_p1_dispatch.d"
    )
    dispatcher = dispatcher_path.read_text()
    old_import = '''import geo.internal.segment_polygon_clip_p1_boundary_specialized :
    trySegmentPolygonClipP1BoundarySpecializedInternal;
'''
    new_import = '''import geo.internal.segment_polygon_clip_p1_boundary_shared_bridge :
    trySegmentPolygonClipP1BoundarySharedInternal;
'''
    if old_import not in dispatcher:
        raise RuntimeError("dispatcher specialized import anchor missing")
    dispatcher = dispatcher.replace(old_import, new_import)
    dispatcher = dispatcher.replace(
        "trySegmentPolygonClipP1BoundarySpecializedInternal(",
        "trySegmentPolygonClipP1BoundarySharedInternal(",
    )
    dispatcher_path.write_text(dispatcher)

    pic_flag = "-relocation-model=pic" if compiler_kind(compiler) == "ldc" else "-fPIC"

    special_obj = outdir / "boundary-specialized.pic.o"
    special_cmd = [
        compiler,
        "-c",
        pic_flag,
        *["-I" + p for p in imps],
        str(source_root / SPECIAL_PATH),
        *flags,
        "-of=" + str(special_obj),
    ]
    p = run(special_cmd, cwd=outdir, check=False)
    (outdir / "special-compile.stdout").write_text(p.stdout)
    (outdir / "special-compile.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("PIC specialized module compile failed")

    bridge_obj = outdir / "boundary-shared-bridge.pic.o"
    bridge_cmd = [
        compiler,
        "-c",
        pic_flag,
        *["-I" + p for p in imps],
        str(bridge_path),
        *flags,
        "-of=" + str(bridge_obj),
    ]
    p = run(bridge_cmd, cwd=outdir, check=False)
    (outdir / "bridge-compile.stdout").write_text(p.stdout)
    (outdir / "bridge-compile.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("PIC shared bridge compile failed")

    shared = outdir / "libgeo_p1_boundary_specialized.so"
    shared_cmd = [
        tool("cc"),
        "-shared",
        "-Wl,--allow-shlib-undefined",
        "-o", str(shared),
        str(bridge_obj),
        str(special_obj),
    ]
    p = run(shared_cmd, cwd=outdir, check=False)
    (outdir / "shared-link.stdout").write_text(p.stdout)
    (outdir / "shared-link.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("shared link failed")

    binary = outdir / "benchmark"
    link_cmd = [
        compiler,
        "-i=geo",
        "-i=euclid_core",
        "-i=-" + BRIDGE_MODULE,
        "-i=-" + SPECIAL_MODULE,
        *["-I" + p for p in imps],
        str(source_root / "benchmarks" / "segment_polygon_bench.d"),
        *flags,
        "-L--export-dynamic",
        "-L--allow-shlib-undefined",
        "-L-L" + str(outdir),
        "-L-l:libgeo_p1_boundary_specialized.so",
        "-L-rpath=$ORIGIN",
        "-of=" + str(binary),
    ]
    p = run(link_cmd, cwd=outdir, check=False)
    (outdir / "main-link.stdout").write_text(p.stdout)
    (outdir / "main-link.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError(
            "shared-isolated executable link failed\n" +
            p.stdout + p.stderr
        )

    # Hard verification: neither bridge implementation nor specialized P1 may
    # be defined in the executable. They may appear only as UND references.
    exe_symbols = capture([tool("readelf"), "-Ws", "--wide", str(binary)])
    forbidden = (
        "trySegmentPolygonClipP1BoundarySpecializedInternal",
        "trySegmentPolygonClipP1BoundarySharedInternal",
    )
    for line in exe_symbols.splitlines():
        fields = line.split()
        if len(fields) < 8:
            continue
        decoded = demangle(fields[-1])
        if any(name in decoded for name in forbidden) and fields[6] != "UND":
            raise RuntimeError(
                "shared boundary code still defined in executable: " + line
            )

    smoke = run([str(binary), "--check"], cwd=outdir, check=False)
    (outdir / "smoke.stdout").write_text(smoke.stdout)
    (outdir / "smoke.stderr").write_text(smoke.stderr)
    if smoke.returncode:
        raise RuntimeError(
            "shared-isolated semantic smoke failed\n" +
            smoke.stdout + smoke.stderr
        )

    return (
        binary,
        shared,
        special_obj,
        bridge_obj,
        special_cmd,
        bridge_cmd,
        shared_cmd,
        link_cmd,
    )


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
        "purpose": "outer-specialization-shared-object-isolation",
        "compiler": compiler,
        "compiler_version": capture([compiler, "--version"]),
        "revisions": rev,
        "builds": {},
    }

    with tempfile.TemporaryDirectory(prefix="geo-d-shared-special-") as tmp:
        wts = {}
        try:
            for label, sha in rev.items():
                wt = Path(tmp) / label
                git("worktree", "add", "--detach", str(wt), sha)
                wts[label] = wt

            bd = out / "control"
            bd.mkdir()
            binary, cmd = build_control(wts["control"], compiler, bd)
            record["builds"]["control"] = {
                "command": cmd,
                "binary_size": binary.stat().st_size,
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "symbols": capture_symbols(binary, bd, "exe"),
            }

            bd = out / "candidate-shared"
            bd.mkdir()
            (
                binary,
                shared,
                special_obj,
                bridge_obj,
                special_cmd,
                bridge_cmd,
                shared_cmd,
                link_cmd,
            ) = build_shared_isolated(
                wts["candidate"], compiler, bd
            )
            record["builds"]["candidate-shared"] = {
                "special_compile_command": special_cmd,
                "bridge_compile_command": bridge_cmd,
                "shared_link_command": shared_cmd,
                "main_link_command": link_cmd,
                "special_object_size": special_obj.stat().st_size,
                "bridge_object_size": bridge_obj.stat().st_size,
                "binary_size": binary.stat().st_size,
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "shared_size": shared.stat().st_size,
                "shared_sha256": hashlib.sha256(shared.read_bytes()).hexdigest(),
                "executable_symbols": capture_symbols(binary, bd, "exe"),
                "shared_symbols": capture_symbols(shared, bd, "shared"),
            }

            record["status"] = "passed"
        finally:
            for wt in wts.values():
                git("worktree", "remove", "--force", str(wt))
            (out / "summary.json").write_text(json.dumps(record, indent=2) + "\n")

    print(out)


if __name__ == "__main__":
    main()
