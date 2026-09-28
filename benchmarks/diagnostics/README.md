# Diagnostic benchmarks

This directory contains one-off diagnostic tools used to investigate
numerical implementation and compiler-code-generation behavior.

They are not part of the regular performance regression benchmark suite.

## `run_toprec_probe.sh`

Compares the production robust-expansion implementation using
`core.math.toPrec!double` with a diagnostic variant using direct binary64
arithmetic.

The probe was used to isolate the runtime cost of LDC's non-inlined
`toPrec!double` calls.

Removing only those rounding-call boundaries reduced the cost of the
error-free-transformation and exact-expansion paths substantially, showing
that the principal performance deficit was not caused by the expansion
algorithms themselves.

The direct-arithmetic variant intentionally does not provide the portable
D-language rounding guarantee and must not be used as the production
implementation.

## `run_ldc_ir_rounding_probe.sh`

Compares three implementations derived from the current rounding backend:

1. a portable `core.math.toPrec!double` reference variant;
2. a direct-D binary64 diagnostic variant;
3. the production LDC backend using explicit plain LLVM binary64 arithmetic
   through `ldc.llvmasm.__ir_pure`.

The diagnostic was used to validate the LDC-specific rounding backend
adopted in ADR-0014 and is kept aligned with the current
`geo.internal.binary64_rounding` architecture.

The probe checks:

- bitwise agreement of the production backend with `toPrec!double` on
  selected edge cases and 1,000,000 additional deterministic finite
  binary64 operand pairs;
- a negative control that deliberately corrupts the addition backend and
  verifies that a mismatch terminates the semantic probe with non-zero status
  even when compiled with `-release`;
- generated hot-path instructions;
- absence of unintended x87 arithmetic;
- absence of fused multiply-add contraction;
- absence of residual `toPrec` calls;
- component and exact-expansion performance.

The explicit LLVM-IR implementation matched direct binary64 arithmetic
performance while preserving the tested `toPrec!double` results.

## Status

These tools document the investigation that led to the explicit binary64
rounding backend.

Normal performance regression testing should use the benchmark runners in
the parent `benchmarks/` directory instead.


## Polygon Union P3 stage probe

`polygon_union_p3_stage_probe.d` is a research-only diagnostic for issue #42.

It compiles the normal public `polygonUnion` path with the explicit version
identifier `GeoPolygonUnionP3Diagnostics`. That identifier enables
package-internal, thread-local counters and stage timing inside the P1
orchestration. Builds without the identifier contain none of that
instrumentation.

The probe records source-edge and candidate counts, intermediate arrangement
cardinalities, and median stage timings over seven post-warm-up public calls.

The envelope scan is deliberately a separate diagnostic pass. Its timing is
reported separately and must not be interpreted as an optimization already
present in P1.

The first retained fixtures compare disjoint and overlapping regular convex
polygons at 16, 64, and 128 vertices per input. Additional adversarial/high-
crossing fixtures are a later research slice; no P3 algorithm is selected by
this first probe.

This diagnostic is evidence only. It is not a public API, a reusable spatial
index, or part of the normal performance-regression suite.


## Polygon Union P3 event-workspace control

`polygon_union_p3_event_workspace_probe.d` isolates the P1 noding workspace
without modifying `polygonUnion` or the production P1 orchestration.

It compares:

1. the current eager P1 worst-case event reservation; and
2. a two-pass exact-sized control.

Both paths retain the same deterministic all-pairs source-edge traversal. The
control first performs an additional exact contact-classification pass to count
the required event capacity for every source edge, then allocates exactly that
flat event storage and runs the existing append logic over all pairs again.

Before timing, the probe verifies edge by edge and event by event that both
workspace strategies produce the same exact noding-event sequence.

The control is deliberately pessimistic in CPU work: it performs one extra
O(n^2) exact classification pass. A speedup therefore isolates the value of
avoiding eager worst-case event allocation rather than conflating it with a
candidate-discovery optimization.

This is research evidence only. It is not a production workspace design and
does not establish a non-quadratic worst-case event bound.


## Polygon Union P3 envelope-gated workspace control

`polygon_union_p3_envelope_workspace_probe.d` compares two exact-sized event
workspace strategies while leaving `polygonUnion` and P1 production code
unchanged.

Both strategies retain the same deterministic nested source-edge pair order.
The baseline performs exact contact classification for every pair. The
envelope-gated control first applies a closed axis-aligned source-coordinate
segment-envelope overlap test and performs exact contact classification only for
pairs that pass that necessary condition.

The control intentionally remains O(n^2) in cheap envelope comparisons. It does
not implement a sweep line, R-tree, quadtree, STR tree, or any reusable
spatial-index/container abstraction.

Before timing, the probe verifies exact event counts and every exact event,
edge by edge and in sequence, against the all-exact-pairs exact-sized
workspace.

This isolates how much value a minimal deterministic broad phase provides
before more complex candidate-discovery research is justified.


## Polygon Union P3 envelope 100%-candidate stress probe

`polygon_union_p3_envelope_worst_case_probe.d` is a deliberately low-level
segment diagnostic for the envelope broad-phase guard.

It constructs concurrent non-collinear segments whose closed axis-aligned
envelopes all contain the origin. Therefore every pair is an envelope
candidate and every pair is a proper crossing. The guard rejects nothing.

The probe compares exact contact classification alone against
envelope-test-plus-the-same-exact-classification, alternating measurement
order and reporting the median of seven repetitions.

This is not a valid-polygon fixture and makes no polygon-semantics claim. Its
purpose is only to bound the overhead of the proposed envelope guard at 100%
candidate density, complementing the valid sparse and high-crossing polygon
fixtures.


## Polygon Union P3 envelope candidate-density sweep

`polygon_union_p3_envelope_density_probe.d` is a low-level segment diagnostic
at a fixed 256 source segments.

The segments are distributed over spatially separated concurrent clusters.
Within one cluster every pair has overlapping envelopes and is a proper
crossing. Across clusters the segment envelopes are disjoint.

Using 1, 2, 4, 8, 16, 32, and 64 equal clusters sweeps candidate density from
100% down through approximately 50%, 25%, 12%, 6%, 3%, and 1% while total pair
count remains constant.

The probe compares exact classification of every pair against
envelope-test-plus-exact-classification of candidates only. Measurement order
alternates across seven repetitions.

This diagnostic is intended to locate the compiler-specific crossover region
for the envelope guard. It is not itself a production threshold policy.


## Polygon Union P3 envelope upper-density refinement

`polygon_union_p3_envelope_upper_density_probe.d` refines the high-density
crossover region at a fixed 256 source segments.

One concurrent dense cluster contains 216, 224, 232, 240, 248, 252, 254, or
255 segments. The remaining segments are spatially isolated from the dense
cluster and from each other. Candidate density is therefore exactly
`C(denseCount, 2) / C(256, 2)`, covering approximately 71% through 99%.

The probe compares exact classification of every pair against
envelope-test-plus-exact-classification of candidates only, alternating
measurement order across seven repetitions.

This diagnostic narrows the compiler-specific break-even region. It does not
define a production threshold by itself.
