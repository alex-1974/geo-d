#!/usr/bin/env python3
"""Tightly interleaved ABBA comparison for sparse clipping cases."""

import argparse, hashlib, json, math, os
from datetime import datetime, timezone
from pathlib import Path
import shutil, subprocess, tempfile

ROOT=Path(__file__).resolve().parents[1]

def git(*args):
    return subprocess.check_output(["git","-C",str(ROOT),*args],text=True).strip()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base",default="4828889625ff2dd25b44dc545a5e9addb27310ef")
    ap.add_argument("--candidate",default="5fe9abcece98ad8c8d0c29d97c9aa28591d20bcc")
    ap.add_argument("--cpu",type=int,default=0)
    ap.add_argument("--cycles",type=int,default=3)
    ap.add_argument("--rounds",type=int,default=9)
    ap.add_argument("--target-ms",type=int,default=30)
    ap.add_argument("--output",type=Path)
    a=ap.parse_args()
    if a.cpu not in os.sched_getaffinity(0): ap.error("CPU not allowed")
    runner=ROOT/"benchmarks/run_segment_polygon_targeted.py"
    rev={"base":git("rev-parse","--verify",a.base+"^{commit}"),
         "candidate":git("rev-parse","--verify",a.candidate+"^{commit}")}
    out=(a.output or ROOT/"build"/("limb67-targeted-"+datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))).resolve()
    out.mkdir(parents=True,exist_ok=False)
    record={"format":1,"status":"incomplete","purpose":"targeted-abba",
            "revisions":rev,"cpu":a.cpu,"cycles":a.cycles,"rounds":a.rounds,
            "target_ms":a.target_ms,"runner_sha256":hashlib.sha256(runner.read_bytes()).hexdigest(),
            "runs":[]}
    with tempfile.TemporaryDirectory(prefix="geo-d-limb67-targeted-") as tmp:
        wt={}
        try:
            for label,sha in rev.items():
                p=Path(tmp)/label
                git("worktree","add","--detach",str(p),sha)
                wt[label]=p
            targets=[(s,c) for s in ["int","long","float","double"]
                     for c in ["sparse-1","sparse-4","sparse-16","sparse-64","dense-64"]]
            for compiler in ["dmd","ldc2"]:
                for scalar,case in targets:
                    for cycle in range(a.cycles):
                        order=["base","candidate","candidate","base"] if cycle%2==0 else ["candidate","base","base","candidate"]
                        for pos,label in enumerate(order):
                            name=f"{compiler}-{scalar}-{case}-c{cycle}-p{pos}-{label}"
                            cmd=["python3",str(runner),"--source-root="+str(wt[label]),
                                 "--compiler="+compiler,"--cpu="+str(a.cpu),
                                 "--scalar="+scalar,"--case="+case,
                                 "--rounds="+str(a.rounds),"--target-ms="+str(a.target_ms),
                                 "--output="+str(out/name)]
                            print(name,flush=True)
                            res=subprocess.run(cmd,cwd=wt[label])
                            record["runs"].append({"name":name,"compiler":compiler,"scalar":scalar,
                                "case":case,"cycle":cycle,"position":pos,"label":label,
                                "revision":rev[label],"returncode":res.returncode})
                            (out/"comparison.json").write_text(json.dumps(record,indent=2)+"\n")
                            if res.returncode: raise RuntimeError(name+" failed")
            record["status"]="passed"
        finally:
            for p in wt.values(): git("worktree","remove","--force",str(p))
            record["finished_utc"]=datetime.now(timezone.utc).isoformat()
            (out/"comparison.json").write_text(json.dumps(record,indent=2)+"\n")
    print("comparison record:",out)

if __name__=="__main__": main()
