#!/usr/bin/env python3
"""Factor probe for #165: helper argument liveness vs goto CFG effect."""

import argparse, hashlib, json, re, shutil, subprocess, tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

CALL_BLOCK='''        applySmallBoundaryProvenanceSecondPass(
            query,
            queryBounds,
            polygon,
            edgeFirstRawEventPlusOne,
            rawToUnique,
            events[],
            boundaryStarts[],
            boundaryEnds[],
            afterLocation[]
        );

        goto afterSmallBoundaryProvenanceSecondPass;
'''
NOARG_BLOCK='''        smallBoundaryCodegenProbe();

        goto afterSmallBoundaryProvenanceSecondPass;
'''
REFARGS_BLOCK='''        applySmallBoundaryProvenanceSecondPass(
            query,
            queryBounds,
            polygon,
            edgeFirstRawEventPlusOne,
            rawToUnique,
            events,
            boundaryStarts,
            boundaryEnds,
            afterLocation
        );

        goto afterSmallBoundaryProvenanceSecondPass;
'''

HELPER_SIGNATURE='''private void applySmallBoundaryProvenanceSecondPass(T)(
    Segment2!T query,
    Bounds2!T queryBounds,
    scope Polygon2View!T polygon,
    scope const(size_t)[] edgeFirstRawEventPlusOne,
    scope const(size_t)[] rawToUnique,
    scope const(ExactOverlayPoint)[] events,
    scope size_t[] boundaryStarts,
    scope size_t[] boundaryEnds,
    scope IntervalLocation[] afterLocation
)
'''

HELPER_REF_SIGNATURE='''private void applySmallBoundaryProvenanceSecondPass(T)(
    scope ref Segment2!T query,
    scope ref Bounds2!T queryBounds,
    scope ref Polygon2View!T polygon,
    scope ref size_t[] edgeFirstRawEventPlusOne,
    scope ref size_t[] rawToUnique,
    scope ref ExactOverlayPoint[] events,
    scope ref size_t[] boundaryStarts,
    scope ref size_t[] boundaryEnds,
    scope ref IntervalLocation[] afterLocation
)
'''

PROBE_DEF='''
__gshared size_t smallBoundaryCodegenProbeSink;

pragma(inline, false)
private void smallBoundaryCodegenProbe()
    nothrow @trusted @nogc
{
    ++smallBoundaryCodegenProbeSink;
}


'''
CONTEXT_BLOCK='''        SmallBoundaryCodegenContext!T context =
            SmallBoundaryCodegenContext!T(
                query,
                queryBounds,
                polygon,
                edgeFirstRawEventPlusOne,
                rawToUnique,
                events[],
                boundaryStarts[],
                boundaryEnds[],
                afterLocation[]
            );

        applySmallBoundaryProvenanceSecondPassViaContext(
            context
        );

        goto afterSmallBoundaryProvenanceSecondPass;
'''

NESTED_BLOCK='''        pragma(inline, false)
        void applySmallBoundaryProvenanceSecondPassNested()
            @safe
        {
            applySmallBoundaryProvenanceSecondPass(
                query,
                queryBounds,
                polygon,
                edgeFirstRawEventPlusOne,
                rawToUnique,
                events[],
                boundaryStarts[],
                boundaryEnds[],
                afterLocation[]
            );
        }

        applySmallBoundaryProvenanceSecondPassNested();

        goto afterSmallBoundaryProvenanceSecondPass;
'''

CONTEXT_DEF='''
private struct SmallBoundaryCodegenContext(T)
if (isSegmentPolygonClipScalar!T)
{
    Segment2!T query;
    Bounds2!T queryBounds;
    Polygon2View!T polygon;
    const(size_t)[] edgeFirstRawEventPlusOne;
    const(size_t)[] rawToUnique;
    const(ExactOverlayPoint)[] events;
    size_t[] boundaryStarts;
    size_t[] boundaryEnds;
    IntervalLocation[] afterLocation;
}


pragma(inline, false)
private void applySmallBoundaryProvenanceSecondPassViaContext(T)(
    scope ref SmallBoundaryCodegenContext!T context
)
    @safe
if (isSegmentPolygonClipScalar!T)
{
    applySmallBoundaryProvenanceSecondPass(
        context.query,
        context.queryBounds,
        context.polygon,
        context.edgeFirstRawEventPlusOne,
        context.rawToUnique,
        context.events,
        context.boundaryStarts,
        context.boundaryEnds,
        context.afterLocation
    );
}


'''


DRIVER=r'''
void main(string[] args)
{
    bool checkOnly;
    size_t rounds=1, iterations=1;
    long target=1;
    foreach(arg; args[1 .. $])
    {
        if(arg=="--check") checkOnly=true;
        else enforce(false,"unknown option: "~arg);
    }
    writeln("fixture_header,scalar,case,edges,expected_fact_bits,expected_status,expected_components");
    writeln("sample_header,scalar,case,operation,edges,expected_components,round,iterations,warmup,elapsed_ns,gc_bytes,gc_collections");
    writeln("summary_header,scalar,case,operation,min_ns_per_op,median_ns_per_op,max_ns_per_op");
    run!SCALAR_TYPE(checkOnly,rounds,iterations,target);
    writefln("sink,%s",benchmarkSink);
}
'''

def run(cmd,cwd=None,check=True):
    p=subprocess.run(cmd,cwd=ROOT if cwd is None else cwd,text=True,capture_output=True)
    if check and p.returncode:
        raise RuntimeError("command failed: "+repr(cmd)+"\n"+p.stdout+p.stderr)
    return p

def capture(cmd,cwd=None):
    return run(cmd,cwd).stdout

def git(*args):
    return capture(["git","-C",str(ROOT),*args]).strip()

def tool(name):
    p=shutil.which(name)
    if not p: raise RuntimeError("tool not found: "+name)
    return p

def demangle(name):
    p=run([tool("c++filt"),"-s","dlang",name],check=False)
    return p.stdout.strip() if p.returncode==0 and p.stdout.strip() else name

def compiler_kind(path):
    return "ldc" if Path(path).name.startswith("ldc") else "dmd"

def build(source_root,compiler_name,scalar,outdir):
    compiler=shutil.which(compiler_name)
    if not compiler: raise RuntimeError("compiler not found: "+compiler_name)
    src=(source_root/"benchmarks/segment_polygon_bench.d").read_text()
    marker="void main(string[] args)"
    driver=outdir/("driver-"+scalar+".d")
    driver.write_text(src[:src.index(marker)]+DRIVER.replace("SCALAR_TYPE",scalar))
    imports=capture(["python3",str(source_root/"tools/dub-import-paths.py"),
                     "--compiler="+compiler],source_root).splitlines()
    flags=["-O3","-release"] if compiler_kind(compiler)=="ldc" else ["-O","-inline","-release"]
    flags.append("-boundscheck=safeonly")
    binary=outdir/"benchmark"
    cmd=[compiler,"-i",*["-I"+p for p in imports],str(driver),*flags,"-of="+str(binary)]
    p=run(cmd,outdir,check=False)
    (outdir/"build.stdout").write_text(p.stdout)
    (outdir/"build.stderr").write_text(p.stderr)
    if p.returncode: raise RuntimeError("build failed: "+p.stdout+p.stderr)
    return binary,compiler,flags,cmd

def p1_symbol(binary):
    txt=capture([tool("readelf"),"-Ws","--wide",str(binary)])
    pat=re.compile(r"^\s*\d+:\s+([0-9a-fA-F]+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$")
    found=[]
    for line in txt.splitlines():
        m=pat.match(line)
        if not m: continue
        value,size,stype,bind,vis,ndx,name=m.groups()
        if stype!="FUNC": continue
        d=demangle(name)
        if "trySegmentPolygonClipP1Internal" in d:
            found.append((int(value,16),int(size),name,d))
    if not found: raise RuntimeError("P1 symbol not found")
    found.sort()
    return found[0],txt

def capture_build(source_root,compiler,scalar,outdir):
    binary,compiler_path,flags,cmd=build(source_root,compiler,scalar,outdir)
    (addr,size,name,dem),symtxt=p1_symbol(binary)
    (outdir/"readelf-symbols.txt").write_text(symtxt)
    dis=run([tool("objdump"),"-drw","--no-show-raw-insn","--disassemble="+name,str(binary)],check=False)
    (outdir/"p1-disassembly.txt").write_text(dis.stdout+dis.stderr)
    return {
        "compiler":compiler_path,
        "compiler_version":capture([compiler_path,"--version"]),
        "release_flags":flags,
        "command":cmd,
        "binary_size":binary.stat().st_size,
        "binary_sha256":hashlib.sha256(binary.read_bytes()).hexdigest(),
        "p1_address":addr,
        "p1_size":size,
        "p1_name":name,
        "p1_demangled":dem,
    }

def make_variant(original,kind):
    s=original
    if CALL_BLOCK not in s:
        raise RuntimeError("candidate call block anchor missing")
    marker="package(geo)\nSegmentPolygonClipInternalStatus\ntrySegmentPolygonClipP1Internal"
    if kind.startswith("noarg"):
        s=s.replace(CALL_BLOCK,NOARG_BLOCK,1)
        pos=s.index(marker)
        s=s[:pos]+PROBE_DEF+s[pos:]
    elif kind.startswith("refargs"):
        s=s.replace(CALL_BLOCK,REFARGS_BLOCK,1)
        if HELPER_SIGNATURE not in s:
            raise RuntimeError("helper signature anchor missing")
        s=s.replace(HELPER_SIGNATURE,HELPER_REF_SIGNATURE,1)
    elif kind.startswith("context"):
        s=s.replace(CALL_BLOCK,CONTEXT_BLOCK,1)
        pos=s.index(marker)
        s=s[:pos]+CONTEXT_DEF+s[pos:]
    elif kind.startswith("nested"):
        s=s.replace(CALL_BLOCK,NESTED_BLOCK,1)
    if kind.endswith("fallthrough"):
        s=s.replace("\n        goto afterSmallBoundaryProvenanceSecondPass;\n","\n",1)
        s=s.replace("afterSmallBoundaryProvenanceSecondPass:\n","",1)
    return s

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base",required=True)
    ap.add_argument("--candidate",required=True)
    ap.add_argument("--compiler",required=True)
    ap.add_argument("--scalar",choices=["int","long","float","double"],required=True)
    ap.add_argument("--output",type=Path,required=True)
    a=ap.parse_args()

    base=git("rev-parse","--verify",a.base+"^{commit}")
    cand=git("rev-parse","--verify",a.candidate+"^{commit}")
    out=a.output.resolve(); out.mkdir(parents=True,exist_ok=False)
    rec={"format":1,"status":"incomplete","purpose":"second-boundary-codegen-factor-probe",
         "base":base,"candidate":cand,"compiler_requested":a.compiler,"scalar":a.scalar,
         "variants":{}}

    with tempfile.TemporaryDirectory(prefix="geo-d-factor-probe-") as tmp:
        b=Path(tmp)/"base"; c=Path(tmp)/"candidate"
        git("worktree","add","--detach",str(b),base)
        git("worktree","add","--detach",str(c),cand)
        try:
            bd=out/"base"; bd.mkdir()
            rec["variants"]["base"]=capture_build(b,a.compiler,a.scalar,bd)

            path=c/"source/geo/internal/segment_polygon_clip_p1.d"
            original=path.read_text()
            for kind in [
                "fullargs-goto",
                "noarg-goto",
                "refargs-goto",
                "context-goto",
                "nested-goto",
                "fullargs-fallthrough",
                "noarg-fallthrough",
                "refargs-fallthrough",
                "context-fallthrough",
                "nested-fallthrough",
            ]:
                path.write_text(original if kind=="fullargs-goto" else make_variant(original,kind))
                bd=out/kind; bd.mkdir()
                rec["variants"][kind]=capture_build(c,a.compiler,a.scalar,bd)
            rec["status"]="passed"
        finally:
            git("worktree","remove","--force",str(b))
            git("worktree","remove","--force",str(c))
            (out/"summary.json").write_text(json.dumps(rec,indent=2)+"\n")
    print(out)

if __name__=="__main__":
    main()
