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
