# Performance and Benchmarking

Performance is a first-class quality property of geo-d.

The library is intended for geometry-heavy workloads where small primitive
operations may be executed millions or billions of times. Correct and robust
algorithms are not sufficient if their implementation imposes avoidable
overhead.

The performance objective is:

> For comparable semantics and algorithms, geo-d should approach the
> performance of well-optimised C and C++ implementations.

This is a development objective, not part of the public API contract.

Correctness, numerical robustness, documented ownership semantics and safety
requirements must not be weakened merely to improve benchmark results.

## Primary performance compiler

LDC is the primary compiler for performance work.

Primary benchmark configuration:

```text
ldc2
-O3
-release
-boundscheck=off
```

The exact command line used by a benchmark must be recorded or reproducible
from repository tooling.

DMD remains a required supported compiler and should also be benchmarked for:

- performance regressions;
- compiler-specific pathological behaviour;
- unexpectedly large differences from LDC.

Performance-sensitive implementation decisions should normally be based on
LDC results unless there is a compelling reason otherwise.

## C and C++ reference implementations

Important hot paths should be compared with small C or C++ reference
implementations where useful.

A direct D-versus-C/C++ comparison is valid only when the implementations
provide sufficiently comparable semantics.

Whenever practical, the reference should use:

- the same algorithm;
- the same input representation;
- the same numerical guarantees;
- the same treatment of degenerate input;
- equivalent allocation behaviour;
- equivalent result construction.

A simpler or numerically weaker implementation may still be benchmarked, but
must be labelled as a baseline rather than as an equivalent implementation.

For example, a naive binary64 shoelace area implementation is useful for
showing the approximate cost of ordinary floating-point arithmetic, but it is
not semantically equivalent to geo-d's correctly-rounded exact signed-area
implementation.

## Performance targets

The following are engineering targets, not compatibility guarantees.

For semantically comparable implementations:

| Operation class | Development target |
| --- | --- |
| Simple scalar and geometry primitives | close to C/C++; ideally within about 1.25x |
| Linear traversal kernels | close to C/C++ per element; ideally within about 1.25x |
| Ordinary robust-predicate fast paths | ideally within about 1.5x |
| More expensive exact fallback paths | ideally within about 2x when algorithms are comparable |
| Higher-level geometry algorithms | same asymptotic behaviour and preferably within about 1.5x |

A slowdown greater than approximately 2x relative to a comparable optimised
C/C++ implementation should normally trigger investigation.

Such a difference may be justified, but the reason should be understood.

Possible causes include:

- stronger numerical semantics;
- additional validation;
- unavoidable representation differences;
- compiler optimisation limitations;
- abstraction overhead;
- unnecessary conversions or temporary objects;
- repeated exact-arithmetic work;
- missed inlining or vectorisation opportunities;
- memory-access behaviour.

## Benchmark layers

geo-d benchmarks should distinguish three layers.

### 1. Public API benchmarks

These measure the actual operations library users call.

Examples include:

```text
distance
orientation
segmentIntersectionKind
trySegmentIntersectionPoint
signedArea
polygonArea
tryClassifyPointInPolygon
validateRing
validatePolygon
trySimplifyDouglasPeuckerInto
```

Public API benchmarks are the primary measure of user-visible performance.

### 2. Component benchmarks

Selected internal operations may be benchmarked to explain where time is
spent.

Examples include:

- exact determinant construction;
- fixed-width arithmetic;
- exact accumulation;
- rational construction;
- correctly-rounded conversion.

Component benchmarks are diagnostic tools. They do not replace public API
benchmarks.

### 3. External reference benchmarks

Small C/C++ reference implementations and, where semantics are sufficiently
comparable, established geometry libraries may be used to provide an external
performance reference.

External comparisons must state semantic differences explicitly.

## Fast paths and fallback paths

Robust algorithms must not be represented by a single favourable benchmark.

Where an operation has materially different execution paths, those paths
should be measured independently.

For robust orientation predicates this may include:

```text
ordinary fast path
near-collinear input
expansion or intermediate fallback
exact fallback
```

For segment intersection this may include:

```text
obvious disjoint segments
ordinary proper crossing
shared endpoint
T-junction
collinear overlap
near-parallel input
exact fallback
unique-point construction
```

The common path and the adversarial path answer different performance
questions and should not be combined into one opaque number.

## Input sizes and scaling

Algorithms whose cost depends on geometry size must be benchmarked at multiple
input sizes.

Typical useful sizes include:

```text
10
100
1,000
10,000
```

Larger or smaller cases may be added where appropriate.

The benchmark should make asymptotic behaviour visible.

For example:

- polyline operations should report cost per vertex where useful;
- point-in-polygon should be measured over increasing ring sizes;
- validation should expose quadratic behaviour where applicable;
- simplification should include cases with different retained-point ratios.

A benchmark suite should not hide poor scaling behind one convenient input
size.

## Benchmark data

Input generation must normally happen outside the timed region.

Datasets should be deterministic and reproducible.

A benchmark should contain enough variation to prevent the compiler from
reducing the operation to a compile-time constant or an unrealistically
predictable special case.

Where appropriate, paired or alternating inputs should be used.

Benchmark datasets should include:

- ordinary representative cases;
- boundary cases relevant to performance;
- numerically difficult cases;
- large geometries where algorithmic scaling matters.

Adversarial datasets must be identified as such.

## Timed region

The timed region should contain only the operation being measured and
unavoidable result handling.

It should not include unrelated work such as:

- geometry generation;
- dynamic test-data allocation;
- console output;
- file access;
- benchmark setup.

If the public operation itself allocates, that allocation is part of the
operation and must remain in the timed region.

If the public operation is documented as allocation-free, the benchmark must
not introduce allocation into the measured operation.

## Preventing invalid optimisation

Benchmarks must ensure that the compiler cannot eliminate the measured work.

Results should contribute to an observable benchmark sink.

Benchmark wrappers may use:

```d
pragma(inline, false)
```

where that helps preserve the intended benchmark boundary.

Such barriers should be minimal: benchmarks must not artificially prevent
optimisations that would also be available to real callers.

## Warm-up and repetition

One timing run is not sufficient evidence for a performance conclusion.

Benchmarks should support repeated measurements.

Performance comparisons should preferably use:

- a warm-up phase;
- multiple measured runs;
- the median as the primary summary;
- observed spread or another simple variability measure.

Large performance differences can be investigated with fewer repetitions
during development, but final recorded comparisons should be repeatable.

## Machine and toolchain metadata

Performance results intended for comparison or documentation should record at
least:

```text
CPU
architecture
operating system
D compiler and version
C/C++ compiler and version where applicable
compiler flags
benchmark revision
```

Where CPU-frequency scaling, thermal throttling or background workload may
materially affect results, this should be considered when interpreting small
differences.

## Interpreting small differences

Small benchmark differences should not immediately drive source changes.

Differences close to measurement noise should be treated as inconclusive.

Optimisation work should focus first on:

- large absolute costs;
- frequently executed operations;
- poor scaling;
- repeated exact-arithmetic work;
- clear D-versus-C/C++ gaps;
- compiler-visible abstraction overhead.

Code complexity should not be increased for an unrepeatable microbenchmark
improvement.

## Numerical guarantees

Performance optimisation must preserve the documented numerical contract.

In particular, an optimisation must not silently replace:

- exact predicates with epsilon predicates;
- exact accumulation with ordinary floating-point accumulation;
- correctly-rounded construction with approximate construction;
- checked conversion with unchecked casts.

A faster implementation with weaker semantics is a different algorithm and
must not replace the public operation unless the API contract itself is
deliberately changed.

## Optimisation workflow

Performance work should normally follow this sequence:

1. Establish a reproducible public API benchmark.
2. Establish an external or simpler reference when useful.
3. Measure the gap.
4. Profile or isolate expensive components.
5. Form a concrete optimisation hypothesis.
6. Change one relevant implementation aspect.
7. Run correctness tests.
8. Re-run the benchmark.
9. Verify that the improvement is repeatable.
10. Record significant findings when they affect future maintenance.

Optimisation should be evidence-driven rather than speculative.

## Initial benchmark expansion priorities

The existing intersection and signed-area benchmarks remain useful.

The next benchmark work should prioritise:

1. orientation;
2. scalar conversion and quantisation;
3. elementary metric operations;
4. polyline metric operations;
5. segment overlap construction;
6. polygon area;
7. point-in-polygon;
8. topology validation;
9. Douglas-Peucker simplification.

Orientation is the preferred first C/C++ comparison because it is:

- a very small hot primitive;
- used by multiple higher-level algorithms;
- sensitive to robustness strategy;
- suitable for separate fast-path and fallback-path measurements.

## Robust binary64 orientation performance

### Benchmark conditions

The robust `orientation(double)` implementation is compared against an
algorithm-equivalent C++ reference that mirrors the same high-level structure
and major helper boundaries:

- filtered binary64 fast path;
- exact expansion fallback;
- exact dyadic fallback.

The controlled comparison reported here used:

- LDC 1.41.0;
- D frontend 2.111.0;
- LLVM 19.1.7;
- GCC 15.2.0;
- x86-64;
- native CPU code generation;
- release optimization;
- bounds checks disabled for the D benchmark;
- `-O3 -DNDEBUG -march=native -ffp-contract=off -fno-fast-math` for the C++
  reference;
- one pinned physical CPU;
- the SMT sibling taken offline;
- performance governor and performance energy preference;
- turbo disabled;
- observed clock frequency approximately 2.60 GHz.

D and C++ runs were alternated across four controlled rounds in order to
reduce run-order and thermal bias.

The initial uncontrolled smoke runs are intentionally not used for comparative
ratios. Only the controlled alternating runs at the stabilized CPU frequency
are treated as reference measurements.

The reported values are arithmetic means of the per-round benchmark medians.

### Controlled D/LDC versus C++ reference

| Robust binary64 path | D/LDC | C++/GCC | D/C++ |
| --- | ---: | ---: | ---: |
| Filter fast path | 20.91 ns | 22.63 ns | **0.924x** |
| Expansion fallback, collinear | 101.27 ns | 103.51 ns | **0.978x** |
| Expansion fallback, near-degenerate | 128.10 ns | 116.39 ns | **1.101x** |
| Dyadic fallback, collinear | 482.66 ns | 448.24 ns | **1.077x** |
| Dyadic fallback, near-degenerate | 476.00 ns | 389.85 ns | **1.221x** |
| Dyadic fallback, subnormal | 261.65 ns | 185.44 ns | **1.411x** |

The ordinary filtered path is slightly faster than the current GCC reference.
The collinear expansion fallback is effectively at parity with C++, while the
near-degenerate expansion fallback remains approximately 10% slower.

The dyadic fallback remains the largest relative gap, particularly for the
subnormal case, but all measured dyadic cases remain below the 1.5x
investigation threshold. These paths are also exceptional fallbacks rather
than the expected workload for ordinary finite geometry.

### Expansion component comparison

The same controlled environment was used for the lower-level expansion
comparison.

| Expansion component | D/LDC | C++/GCC | D/C++ |
| --- | ---: | ---: | ---: |
| `twoSum` | 3.72 ns | 5.25 ns | **0.709x** |
| `twoDiff` | 3.72 ns | 4.71 ns | **0.790x** |
| `fastTwoSum` | 3.10 ns | 4.84 ns | **0.641x** |
| `twoProduct` | 5.80 ns | 6.24 ns | **0.929x** |
| `scaleExpansion 2->4` | 15.65 ns | 16.28 ns | **0.961x** |
| `fastExpansionSum 4+4` | 45.20 ns | 41.37 ns | **1.093x** |
| Exact orientation, collinear | 77.39 ns | 81.68 ns | **0.947x** |
| Exact orientation, near-degenerate | 89.86 ns | 98.07 ns | **0.916x** |

The primitive EFT measurements are useful diagnostically, but the complete
expansion and orientation measurements are the more meaningful cross-language
comparison because minor differences in helper inlining can affect isolated
primitive timings.

### Effect of the explicit binary64 rounding backend

The original robust binary64 implementation used `core.math.toPrec!double` at
every elementary rounding point required by the filter and expansion
arithmetic.

Under LDC 1.41, these operations resulted in non-inlined runtime calls.
Component-level investigation showed that the call boundaries, rather than the
robust arithmetic itself, dominated the cost of the exact expansion
implementation.

The LDC-specific backend introduced by ADR-0014 replaces those runtime calls
with explicit plain LLVM binary64 operations:

- `fadd double`;
- `fsub double`;
- `fmul double`.

No fast-math flags are attached.

DMD and other compilers continue to use the portable
`core.math.toPrec!double` implementation.

Before adopting the backend, the explicit LLVM operations were validated
against `toPrec!double` for edge cases and 1,000,000 additional
deterministically generated finite binary64 operand pairs. Addition,
subtraction, and multiplication were bit-identical in all tested cases.

Code-generation inspection of the relevant LDC hot paths additionally
confirmed:

- no x87 floating-point arithmetic;
- no fused multiply-add contraction;
- no remaining `toPrec` calls;
- scalar binary64 arithmetic using the expected SSE/AVX scalar instructions.

The resulting end-to-end improvement is substantial:

| Robust binary64 path | Before | After | Change |
| --- | ---: | ---: | ---: |
| Filter fast path | 29.40 ns | 20.91 ns | **-28.9%** |
| Expansion fallback, collinear | 238.85 ns | 101.27 ns | **-57.6%** |
| Expansion fallback, near-degenerate | 275.33 ns | 128.10 ns | **-53.5%** |
| Dyadic fallback, collinear | 497.77 ns | 482.66 ns | **-3.0%** |
| Dyadic fallback, near-degenerate | 507.47 ns | 476.00 ns | **-6.2%** |
| Dyadic fallback, subnormal | 294.41 ns | 261.65 ns | **-11.1%** |

The large improvement in the filter and expansion paths confirms that the
previous performance deficit was primarily caused by the LDC `toPrec` call
boundaries rather than by the robust predicate algorithms themselves.

The smaller improvement in dyadic end-to-end cases is expected: the dyadic
arithmetic backend itself was not changed, but these calls still pass through
now-cheaper filter and exact-fallback preparation before reaching the dyadic
determinant.

### Performance gate status

The provisional performance targets for geo-d are:

- simple primitives and linear loops: ideally no more than 1.25x a comparable
  C/C++ implementation;
- robust ordinary fast paths: ideally no more than 1.5x;
- exact fallbacks: ideally no more than 2x;
- higher-level algorithms: same asymptotic complexity and preferably no more
  than 1.5x;
- ratios above 2x for comparable implementations require investigation.

For robust `orientation(double)`, the current implementation passes all
applicable gates.

The ordinary filtered path is **0.924x** the algorithm-equivalent C++
reference.

The exact expansion fallbacks are **0.978x** and **1.101x**.

The measured dyadic fallbacks range from **1.077x** to **1.411x**.

Therefore, as of the explicit binary64 rounding backend, there is no remaining
robust binary64 orientation path above the 1.5x target and no current
orientation performance blocker.

Further optimization of these paths is not required for the present maturity
milestone unless later workloads, architectures, compiler versions, or
regression benchmarks reveal a new material gap.

## Geometry bounding-box performance

The public geometry-bounds operation is a linear reduction over stored
coordinates.

For a segment its complexity is O(1). For polyline and linear-ring views it is
O(n), and for polygons it is O(total stored vertices). Auxiliary storage is
O(1), and the operation performs no allocation.

### Benchmark scope

`benchmarks/bounding_box_bench.d` measures `tryBounds()` for ordinary finite
binary64 geometry and compares it with diagnostic raw-slice implementations.

Polyline sizes are:

- 10 points;
- 100 points;
- 1,000 points;
- 10,000 points;
- 100,000 points.

The polygon case contains four rings with 2,500 stored vertices each, for
10,000 total vertices.

All benchmark-data allocation occurs before the timed operation.

The comparison implementations are:

1. the public `tryBounds()` view-based operation;
2. a raw-slice reduction using `Bounds2.tryExtend()`;
3. a direct scalar min/max reduction.

The polygon benchmark additionally contains a direct nested-ring scalar
reduction.

These are intra-D diagnostic comparisons. They are not substitutes for an
algorithm-equivalent C/C++ reference and therefore must not be interpreted as
cross-language performance ratios.

### Initial optimized baseline

Repeated release measurements on the development machine showed approximately
linear steady-state behaviour.

    LDC:

        PolylineView, 1,000..100,000 points:
            approximately 1.2 ns per point

        PolygonView, 4 x 2,500 vertices:
            approximately 1.4 ns per point

    DMD:

        PolylineView, 1,000..100,000 points:
            approximately 4.0-4.4 ns per point

        PolygonView, 4 x 2,500 vertices:
            approximately 4.7-5.0 ns per point

The LDC public polyline implementation is approximately at parity with the
direct scalar raw-slice extrema loop for large inputs.

DMD retains a measurable gap to that direct loop, approximately 1.4x for large
polylines in the measured runs. This remains a diagnostic compiler/code-
generation difference rather than evidence of view-abstraction overhead:
the public implementation is substantially faster than the original
`Bounds2.tryExtend()` reduction.

### Bounds-accumulator optimization

The initial implementation used `Bounds2.tryExtend()` for every stored point.

That operation is an appropriate general-purpose single-point mutation
primitive, but benchmarking showed that repeatedly invoking its full state
handling inside a large linear reduction introduced measurable hot-loop cost.

The retained implementation therefore uses a private scalar-extrema
accumulator while traversing geometry and constructs the final `Bounds2` only
after the reduction completes.

The change preserves:

- empty-geometry semantics;
- transactional failure on NaN;
- support for infinities;
- exact coordinate extrema;
- polygon representation semantics;
- allocation-free execution;
- O(n) time and O(1) auxiliary storage.

For large polylines the change reduced measured end-to-end cost by roughly
30 percent relative to the original implementation.

The optimization is private implementation detail and does not alter the
public API or numerical contract.

### Current assessment

The geometry-bounds implementation has the expected asymptotic behaviour and
no material abstraction penalty under the primary performance compiler.

The remaining DMD difference relative to a hand-written direct extrema loop is
recorded for regression tracking but does not currently justify additional
source complexity.

No geometry-bounds performance blocker remains for the current v1 maturity
milestone.
