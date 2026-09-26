# Polygon union research

Status: research gate for Issue #36  
Branch: `research/polygon-union-overlay`  
Scope: coordinate-system-agnostic Euclidean 2D polygon union only

## 1. Purpose

The OSM-editor consumer audit identified polygon union as the first
consumer-backed geometry construction that is genuinely missing from
`geo-d`.

The requirement is not OSM-specific:

- accept two valid polygonal regions;
- construct their set-theoretic union;
- reconstruct resulting exterior boundaries and holes;
- permit more than one disconnected polygon component;
- preserve the library's separation between exact topology and rounded
  coordinate construction.

This document is a research artifact. It does **not** define a public API and
does not authorize production implementation.

Related evidence:

- Issue #36;
- `docs/osm-editor-workflow-requirements.md`;
- `DESIGN_PRINCIPLES.md`;
- the existing robust segment-intersection and polygon-validation contracts.

## 2. Existing geo-d constraints

Any union design has to preserve the contracts already established by
`geo-d`.

### 2.1 Representation and validation remain separate

`Polygon2View` is a non-owning view. It does not allocate, copy, validate,
repair, normalize winding, or infer ring roles from orientation.

A union operation therefore must not silently turn representable invalid input
into a repaired polygon.

The strongest initial contract is:

> polygon union accepts inputs that satisfy the existing
> `validatePolygon` contract, plus operation-specific finite/scalar
> preconditions.

If a later design deliberately accepts a wider input domain, that must be a
separate documented decision.

### 2.2 Topology is not decided from rounded construction

The existing intersection contract is explicit:

- topological classification is exact in the supported input domain;
- coordinate construction is a separate rounded operation;
- a global epsilon is not used to guess topology.

Polygon overlay must preserve the same principle.

In particular, rounded intersection coordinates must not be used as the
authoritative test for:

- whether two split vertices are identical;
- which edge precedes another around an arrangement vertex;
- whether a zero-length subedge exists mathematically;
- whether a boundary cycle closes;
- whether a ring is exterior or a hole.

### 2.3 Ownership and allocation are part of the contract

Variable-size output is unavoidable.

The established preference is:

1. views for borrowed input;
2. no hidden allocation on low-level paths where caller management is
   practical;
3. caller-provided destination/workspace and size queries when feasible;
4. an owning abstraction only when it is genuinely the clearer contract.

The research must therefore separate the **overlay algorithm** from the
eventual **public result-storage API**.

### 2.4 Determinism matters

Union is mathematically commutative. The implementation should not expose
accidental traversal-order differences as unstable output.

The public design must define deterministic behavior for at least:

- component order;
- exterior/hole order;
- ring starting vertex;
- ring direction, if direction is normalized at all;
- ties at vertices where several boundary edges meet.

Deterministic output does not necessarily require a single geometric
canonicalization policy, but it does require a documented ordering policy.

## 3. Reference implementations and models

The goal of this comparison is not to copy another library's API. It is to
identify robust implementation models and independent validation oracles.

## 3.1 CGAL 2D regularized Boolean set operations

CGAL's `Boolean_set_operations_2` package is the strongest semantic reference
for the exact-topology model required by `geo-d`.

Relevant properties:

- it implements regularized Boolean set operations on polygonal point sets;
- union is exposed as `join`;
- simple polygons and polygons with holes are supported;
- range-based union may return multiple polygons with holes;
- the documented examples use
  `Exact_predicates_exact_constructions_kernel`;
- for aggregate operations CGAL documents construction of a planar
  arrangement using a sweep-line algorithm and extraction of the result from
  that arrangement.

For `geo-d`, the important architectural idea is:

> build a topologically authoritative arrangement first, then extract region
> boundaries from it.

CGAL is also a strong candidate for an **offline exact oracle**. Finite
`int`, `long`, `float`, and `double` input coordinates can be converted
to exact rational values for a reference calculation without making CGAL a
runtime dependency.

References:

- https://doc.cgal.org/latest/Boolean_set_operations_2/index.html
- https://doc.cgal.org/latest/Boolean_set_operations_2/group__boolean__join.html

## 3.2 JTS / GEOS OverlayNG

JTS OverlayNG and its GEOS port provide a modern graph/noding overlay
architecture and extensive practical robustness work.

Relevant properties:

- overlay is based on noded edges and a topology graph;
- the computation precision model can differ from the input precision model;
- fixed-precision overlay uses snap rounding;
- floating-precision overlay uses a faster noder that may not be fully robust;
- `OverlayNGRobust` retries with increasingly robust snapping strategies and
  finally snap rounding;
- strict mode can omit lower-dimensional artifacts caused by topology collapse.

This is valuable implementation evidence, especially for:

- noding architecture;
- edge labeling;
- graph extraction;
- robust fallback strategy;
- performance-oriented clipping and indexing.

However, its default robustness model is not automatically the `geo-d`
semantic model.

Snap rounding deliberately changes coordinates and can change topology at the
selected precision. That is useful and valid when a precision model is part of
the contract, but `geo-d` currently defines topology from the representable
input values themselves.

Therefore:

> OverlayNG is a primary architecture reference and a secondary differential
> oracle, but snap rounding must not silently become geo-d's default topology
> semantics.

References:

- https://locationtech.github.io/jts/javadoc/org/locationtech/jts/operation/overlayng/OverlayNG.html
- https://locationtech.github.io/jts/javadoc/org/locationtech/jts/operation/overlayng/OverlayNGRobust.html
- https://libgeos.org/doxygen/classgeos_1_1operation_1_1overlayng_1_1OverlayNG.html

## 3.3 Clipper2

Clipper2 is a strong practical reference for high-performance polygon clipping.

Relevant properties:

- union, intersection, difference, and XOR are implemented;
- both integer and floating-facing APIs use integer coordinates internally;
- floating input is scaled to integers and de-scaled afterwards;
- the integer representation is the basis of its robustness model;
- the documentation explicitly discusses coordinate-range limits and rounding
  artifacts.

This makes Clipper2 especially useful for:

- integer-domain differential tests;
- scanbeam/active-edge implementation ideas;
- stress/performance comparisons;
- shared-edge and complex clipping fixtures.

It is not a direct semantic match for unquantized floating `geo-d` input,
because its floating path intentionally quantizes coordinates.

References:

- https://www.angusj.com/clipper2/Docs/Overview.htm
- https://www.angusj.com/clipper2/Docs/Robustness.htm

## 3.4 Boost.Geometry

Boost.Geometry exposes OGC-style polygon union and writes results to an output
collection, so it is useful API and behavior evidence for result multiplicity.

Its documentation requires valid polygon input and explicitly notes that
algorithms such as union do not perform validity repair.

The release history also contains multiple fixes for union edge cases across
versions. That is useful evidence that robust overlay is not a small extension
of segment intersection and deserves an independent research/design gate.

Boost.Geometry is therefore a useful secondary differential implementation,
not the preferred semantic oracle for `geo-d`.

References:

- https://www.boost.org/doc/libs/latest/libs/geometry/doc/html/geometry/reference/algorithms/union_/union__3.html
- https://www.boost.org/latest/libs/geometry/doc/html/geometry/release_notes.html

## 4. Algorithm-family comparison

## 4.1 Pairwise traversal algorithms

Algorithms in the Weiler-Atherton / Greiner-Hormann family are attractive for
small simple-polygon cases because the implementation can be compact.

They are a poor primary architecture for the required scope because the hard
cases are exactly the cases `geo-d` must define explicitly:

- holes;
- disconnected output;
- coincident/shared edges;
- partially overlapping collinear edges;
- multiple segments meeting at one exact point;
- deterministic reconstruction after degeneracies.

Disposition: useful educational/reference material, not the preferred
production core.

## 4.2 Scanbeam / active-edge clipping

Vatti/Clipper-style scanbeam algorithms are proven practical designs for
polygon clipping and can be highly performant.

Their strongest robustness story is usually tied to an integer or quantized
coordinate model.

Disposition:

- study for event ordering, active-edge handling, and performance;
- use Clipper2 for integer-domain differential evidence;
- do not adopt quantization as an implicit floating-point semantic change.

## 4.3 Noded planar arrangement / overlay graph

A planar arrangement model is the best fit for the existing `geo-d`
contracts.

Conceptually:

1. enumerate polygon boundary segments with source/ring metadata;
2. discover all cross-boundary intersections and overlaps;
3. node/split every boundary at topologically exact event positions;
4. create exact arrangement vertices and directed subedges;
5. classify edge sides or arrangement faces with respect to both operands;
6. keep the boundary separating union interior from union exterior;
7. trace closed result cycles;
8. reconstruct exteriors, holes, and disconnected components;
9. materialize public output coordinates only after topology is fixed.

This architecture naturally separates:

- exact topological decisions;
- coordinate construction;
- boundary reconstruction;
- result storage.

Disposition: **preferred research architecture**.

## 5. Central numerical problem: exact arrangement vertices

The main numerical problem is larger than computing one correctly rounded
segment-intersection point.

For segment intersection, `geo-d` can classify the crossing exactly and then
round one constructed point to binary64.

Overlay needs more.

The arrangement must be able to determine exactly whether intersection events
from different segment pairs denote the same mathematical point and how those
events are ordered along segments and around vertices.

For finite binary input:

- original integer coordinates are exact integers;
- original `float` and `double` coordinates are exact dyadic rationals;
- a proper line/segment intersection is generally a rational coordinate and
  is not necessarily dyadic.

Therefore a robust arrangement needs an internal representation capable of
exact equality/order for rational intersection positions.

### 5.1 Recommended internal direction

Do **not** round every crossing immediately to `double` and use the rounded
point as the graph key.

Instead, investigate an internal exact event representation built from the
same arithmetic foundation already used by robust intersection construction.

The required internal operations include:

- exact equality of event positions;
- exact ordering of events along a source segment;
- exact comparison of coordinates where sweep/event ordering requires it;
- exact identification of coincident overlap endpoints;
- stable hashing or an alternative deterministic interning strategy.

This representation is an implementation detail and should not be promoted to
the public API merely because overlay needs it.

### 5.2 Output rounding can still alter topology

Even if the internal arrangement is exact, final conversion to a public
coordinate type can collapse two distinct exact vertices to the same rounded
binary64 point.

That means "exact topology internally, then always emit rounded points" is not
by itself a complete contract.

Three broad policies exist:

1. **round and validate; fail if materialization changes required topology**;
2. expose exact/rational public coordinates;
3. explicitly quantize/snap to a caller-selected precision model before
   overlay.

For the current `geo-d` scalar and API model, option 1 is the best research
baseline.

Option 2 would be a major public scalar-model expansion.

Option 3 may be useful in a future explicitly quantized API, but it would be a
different topology contract and must never happen implicitly.

Research recommendation:

> prototype exact topology plus rounded materialization with an explicit
> "cannot represent valid result under the requested output scalar" failure
> path.

No public failure type or spelling is proposed yet.

## 6. Input contract and degeneracy matrix

The first design should operate on individually valid polygon inputs under the
existing validator.

Cross-operand interactions still require explicit semantics.

The research/test matrix must include at least:

### Ordinary cases

- disjoint polygons;
- partial overlap;
- one polygon wholly contained in the other;
- identical polygons;
- polygon contained inside an existing hole;
- overlap that removes part or all of a hole;
- union producing multiple disconnected components.

### Boundary contacts

- one shared vertex;
- multiple shared vertices;
- a complete shared edge;
- a partially shared collinear edge;
- several consecutive shared edges;
- a vertex touching the interior of the other polygon's edge;
- coincident boundaries with opposite traversal directions.

### Numerically difficult cases

- intersections extremely close to existing vertices;
- several intersections that round to the same binary64 coordinate;
- very large and very small finite magnitudes;
- subnormal floating coordinates;
- full-range supported integer cases where intermediate arithmetic exceeds
  native widths;
- argument order and ring-order permutations.

### Invalid/non-finite cases

The operation should not silently repair:

- non-finite coordinates;
- self-intersecting rings;
- invalid hole relationships;
- zero-length edges where the existing validation contract rejects them.

The exact failure contract remains a design-gate question.

## 7. Result multiplicity and representation

A polygon union cannot assume one result polygon.

The result may need:

- zero components if empty polygons are admitted and both operands are empty;
- one polygon;
- multiple disconnected polygons;
- holes inside any component.

This means the existing `Polygon2View` is suitable as an **input** model but
is not by itself an owning result container.

### 7.1 Public-result options to evaluate

#### Option A — caller-provided flat buffers

Possible ingredients:

- point destination;
- ring-descriptor destination;
- polygon/component descriptor destination;
- workspace;
- a size/planning pass.

Advantages:

- explicit allocation;
- compatible with low-level `@nogc` goals;
- views can reference caller-owned result storage.

Costs:

- exact output size is known only after overlay;
- a pure size query may itself require most of the overlay computation;
- two-pass execution may duplicate expensive work unless the planning result
  is reusable.

#### Option B — explicit owning overlay result

Advantages:

- naturally handles unknown result size;
- straightforward consumer ergonomics;
- easier first production implementation.

Costs:

- introduces the first owning variable-size polygon result abstraction;
- hidden/default allocation would need a deliberate contract;
- must not make existing views dependent on an owning type.

#### Option C — caller-supplied allocator/build sink

Advantages:

- explicit allocation policy;
- can stream reconstructed rings/components into caller-selected storage.

Costs:

- materially more complex API;
- difficult rollback semantics if a late materialization failure occurs;
- may expose implementation structure prematurely.

Research disposition:

> keep the overlay core independent from public ownership choice. Do not
> introduce an owning public polygon type solely to unblock the first
> experiment.

## 8. Deterministic output policy

The implementation should be tested under:

- operand swap;
- ring reversal;
- equivalent ring start rotations;
- segment enumeration changes that do not change geometry.

A useful deterministic target is:

- identical geometric union under operand swap;
- stable component/ring ordering under a documented canonical key;
- stable ring start under the same canonical key;
- no dependency on hash-table iteration order.

The exact canonical key is not yet selected.

Any ordering scheme must be defined using exact internal geometry where
possible, not unstable rounded intermediate coordinates.

## 9. Complexity and implementation staging

For two polygons with `n` and `m` boundary edges and `k` arrangement
intersections, production-quality overlay should avoid unconditional
`O(n*m)` intersection discovery for large inputs.

Sweep-line or indexed noding is the likely production direction.

However, the first research prototype should optimize for semantic evidence,
not throughput.

Recommended staging:

### Phase R1 — exact semantic prototype

- pairwise edge-pair discovery is acceptable;
- exact event identity/order;
- explicit overlap handling;
- exact arrangement graph;
- deterministic boundary tracing;
- small exhaustive/degenerate fixture set;
- no public API.

Purpose: establish the correctness model.

### Phase R2 — independent differential harness

Compare generated fixtures against:

1. CGAL with exact predicates/exact constructions — primary exact oracle;
2. GEOS/JTS OverlayNG — pragmatic secondary oracle;
3. Clipper2 for integer/scaled integer fixtures;
4. Boost.Geometry as an additional implementation diversity check.

Disagreements must be classified by semantic contract rather than majority
vote.

### Phase R3 — scalable noding

Only after the topology model is stable:

- sweep-line or spatially indexed intersection discovery;
- benchmark event/noding cost;
- compare DMD and LDC;
- preserve exact semantic results from R1.

## 10. Property and metamorphic verification

Useful properties include:

- commutativity: `A union B == B union A` geometrically;
- idempotence: `A union A == A`;
- identity: `A union empty == A`, if empty input is admitted;
- containment: every input interior point belongs to the result;
- area monotonicity: union area is not smaller than either valid operand;
- permutation invariance under ring start rotation;
- ring-reversal invariance where input winding is semantically irrelevant;
- translation invariance for transformations representable without scalar
  overflow;
- exact integer fixtures agree with an exact reference implementation.

Geometric equality for these tests must not be reduced to sequence equality of
ring arrays unless the output contract deliberately canonicalizes sequence
representation.

## 11. Recommended architecture

Current research recommendation:

1. **Proceed** with a dedicated overlay design/prototype gate.
2. Use a **noded planar arrangement / overlay graph** as the primary internal
   architecture.
3. Preserve **exact topological decisions** for finite supported scalar input.
4. Develop an **internal exact overlay-event representation** rather than
   using rounded binary64 intersection coordinates as graph identity.
5. Perform public-coordinate rounding only after the selected union boundary
   is known.
6. Treat topology-changing output rounding as an explicit failure/design case,
   not as silent repair.
7. Require valid polygon input initially; keep validation explicit.
8. Keep result-storage/API ownership separate from the overlay core.
9. Use CGAL exact Boolean set operations as the primary independent semantic
   oracle.
10. Keep JTS/GEOS, Clipper2, and Boost.Geometry as diverse secondary evidence.
11. Do not expose intersection/difference/symmetric-difference publicly merely
    because an internal generalized overlay engine could support them.
12. Do not introduce implicit snap rounding or a global epsilon.

## 12. What is not decided yet

This research does not yet choose:

- a public function name;
- a public result type;
- an owning polygon type;
- a workspace-size API;
- a failure/result enum;
- ring orientation normalization;
- component/ring canonical ordering;
- whether empty input is accepted;
- whether `real` is supported;
- whether an explicitly quantized/snap-rounded mode should ever exist;
- whether a general Boolean-overlay internal engine is worth the additional
  complexity in the first implementation.

Those belong to the next design/ADR gate.

## 13. Issue #36 acceptance status

This document satisfies the first research comparison and narrows the
architecture, but Issue #36 should remain open until the repository also has a
concrete executable research prototype or equivalent evidence for the exact
event/arrangement model.

Current status:

- [x] relevant algorithm families and robust-overlay models compared;
- [x] degeneracy/shared-boundary cases enumerated;
- [x] numerical/topological construction direction proposed against existing
      `geo-d` contracts;
- [x] result multiplicity and ownership options evaluated;
- [x] performance/complexity staging documented;
- [x] independent oracle strategy identified;
- [x] recommendation recorded: proceed to an exact-arrangement
      design/prototype gate;
- [ ] exact-event representation validated by executable prototype/evidence;
- [ ] public API remains blocked pending a separate design/ADR decision.

## 14. Primary references

CGAL:

- https://doc.cgal.org/latest/Boolean_set_operations_2/index.html
- https://doc.cgal.org/latest/Boolean_set_operations_2/group__boolean__join.html

JTS / GEOS:

- https://locationtech.github.io/jts/javadoc/org/locationtech/jts/operation/overlayng/OverlayNG.html
- https://locationtech.github.io/jts/javadoc/org/locationtech/jts/operation/overlayng/OverlayNGRobust.html
- https://libgeos.org/doxygen/classgeos_1_1operation_1_1overlayng_1_1OverlayNG.html

Clipper2:

- https://www.angusj.com/clipper2/Docs/Overview.htm
- https://www.angusj.com/clipper2/Docs/Robustness.htm

Boost.Geometry:

- https://www.boost.org/doc/libs/latest/libs/geometry/doc/html/geometry/reference/algorithms/union_/union__3.html
- https://www.boost.org/latest/libs/geometry/doc/html/geometry/release_notes.html
