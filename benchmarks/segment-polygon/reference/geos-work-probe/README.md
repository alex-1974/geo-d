# GEOS 3.13.1 work-attribution probe

Tracking: #82.

This directory is research-only mechanism instrumentation for the native GEOS
reference used by the segment/polygon clipping benchmark.

The ordinary uninstrumented native runner remains authoritative for wall-clock
comparison. This probe adds counters and internal timers, so its own latency
must not be compared with geo-d.

## Pinned source

The runner clones GEOS tag 3.13.1 and requires commit:

    431568d6e311e0bbfb057b4ec3d44d0d3ba3335f

Before patching, every modified GEOS source file is checked against its expected
Git blob ID. Source drift is a hard failure. No patched GEOS source is committed
to geo-d and GEOS does not become a library dependency.

## Recorded work

For every admitted fixture and both query directions the probe records:

- floating OverlayNG success/fallback counts;
- fast binary64 orientation-filter hits and Double-Double fallbacks;
- Double-Double intersection constructions;
- monotone-chain and chain-pair counts;
- actual segment-intersection tests and proper intersections;
- clipping-envelope segment tests;
- polygon/line segments before and after GEOS clipping/limiting;
- indexed point-in-area calls;
- diagnostic time in clipping-envelope construction, noding, graph build,
  labelling and result extraction.

The internal timers are stage-attribution evidence only.

## Research questions

The probe is intended to distinguish four hypotheses:

1. GEOS is fast because most robust predicates stay on a cheap binary64 filter
   and rarely fall back to Double-Double.
2. MCIndexNoder, monotone chains and the STRtree reduce the number of segment
   pairs that reach the line intersector.
3. OverlayNG clips input linework and propagates topology labels so it avoids
   repeated point-in-polygon/topology work.
4. GEOS proper-intersection construction is cheaper because it uses
   Double-Double and binary64 output, while geo-d preserves a stronger exact
   rational plus checked-construction contract.

None of these observations changes geo-d semantics by itself.

## Build model

The runner builds an instrumented static GEOS Release configuration with tests,
benchmarks and developer-only flags disabled. Static linkage lets the normal
GEOS C API path share the diagnostic C++ counter object with the probe driver.

The driver uses the same retained 87-fixture admission set and the same native
normalization policy as geos_native_bench.cpp.

## XPS run

From a clean checkout of this research branch:

    bash benchmarks/segment-polygon/reference/geos-work-probe/run_xps_geos_work_probe.sh \
        0 \
        "XPS GEOS mechanism run; otherwise idle." \
        50

The third argument is repeated calls per fixture/direction. Counts are
normalized per call by the analyzer.

The archive excludes the large cloned/build GEOS work tree but retains metadata,
commands, instrumentation patch, build logs, raw probe output, admission data
and audited summaries.

## Interpretation

Controlled uninstrumented wall-clock remains the performance verdict. The probe
only explains work. A GEOS technique is a candidate for geo-d only if a later
D experiment preserves the established topology, numerical, construction,
failure, ownership and safety contracts and then wins controlled ABBA evidence.
