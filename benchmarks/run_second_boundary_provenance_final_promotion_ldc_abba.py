#!/usr/bin/env python3
"""Final promotion confirmation for selected LDC long/float segment-polygon cases."""

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

PAIRS=[
    ("long","boundary-only"),
    ("long","boundary-overlap"),
    ("long","rational-crossing"),
    ("long","hole"),
    ("float","boundary-only"),
    ("float","boundary-overlap"),
    ("float","concave-u"),
    ("float","sparse-64"),
]

def git(*args):
    return subprocess.check_output(["git","-C",str(ROOT),*args],text=True).strip()

def capture(cmd,cwd):
    p=subprocess.run(cmd,cwd=cwd,text=True,capture_output=True)
    if p.returncode:
        raise RuntimeError("command failed: "+repr(cmd)+"\n"+p.stdout+p.stderr)
    return p.stdout

def build_binary(source_root,compiler_name,outdir):
    compiler=shutil.which(compiler_name)
    if not compiler:
        raise RuntimeError("compiler not found: "+compiler_name)
    source=(source_root/"benchmarks/segment_polygon_bench.d").read_text()
    marker="void main(string[] args)"
    if source.count(marker)!=1:
        raise RuntimeError("benchmark main changed")
    driver=outdir/"segment_polygon_targeted.d"
    driver.write_text(source[:source.index(marker)]+DRIVER_MAIN)
    imports=capture(["python3",str(source_root/"tools/dub-import-paths.py"),
                     "--compiler="+compiler],source_root).splitlines()
    binary=outdir/"benchmark"
    kind="ldc" if Path(compiler).name.startswith("ldc") else "dmd"
    flags=["-O3","-release"] if kind=="ldc" else ["-O","-inline","-release"]
    flags.append("-boundscheck=safeonly")
    cmd=[compiler,"-i",*["-I"+p for p in imports],str(driver),*flags,
         "-of="+str(binary)]
    p=subprocess.run(cmd,cwd=outdir,text=True,capture_output=True)
    (outdir/"build.stdout").write_text(p.stdout)
    (outdir/"build.stderr").write_text(p.stderr)
    (outdir/"build.command.json").write_text(json.dumps(cmd,indent=2)+"\n")
    if p.returncode:
        raise RuntimeError("build failed: "+str(outdir)+"\n"+p.stdout+p.stderr)
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
    a=ap.parse_args()

    allowed=os.sched_getaffinity(0)
    if a.cpu not in allowed:
        ap.error("CPU not allowed")
    os.sched_setaffinity(0,{a.cpu})

    rev={"base":git("rev-parse","--verify",a.base+"^{commit}"),
         "candidate":git("rev-parse","--verify",a.candidate+"^{commit}")}

    stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out=(a.output or ROOT/"build"/("second-boundary-provenance-final-promotion-ldc-abba-"+stamp)).resolve()
    out.mkdir(parents=True,exist_ok=False)

    record={"format":1,"status":"incomplete","purpose":"second-boundary-provenance-final-promotion-ldc-abba",
            "revisions":rev,"cpu":a.cpu,"allowed_affinity":sorted(allowed),
            "cycles":a.cycles,"rounds":a.rounds,"target_ms":a.target_ms,
            "notes":a.notes,"pairs":[{"scalar":x,"case":y} for x,y in PAIRS],"runs":[],"builds":[],
            "started_utc":datetime.now(timezone.utc).isoformat(),
            "limitations":["No frequency/turbo control imposed.",
                           "Binaries built once before timing.",
                           "relationship retained as same-binary control."]}

    with tempfile.TemporaryDirectory(prefix="geo-d-small-boundary-contact-") as tmp:
        wt={}; binaries={}
        try:
            for label,sha in rev.items():
                p=Path(tmp)/label
                git("worktree","add","--detach",str(p),sha)
                wt[label]=p
            for compiler in ["ldc2"]:
                for label in ["base","candidate"]:
                    bd=out/"build"/compiler/label
                    bd.mkdir(parents=True,exist_ok=False)
                    binary,version=build_binary(wt[label],compiler,bd)
                    binaries[(compiler,label)]=binary
                    record["builds"].append({
                        "compiler":compiler,"label":label,"revision":rev[label],
                        "compiler_version":version,
                        "binary_sha256":hashlib.sha256(binary.read_bytes()).hexdigest()
                    })
            for compiler in ["ldc2"]:
                for label in ["base","candidate"]:
                    run_one(binaries[(compiler,label)],
                            out/"warmup"/compiler/label,
                            "long","boundary-only",3,20)
                for scalar,case in PAIRS:
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
