#!/usr/bin/env python3
"""Targeted ABBA for #165 using a static ABI bridge in one executable."""

import argparse, hashlib, json, os, shutil, subprocess, tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

DRIVER_MAIN=r'''
private void runSelected(T)(string caseName,size_t rounds,size_t iterations,long target)
{
    auto cases=corpus!T();
    foreach(ref c; cases)
    {
        if(c.name!=caseName) continue;
        preflight(c);
        writefln("fixture,%s,%s,%s,%s,%s,%s",T.stringof,c.name,
            c.edges,c.expectedFacts,c.expectedStatus,c.expected.length);
        measure!(relationship!T)(c,"relationship",rounds,iterations,target);
        measure!(clipping!T)(c,"clipping",rounds,iterations,target);
        return;
    }
    enforce(false,"unknown case");
}
void main(string[] args)
{
    enforce(args.length==6);
    const scalar=args[1],caseName=args[2];
    const rounds=args[3].to!size_t;
    const iterations=args[4].to!size_t;
    const target=args[5].to!long;
    writeln("fixture_header,scalar,case,edges,expected_fact_bits,expected_status,expected_components");
    writeln("sample_header,scalar,case,operation,edges,expected_components,round,iterations,warmup,elapsed_ns,gc_bytes,gc_collections");
    writeln("summary_header,scalar,case,operation,min_ns_per_op,median_ns_per_op,max_ns_per_op");
    if(scalar=="int") runSelected!int(caseName,rounds,iterations,target);
    else if(scalar=="long") runSelected!long(caseName,rounds,iterations,target);
    else if(scalar=="float") runSelected!float(caseName,rounds,iterations,target);
    else if(scalar=="double") runSelected!double(caseName,rounds,iterations,target);
    else enforce(false,"unknown scalar");
    writefln("sink,%s",benchmarkSink);
}
'''

CASES=["boundary-only","boundary-overlap","crossing","dense-4"]
SPECIAL_MODULE="geo.internal.segment_polygon_clip_p1_boundary_specialized"
BRIDGE_MODULE="geo.internal.segment_polygon_clip_p1_boundary_static_bridge"
SPECIAL_PATH=Path("source/geo/internal/segment_polygon_clip_p1_boundary_specialized.d")
BRIDGE_PATH=Path("source/geo/internal/segment_polygon_clip_p1_boundary_static_bridge.d")
BRIDGE_DI_PATH=Path("source/geo/internal/segment_polygon_clip_p1_boundary_static_bridge.di")

BRIDGE_SOURCE=r'''module geo.internal.segment_polygon_clip_p1_boundary_static_bridge;

import geo.internal.segment_polygon_clip_p1 :
    SegmentPolygonClipInternalStatus;
import geo.internal.segment_polygon_clip_p1_boundary_specialized :
    trySegmentPolygonClipP1BoundarySpecializedInternal;
import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;
import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;

package(geo) SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!int query, scope Polygon2View!int polygon,
    out SegmentPolygonClipOwnedResultInternal owned) @safe
{
    return trySegmentPolygonClipP1BoundarySpecializedInternal(query,polygon,owned);
}
package(geo) SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!long query, scope Polygon2View!long polygon,
    out SegmentPolygonClipOwnedResultInternal owned) @safe
{
    return trySegmentPolygonClipP1BoundarySpecializedInternal(query,polygon,owned);
}
package(geo) SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!float query, scope Polygon2View!float polygon,
    out SegmentPolygonClipOwnedResultInternal owned) @safe
{
    return trySegmentPolygonClipP1BoundarySpecializedInternal(query,polygon,owned);
}
package(geo) SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!double query, scope Polygon2View!double polygon,
    out SegmentPolygonClipOwnedResultInternal owned) @safe
{
    return trySegmentPolygonClipP1BoundarySpecializedInternal(query,polygon,owned);
}
'''

BRIDGE_INTERFACE=r'''module geo.internal.segment_polygon_clip_p1_boundary_static_bridge;

import geo.internal.segment_polygon_clip_p1 :
    SegmentPolygonClipInternalStatus;
import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;
import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;

package(geo) SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!int, scope Polygon2View!int,
    out SegmentPolygonClipOwnedResultInternal) @safe;
package(geo) SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!long, scope Polygon2View!long,
    out SegmentPolygonClipOwnedResultInternal) @safe;
package(geo) SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!float, scope Polygon2View!float,
    out SegmentPolygonClipOwnedResultInternal) @safe;
package(geo) SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1BoundaryStaticInternal(
    Segment2!double, scope Polygon2View!double,
    out SegmentPolygonClipOwnedResultInternal) @safe;
'''

def git(*args):
    return subprocess.check_output(["git","-C",str(ROOT),*args],text=True).strip()

def capture(cmd,cwd):
    p=subprocess.run(cmd,cwd=cwd,text=True,capture_output=True)
    if p.returncode:
        raise RuntimeError("command failed: "+repr(cmd)+"\n"+p.stdout+p.stderr)
    return p.stdout

def compiler_kind(compiler):
    return "ldc" if Path(compiler).name.startswith("ldc") else "dmd"

def release_flags(compiler):
    flags=["-O3","-release"] if compiler_kind(compiler)=="ldc" else ["-O","-inline","-release"]
    flags.append("-boundscheck=safeonly")
    return flags

def imports(source_root,compiler):
    return capture(["python3",str(source_root/"tools/dub-import-paths.py"),
                    "--compiler="+compiler],source_root).splitlines()

def write_targeted_driver(source_root,outdir):
    source=(source_root/"benchmarks/segment_polygon_bench.d").read_text()
    marker="void main(string[] args)"
    if source.count(marker)!=1:
        raise RuntimeError("benchmark main changed")
    driver=outdir/"segment_polygon_targeted.d"
    driver.write_text(source[:source.index(marker)]+DRIVER_MAIN)
    return driver

def build_base(source_root,compiler_name,outdir):
    compiler=shutil.which(compiler_name)
    if not compiler:
        raise RuntimeError("compiler not found: "+compiler_name)
    imps=imports(source_root,compiler)
    flags=release_flags(compiler)
    driver=write_targeted_driver(source_root,outdir)
    binary=outdir/"benchmark"
    cmd=[compiler,"-i",*["-I"+p for p in imps],str(driver),*flags,
         "-of="+str(binary)]
    p=subprocess.run(cmd,cwd=outdir,text=True,capture_output=True)
    (outdir/"build.stdout").write_text(p.stdout)
    (outdir/"build.stderr").write_text(p.stderr)
    (outdir/"build.command.json").write_text(json.dumps(cmd,indent=2)+"\n")
    if p.returncode:
        raise RuntimeError("base build failed: "+p.stdout+p.stderr)
    return binary,capture([compiler,"--version"],source_root)

def patch_candidate_for_bridge(source_root):
    bridge=source_root/BRIDGE_PATH
    bridge_di=source_root/BRIDGE_DI_PATH
    bridge.write_text(BRIDGE_SOURCE)
    bridge_di.write_text(BRIDGE_INTERFACE)

    dispatcher_path=source_root/"source/geo/internal/segment_polygon_clip_p1_dispatch.d"
    dispatcher=dispatcher_path.read_text()
    old='''import geo.internal.segment_polygon_clip_p1_boundary_specialized :
    trySegmentPolygonClipP1BoundarySpecializedInternal;
'''
    new='''import geo.internal.segment_polygon_clip_p1_boundary_static_bridge :
    trySegmentPolygonClipP1BoundaryStaticInternal;
'''
    if old in dispatcher:
        dispatcher=dispatcher.replace(old,new)
        dispatcher=dispatcher.replace(
            "trySegmentPolygonClipP1BoundarySpecializedInternal(",
            "trySegmentPolygonClipP1BoundaryStaticInternal(")
        dispatcher_path.write_text(dispatcher)
    elif new in dispatcher:
        if "trySegmentPolygonClipP1BoundaryStaticInternal(" not in dispatcher:
            raise RuntimeError("dispatcher bridge import present but call anchor missing")
    else:
        raise RuntimeError("dispatcher specialized/static-bridge import anchor missing")

def build_candidate_static(source_root,compiler_name,outdir):
    compiler=shutil.which(compiler_name)
    if not compiler:
        raise RuntimeError("compiler not found: "+compiler_name)
    imps=imports(source_root,compiler)
    flags=release_flags(compiler)
    patch_candidate_for_bridge(source_root)

    special_obj=outdir/"boundary-specialized.o"
    special_cmd=[compiler,"-c",*["-I"+p for p in imps],
                 str(source_root/SPECIAL_PATH),*flags,"-of="+str(special_obj)]
    p=subprocess.run(special_cmd,cwd=outdir,text=True,capture_output=True)
    (outdir/"special-build.stdout").write_text(p.stdout)
    (outdir/"special-build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("special build failed: "+p.stdout+p.stderr)

    bridge_obj=outdir/"boundary-static-bridge.o"
    bridge_cmd=[compiler,"-c",*["-I"+p for p in imps],
                str(source_root/BRIDGE_PATH),*flags,"-of="+str(bridge_obj)]
    p=subprocess.run(bridge_cmd,cwd=outdir,text=True,capture_output=True)
    (outdir/"bridge-build.stdout").write_text(p.stdout)
    (outdir/"bridge-build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("bridge build failed: "+p.stdout+p.stderr)

    nm=shutil.which("nm")
    if not nm:
        raise RuntimeError("nm not found")
    bridge_symbols=capture([nm,"-S",str(bridge_obj)],outdir)
    if "trySegmentPolygonClipP1BoundarySpecializedInternal" not in bridge_symbols:
        raise RuntimeError("bridge object lacks specialized template instantiations")

    driver=write_targeted_driver(source_root,outdir)
    binary=outdir/"benchmark"
    cmd=[compiler,"-i","-i=-"+BRIDGE_MODULE,"-i=-"+SPECIAL_MODULE,
         *["-I"+p for p in imps],str(driver),*flags,
         str(bridge_obj),str(special_obj),"-of="+str(binary)]
    p=subprocess.run(cmd,cwd=outdir,text=True,capture_output=True)
    (outdir/"link.stdout").write_text(p.stdout)
    (outdir/"link.stderr").write_text(p.stderr)
    (outdir/"build.command.json").write_text(json.dumps(cmd,indent=2)+"\n")
    if p.returncode:
        raise RuntimeError("static candidate link failed: "+p.stdout+p.stderr)

    # Verify semantic correctness before timing.
    smoke=subprocess.run([str(binary),"double","boundary-only","1","2","1"],
                         cwd=outdir,text=True,capture_output=True)
    (outdir/"semantic-smoke.stdout").write_text(smoke.stdout)
    (outdir/"semantic-smoke.stderr").write_text(smoke.stderr)
    if smoke.returncode:
        raise RuntimeError("static candidate semantic smoke failed: "+
                           smoke.stdout+smoke.stderr)

    return binary,capture([compiler,"--version"],source_root)

def run_one(binary,outdir,scalar,case,rounds,target_ms):
    outdir.mkdir(parents=True,exist_ok=False)
    cmd=[str(binary),scalar,case,str(rounds),"0",str(target_ms)]
    (outdir/"command.json").write_text(json.dumps(cmd,indent=2)+"\n")
    stdout_path=outdir/"samples.stdout"
    stderr_path=outdir/"samples.stderr"
    with stdout_path.open("w") as so, stderr_path.open("w") as se:
        p=subprocess.run(cmd,cwd=outdir,text=True,stdout=so,stderr=se)
    if p.returncode:
        raise RuntimeError("measurement failed: "+str(outdir)+"\n"+
                           stdout_path.read_text()+stderr_path.read_text())
    return cmd

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base",required=True)
    ap.add_argument("--candidate",required=True)
    ap.add_argument("--cpu",type=int,default=0)
    ap.add_argument("--cycles",type=int,default=6)
    ap.add_argument("--rounds",type=int,default=7)
    ap.add_argument("--target-ms",type=int,default=50)
    ap.add_argument("--notes",default="")
    ap.add_argument("--output",type=Path)
    ap.add_argument("--compilers",default="dmd,ldc2")
    ap.add_argument("--scalars",default="int,long,float,double")
    ap.add_argument("--cases",default=",".join(CASES))
    a=ap.parse_args()

    allowed=os.sched_getaffinity(0)
    if a.cpu not in allowed:
        ap.error("CPU not allowed")
    os.sched_setaffinity(0,{a.cpu})

    compilers=[x for x in a.compilers.split(",") if x]
    scalars=[x for x in a.scalars.split(",") if x]
    cases=[x for x in a.cases.split(",") if x]
    allowed_compilers={"dmd","ldc2"}
    allowed_scalars={"int","long","float","double"}
    if not compilers or any(x not in allowed_compilers for x in compilers):
        ap.error("invalid --compilers")
    if not scalars or any(x not in allowed_scalars for x in scalars):
        ap.error("invalid --scalars")
    if not cases or any(x not in CASES for x in cases):
        ap.error("invalid --cases")

    rev={"base":git("rev-parse","--verify",a.base+"^{commit}"),
         "candidate":git("rev-parse","--verify",a.candidate+"^{commit}")}

    stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out=(a.output or ROOT/"build"/("second-boundary-static-abba-"+stamp)).resolve()
    out.mkdir(parents=True,exist_ok=False)

    record={"format":1,"status":"incomplete","purpose":"second-boundary-static-abi-abba",
            "revisions":rev,"cpu":a.cpu,"allowed_affinity":sorted(allowed),
            "cycles":a.cycles,"rounds":a.rounds,"target_ms":a.target_ms,
            "notes":a.notes,"cases":cases,"compilers":compilers,
            "scalars":scalars,"runs":[],"builds":[],
            "started_utc":datetime.now(timezone.utc).isoformat(),
            "limitations":["No frequency/turbo control imposed.",
                           "Binaries built once before timing.",
                           "relationship retained as same-binary control.",
                           "Candidate uses a static ABI bridge to control template placement."]}

    with tempfile.TemporaryDirectory(prefix="geo-d-second-boundary-static-") as tmp:
        wt={}; binaries={}
        try:
            for label,sha in rev.items():
                p=Path(tmp)/label
                git("worktree","add","--detach",str(p),sha)
                wt[label]=p

            for compiler in compilers:
                for label in ["base","candidate"]:
                    bd=out/"build"/compiler/label
                    bd.mkdir(parents=True,exist_ok=False)
                    if label=="base":
                        binary,version=build_base(wt[label],compiler,bd)
                    else:
                        binary,version=build_candidate_static(wt[label],compiler,bd)
                    binaries[(compiler,label)]=binary
                    record["builds"].append({
                        "compiler":compiler,"label":label,"revision":rev[label],
                        "compiler_version":version,
                        "binary_sha256":hashlib.sha256(binary.read_bytes()).hexdigest()
                    })

            for compiler in compilers:
                for label in ["base","candidate"]:
                    run_one(binaries[(compiler,label)],
                            out/"warmup"/compiler/label,
                            "double","boundary-only",3,20)
                for scalar in scalars:
                    for case in cases:
                        for cycle in range(a.cycles):
                            order=(["base","candidate","candidate","base"]
                                   if cycle%2==0 else
                                   ["candidate","base","base","candidate"])
                            for pos,label in enumerate(order):
                                name=f"{compiler}-{scalar}-{case}-c{cycle}-p{pos}-{label}"
                                print("[measure]",name,flush=True)
                                cmd=run_one(binaries[(compiler,label)],
                                            out/"runs"/name,scalar,case,
                                            a.rounds,a.target_ms)
                                record["runs"].append({
                                    "name":name,"compiler":compiler,"scalar":scalar,
                                    "case":case,"cycle":cycle,"position":pos,
                                    "label":label,"revision":rev[label],"command":cmd
                                })
                                (out/"comparison.json").write_text(
                                    json.dumps(record,indent=2)+"\n")
            record["status"]="passed"
        finally:
            for p in wt.values():
                git("worktree","remove","--force",str(p))
            record["finished_utc"]=datetime.now(timezone.utc).isoformat()
            (out/"comparison.json").write_text(json.dumps(record,indent=2)+"\n")

    print("comparison record:",out)

if __name__=="__main__":
    main()
