# Cloud diagnostic — 2026-10-01

This is a harness validation and diagnostic record, **not a controlled release
performance baseline**. #82 and #52 remain open.

Executed source commit: `629d86824d7df2929216333c553139905e86bdac`.
The metadata records its tree and the executed benchmark's SHA-256. Both runs
were clean, with no production source changes. DMD 2.111.0 and LDC 1.41.0
(frontend 2.111.0), DUB 1.40.0, released Core 0.1.2; Linux x86-64 cloud host
reporting AMD EPYC 9V74. Compiler commands, import paths, CPU/platform and
exposed frequency settings are preserved in each metadata file.

DMD ran first, followed serially by LDC, pinned to allowed CPU 0. No host
frequency/turbo or background-load controls were imposed. Each operation/case
used three measured rounds and adaptive five-millisecond calibration. The
actual iterations, warm-up, elapsed nanoseconds and GC counters are retained.
Some short or high-cost samples have few iterations, so these values are
unsuitable as regression thresholds or language/reference parity claims.

Reproduction (substitute an allowed CPU on the target machine):

```sh
python3 benchmarks/run_segment_polygon.py --compiler=dmd --cpu=0 --rounds=3 --target-ms=5
python3 benchmarks/run_segment_polygon.py --compiler=ldc2 --cpu=0 --rounds=3 --target-ms=5
```

## Validation

- Both assertion-enabled and optimized-release preflights passed on each
  compiler: 22 int, 24 long, 23 float, and 23 double fixtures.
- Both query directions passed the explicit facts/status/component-coordinate
  and traversal-order expectations, including both checked collapse failures.
- Each compiler produced 184 operation/case summaries and 552 raw samples.
- Every relationship sample reported zero current-thread GC bytes; the wrapper
  also compiled `@nogc`.
- Constructive clipping allocated inside the timed operation. For these runs,
  double crossing used 24,752 GC bytes/call, sparse-64 (256 edges, one output
  component) used 1,093,808, and dense-64 (256 edges, 64 components) used
  1,100,800 on both compilers. These are cumulative runtime allocated-byte
  deltas, not allocation counts or live/peak memory. They suggest a concrete
  workspace-cost investigation for #82; no reduction is claimed here.

## Illustrative clipping medians

Times include allocation/materialization and consumption of every output
coordinate, with automatic GC enabled. The cloud timings below only locate
workloads for follow-up; use the raw round distributions and metadata.

| Double fixture | Edges | Components | DMD median µs/call | LDC median µs/call |
| --- | ---: | ---: | ---: | ---: |
| crossing | 4 | 1 | 39.977 | 16.948 |
| sparse-64 | 256 | 1 | 477.925 | 146.667 |
| dense-64 | 256 | 64 | 4549.800 | 1864.775 |

The sparse/dense comparison changes both topology and consumed result size;
it is not an isolated sorting benchmark. No C/C++ counterpart was measured.
The next qualification work is a longer controlled-machine run, followed by
investigation of workspace allocation/scaling and any semantically comparable
reference gap.

The retained record contains unmodified metadata, resolved DUB graph, both
preflight outputs, and all raw/summary samples. Successful build/stdout/stderr
files were empty and are omitted; reproducible binaries are omitted. The
executed source is in the source commit above and its SHA-256 is recorded.
