# ADR-0023 — Polygon union exact-overlay and result contract

**Status:** Proposed  
**Date:** 2026-09-27

## Context

The OSM-editor consumer audit identified polygon union as a genuine missing
coordinate-system-agnostic Euclidean 2D construction in `geo-d`.

The existing public surface already provides the main low-level ingredients:

- `Polygon2View` and `LinearRing2View`;
- exact orientation for the current robust scalar domain;
- exact segment-intersection topology;
- exact proper-intersection construction data before final binary64 rounding;
- exact point-in-polygon classification for represented input points;
- ring and polygon topology validation;
- exact signed-area accumulation before final rounding.

It does not provide an operation that constructs the geometric union of two
polygons and reconstructs the resulting exterior boundaries and holes.

Issue #36 researched robust overlay architectures. Draft research PR #37 added
executable evidence for exact overlay-event comparison. Issue #38 is the
design gate for the durable contract.

The research establishes a particularly important numerical fact.

Two mathematically distinct proper segment intersections can both correctly
round to the same binary64 coordinate. Therefore rounded construction points
cannot be used as authoritative arrangement-vertex identity or event order.

This ADR proposes the overlay architecture and the result semantics that must
be established before production polygon-union implementation begins.

It deliberately does not select final public API spelling.

## Decision

### 1. Polygon union belongs in geo-d

Polygon union is a Euclidean 2D geometry operation.

It does not require:

- a CRS;
- projection semantics;
- ellipsoidal/geodesic semantics;
- OSM tags or relation semantics;
- spatial indexing as part of the public geometry contract.

The operation therefore belongs in `geo-d`.

The consumer evidence currently promotes **union only**.

A generalized internal overlay core may be used when that materially improves
correctness, reuse inside the implementation, or verification. That does not
promote intersection, difference, or symmetric difference to public API.

### 2. Initial robust scalar domain

The topology-supported input scalar domain is:

~~~text
int
long
float
double
~~~

This matches the current exact/robust predicate and intersection domain.

`real` remains outside this gate.

This ADR does not alter ADR-0016 and does not permit conversion of `real` to
`double` to simulate robust support.

### 3. Semantic input domain is valid polygons, including empty polygons

The semantic domain follows the established polygon-validation contract.

An empty `Polygon2View` is a valid empty polygon.

A non-empty input polygon must satisfy the existing `validatePolygon`
contract.

Polygon union does not silently:

- repair invalid rings;
- normalize invalid ring relationships;
- resolve self-intersections;
- discard invalid holes;
- snap malformed geometry onto a precision grid.

The final public API may expose validation failure as a checked result rather
than a language-level precondition. That spelling remains an API-design
question.

The set semantics themselves are defined only for the valid-polygon domain.

### 4. Union is a regularized two-dimensional set operation

The operation constructs the regularized two-dimensional union of the two
valid polygonal regions.

Lower-dimensional contacts do not create artificial self-touching rings.

Consequences include:

- empty union empty is empty;
- union with an empty operand is the other region;
- containment returns the containing region;
- overlapping regions merge where their two-dimensional interiors connect;
- a shared boundary edge disappears from the result when union interior lies
  on both sides of that edge;
- polygons that meet only at an isolated point remain separate result
  components rather than becoming one self-touching ring.

Result components are therefore components of the **two-dimensional
interior**, not components merely connected through an isolated boundary
point.

This preserves the existing rule that one `Polygon2View` represents a
polygon with connected interior and does not encode multiple regions through a
self-touching ring.

### 5. Exact topology remains authoritative

The overlay topology must be determined from exact represented input geometry.

No global epsilon is introduced.

No rounded constructed coordinate may determine:

- event identity;
- event ordering;
- edge splitting;
- collinearity;
- shared-edge identity;
- arrangement adjacency;
- union interior/exterior classification;
- cycle closure;
- component or hole topology.

Rounded coordinates are construction output only.

This extends the topology/construction separation established by ADR-0004,
ADR-0005, ADR-0006, ADR-0014, and ADR-0022.

### 6. The primary internal model is a noded planar arrangement

The production direction is a planar arrangement / overlay graph.

Conceptually:

~~~text
validated polygon boundaries
        |
        v
exact pair/contact discovery
        |
        v
exact noding and edge splitting
        |
        v
exact arrangement vertices + atomic edges
        |
        v
2D cell / side labels for A and B
        |
        v
select boundary separating union interior from union exterior
        |
        v
trace exact result cycles
        |
        v
group exterior cycles + holes into result components
        |
        v
materialize public coordinates
~~~

A first correctness implementation may use pairwise boundary-segment
comparisons.

The eventual scalable implementation should avoid unconditional quadratic
candidate discovery for large inputs, but acceleration must not change the
semantic result.

### 7. Exact overlay points reuse the established rational-coordinate model

An internal overlay vertex is represented conceptually as an exact rational
point:

~~~text
xNumerator
------------ * 2^-1074
 denominator

yNumerator
------------ * 2^-1074
 denominator
~~~

with one positive denominator shared by x and y.

Proper segment crossings reuse the existing exact construction model:

~~~text
ExactProperIntersection
~~~

or a geometry-neutral equivalent derived from it.

Original input vertices and endpoint/overlap events are lifted into the same
exact coordinate model without rounding.

The existing A2 bounds remain the baseline for one constructed coordinate:

~~~text
coordinate/difference domain     66 limbs
dyadic products                  132 limbs
coordinate numerator             198 limbs
~~~

The current 198-limb numerator has 6336 bits. ADR-0022 records a conservative
construction bound below `2^6299`.

This ADR does not enlarge these widths by assumption.

Any additional fixed-width intermediate introduced by overlay must receive its
own range proof before the ADR can become Accepted.

### 8. Exact rational points are not normalized by GCD

Canonical fraction reduction is not required for geometric identity.

Two exact coordinates are compared by sign-aware cross-denominator integer
comparison.

Two exact points are equal exactly when both rational coordinates compare
equal.

The research prototype demonstrates this for proper intersections that denote
the same point while carrying different raw denominators.

Global arrangement-vertex identity should therefore be assigned by exact
lexicographic point ordering and deduplication rather than by hashing raw,
unreduced numerator/denominator storage.

This avoids making arbitrary-precision GCD or normalized rational storage a
new core dependency.

### 9. Edge events are ordered exactly along their source segment

Every event attached to one non-degenerate source segment is ordered without
constructing a floating segment parameter.

For a non-vertical source segment, x is strictly monotone along the segment.

For a vertical source segment, y is strictly monotone.

Exact rational coordinate comparison therefore defines source-edge event
order.

The executable research probe verifies:

- different-denominator equality;
- non-vertical event ordering;
- reversed source ordering;
- vertical event ordering;
- distinct exact events that collapse to one rounded binary64 value.

### 10. Collinear overlap is noded through exact input endpoints

For two collinear input segments, a positive-length overlap introduces no new
rational endpoint.

The overlap endpoints are selected from existing input endpoints, consistent
with the existing `trySegmentIntersectionOverlap` contract.

The overlay noder shall insert the exact overlap endpoints into both source
edges.

After all events are inserted, both source boundaries are split into atomic
segments.

Coincident atomic segments are identified by their exact endpoint vertex IDs,
independently of source traversal direction.

An atomic segment records which operand boundaries contribute to it.

The minimum operand-membership information is conceptually:

~~~text
A boundary contributes
B boundary contributes
~~~

plus any internal provenance required for deterministic diagnostics or
construction.

The arrangement must handle at least:

- identical shared edges with the same source direction;
- identical shared edges with opposite source directions;
- partially overlapping collinear edges;
- several consecutive shared edges;
- a source vertex lying in the interior of the other operand's edge.

### 11. Arrangement angular order reuses source-segment directions

A noded atomic segment remains collinear with the original input segment from
which it was produced.

Therefore outgoing half-edge angular order at an arrangement vertex does not
need to subtract two large rational event coordinates merely to rediscover the
edge direction.

Each atomic half-edge can retain or reconstruct the exact direction of an
original contributing source segment, reversing it when necessary.

Those source directions are differences of represented input coordinates and
already belong to the established exact difference/product domain.

Angular ordering can therefore use:

1. an exact half-plane/quadrant classification of the signed source
   direction;
2. the exact sign of the cross product between source directions;
3. deterministic tie handling for collinear rays.

Coincident atomic edges must be deduplicated before a same-ray tie could become
two distinct arrangement edges.

This is the preferred direction because it reuses the existing 66/132-limb
difference/product arithmetic instead of inventing a wider rational-direction
determinant.

**Acceptance gate:** an executable prototype must verify this angular-order
model for ordinary crossings, T-junctions, shared edges, opposite rays, and
multi-edge vertices before production implementation.

### 12. Union selection is based on exact two-operand region labels

The arrangement must determine, for each two-dimensional cell or equivalent
edge side, the exact parity pair:

~~~text
insideA
insideB
~~~

The union state is:

~~~text
insideA || insideB
~~~

A result boundary is an atomic edge whose two sides have different union
states.

This rule handles shared edges without source-order special cases.

Examples:

~~~text
identical polygons
    shared edge toggles A and B together
    outside/outside <-> inside/inside
    union edge is retained

adjacent polygons sharing an edge
    one side is inside A, the other inside B
    union is inside on both sides
    shared edge is removed
~~~

The implementation may realize exact region labels through a DCEL-style face
model, a sweep/depth propagation model, or an equivalent arrangement method.

The choice must preserve the same exact parity semantics.

**Acceptance gate:** before this ADR becomes Accepted, executable fixtures must
establish labeling for disconnected and nested arrangement components, not
only one connected crossing graph.

### 13. Exact boundary cycles are selected before coordinate materialization

Boundary tracing operates on exact arrangement vertex IDs and exact atomic
edges.

The selected exact boundary graph must be decomposed into simple closed result
cycles consistent with the regularized union semantics.

A self-touching cycle is not used to encode multiple regions.

Where an isolated boundary contact would otherwise join two cycles at one
vertex, separate cycles remain separate when their two-dimensional interiors
are distinct.

Exterior cycles and hole cycles are grouped into polygon components in exact
topology before public coordinate rounding.

### 14. The construction scalar follows IntersectionScalar

Polygon union can introduce rational intersection vertices even when every
input coordinate is integral.

Therefore output cannot generally remain in the input scalar domain.

The proposed construction scalar follows the existing construction family:

~~~text
input      union construction coordinate

int        double
long       double
float      double
double     double
~~~

Conceptually the result coordinate type is:

~~~d
IntersectionScalar!T
~~~

No new competing construction-scalar policy is introduced.

This remains a **proposed semantic decision**, not final public API spelling.

### 15. Output materialization is all-or-nothing

Exact union topology may exist even when it cannot be represented faithfully
by the public construction scalar.

Materialization therefore remains fallible.

All exact result vertices are rounded with the existing explicit
round-to-nearest, ties-to-even binary64 construction machinery.

Materialization fails if any required exact coordinate does not round to a
finite construction value.

Materialization also fails if rounding would change required result topology.

No partial result is exposed on failure.

No silent snap, vertex deletion, edge collapse, or topology repair is
performed.

### 16. Topology-preserving materialization requires more than finite rounding

The exact-event research demonstrates that two distinct exact vertices may
round to the same binary64 point.

Therefore successful materialization must verify at least:

- every required exact result coordinate rounds to a finite value;
- distinct exact result vertices required as distinct vertices do not collapse
  to one rounded point;
- no required result edge becomes zero-length;
- rounded non-adjacent result edges do not acquire a new crossing or
  positive-length overlap;
- each rounded result polygon satisfies the existing polygon-validation
  contract;
- rounded component relationships do not introduce an interior overlap or
  another relationship absent from the exact result topology.

The final implementation may prove some checks redundant from stronger
invariants and omit them.

It may not omit a check merely because ordinary inputs rarely trigger it.

**Acceptance gate:** the precise minimal validation set must be established by
the materialization prototype before this ADR becomes Accepted.

### 17. Result components preserve Polygon2View semantics

Each non-empty result component is representable as one valid polygon:

~~~text
ring 0      exterior
ring 1..n   holes
~~~

and has connected interior.

The complete union result may contain zero, one, or multiple polygon
components.

Multiple components are a higher-level collection of valid polygons; they are
not encoded as one self-touching `Polygon2View`.

Two result components may share an isolated boundary point when the exact
regularized union has separate interior components that meet only at that
point.

### 18. Proposed deterministic representation

Determinism is part of the result contract.

The proposed canonical construction rules are:

- trace every result boundary with union interior on the left;
- exterior cycles are therefore counter-clockwise in the ordinary Cartesian
  orientation;
- hole cycles are clockwise;
- choose the exact lexicographically smallest vertex as each ring's starting
  vertex;
- sort holes by their exact canonical starting vertex, with deterministic
  structural tie breakers if needed;
- sort polygon components by the exact canonical starting vertex of the
  exterior ring, again with deterministic structural tie breakers if needed.

Canonicalization decisions are made from exact arrangement geometry before
rounding.

Successful materialization must preserve the selected sequence identity; a
rounding collapse that destroys it is a representability failure.

**Acceptance gate:** permutation/reversal/property tests must verify that
operand order, source ring direction, and source ring start rotation do not
change the canonical result.

### 19. Proposed ownership model is an explicit owning immutable result

Polygon union has inherently data-dependent output size:

- intersection count is data dependent;
- split-edge count is data dependent;
- component count is data dependent;
- hole count is data dependent.

The algorithm also requires variable-size arrangement workspace.

A caller-buffer-only API would either require:

- a pessimistic worst-case allocation;
- an expensive planning execution that performs most of the overlay and then
  repeats it;
- or a public reusable plan/workspace abstraction whose complexity is not yet
  justified by a consumer.

The proposed initial public ownership model is therefore an **explicit owning,
read-only result**.

Its semantic requirements are:

- it owns the point/ring/component storage required by the constructed result;
- ordinary result copies must not perform hidden deep copies;
- shared backing storage, if used, is immutable through the result API;
- component access can expose ordinary `Polygon2View` /
  `LinearRing2View`-compatible read-only views where lifetime can be expressed
  safely;
- allocation behavior is documented explicitly;
- the union operation is not promised `@nogc`;
- the exact overlay core remains separable from the owning presentation so a
  future caller-managed/storage-specialized API remains possible without
  redefining topology.

This is the first concrete consumer that justifies revisiting the owning
aggregate deferral in ADR-0003.

This ADR still does **not** choose the public result type name or exact field
layout.

**Acceptance gate:** a small ownership/lifetime prototype must verify safe
copying, view lifetime, and absence of accidental mutable aliases before this
decision becomes Accepted.

### 20. No public exact-rational geometry type is introduced

The exact arrangement representation remains internal.

This ADR does not expose:

- arbitrary-precision integers;
- rational coordinate values;
- exact overlay vertices;
- DCEL/half-edge internals;
- arrangement face objects.

Those are implementation mechanisms, not consumer geometry types.

### 21. Internal overlay generality does not widen public scope

A union implementation may internally encode an operation selector or
generalized edge/face labels if that materially simplifies a correct overlay
engine.

That internal architecture does not authorize public:

- polygon intersection;
- polygon difference;
- symmetric difference.

Each additional public operation still requires consumer or research evidence
and an explicit API decision.

### 22. Performance staging

Correctness comes before asymptotic optimization.

The implementation stages are:

#### Stage P1 — semantic overlay core

A pairwise segment-contact/noding implementation is acceptable.

Target complexity may be quadratic in the total boundary-edge count.

The purpose is to validate:

- exact noding;
- shared-boundary semantics;
- arrangement embedding;
- region labels;
- cycle reconstruction;
- materialization checks.

#### Stage P2 — differential/property qualification

Verify against independent implementations and mathematical properties.

Primary exact reference:

- CGAL Boolean set operations using exact predicates/exact constructions.

Secondary implementation diversity:

- JTS/GEOS OverlayNG;
- Clipper2 for integer/scaled-integer cases;
- Boost.Geometry.

Disagreement is investigated semantically rather than decided by majority
vote.

#### Stage P3 — scalable candidate discovery

After P1 semantics are frozen, investigate sweep-line or indexed pair
discovery.

The accelerated implementation must reproduce the P1 exact result contract.

### 23. Required property and metamorphic verification

The final implementation must include, where applicable:

- commutativity: `union(A, B)` geometrically equals `union(B, A)`;
- idempotence: `union(A, A) == A` after canonical construction;
- empty identity;
- containment cases;
- disjoint multi-component cases;
- shared-edge adjacency;
- partial collinear overlap;
- point-only contact;
- hole preservation;
- hole removal by overlap;
- creation/removal of disconnected components as appropriate;
- source ring reversal invariance;
- source ring start-rotation invariance;
- operand-order invariance;
- full-range integral stress;
- finite binary64 extreme/subnormal cases;
- exact vertices that collide after binary64 rounding and therefore force
  construction failure;
- deterministic repeated execution.

Where sequence equality is asserted, it applies only after the canonical result
rules have been established.

### 24. Research references

The architecture research compared several mature implementations.

CGAL's 2D Boolean set operations use planar arrangements and document
sweep-line construction for aggregate Boolean operations. Exact-kernel examples
provide a strong independent reference for exact topology.

JTS/GEOS OverlayNG provides strong noding/overlay-graph implementation evidence
and makes precision-model choices explicit. Its fixed-precision robustness via
snap rounding is useful reference material but is not adopted as the default
`geo-d` topology contract.

Clipper2 provides high-performance clipping evidence and useful integer-domain
differential fixtures. Its floating-facing API scales coordinates to integer
coordinates internally, so that precision model is not silently adopted by
`geo-d`.

Boost.Geometry provides additional API/implementation diversity and evidence
for the complexity of real-world overlay edge cases.

Research detail is retained in issue #36 and draft research PR #37.

## Proposed consequences

### Positive

- The first genuinely missing OSM-editor-backed geometry construction receives
  a robust architecture rather than an opportunistic clipping helper.
- Exact topology remains consistent with the existing geo-d numerical model.
- Existing exact intersection arithmetic is reused instead of introducing a
  second rational backend.
- Rounded construction cannot silently redefine arrangement topology.
- Shared-edge and point-contact semantics are explicit.
- Multi-component output is represented without invalid self-touching rings.
- The construction scalar follows an existing public scalar family.
- Output ordering is designed to be deterministic.
- Public exact-arithmetic internals remain hidden.
- Future acceleration can replace candidate discovery without changing
  semantics.

### Costs

- Polygon overlay is substantially more complex than the existing primitive
  algorithms.
- Exact event comparison uses wide fixed-width cross products.
- Arrangement workspace is data dependent.
- The proposed initial owning result requires documented allocation.
- Some mathematically valid exact unions may be unrepresentable as valid
  binary64 polygon output and must fail construction.
- Robust `real` union remains unavailable.
- A correctness-first P1 implementation may initially be quadratic.

## Alternatives considered

### Use rounded binary64 intersection points as arrangement vertices

Rejected.

Executable research demonstrates distinct exact events that both round to
`0.5`.

### Use a global epsilon to merge nearby events

Rejected.

Event identity is topology.

### Snap-round all input and intersections to a precision grid

Rejected as the default contract.

That is a different explicitly quantized geometry operation.

### Use Clipper2-style integer scaling for floating input

Rejected as the default contract for the same reason.

It may remain a differential/performance reference.

### Expose exact rational coordinates publicly

Rejected for the initial union capability.

The consumer requires polygon union, not a new public rational-geometry scalar
system.

### Return the result in the input scalar type

Rejected.

Integral and floating input polygons can intersect at coordinates not
representable in the input scalar type.

### Encode multiple components in one self-touching Polygon2View

Rejected.

It contradicts the established valid-ring and connected-polygon-interior
model.

### Require only caller-provided result buffers

Not selected for the initial contract.

Unknown output and workspace size would force either pessimistic bounds,
duplicated overlay work, or a substantially more complex planning API.

A future caller-managed API remains possible if consumer evidence justifies it.

### Introduce all Boolean polygon operations together

Rejected.

Only union currently has direct consumer-backed promotion.

## Relationship to existing decisions

ADR-0003 establishes view-first variable-size geometry and explicitly defers
owning aggregates until a concrete consumer requires them.

ADR-0004 requires robust topology and prohibits a global epsilon.

ADR-0005 and ADR-0006 separate exact segment-intersection topology from rounded
coordinate construction.

ADR-0009 defines structural polygon ring roles independently of winding.

ADR-0012 defines valid rings/polygons, allows the empty polygon, requires
connected polygon interior, and keeps topology validation exact.

ADR-0014 requires explicit binary64 rounding where the contract depends on
rounding.

ADR-0016 keeps robust `real` topology deferred.

ADR-0019 defines the v2 API-family naming/UFCS policy.

ADR-0020 prevents internal geo-d implementation details from leaking into
`euclid-core-d` without common public declaration-identity need.

ADR-0022 establishes the geometry-neutral exact-coordinate machinery and the
198/132-limb rational-coordinate construction model reused by this proposal.

## Evidence already established

Issue #36 and research PR #37 establish:

- consumer-backed need for polygon union;
- comparison of arrangement, OverlayNG, scanbeam/integer, and other overlay
  models;
- preferred exact-arrangement direction;
- exact cross-denominator coordinate comparison;
- exact proper-intersection event equality;
- exact event ordering along source segments;
- a binary64 collision case where two distinct exact events both round to
  `0.5`;
- DMD 2.111.0, current DMD, LDC 1.41.0, and current LDC execution of the
  exact-event unit tests.

The research CI completed successfully before this design promotion.

Subsequent executable design probes on draft PR #37 additionally establish:

- exact source-direction angular ordering without subtracting rational overlay
  vertices; CI run #72 passed DMD 2.111.0, LDC 1.41.0, and both rolling
  canaries;
- exact shared/partial-collinear noding into atomic A/B/AB boundary spans;
  CI run #73 passed the same four jobs;
- dual-cell `(insideA, insideB)` parity propagation for disjoint, nested,
  overlapping, identical, and adjacent cases; CI run #74 passed;
- local point-contact boundary continuation by exact angular face-following;
  CI run #75 passed, while full cycle reconstruction remains a separate gate;
- two independent binary64 materialization hazards: exact-vertex collapse and
  a valid exact signed-long ring that retains four distinct rounded vertices
  yet becomes topologically invalid after rounding; CI run #76 passed;
- an immutable GC-backed owning-result prototype whose descriptor copies share
  immutable point/ring/component backing and whose `Polygon2View` access
  remains usable after the original owner descriptor is dropped; CI run #77
  passed;
- exact canonical cycle-start/sequence comparison independent of stored ring
  start, source-segment storage reversal for an identically oriented
  half-edge, and A/B label exchange for union membership; CI run #78 passed.

These probes remain research-only implementation evidence. They are not
production source or package exports.

## Acceptance gates

This ADR remains **Proposed** until all of the following are resolved with
executable evidence or an explicit proof:

- [x] exact source-direction angular ordering is prototyped for crossing,
      T-junction, shared-edge, opposite-ray, and multi-edge vertices;
- [x] shared-edge and partial-collinear-overlap noding fixtures produce the
      required operand-boundary membership;
- [x] exact region labeling is demonstrated for connected, disconnected, and
      nested arrangement components;
- [ ] exact cycle reconstruction handles point-only contacts without creating
      self-touching rings;
- [ ] the topology-preserving binary64 materialization check set is proven
      sufficient for the selected result contract;
- [x] the owning immutable result/lifetime model is prototyped with DMD and
      LDC;
- [x] deterministic canonicalization primitives are verified under A/B label
      exchange, source reversal, and ring start rotation; full overlay-level
      permutation invariance remains part of production/property verification;
- [ ] complexity, allocation, and failure behavior are documented against the
      executable candidate;
- [ ] Issue #38 records the final disposition of every open design question.

Only after these gates pass may the ADR move to **Accepted** and production
polygon-union implementation begin.

## Implementation gate

This Proposed ADR does **not** authorize a public polygon-union API or
production overlay implementation.

Permitted work before acceptance is limited to:

- internal research/prototype code;
- range proofs;
- differential/property harnesses;
- design fixtures;
- ownership/lifetime probes;
- documentation needed to decide the gates above.

Public API spelling and package exports remain frozen until the design gate is
accepted.
