#!/usr/bin/env python3
import argparse, hashlib, json, os, shutil, subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/"benchmarks"/"valid_ring_winding_probe.d"

def cap(cmd,cwd=ROOT):
    p=subprocess.run(cmd,cwd=cwd,text=True,capture_output=True)
    if p.returncode:
        raise RuntimeError("command failed: "+repr(cmd)+"\n"+p.stdout+p.stderr)
    return p.stdout

def build(name,out):
    cc=shutil.which(name)
    if not cc: raise RuntimeError("missing compiler: "+name)
    imports=cap(["python3",str(ROOT/"tools"/"dub-import-paths.py"),"--compiler="+cc]).splitlines()
    flags=["-O3","-release","-boundscheck=safeonly"] if Path(cc).name.startswith("ldc") else ["-O","-inline","-release","-boundscheck=safeonly"]
    binary=out/("winding-"+name)
    cmd=[cc,"-i",*["-I"+x for x in imports],str(SRC),*flags,"-of="+str(binary)]
    p=subprocess.run(cmd,cwd=out,text=True,capture_output=True)
    (out/(name+".build.stdout")).write_text(p.stdout)
    (out/(name+".build.stderr")).write_text(p.stderr)
    if p.returncode: raise RuntimeError("build failed\n"+p.stdout+p.stderr)
    return binary,cap([cc,"--version"])

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--compiler",action="append",choices=["dmd","ldc2"])
    ap.add_argument("--cpu",type=int,default=0)
    ap.add_argument("--rounds",type=int,default=7)
    ap.add_argument("--iterations",type=int,default=1000)
    ap.add_argument("--notes",default="")
    ap.add_argument("--allow-dirty",action="store_true")
    ap.add_argument("--output",type=Path)
    a=ap.parse_args()
    if a.cpu not in os.sched_getaffinity(0): ap.error("CPU not allowed")
    os.sched_setaffinity(0,{a.cpu})
    head=cap(["git","rev-parse","HEAD"]).strip()
    branch=cap(["git","branch","--show-current"]).strip()
    dirty_lines=cap([
        "git","status","--porcelain","--untracked-files=normal","--",
        "source","benchmarks",".github/workflows"
    ]).splitlines()
    if dirty_lines and not a.allow_dirty:
        raise RuntimeError("research source is dirty:\n"+"\n".join(dirty_lines))
    stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out=(a.output or ROOT/"build"/("valid-ring-winding-"+stamp)).resolve()
    out.mkdir(parents=True,exist_ok=False)
    rec={
        "format":1,
        "status":"incomplete",
        "purpose":"valid-ring-winding-mechanism-comparison",
        "head":head,
        "branch":branch,
        "dirty":bool(dirty_lines),
        "dirty_lines":dirty_lines,
        "cpu":a.cpu,
        "allowed_affinity":sorted(os.sched_getaffinity(0)),
        "rounds":a.rounds,
        "iterations":a.iterations,
        "notes":a.notes,
        "started_utc":datetime.now(timezone.utc).isoformat(),
        "builds":[],
        "runs":[],
        "limitations":[
            "Mechanism microbenchmark only; production promotion requires independent end-to-end ABBA.",
            "No CPU frequency/turbo control is imposed by this runner."
        ]
    }
    compilers=a.compiler or ["dmd","ldc2"]
    try:
        for comp in compilers:
            b,ver=build(comp,out)
            rec["builds"].append({
                "compiler":comp,
                "version":ver,
                "sha256":hashlib.sha256(b.read_bytes()).hexdigest()
            })
            smoke=subprocess.run([str(b)],cwd=out,text=True,capture_output=True)
            (out/(comp+".equivalence.stdout")).write_text(smoke.stdout)
            (out/(comp+".equivalence.stderr")).write_text(smoke.stderr)
            if smoke.returncode: raise RuntimeError("equivalence failed "+comp+"\n"+smoke.stdout+smoke.stderr)
            for scalar in ["int","long","float","double"]:
                for sub in [1,4,16,64,256]:
                    p=subprocess.run([str(b),scalar,str(sub),str(a.rounds),str(a.iterations)],cwd=out,text=True,capture_output=True)
                    name=f"{comp}-{scalar}-sparse-{sub}"
                    (out/(name+".stdout")).write_text(p.stdout)
                    (out/(name+".stderr")).write_text(p.stderr)
                    if p.returncode: raise RuntimeError("run failed "+name+"\n"+p.stdout+p.stderr)
                    rec["runs"].append({"compiler":comp,"scalar":scalar,"subdivisions":sub,"stdout":name+".stdout"})
                    (out/"record.json").write_text(json.dumps(rec,indent=2)+"\n")
        rec["status"]="passed"
    finally:
        rec["finished_utc"]=datetime.now(timezone.utc).isoformat()
        (out/"record.json").write_text(json.dumps(rec,indent=2)+"\n")
    print("record:",out)
if __name__=="__main__": main()
