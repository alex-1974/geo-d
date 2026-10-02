#!/usr/bin/env python3
"""Targeted immutable segment/polygon measurement for one scalar/fixture."""

import argparse
from datetime import datetime, timezone
import hashlib, json, os
from pathlib import Path
import platform, shutil, subprocess

ROOT = Path(__file__).resolve().parents[1]
HARNESS = Path(__file__).resolve()

DRIVER_MAIN = r'''
private void runSelected(T)(
    string caseName,
    size_t rounds,
    size_t iterations,
    long target
)
{
    auto cases = corpus!T();

    foreach (ref c; cases)
    {
        if (c.name != caseName)
            continue;

        preflight(c);
        writefln("fixture,%s,%s,%s,%s,%s,%s", T.stringof, c.name,
            c.edges, c.expectedFacts, c.expectedStatus, c.expected.length);

        measure!(relationship!T)(
            c, "relationship", rounds, iterations, target);
        measure!(clipping!T)(
            c, "clipping", rounds, iterations, target);
        return;
    }

    enforce(false, "unknown case");
}

void main(string[] args)
{
    enforce(args.length == 6);

    const scalar = args[1];
    const caseName = args[2];
    const rounds = args[3].to!size_t;
    const iterations = args[4].to!size_t;
    const target = args[5].to!long;

    writeln("fixture_header,scalar,case,edges,expected_fact_bits,expected_status,expected_components");
    writeln("sample_header,scalar,case,operation,edges,expected_components,round,iterations,warmup,elapsed_ns,gc_bytes,gc_collections");
    writeln("summary_header,scalar,case,operation,min_ns_per_op,median_ns_per_op,max_ns_per_op");

    if (scalar == "int")
        runSelected!int(caseName, rounds, iterations, target);
    else if (scalar == "long")
        runSelected!long(caseName, rounds, iterations, target);
    else if (scalar == "float")
        runSelected!float(caseName, rounds, iterations, target);
    else if (scalar == "double")
        runSelected!double(caseName, rounds, iterations, target);
    else
        enforce(false, "unknown scalar");

    writefln("sink,%s", benchmarkSink);
}
'''

def capture(args, cwd):
    p=subprocess.run(args,cwd=cwd,text=True,capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stdout+p.stderr)
    return p.stdout

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source-root",type=Path,required=True)
    ap.add_argument("--compiler",choices=["dmd","ldc2"],required=True)
    ap.add_argument("--cpu",type=int,required=True)
    ap.add_argument("--scalar",choices=["int","long","float","double"],required=True)
    ap.add_argument("--case",required=True)
    ap.add_argument("--rounds",type=int,default=9)
    ap.add_argument("--iterations",type=int,default=0)
    ap.add_argument("--target-ms",type=int,default=30)
    ap.add_argument("--output",type=Path,required=True)
    args=ap.parse_args()

    root=args.source_root.resolve()
    if args.cpu not in os.sched_getaffinity(0):
        ap.error("CPU not allowed")
    os.sched_setaffinity(0,{args.cpu})
    compiler=shutil.which(args.compiler)
    if not compiler:
        ap.error("compiler not found")

    out=args.output.resolve()
    out.mkdir(parents=True,exist_ok=False)

    source=(root/"benchmarks/segment_polygon_bench.d").read_text()
    marker="void main(string[] args)"
    if source.count(marker)!=1:
        raise RuntimeError("benchmark main changed")
    driver=out/"segment_polygon_targeted.d"
    driver.write_text(source[:source.index(marker)] + DRIVER_MAIN)

    imports=capture(["python3",str(root/"tools/dub-import-paths.py"),"--compiler="+compiler],root).splitlines()
    binary=out/"benchmark"
    kind="ldc" if Path(compiler).name.startswith("ldc") else "dmd"
    release=["-O3","-release"] if kind=="ldc" else ["-O","-inline","-release"]
    release.append("-boundscheck=safeonly")
    cmd=[compiler,"-i",*["-I"+p for p in imports],str(driver),*release,"-of="+str(binary)]
    b=subprocess.run(cmd,cwd=out,text=True,capture_output=True,check=True)
    (out/"build.stdout").write_text(b.stdout); (out/"build.stderr").write_text(b.stderr)

    run=[str(binary),args.scalar,args.case,str(args.rounds),str(args.iterations),str(args.target_ms)]
    r=subprocess.run(run,cwd=out,text=True,capture_output=True,check=True)
    (out/"samples.stdout").write_text(r.stdout); (out/"samples.stderr").write_text(r.stderr)

    meta={
      "format":1,"status":"passed","purpose":"targeted-comparison",
      "commit":capture(["git","rev-parse","HEAD"],root).strip(),
      "tree":capture(["git","rev-parse","HEAD^{tree}"],root).strip(),
      "dirty":bool(capture(["git","status","--porcelain","--","source","benchmarks","tools"],root)),
      "compiler_version":capture([compiler,"--version"],root),
      "cpu":args.cpu,"scalar":args.scalar,"case":args.case,
      "rounds":args.rounds,"iterations":args.iterations,"target_ms":args.target_ms,
      "driver_sha256":hashlib.sha256(driver.read_bytes()).hexdigest(),
      "source_benchmark_sha256":hashlib.sha256(source.encode()).hexdigest(),
      "limitations":["No frequency/turbo control imposed.","relationship is retained as a same-process control."]
    }
    (out/"metadata.json").write_text(json.dumps(meta,indent=2)+"\n")

if __name__=="__main__":
    main()
