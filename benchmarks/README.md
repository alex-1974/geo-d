# geo-d benchmarks

These benchmarks measure computationally significant geo-d algorithm
families and selected internal exact-arithmetic components.

The suite currently covers segment intersection, signed area, and
orientation predicates.

They are intended primarily for:

- detecting performance regressions;
- comparing implementation changes;
- identifying expensive exact-arithmetic paths.

Absolute timings are machine-, compiler- and build-dependent and are not
part of the public API contract.

## Benchmarks

`intersection_bench.d` measures end-to-end operations including:

- ordinary disjoint classification;
- ordinary proper-crossing classification;
- collinear overlap classification;
- near-parallel binary64 classification;
- full-range binary64 classification;
- shared-endpoint construction;
- T-junction construction;
- integer proper-crossing construction;
- binary64 proper-crossing construction;
- non-dyadic rational construction;
- near-parallel construction;
- full-range binary64 construction;
- parameter-underflow construction.

`intersection_exact_bench.d` isolates selected exact-arithmetic
components:

- one exact orientation determinant;
- exact proper-intersection rational construction;
- one exact rational-to-binary64 rounding operation.

## LDC release build

From the repository root:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/intersection_bench.d \
        -of=/tmp/geo-d-intersection-bench-ldc

    /tmp/geo-d-intersection-bench-ldc

For the component benchmark:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/intersection_exact_bench.d \
        -of=/tmp/geo-d-intersection-exact-bench-ldc

    /tmp/geo-d-intersection-exact-bench-ldc

## DMD release build

From the repository root:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/intersection_bench.d \
        -of=/tmp/geo-d-intersection-bench-dmd

    /tmp/geo-d-intersection-bench-dmd

For the component benchmark:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/intersection_exact_bench.d \
        -of=/tmp/geo-d-intersection-exact-bench-dmd

    /tmp/geo-d-intersection-exact-bench-dmd

## Signed-area benchmarks

`area_bench.d` compares the correctly-rounded exact `signedArea()` path
with a local naive binary64 shoelace implementation.

The naive implementation exists only as a performance baseline and does
not provide the numerical contract of the public geo-d operation.

The benchmark covers:

- ordinary integer and binary64 triangles;
- translated full-range integer coordinates;
- ordinary binary64 rings with 10, 100, 1,000 and 10,000 vertices;
- a finite full-range binary64 triangle.

`area_exact_bench.d` isolates selected exact signed-area components:

- one exact orientation determinant;
- first determinant accumulation;
- two determinant accumulations;
- one exact dyadic-to-binary64 area rounding operation.

For the area benchmarks, build with LDC using:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/area_bench.d \
        -of=/tmp/geo-d-area-bench-ldc

    /tmp/geo-d-area-bench-ldc

For the component benchmark:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/area_exact_bench.d \
        -of=/tmp/geo-d-area-exact-bench-ldc

    /tmp/geo-d-area-exact-bench-ldc

With DMD:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/area_bench.d \
        -of=/tmp/geo-d-area-bench-dmd

    /tmp/geo-d-area-bench-dmd

and:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/area_exact_bench.d \
        -of=/tmp/geo-d-area-exact-bench-dmd

    /tmp/geo-d-area-exact-bench-dmd

### Initial signed-area baseline

On the development machine, the initial exact implementation showed
approximately linear cost for ordinary binary64 rings.

    LDC release:
        n=100       62.27 us/op
        n=1,000    634.92 us/op
        n=10,000     6.20 ms/op

        steady-state cost:
            about 0.62-0.64 us per vertex

    DMD release:
        n=100      149.68 us/op
        n=1,000      1.54 ms/op
        n=10,000    15.21 ms/op

        steady-state cost:
            about 1.50-1.54 us per vertex

The initial component measurements were:

    LDC release:
        exact determinant             728.53 ns
        first accumulator write        29.85 ns
        second/additional add         ~102.53 ns
        final area rounding           188.71 ns

    DMD release:
        exact determinant            1266.91 ns
        first accumulator write       108.49 ns
        second/additional add        ~373.96 ns
        final area rounding           306.29 ns

The additional-add values are derived from the difference between the
two-add and first-add benchmark cases.

These measurements indicate that the principal cost is per-vertex exact
determinant construction, with exact accumulation also significant,
especially under DMD. Final binary64 rounding is performed only once per
ring and is not the dominant cost for non-trivial rings.

The full-range binary64 triangle benchmark is intentionally adversarial
for numerical range, but its axis-aligned geometry creates exact zero
differences and products. Its timing must therefore not be interpreted as
representative full-range determinant throughput.

No floating-point fast path is implied by these measurements. The first
performance work should remove redundant work from the exact implementation
while preserving the signed-area numerical contract.

## Intersection optimisation history

The initial exact construction implementation deliberately favoured a
simple and obviously bounded fixed-width arithmetic design.

Benchmarking later identified three major optimisation opportunities:

1. Fixed-width multiplication now skips inactive leading and trailing
   limb ranges while preserving all arithmetic inside the active range.

2. Exact rational-to-binary64 rounding compares and subtracts shifted
   divisors directly instead of repeatedly materialising large shifted
   fixed-width integers.

3. The public unique-point construction path avoids two redundant exact
   orientation determinants after the authoritative classifier and
   endpoint handling have already established a strict proper crossing.

These changes do not alter the public intersection semantics or the
correctly-rounded binary64 construction contract.

## Observed development result

On the development machine used during the optimisation work, ordinary
binary64 proper-crossing construction changed approximately as follows:

    LDC release:
        59.05 us/op -> 3.03 us/op
        about 19.5x faster

    DMD release:
        130.10 us/op -> 7.29 us/op
        about 17.8x faster

These values are historical reference measurements only. They are not
portable performance guarantees.

Ordinary segment-intersection classification remained around the
sub-microsecond range, while exact full-range and construction paths
benefited most from the fixed-width arithmetic improvements.

## Signed-area optimisation result

Profiling of the initial correctly-rounded signed-area implementation showed
that its cost was dominated by per-vertex exact arithmetic rather than by
the final binary64 rounding step.

Two semantics-preserving optimisations were retained.

First, signed-area triangle-fan traversal now decodes the fixed fan origin
only once and reuses the previous relative vertex vector. For each new
vertex, only that vertex is decoded and converted to a relative vector.

Second, fixed-width unsigned addition and subtraction now skip inactive
zero-limb ranges. This benefits signed-area determinant accumulation and
product differences as well as other users of the shared exact-arithmetic
primitives.

An attempted area-specific cross-width accumulator optimisation improved
isolated accumulator measurements but caused an end-to-end regression with
DMD. It was therefore rejected.

On the development machine, ordinary binary64 rings changed approximately
as follows.

    LDC release:

        initial:
            n=100          62.27 us/op
            n=1,000       634.92 us/op
            n=10,000        6.20 ms/op

        final:
            n=100          40.88 us/op
            n=1,000       384.85 us/op
            n=10,000        3.94 ms/op

        steady-state cost:
            about 0.39-0.41 us per vertex

        improvement at n=10,000:
            about 36 percent

    DMD release:

        initial:
            n=100         149.68 us/op
            n=1,000         1.54 ms/op
            n=10,000       15.21 ms/op

        final:
            n=100         108.06 us/op
            n=1,000         1.08 ms/op
            n=10,000       11.00 ms/op

        steady-state cost:
            about 1.08-1.10 us per vertex

        improvement at n=10,000:
            about 28 percent

The sparse fixed-width addition/subtraction change was also checked against
the existing segment-intersection benchmarks. No material regression was
observed; representative exact-construction cases improved slightly.

The retained implementation therefore continues to provide exact
determinant accumulation and one correctly-rounded binary64 result without
introducing a floating-point fast path.

Further optimisation, such as fused exact cross-product construction or a
certified floating-point fast path, is deferred until a concrete workload
demonstrates that the remaining cost is material.

## Orientation benchmarks

`orientation_bench.d` measures the public `orientation()` operation
end-to-end.

The benchmark covers:

- ordinary and full-range `int`;
- ordinary and full-range `long`;
- ordinary `float`;
- ordinary binary64 cases certified by the first-stage filter;
- binary64 collinear and near-collinear expansion fallback cases;
- binary64 full-range dyadic fallback cases;
- minimum-subnormal binary64 fallback cases.

The benchmark uses two alternating inputs per case, a warm-up phase,
seven measured repetitions, and reports median, minimum, and maximum
nanoseconds per operation.

Build with LDC using:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -mcpu=native \
        -i \
        -Isource \
        benchmarks/orientation_bench.d \
        -of=/tmp/geo-d-orientation-bench-ldc

    /tmp/geo-d-orientation-bench-ldc

With DMD:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/orientation_bench.d \
        -of=/tmp/geo-d-orientation-bench-dmd

    /tmp/geo-d-orientation-bench-dmd

### C++ orientation reference

`reference/cpp/orientation_bench.cpp` is a diagnostic reference benchmark,
not a complete independent implementation of geo-d's robust orientation
contract.

Its comparisons have different strengths:

- `int` uses the same exact algorithm and is directly comparable;
- `long manual` uses the portable 32-bit-limb multiplication algorithm;
- `long native u128` uses GNU/Clang `unsigned __int128` and is the closest
  reference for the LDC `core.int128` implementation;
- `double certified filter` implements only the first-stage certified
  binary64 filter;
- `double naive baseline` is intentionally non-robust.

There is currently no C++ reference implementation for geo-d's expansion
or dyadic binary64 fallbacks.

The C++ algorithms are inline and may be inlined into their no-inline
benchmark wrappers. Consequently, these results are compiler/code-generation
references and do not guarantee identical function-call overhead to the
public D API.

Build the GCC reference using strict floating-point semantics:

    g++ \
        -O3 \
        -DNDEBUG \
        -march=native \
        -ffp-contract=off \
        -std=c++20 \
        benchmarks/reference/cpp/orientation_bench.cpp \
        -o=/tmp/geo-d-orientation-bench-cpp

    /tmp/geo-d-orientation-bench-cpp

Do not use `-ffast-math` for the certified-filter comparison. It may
invalidate assumptions required by the robustness checks.

Absolute D-versus-C++ timings remain compiler-, machine-, and build-dependent.
They are diagnostic measurements, not performance guarantees.

## Geometry bounding-box benchmark

`bounding_box_bench.d` measures end-to-end axis-aligned bounding-box
computation through the public `tryBounds()` API.

The benchmark covers:

- `PolylineView!double` with 10, 100, 1,000, 10,000 and 100,000 points;
- `PolygonView!double` with four rings of 2,500 vertices each;
- the public view-based API;
- a raw-slice reduction using `Bounds2.tryExtend()`;
- a direct raw-slice extrema loop;
- a direct nested-ring polygon extrema loop.

The reference loops are diagnostic comparisons only. They are not separate
public APIs and do not establish a cross-language performance guarantee.

All dynamic benchmark-data allocation is performed before the timed regions.
Each timed operation itself remains allocation-free.

The benchmark uses two alternating datasets per case, a warm-up phase,
seven measured repetitions and reports the median time per operation and
per point.

Build with LDC using:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/bounding_box_bench.d \
        -of=/tmp/geo-d-bounding-box-bench-ldc

    /tmp/geo-d-bounding-box-bench-ldc

With DMD:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/bounding_box_bench.d \
        -of=/tmp/geo-d-bounding-box-bench-dmd

    /tmp/geo-d-bounding-box-bench-dmd

### Initial geometry-bounds baseline

On the development machine, the optimized implementation showed approximately
linear steady-state cost for ordinary finite binary64 data.

    LDC release:

        polyline, n=1,000..100,000:
            about 1.2 ns per point

        polygon, 4 x 2,500 vertices:
            about 1.4 ns per point

    DMD release:

        polyline, n=1,000..100,000:
            about 4.0-4.4 ns per point

        polygon, 4 x 2,500 vertices:
            about 4.7-5.0 ns per point

The first implementation reduced geometry bounds by repeatedly calling
`Bounds2.tryExtend()` inside the hot loop.

Benchmarking showed that a private scalar-extrema accumulator reduced
large-polyline cost by roughly 30 percent while preserving the public
`tryBounds()` semantics.

Under LDC, the optimized public polyline path is approximately at parity with
the direct raw-slice extrema loop. Under DMD, the public path remains slower
than the direct extrema loop but is materially faster than the original
`Bounds2.tryExtend()` reduction.

The polygon comparison demonstrates that source-level loop simplicity does not
by itself predict generated-code performance: under LDC the direct nested-ring
extrema reference was slower than both the public implementation and the
`Bounds2.tryExtend()` reference.

No further geometry-bounds optimization is currently justified by these
measurements.

## Polyline-length benchmark

`polyline_length_bench.d` measures end-to-end `polylineLength()` throughput
for ordinary finite `PolylineView!double` inputs.

The public implementation uses compensated accumulation as defined by
ADR-0017.

The benchmark compares it with a local ordinary sequential-accumulation
baseline corresponding to the previous implementation.

The ordinary baseline is diagnostic only. It is not a separate public API.

The benchmark covers polylines with:

```text
10
100
1,000
10,000
```

stored points.

It uses two alternating deterministic datasets per size, a warm-up phase,
seven measured repetitions, and reports median time per operation and per
segment.

All dynamic test-data allocation occurs before timing.

The benchmark also contains a deterministic numerical probe consisting of 256
repetitions of:

```text
0 -> 2^52 -> 0 -> 1 -> 0
```

The exactly representable mathematical result is:

```text
2^61 + 512
```

On the development machine, ordinary binary64 sequential accumulation lost
512 units in this case, while the public compensated implementation produced
the expected representable result under both DMD and LDC.

Build with LDC using:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/polyline_length_bench.d \
        -of=/tmp/geo-d-polyline-length-bench-ldc

    /tmp/geo-d-polyline-length-bench-ldc

With DMD:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/polyline_length_bench.d \
        -of=/tmp/geo-d-polyline-length-bench-dmd

    /tmp/geo-d-polyline-length-bench-dmd

### Initial compensated polyline-length baseline

On the development machine, the retained production implementation measured:

```text
LDC release:

    n=1,000:
        public compensated   4.274 ns/segment
        ordinary baseline    3.697 ns/segment
        overhead             about 15.6 %

    n=10,000:
        public compensated   4.607 ns/segment
        ordinary baseline    4.171 ns/segment
        overhead             about 10.4 %

DMD release:

    n=1,000:
        public compensated  18.969 ns/segment
        ordinary baseline   16.162 ns/segment
        overhead             about 17.4 %

    n=10,000:
        public compensated  18.729 ns/segment
        ordinary baseline   16.274 ns/segment
        overhead             about 15.1 %
```

The measured cost is accepted because compensated accumulation materially
improves mixed-scale numerical behaviour while preserving the public
allocation, complexity, exception, and non-finite-value contracts.

Absolute timings are development measurements and are not portable
performance guarantees.

## Metric benchmark

`metric_bench.d` measures the public metric operations:

- `squaredDistance()`;
- `distance()`;
- `segmentLength()`;
- `tryPointSegmentDistance()`;
- `tryNearestPoint()`.

Ordinary finite binary64 cases are compared with local direct mathematical
references.

These references are diagnostic comparisons only. In particular, the direct
point-to-segment and nearest-point references are restricted to moderate
finite inputs and do not implement geo-d's full numerical-range contract.

Large-range cases therefore benchmark only the public implementation. Their
purpose is to exercise the scaled fallback paths for inputs where naive
unscaled intermediate arithmetic can overflow.

All benchmark data is prepared before timing.

The benchmark uses:

- two alternating deterministic inputs per case;
- a warm-up phase;
- seven measured repetitions;
- the median measured time;
- 3,000,000 operations per metric-primitive sample;
- 1,000,000 operations per point/segment sample.

Results are reported in nanoseconds per operation.

### Build

LDC:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/metric_bench.d \
        -of=/tmp/geo-d-metric-bench-ldc

    /tmp/geo-d-metric-bench-ldc

DMD:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/metric_bench.d \
        -of=/tmp/geo-d-metric-bench-dmd

    /tmp/geo-d-metric-bench-dmd

### Initial metric baseline

Benchmark harness commit:

    cc48a48f4f53

Production ordinary-range metric fast path:

    9bab553

Development environment:

    CPU:
        not reported by lscpu

    OS:
        Ubuntu 26.04.1 LTS

    Kernel:
        Linux 6.17.0-22-generic x86_64 GNU/Linux

    LDC:
        1.41.0
        DMD frontend 2.111.0
        LLVM 19.1.7

    DMD:
        2.111.0

The retained production implementation measured:

```text
LDC release:

    metric primitives:

        squaredDistance double       5.44 ns/op
        direct squared double        5.43 ns/op

        distance double              7.56 ns/op
        direct distance double       7.55 ns/op

        distance long               12.09 ns/op
        direct distance long        10.19 ns/op

        segmentLength double         7.63 ns/op
        direct segment double        7.55 ns/op

        segmentLength long          10.42 ns/op
        direct segment long         10.48 ns/op

    point-to-segment distance:

        public interior             25.39 ns/op
        direct interior             10.11 ns/op

        public endpoint clamp       20.83 ns/op
        direct endpoint clamp       10.18 ns/op

        public degenerate           16.18 ns/op
        direct degenerate            9.49 ns/op

        public huge-range interior  43.39 ns/op

    nearest point:

        public interior             21.16 ns/op
        direct interior             12.60 ns/op

        public endpoint clamp       20.49 ns/op
        direct endpoint clamp       11.49 ns/op

        public degenerate           14.05 ns/op
        direct degenerate            9.08 ns/op

        public huge-range interior  32.63 ns/op


DMD release:

    metric primitives:

        squaredDistance double       7.67 ns/op
        direct squared double        7.77 ns/op

        distance double             12.21 ns/op
        direct distance double      12.15 ns/op

        distance long               17.86 ns/op
        direct distance long        14.72 ns/op

        segmentLength double        13.17 ns/op
        direct segment double       13.15 ns/op

        segmentLength long          18.96 ns/op
        direct segment long         16.41 ns/op

    point-to-segment distance:

        public interior             39.35 ns/op
        direct interior             18.74 ns/op

        public endpoint clamp       44.85 ns/op
        direct endpoint clamp       18.82 ns/op

        public degenerate           37.80 ns/op
        direct degenerate           18.28 ns/op

        public huge-range interior 113.85 ns/op

    nearest point:

        public interior             41.69 ns/op
        direct interior             18.49 ns/op

        public endpoint clamp       33.66 ns/op
        direct endpoint clamp       15.43 ns/op

        public degenerate           26.14 ns/op
        direct degenerate           13.59 ns/op

        public huge-range interior  71.43 ns/op
```

The binary64 scalar primitives are approximately at direct-reference parity.

The `long` paths incur some additional cost for exact integral component
difference handling before conversion to the floating metric scalar. This
preserves the supported full signed-`long` coordinate domain.

### Point/segment optimisation result

The initial implementation used exponent-scaled arithmetic for every
projection and perpendicular-distance computation.

Profiling by focused benchmarking showed that this full-range machinery was
also paid for by ordinary moderate binary64 geometry.

Commit `9bab553` introduced a conservative ordinary-range fast path inside the
private metric helpers. Inputs whose products are safely representable use
direct arithmetic. Inputs outside that domain retain the existing
exponent-scaled implementation.

Representative ordinary-case development measurements changed approximately
as follows:

```text
LDC release:

    point-segment interior:
        41.44 -> 25.39 ns/op
        about 39 percent faster

    point-segment endpoint clamp:
        29.05 -> 20.83 ns/op
        about 28 percent faster

    nearest-point interior:
        30.32 -> 21.16 ns/op
        about 30 percent faster

    nearest-point endpoint clamp:
        27.98 -> 20.49 ns/op
        about 27 percent faster


DMD release:

    point-segment interior:
        125.97 -> 39.35 ns/op
        about 69 percent faster

    point-segment endpoint clamp:
        97.78 -> 44.85 ns/op
        about 54 percent faster

    nearest-point interior:
        85.48 -> 41.69 ns/op
        about 51 percent faster

    nearest-point endpoint clamp:
        83.76 -> 33.66 ns/op
        about 60 percent faster
```

The conservative range check adds a small cost to the extreme-range fallback
path. Representative development measurements changed from approximately
39.71 to 43.39 ns/op under LDC and 104.28 to 113.85 ns/op under DMD for the
point-to-segment huge-range case.

For nearest-point huge-range inputs, the corresponding measurements changed
from approximately 29.52 to 32.63 ns/op under LDC and 68.81 to 71.43 ns/op
under DMD.

This trade-off is accepted because ordinary finite geometry receives a large
latency reduction while the existing full-range semantics remain available.

A second experiment attempted to hoist the range decision out of the private
metric helpers so that a caller could reuse one guard across projection and
perpendicular-distance work. Measurements did not show a stable overall
benefit and showed regressions in several paths. That design was rejected.

Absolute timings are machine-, compiler-, build-, and workload-dependent and
are not public performance guarantees.

## Conversion and quantisation benchmark

`conversion_bench.d` measures representative public operations from
`geo.convert`.

The benchmark covers checked conversion for:

- `Point2!int -> Point2!long`;
- `Point2!long -> Point2!int`, including success and range failure;
- `Point2!long -> Point2!double`;
- `Point2!double -> Point2!int`, including success and fractional failure;
- `Point2!double -> Point2!float`;
- representative four-coordinate `Segment2` conversions.

It also measures the public binary64 quantisation operations:

- `rounded`;
- `floored`;
- `ceiled`;
- `truncated`.

Local direct implementations reproduce the relevant conversion and
quantisation semantics and are diagnostic references only.

The benchmark uses two alternating deterministic inputs per case, a warm-up
phase, seven measured repetitions, and reports median nanoseconds per
operation.

All benchmark inputs are prepared before timing.

### Build

LDC:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/conversion_bench.d \
        -of=/tmp/geo-d-conversion-bench-ldc

    /tmp/geo-d-conversion-bench-ldc

DMD:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/conversion_bench.d \
        -of=/tmp/geo-d-conversion-bench-dmd

    /tmp/geo-d-conversion-bench-dmd

### Initial conversion baseline

Benchmark harness commit:

    f5161f0fac1e

The retained production implementation measured:

```text
LDC release:

    Point2 conversion:

        int -> long:
            public   1.55 ns/op
            direct   1.56 ns/op

        long -> int success:
            public   1.74 ns/op
            direct   1.76 ns/op

        long -> int failure:
            public   1.70 ns/op
            direct   1.71 ns/op

        long -> double:
            public   7.63 ns/op
            direct   8.75 ns/op

        double -> int success:
            public   7.80 ns/op
            direct   6.42 ns/op

        double -> int fractional failure:
            public   5.49 ns/op
            direct   5.28 ns/op

        double -> float:
            public  10.30 ns/op
            direct  11.03 ns/op

    Segment2 conversion:

        long -> int:
            public   3.22 ns/op
            direct   3.02 ns/op

        double -> int:
            public  18.15 ns/op
            direct  16.13 ns/op

    Point2!double quantisation:

        rounded:
            public  14.40 ns/op
            direct  14.40 ns/op

        floored:
            public  10.25 ns/op
            direct  10.55 ns/op

        ceiled:
            public  10.50 ns/op
            direct  10.63 ns/op

        truncated:
            public  11.85 ns/op
            direct  12.72 ns/op


DMD release:

    Point2 conversion:

        int -> long:
            public   3.37 ns/op
            direct   2.02 ns/op

        long -> int success:
            public  11.07 ns/op
            direct   7.93 ns/op

        long -> int failure:
            public   5.16 ns/op
            direct   7.49 ns/op

        long -> double:
            public   8.71 ns/op
            direct   7.56 ns/op

        double -> int success:
            public  25.59 ns/op
            direct  21.56 ns/op

        double -> int fractional failure:
            public  17.30 ns/op
            direct  15.05 ns/op

        double -> float:
            public  31.53 ns/op
            direct  26.32 ns/op

    Segment2 conversion:

        long -> int:
            public  24.07 ns/op
            direct  18.16 ns/op

        double -> int:
            public  54.70 ns/op
            direct  44.58 ns/op

    Point2!double quantisation:

        rounded:
            public  24.39 ns/op
            direct  24.85 ns/op

        floored:
            public  15.17 ns/op
            direct  14.80 ns/op

        ceiled:
            public  19.03 ns/op
            direct  19.03 ns/op

        truncated:
            public  18.16 ns/op
            direct  18.41 ns/op
```

Under LDC, checked conversions are generally at or close to their direct
references. The successful `double -> int` path shows a small additional
cost, but no dominant abstraction overhead was identified.

DMD shows a consistent additional cost on several successful checked
conversion paths, particularly where multiple scalar checks are composed.
The absolute latency remains small and no single local operation accounts for
the difference.

An explicit `pragma(inline, true)` experiment on the private scalar conversion
helper was measured under both compilers. It did not produce a stable overall
improvement and regressed several representative cases, so the change was
rejected.

The quantisation operations are effectively at direct-reference parity under
both LDC and DMD. No production optimisation is justified by these
measurements.

Absolute timings are machine-, compiler-, build-, and workload-dependent and
are not public performance guarantees.

## Point-in-polygon benchmark

`point_in_polygon_bench.d` measures robust public
`tryClassifyPointInPolygon()` performance.

Coverage includes:

- single-ring polygons with 16, 128, and 1,024 stored vertices;
- inside, outside, and boundary queries;
- an exterior ring plus four holes, with 1,536 total stored vertices;
- a near-collinear binary64 robust-predicate case;
- a full-range signed-`long` case.

Ordinary moderate binary64 workloads are compared with a local diagnostic
even-odd reference.

The reference deliberately applies a closed y-range prefilter before
evaluating an ordinary binary64 determinant. It is suitable only for the
moderate exactly representable benchmark geometry and is not a replacement
for geo-d's robust predicate semantics.

The timed wrappers alternate between two runtime query points. This prevents
an optimizing compiler from hoisting a loop-invariant classification out of
the benchmark loop.

An earlier development version used one constant query per timed wrapper.
LDC optimized the direct-reference classification almost completely out of
the loop, producing impossible sub-nanosecond results for 1,024-vertex
polygons. Those measurements were rejected and are not part of the retained
baseline.

Benchmark harness commit:

    ccb81e0c6533

Production y-range prefilter:

    647eaee

### Production optimization

Before commit `647eaee`, point-in-ring classification evaluated robust
`orientation()` for every stored edge until boundary detection.

A point can lie on an edge, or that edge can contribute to the horizontal
even-odd crossing rule, only when the query y-coordinate lies inside the
closed y-range of the edge.

The implementation therefore now performs this inexpensive y-range test
before invoking the robust orientation predicate.

The complete ring traversal remains unchanged:

- every stored vertex is still inspected;
- non-finite coordinates still cause failure;
- boundary still has precedence;
- even-odd semantics are unchanged;
- robust orientation is still used whenever an edge can geometrically
  affect the classification.

### Representative results

For a 1,024-vertex single ring:

| Case | LDC before | LDC after | Speedup | DMD before | DMD after | Speedup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| inside | 19,244.60 ns | 2,621.43 ns | 7.34x | 26,831.58 ns | 4,423.44 ns | 6.07x |
| outside | 18,896.63 ns | 2,628.20 ns | 7.19x | 27,130.36 ns | 4,258.11 ns | 6.37x |
| boundary | 5,370.02 ns | 2,715.03 ns | 1.98x | 8,813.80 ns | 4,571.81 ns | 1.93x |

For the 1,536-vertex exterior-plus-four-holes workload:

| Case | LDC before | LDC after | Speedup | DMD before | DMD after | Speedup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| shell interior | 28,153.76 ns | 3,961.43 ns | 7.11x | 41,156.38 ns | 6,450.73 ns | 6.38x |
| inside hole | 29,589.44 ns | 4,090.03 ns | 7.23x | 41,121.15 ns | 6,640.73 ns | 6.19x |
| hole boundary | 27,604.19 ns | 4,738.23 ns | 5.83x | 37,869.72 ns | 7,088.03 ns | 5.34x |

The ordinary large-ring cost after the optimization is approximately:

    LDC:
        2.6 ns per stored vertex

    DMD:
        4.2 to 4.6 ns per stored vertex

The diagnostic direct reference measured approximately:

    LDC:
        0.9 to 1.0 ns per stored vertex

    DMD:
        4.2 to 4.7 ns per stored vertex

Under DMD, the robust public implementation is therefore approximately at
the direct-reference level for the large ordinary workloads after the
prefilter.

The robust-special-case measurements did not regress:

    near-collinear binary64:

        LDC:
            134.22 -> 122.14 ns/op

        DMD:
            259.75 -> 249.60 ns/op

    full-range signed long:

        LDC:
            33.04 -> 25.41 ns/op

        DMD:
            116.66 -> 87.73 ns/op

These measurements support retaining the y-range prefilter: it removes
robust predicate work only for geometrically irrelevant edges while
preserving the full public numerical and failure semantics.

Absolute timings are machine-, compiler-, build-, and workload-dependent and
are not public performance guarantees.
