#!/usr/bin/env python3
"""Prebuild immutable targeted binaries, then run tightly interleaved ABBA measurements."""

import argparse, hashlib, json, os, shutil, subprocess, tempfile, time
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

DRIVER_MAIN=r'''
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

def git(*args):
    return subprocess.check_output(["git","-C",str(ROOT),*args],text=True).strip()

def capture(cmd,cwd):
    p=subprocess.run(cmd,cwd=cwd,text=True,capture_output=True)
    if p.returncode:
        raise RuntimeError("command failed: "+repr(cmd)+"\n"+p.stdout+p.stderr)
    return p.stdout

def build_binary(source_root, compiler_name, outdir):
    compiler=shutil.which(compiler_name)
    if not compiler:
        raise RuntimeError("compiler not found: "+compiler_name)
    source=(source_root/"benchmarks/segment_polygon_bench.d").read_text()
    marker="void main(string[] args)"
    if source.count(marker)!=1:
        raise RuntimeError("benchmark main changed")
    driver=outdir/"segment_polygon_targeted.d"
    driver.write_text(source[:source.index(marker)]+DRIVER_MAIN)
    imports=capture(
        ["python3",str(source_root/"tools/dub-import-paths.py"),"--compiler="+compiler],
        source_root
    ).splitlines()
    binary=outdir/"benchmark"
    kind="ldc" if Path(compiler).name.startswith("ldc") else "dmd"
    release=["-O3","-release"] if kind=="ldc" else ["-O","-inline","-release"]
    release.append("-boundscheck=safeonly")
    cmd=[compiler,"-i",*["-I"+p for p in imports],str(driver),*release,"-of="+str(binary)]
    p=subprocess.run(cmd,cwd=outdir,text=True,capture_output=True)
    (outdir/"build.stdout").write_text(p.stdout)
    (outdir/"build.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("build failed: "+str(outdir))
    return binary, capture([compiler,"--version"],source_root)

def run_one(binary,outdir,scalar,case,rounds,target_ms):
    outdir.mkdir(parents=True,exist_ok=False)
    cmd=[str(binary),scalar,case,str(rounds),"0",str(target_ms)]
    p=subprocess.run(cmd,cwd=outdir,text=True,capture_output=True)
    (outdir/"samples.stdout").write_text(p.stdout)
    (outdir/"samples.stderr").write_text(p.stderr)
    if p.returncode:
        raise RuntimeError("measurement failed: "+str(outdir))
    return cmd

def thermal_snapshot(cpu):
    base = Path(f"/sys/devices/system/cpu/cpu{cpu}/thermal_throttle")
    def read(name):
        path = base / name
        try:
            return int(path.read_text().strip())
        except (FileNotFoundError, ValueError):
            return None
    temps = []
    for path in sorted(Path("/sys/class/thermal").glob("thermal_zone*/temp")):
        try:
            temps.append(int(path.read_text().strip()))
        except (FileNotFoundError, ValueError):
            pass
    return {
        "utc": datetime.now(timezone.utc).isoformat(),
        "cpu": cpu,
        "thermal_zone_temps": temps,
        "core_throttle_count": read("core_throttle_count"),
        "package_throttle_count": read("package_throttle_count"),
    }

def thermal_delta(before, after):
    deltas = {}
    for key in ("core_throttle_count", "package_throttle_count"):
        if before.get(key) is not None and after.get(key) is not None:
            deltas[key] = after[key] - before[key]
    return deltas

def cooldown(seconds):
    if seconds > 0:
        print(f"[cooldown] {seconds}s", flush=True)
        time.sleep(seconds)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base",default="4828889625ff2dd25b44dc545a5e9addb27310ef")
    ap.add_argument("--candidate",default="5fe9abcece98ad8c8d0c29d97c9aa28591d20bcc")
    ap.add_argument("--cpu",type=int,default=0)
    ap.add_argument("--cycles",type=int,default=3)
    ap.add_argument("--rounds",type=int,default=7)
    ap.add_argument("--target-ms",type=int,default=50)
    ap.add_argument("--output",type=Path)
    ap.add_argument("--cooldown-seconds",type=int,default=0)
    ap.add_argument("--scalars",default="int,long,float,double")
    ap.add_argument("--cases",default="exterior,crossing,sparse-4,sparse-16,sparse-64,dense-64,degenerate-interior,empty")
    ap.add_argument("--compilers",default="dmd,ldc2")
    a=ap.parse_args()

    if a.cpu not in os.sched_getaffinity(0):
        ap.error("CPU not allowed")
    os.sched_setaffinity(0,{a.cpu})

    rev={"base":git("rev-parse","--verify",a.base+"^{commit}"),
         "candidate":git("rev-parse","--verify",a.candidate+"^{commit}")}

    stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out=(a.output or ROOT/"build"/("limb67-prebuilt-abba-"+stamp)).resolve()
    out.mkdir(parents=True,exist_ok=False)

    record={"format":2,"status":"incomplete","purpose":"prebuilt-targeted-abba",
            "revisions":rev,"cpu":a.cpu,"cycles":a.cycles,"rounds":a.rounds,
            "target_ms":a.target_ms,"runs":[],"builds":[],
            "cooldown_seconds":a.cooldown_seconds,
            "thermal_gate":"pending","thermal_blocks":[],
            "limitations":["No frequency/turbo control imposed.",
                           "Binaries are built once before timing; compilation heat is excluded from ABBA interleaving.",
                           "relationship is retained as a same-binary control."]}

    with tempfile.TemporaryDirectory(prefix="geo-d-limb67-prebuilt-") as tmp:
        wt={}
        binaries={}
        try:
            for label,sha in rev.items():
                print(f"[worktree] {label} {sha[:8]}", flush=True)
                p=Path(tmp)/label
                git("worktree","add","--detach",str(p),sha)
                wt[label]=p

            compilers=[x for x in a.compilers.split(",") if x]
            scalars=[x for x in a.scalars.split(",") if x]
            cases=[x for x in a.cases.split(",") if x]
            for compiler in compilers:
                for label in ["base","candidate"]:
                    print(f"[build] {compiler} {label}", flush=True)
                    bd=out/"build"/compiler/label
                    bd.mkdir(parents=True,exist_ok=False)
                    binary,version=build_binary(wt[label],compiler,bd)
                    binaries[(compiler,label)]=binary
                    record["builds"].append({
                        "compiler":compiler,"label":label,"revision":rev[label],
                        "compiler_version":version,
                        "binary_sha256":hashlib.sha256(binary.read_bytes()).hexdigest()
                    })

            targets=[(s,c) for s in scalars for c in cases]

            for compiler in compilers:
                # Warm both immutable binaries before any recorded pair.
                for label in ["base","candidate"]:
                    print(f"[warmup] {compiler} {label}", flush=True)
                    warm=out/"warmup"/compiler/label
                    run_one(binaries[(compiler,label)],warm,"int","sparse-1",3,20)

                for scalar,case in targets:
                    for cycle in range(a.cycles):
                        cooldown(a.cooldown_seconds)
                        thermal_before = thermal_snapshot(a.cpu)
                        order=["base","candidate","candidate","base"] if cycle%2==0 else ["candidate","base","base","candidate"]
                        for pos,label in enumerate(order):
                            name=f"{compiler}-{scalar}-{case}-c{cycle}-p{pos}-{label}"
                            print(f"[measure] {name}", flush=True)
                            dest=out/"runs"/name
                            cmd=run_one(
                                binaries[(compiler,label)],dest,
                                scalar,case,a.rounds,a.target_ms
                            )
                            record["runs"].append({
                                "name":name,"compiler":compiler,"scalar":scalar,
                                "case":case,"cycle":cycle,"position":pos,
                                "label":label,"revision":rev[label],"command":cmd
                            })
                            (out/"comparison.json").write_text(json.dumps(record,indent=2)+"\n")
                        thermal_after = thermal_snapshot(a.cpu)
                        deltas = thermal_delta(thermal_before, thermal_after)
                        record["thermal_blocks"].append({
                            "compiler":compiler,"scalar":scalar,"case":case,
                            "cycle":cycle,"before":thermal_before,
                            "after":thermal_after,"deltas":deltas,
                            "valid":all(value == 0 for value in deltas.values())
                        })
                        if any(value > 0 for value in deltas.values()):
                            record["thermal_gate"]="failed"
                        (out/"comparison.json").write_text(json.dumps(record,indent=2)+"\n")
            if record["thermal_gate"] == "failed":
                record["status"]="invalid-thermal"
            else:
                record["thermal_gate"]="passed"
                record["status"]="passed"
        finally:
            for p in wt.values():
                git("worktree","remove","--force",str(p))
            record["finished_utc"]=datetime.now(timezone.utc).isoformat()
            (out/"comparison.json").write_text(json.dumps(record,indent=2)+"\n")

    print("comparison record:",out)

if __name__=="__main__":
    main()
