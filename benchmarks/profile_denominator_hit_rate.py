#!/usr/bin/env python3
"""Count equal/distinct exact-denominator branches in real clipping fixtures."""
import argparse, hashlib, json, os, re, shutil, subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DRIVER_MAIN = r'''
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
        writefln("profile_case,%s,%s,%s,%s", T.stringof, c.name, iterations, benchmarkSink);
        return;
    }
    enforce(false, "unknown profile case");
}

void main(string[] args)
{
    enforce(args.length == 4);
    const scalar = args[1];
    const caseName = args[2];
    const iterations = args[3].to!size_t;
    if (scalar == "int") profileOne!int(caseName, iterations);
    else if (scalar == "long") profileOne!long(caseName, iterations);
    else if (scalar == "float") profileOne!float(caseName, iterations);
    else if (scalar == "double") profileOne!double(caseName, iterations);
    else enforce(false, "unknown scalar");
}
'''

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cpu",type=int,default=0)
    ap.add_argument("--iterations",type=int,default=200)
    ap.add_argument("--output",type=Path)
    a=ap.parse_args()
    if not hasattr(os,"sched_getaffinity") or a.cpu not in os.sched_getaffinity(0):
        ap.error("--cpu must be an allowed Linux CPU")
    os.sched_setaffinity(0,{a.cpu})
    compiler=shutil.which("dmd")
    if not compiler: ap.error("dmd not found")
    def cap(cmd): return subprocess.check_output(cmd,cwd=ROOT,text=True)
    stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out=(a.output or ROOT/"build"/("denominator-hit-rate-"+stamp)).resolve()
    out.mkdir(parents=True,exist_ok=False)
    source=(ROOT/"benchmarks/segment_polygon_bench.d").read_text()
    marker="void main(string[] args)"
    if source.count(marker)!=1: raise RuntimeError("benchmark main changed")
    driver=out/"segment_polygon_bench.d"
    driver.write_text(source[:source.index(marker)]+DRIVER_MAIN)
    imports=cap(["python3",str(ROOT/"tools/dub-import-paths.py"),"--compiler="+compiler]).splitlines()
    binary=out/"profile"
    build=[compiler,"-O","-inline","-release","-boundscheck=safeonly","-profile","-i",
           *["-I"+p for p in imports],"-of="+str(binary),str(driver)]
    subprocess.run(build,cwd=out,check=True,capture_output=True,text=True)
    cases=["crossing","sparse-4","sparse-16","sparse-64","dense-4","dense-16","dense-64"]
    scalars=["int","long","float","double"]
    rows=[]
    for scalar in scalars:
        for case in cases:
            d=out/(scalar+"-"+case); d.mkdir()
            r=subprocess.run([str(binary),scalar,case,str(a.iterations)],cwd=d,
                             check=True,capture_output=True,text=True)
            (d/"stdout.txt").write_text(r.stdout)
            trace=(d/"trace.log").read_text()
            (d/"trace.log").write_text(trace)
            def calls(name):
                for line in trace.splitlines():
                    if name in line:
                        fields=line.split()
                        if fields and fields[0].isdigit(): return int(fields[0])
                return 0
            hit=calls("compareEqualDenominatorNumerators")
            miss=calls("compareDistinctDenominatorNumerators")
            total=hit+miss
            rows.append({"scalar":scalar,"case":case,"iterations":a.iterations,
                         "equal_hits":hit,"distinct_misses":miss,"total":total,
                         "equal_rate": hit/total if total else None,
                         "avoided_cross_products":2*hit,
                         "executed_cross_products":2*miss})
    record={"format":1,"purpose":"exact-denominator-hit-rate","status":"passed",
            "commit":cap(["git","rev-parse","HEAD"]).strip(),
            "tree":cap(["git","rev-parse","HEAD^{tree}"]).strip(),
            "dirty":bool(cap(["git","status","--porcelain","--","source","benchmarks","tools"])),
            "compiler_version":cap([compiler,"--version"]),"cpu":a.cpu,
            "iterations":a.iterations,
            "driver_sha256":hashlib.sha256(driver.read_bytes()).hexdigest(),
            "rows":rows,
            "limitations":["DMD -profile changes code generation and runtime cost; counts are mechanism evidence only.",
                           "Each process includes one two-direction semantic preflight before the repeated clipping calls.",
                           "No profiler ticks are interpreted as latency."]}
    (out/"hit-rate.json").write_text(json.dumps(record,indent=2)+"\n")
    print(json.dumps(rows,indent=2))
    print("record:",out)

if __name__=="__main__": main()
