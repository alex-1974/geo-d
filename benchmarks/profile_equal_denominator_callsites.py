#!/usr/bin/env python3
"""Profile denominator equality by exact-overlay comparator call site."""

import argparse, json, os, shutil, subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

DRIVER_MAIN=r'''
private void profileOne(T)(string caseName, size_t iterations)
{
    auto cases = corpus!T();
    foreach (ref c; cases)
    {
        if (c.name != caseName) continue;
        preflight(c);
        ulong sink;
        foreach (i; 0 .. iterations)
            sink = sink * 1_000_033UL + clipping(c, i);
        benchmarkSink = sink;
        writefln("profile_case,%s,%s,%s,%s",
            T.stringof, c.name, iterations, benchmarkSink);
        return;
    }
    enforce(false, "unknown profile case");
}

void main(string[] args)
{
    enforce(args.length == 4);
    const scalar=args[1];
    const caseName=args[2];
    const iterations=args[3].to!size_t;
    if (scalar=="int") profileOne!int(caseName,iterations);
    else if (scalar=="long") profileOne!long(caseName,iterations);
    else if (scalar=="float") profileOne!float(caseName,iterations);
    else if (scalar=="double") profileOne!double(caseName,iterations);
    else enforce(false,"unknown scalar");
}
'''

HELPERS={
 "overlay_x_equal":"overlayXEqual",
 "overlay_x_distinct":"overlayXDistinct",
 "overlay_y_equal":"overlayYEqual",
 "overlay_y_distinct":"overlayYDistinct",
 "along_x_equal":"alongXEqual",
 "along_x_distinct":"alongXDistinct",
 "along_y_equal":"alongYEqual",
 "along_y_distinct":"alongYDistinct",
}

def capture(cmd,cwd=ROOT):
    return subprocess.check_output(cmd,cwd=cwd,text=True)

def trace_calls(path,needle):
    for line in path.read_text().splitlines():
        if needle in line:
            fields=line.split()
            if fields and fields[0].isdigit(): return int(fields[0])
    return 0

def run(binary,cwd,scalar,case,iters):
    cwd.mkdir()
    subprocess.run([str(binary),scalar,case,str(iters)],cwd=cwd,check=True,
                   stdout=(cwd/"stdout.txt").open("w"),
                   stderr=(cwd/"stderr.txt").open("w"))
    trace=cwd/"trace.log"
    if not trace.is_file(): raise RuntimeError("missing trace.log")
    return {k:trace_calls(trace,v) for k,v in HELPERS.items()}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--cpu",type=int,default=0)
    ap.add_argument("--iterations",type=int,default=200)
    ap.add_argument("--output",type=Path)
    a=ap.parse_args()
    if a.cpu not in os.sched_getaffinity(0): ap.error("CPU not allowed")
    os.sched_setaffinity(0,{a.cpu})
    dmd=shutil.which("dmd")
    if not dmd: ap.error("dmd not found")
    out=(a.output or ROOT/"build"/("callsite-rates-"+datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))).resolve()
    out.mkdir(parents=True)
    src=(ROOT/"benchmarks/segment_polygon_bench.d").read_text()
    marker="void main(string[] args)"
    driver=out/"segment_polygon_bench.d"
    driver.write_text(src[:src.index(marker)]+DRIVER_MAIN)
    imports=capture(["python3",str(ROOT/"tools/dub-import-paths.py"),"--compiler="+dmd]).splitlines()
    binary=out/"profile"
    subprocess.run([dmd,"-O","-inline","-release","-boundscheck=safeonly","-profile","-i",
                    *["-I"+p for p in imports],"-of="+str(binary),str(driver)],
                   cwd=out,check=True)
    rows=[]
    for scalar in ["int","long","float","double"]:
        for case in ["crossing","sparse-4","sparse-16","sparse-64","dense-4","dense-16","dense-64"]:
            base=run(binary,out/f"{scalar}-{case}-base",scalar,case,0)
            meas=run(binary,out/f"{scalar}-{case}-measured",scalar,case,a.iterations)
            counts={k:meas[k]-base[k] for k in HELPERS}
            row={"scalar":scalar,"case":case,**counts}
            for prefix in ["overlay_x","overlay_y","along_x","along_y"]:
                e=counts[prefix+"_equal"]; d=counts[prefix+"_distinct"]; t=e+d
                row[prefix+"_equal_rate"]=e/t if t else None
            rows.append(row)
    rec={"status":"passed","commit":capture(["git","rev-parse","HEAD"]).strip(),
         "dirty":bool(capture(["git","status","--porcelain","--","source","benchmarks","tools"])),
         "compiler":capture([dmd,"--version"]),"cpu":a.cpu,"iterations":a.iterations,
         "rows":rows,
         "limitations":["DMD -profile is mechanism evidence only; not latency evidence.",
                        "A zero-iteration process is subtracted per scalar/fixture to remove preflight calls."]}
    (out/"callsite-rates.json").write_text(json.dumps(rec,indent=2)+"\n")
    print(json.dumps(rows,indent=2))
    print("record:",out)

if __name__=="__main__": main()
