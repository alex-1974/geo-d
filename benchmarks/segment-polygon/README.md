# Segment/polygon benchmark

Tracking: [Performance #82](https://github.com/alex-1974/geo-d/issues/82).
This harness establishes reproducible measurement inputs, not a performance
guarantee or a completed release qualification.

## Run

From the repository root, with the selected compiler and DUB on PATH:

```sh
python3 benchmarks/run_segment_polygon.py --compiler=dmd --cpu=2
python3 benchmarks/run_segment_polygon.py --compiler=ldc2 --cpu=2
```

Select a CPU allowed by your environment. Omit `--cpu` for unpinned diagnostic
runs. Use the baseline DMD 2.111.0 / LDC 1.41.0 and DUB 1.40.0 for controlled
comparisons. Import paths and dependency versions are resolved with DUB; the
harness neither overrides Core nor copies production code.

Release measurements default to `-boundscheck=safeonly`, retaining checks in
`@safe` code as in a normal consumer release. `--boundscheck=on` is available;
`--boundscheck=off` produces supplementary diagnostic evidence only. Historical
records made before the XPS audit disabled all bounds checks; they do not
qualify the normal consumer configuration.

Each run creates a fresh directory under `build/segment-polygon/`. An explicit
`--output PATH` must also name a new directory. The directory contains:

- `metadata.json`: commit/tree, dirty state, benchmark SHA-256, toolchain and
  build commands, platform/CPU, affinity, exposed frequency settings, and
  completion status;
- `dub-describe.json`: resolved dependency graph;
- the executed benchmark source, tracked diff, build/preflight stdout/stderr;
- `samples.stdout`: fixture expectations, per-round raw samples, summaries,
  and the final consumed-result checksum; `samples.stderr` records failures.

Timing runs refuse tracked changes or untracked benchmark/source/tool inputs
unless `--allow-dirty` explicitly marks a diagnostic run. A dirty result is
not an immutable release baseline. Keep the whole record when sharing results;
a summary without the metadata and raw samples is insufficient.

For CI or development checks:

```sh
python3 benchmarks/run_segment_polygon.py --compiler=dmd --check
python3 benchmarks/run_segment_polygon.py --compiler=ldc2 --smoke
```

Both modes build an assertion-enabled preflight binary and an optimized release
binary and run semantic preflight on each. `--smoke` additionally executes two
iterations per operation for one round. Its timings are deliberately too short
for performance conclusions. CI uses smoke solely to check that the benchmark
continues to build, validate, consume results, and record measurements.

## Semantic preflight and corpus

The benchmark imports only `geo` for production geometry. Explicit checks
remain active in release builds. Every fixture validates its polygon and checks
the four relationship bits, clipping status, component count, endpoint
coordinates, and source traversal order. It checks both query directions;
failure results are never indexed. Expected geometry is hand-derived from
rectangles, a rational triangle crossing, holes, and comb teeth, rather than
computed by the production query. This is a benchmark preflight, not a
replacement for the independent BigInt differential archived under #73/#79.

The four scalar domains (`int`, `long`, `float`, `double`) include:

- exterior/interior/crossing, boundary-only and boundary overlap;
- isolated tangency, empty polygon, and degenerate interior/boundary queries;
- concavity, holes, reversed ring winding, and non-dyadic proper crossing;
- sparse-event rectangles with 4, 16, 64, and 256 edges, including redundant
  collinear vertices, and one retained component;
- dense-event combs with 4, 16, 64, and 256 edges and 1, 4, 16, and 64 retained
  components respectively.

Additional integral cases use wide coordinates. Floating cases include
subnormal and large finite coordinates. `long` includes both positive-component
endpoint collapse and inter-component-gap collapse in binary64; these must
return `unrepresentableConstruction`. All fixture generation, ring storage,
expected geometry, validation, and detailed preflight occur outside timing.

The rectangle/comb event-growth descriptions follow their analytic geometry.
The harness does not instrument private event counts or arithmetic-path
selection. Do not infer observed branch/path distributions from these names.

## What is measured

Relationship and clipping samples are separate. Runtime input alternates
forward and reverse queries behind a non-inlined wrapper whose index is read
through `volatileLoad`, preventing removal/hoisting of repeated calls. Each iteration folds
the returned facts or status, component count, and every endpoint coordinate
into a checksum which is printed after the run. Timing includes wrapper/volatile-index-load,
iteration/checksum overhead and, for clipping, O(k) coordinate consumption for
k components. It does not subtract a synthetic empty-loop baseline or measure
only the private kernel.

Clipping timings include private workspace and immutable-result allocation and
materialization. Results are consumed and discarded each iteration; this is not
a workload retaining all results. Automatic GC remains enabled. An explicit
collection occurs outside each measured round. Record this heap policy when
comparing with another harness or application.

By default each case/operation calibrates by doubling from one iteration until
at least `--target-ms=20` or a cap of 65,536 iterations. The actual counts and
durations are recorded; fast cases reaching the cap may be shorter than the
target. Warm-up is `iterations / 10 + 1` calls. Seven measured rounds report
minimum, median, and maximum ns/op, along with all raw elapsed nanoseconds.
Calibration is additional untimed warm-up. For equal-count reruns use
`--iterations=N --rounds=N`; for longer adaptive runs increase `--target-ms`.
Very short samples and substantial round dispersion require longer reruns.

Each sample records the delta in druntime's current-thread cumulative allocated
GC bytes, and GC collection count. Byte totals can be divided by iterations;
they are not allocation-call counts, malloc totals, retained bytes, or peak
memory. The relationship wrapper is compiled `@nogc`, and its measured GC-byte
delta must be zero. GC profiling defaults/configuration can affect collection
telemetry; retain runtime options alongside the record.

Fixture/sample/summary records have distinct first-column tags and their own
header rows. `expected_components=0` on a failure fixture describes no exposed
geometry, not a successful empty result; consult `expected_status`.

## Qualification and limitations

Cloud/shared-host runs can validate the harness and reveal diagnostic costs,
but do not establish controlled release performance or C++ parity. The harness
records affinity and available governors/frequency limits without changing
frequency, turbo, host scheduling, or background workloads. Document those
controls externally for a qualification run. Execute DMD and LDC serially on
the same otherwise-idle machine and retain repeated-run distributions.

The existing C++ benchmarks in this repository cover expansion/orientation and
polygon union, not this segment/polygon API. There is no matching C++ timing
baseline in this change. Any future reference must match prevalidation,
positive-length closed-set output, retained boundary overlap, isolated-contact
omission, scalar domain and exact-topology/checked-construction behavior, or
document differences explicitly. Epsilon, scaled-grid, or mixed-dimensional
results must not be presented as equivalent work.

Event sorting is documented as O(n log n) and private workspace as O(n), but
sorting cost alone is not a measured end-to-end scaling guarantee. Compare the
sparse and dense families, GC bytes, component-consumption cost, and scalar
domains before attributing a measured difference. No optimization, speedup,
instruction-count verdict, or algorithmic-regression claim follows from adding
this harness. #82 and parent qualification #52 remain open for controlled
measurement and investigation of material costs/reference gaps.

The first retained [cloud diagnostic](results/20261001-cloud/README.md) validates
the harness on both baseline compilers and identifies allocation costs for
follow-up. It does not close the performance qualification.

An [allocation prototype and fresh differential checks](results/20261001-capacity/README.md)
explain the exact-event reservation cost. Its latency gate remains outstanding;
`run_segment_polygon_comparison.py` provides the serial immutable-revision
comparison for a controlled machine.

The [first XPS comparison](results/20261001-xps/README.md) confirms reduced GC
bytes and substantial sparse-workload gains, but also identifies latency
concerns and the historical bounds-check configuration error. PR #84 remains
a draft. The corrected comparison runner applies one snapshotted runner and
`--boundscheck=safeonly` to both immutable source revisions, without modifying
their checkouts. Use `--source-root` only to select a different measured
checkout; metadata identifies that source commit and records the runner hash.

## Consumer-release follow-up

The [safeonly XPS comparison](results/20261001-xps-safeonly/README.md)
now supplies the consumer-release evidence. It recommends PR #84 with an
explicit documented allocation/latency trade-off. The historical observations
above remain unchanged; the broader #82/#52 qualification remains open.

## C/C++ reference qualification

See the [reference assessment](reference/README.md) for the executed, untimed
GEOS semantic probe, candidate matrix and native comparison plan. It uses the
same corpus via `--export-corpus`; it does not establish a C/C++ speed ranking.
