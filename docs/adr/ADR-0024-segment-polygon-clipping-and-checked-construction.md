# ADR-0024 — Robust segment-polygon clipping and checked construction contract

**Status:** Accepted  
**Date:** 2026-09-30

## Context

The OSM-editor consumer audit and clipping research in issue #58 identified a
concrete missing construction in `geo-d`: construct the positive-length linear
parts of a segment retained by a valid polygonal region.

The existing public `SegmentPolygonRelationship` deliberately retains only
existential topology facts:

- exterior presence;
- boundary presence;
- interior presence;
- positive-length boundary overlap.

It deliberately discards:

- ordered contacts;
- transition coordinates;
- transition order;
- clipped result geometry.

That is the correct contract for repeated validation/detection queries, but it
is insufficient for editor workflows that must split or construct linear
geometry at polygon boundaries.

Issue #58 established the clipping semantics and numerical architecture through
executable research.

The research includes:

- an exact ordered one-dimensional partition model;
- an independent BigInt/rational oracle;
- a candidate using the existing geo-d exact event/noding machinery;
- a full exact-cell candidate;
- an exhaustive differential with 125,686 directed integer-grid queries per
  compiler and zero mismatches on DMD and LDC;
- a binary64 endpoint-collapse probe;
- a binary64 inter-component gap-collapse probe.

The research also demonstrated genuine second-use evidence for exact rational
event construction and ordering previously housed under polygon-union internal
naming.

Issue #71 is the design gate for this ADR.

## Decision

### 1. Segment-polygon clipping belongs in geo-d

The operation is coordinate-system-agnostic Euclidean 2D geometry.

It does not require:

- a CRS;
- projection semantics;
- geodesic or ellipsoidal semantics;
- OSM object identity;
- OSM tags;
- layer/bridge/tunnel/indoor policy;
- editor mutation or undo/redo;
- spatial indexing as part of the geometry contract.

Those concerns remain outside `geo-d`.

### 2. Initial robust scalar domain

The supported input scalar domain is:

~~~text
int
long
float
double
~~~

`real` remains outside this contract.

This follows the current robust exact-topology and exact-construction domain.

### 3. Input polygon is prevalidated

The operation is defined for:

- a finite `Segment2!T`;
- a `Polygon2View!T` satisfying `validatePolygon(polygon).valid`.

Polygon validation is deliberately outside the clipping call.

This matches `classifySegmentPolygonRelationship` and permits one validated
polygon to be reused for many segment queries without repeating full polygon
validation.

An empty polygon is valid.

A degenerate finite segment is valid input.

Outside these preconditions no successful clipping geometry has defined
semantics.

Development-time assertions may enforce the preconditions.

### 4. Clipping is one-dimensional regularized closed-set intersection

The constructive result is the set of positive-length one-dimensional
components of:

~~~text
segment ∩ (Interior(P) ∪ Boundary(P))
~~~

followed by omission of connected components of topological dimension zero.

Consequences:

- wholly exterior segment -> successful empty result;
- isolated exterior tangency -> successful empty result;
- isolated vertex touch -> successful empty result;
- wholly interior segment -> complete segment;
- proper crossing -> one or more retained positive-length components;
- positive-length boundary overlap -> retained;
- boundary-only positive-length segment -> retained;
- degenerate input segment -> successful empty result.

The operation is therefore not a generic mixed-dimensional point-set
intersection API.

Consumers that need isolated contact facts use
`SegmentPolygonRelationship`.

### 5. Exact ordered topology is private

The semantic reference model is an exact one-dimensional cell decomposition
along the closed query segment.

Breakpoints include:

- both query endpoints;
- every endpoint of every connected component of query/boundary
  intersection.

Point cells occur at breakpoints and open interval cells occur between adjacent
breakpoints.

Each cell has an exact polygon location:

~~~text
exterior
boundary
interior
~~~

This exact ordered partition remains an implementation detail.

The initial public API does not expose:

- exact breakpoint objects;
- exact rational coordinates;
- point/open-interval cell kinds;
- exact event ordering primitives;
- arrangement or noding objects.

A public partition API requires separate consumer evidence.

### 6. Exact topology precedes construction

No global epsilon is introduced.

Rounded coordinates must not determine:

- event identity;
- event order;
- crossing/tangency classification;
- overlap identity;
- retained-component selection;
- component order;
- component separation.

All topology is established from exact represented geometry before public
coordinate materialization.

### 7. Exact event ordering uses the source segment's monotone axis

For a nondegenerate query segment:

- if `query.a.x != query.b.x`, x is strictly monotone along the segment;
- otherwise y is strictly monotone.

Exact rational coordinate comparison on that axis orders all events from
`query.a` toward `query.b` without constructing a floating segment parameter.

This is the same rule already used by the existing exact intersection and
polygon-union noding machinery.

### 8. Event and cell-count bounds are linear

For `n` total polygon boundary edges:

~~~text
boundary components  <= n
breakpoints          <= 2n + 2
open interval cells  <= 2n + 1
~~~

A fully explicit point+interval cell representation therefore remains O(n).

These bounds justify an O(n) private exact-event workspace.

### 9. Existing exact event machinery is a valid second-use dependency

The clipping research reproduced correct exact breakpoint generation using
the existing machinery for:

- represented input-point lifting;
- exact proper-crossing construction;
- touch events;
- overlap endpoints;
- exact rational point equality;
- exact source-order comparison;
- allocation-free event sort/dedup over caller storage.

Clipping is now a second internal consumer.

A private refactor from polygon-union-specific naming toward geometry-neutral
exact-event naming is justified if production implementation proceeds and the
contracts remain identical.

This does not justify:

- public exact-rational geometry types;
- a public generic noding API;
- moving the machinery to `euclid-core-d`;
- sharing polygon-arrangement-specific logic.

### 10. Construction scalar follows IntersectionScalar

Clipping can introduce rational transition coordinates even for integral input.

The construction scalar follows:

~~~text
IntersectionScalar!T
~~~

which is currently `double` for:

~~~text
int
long
float
double
~~~

No competing construction-scalar policy is introduced.

### 11. Public result is initially an immutable owning result

The first production design uses an explicit immutable owning result.

Successful backing is conceptually:

~~~text
immutable Segment2!double[]
~~~

Components are stored in source-query traversal order.

Ordinary result copies must not deep-copy component geometry.

The exact O(n) event workspace remains private.

A caller-managed or reusable-workspace clipping API is deferred until measured
consumer evidence demonstrates that constructive clipping allocation is
material.

### 12. Why caller-owned exact workspace is not public initially

The efficient exact algorithm needs variable-size exact rational event storage.

Unlike Douglas-Peucker's public `size_t[]` workspace, these events expose
private numerical representation.

Publishing the workspace would require either:

- exposing exact rational internal types; or
- creating an opaque byte/alignment/layout protocol.

Neither is justified by the current consumer.

An O(1)-workspace repeated-scan algorithm is possible in principle but would
trade the current O(n log n) event-ordering direction for O(n^2) contact work.

No current evidence justifies that trade merely to promise `@nogc`.

### 13. Relationship queries remain the allocation-free hot path

`classifySegmentPolygonRelationship` remains:

~~~text
pure nothrow @safe @nogc
~~~

and serves repeated detection/validation queries.

Constructive clipping is a separate path used only when result geometry must
actually be built.

The clipping API therefore does not promise `@nogc`.

### 14. Checked status has three states

The minimum public checked construction status is:

~~~text
notComputed
success
unrepresentableConstruction
~~~

`notComputed` is the default state.

`success` includes successful empty output.

`unrepresentableConstruction` means exact retained topology exists but cannot
be faithfully represented in the selected public construction scalar.

No invalid-input states are included because validity/finiteness are
preconditions.

Allocation/resource exhaustion follows normal D runtime failure semantics and
is not a geometry status.

### 15. Materialization is all-or-nothing

No partial result is exposed.

Every selected exact endpoint must round to a finite public coordinate.

After rounding, the exact strict traversal order of all selected output
endpoints must remain preserved on the source segment's authoritative
monotone axis.

For retained exact components:

~~~text
[s0,e0], [s1,e1], ..., [sk-1,ek-1]
~~~

the exact order is:

~~~text
s0 < e0 < s1 < e1 < ... < sk-1 < ek-1
~~~

along the source traversal axis.

The rounded coordinates must preserve the same strict order.

### 16. Strict source-axis order is the complete 1D topology gate

Preserving strict axis order guarantees simultaneously:

- no positive-length retained component collapses;
- no component reverses;
- no positive exact gap collapses;
- distinct exact components remain disjoint;
- output component order remains faithful.

By transitivity, every later component remains strictly beyond every earlier
component on that axis.

Distinct axis projections are therefore disjoint, so no additional O(k^2)
global pairwise segment-intersection validation is required.

Materialization validation is O(k) for k retained output components.

### 17. Binary64 collapse is a checked construction failure

The research contains two executable counterexamples.

First, a positive exact component with endpoints:

~~~text
long.max - 1
long.max
~~~

has distinct finite exact endpoints that both correctly round to the same
binary64 point.

Second, two exact positive components separated by a narrow hole near `2^53`
remain individually nondegenerate after rounding while their positive exact gap
collapses, causing the rounded components to touch.

Both cases require `unrepresentableConstruction`.

### 18. Successful empty result is distinct from default state

Successful empty output is common:

- wholly exterior query;
- isolated tangent contact;
- isolated vertex contact;
- degenerate query;
- clipping against an empty polygon.

Therefore:

~~~text
status == success && length == 0
~~~

is a normal successful result and must not be confused with:

~~~text
Result.init / status == notComputed
~~~

### 19. Query direction is preserved

Result order follows the source segment from `query.a` toward `query.b`.

Reversing the query reverses component order and each component's traversal
direction.

No direction-independent canonical reordering is performed.

### 20. Initial complexity contract

For `n` polygon boundary edges and `k` retained output components, the first
production implementation may use:

~~~text
event generation       O(n)
event sort/dedup        O(n log n)
selection/labeling      O(n) to O(n log n), depending implementation
materialization         O(k)
private workspace       O(n)
public result storage   O(k)
~~~

This is a correctness-first contract.

Future implementation may improve asymptotic behavior without changing
semantics.

### 21. Polyline clipping remains separate

Polyline clipping is not promoted by this ADR.

After the segment contract exists, polyline composition must separately settle:

- shared source-vertex transitions;
- duplicate split points;
- joining adjacent retained components;
- output component ordering across source segments;
- point-only contacts across segment boundaries;
- aggregate ownership.

Consumer evidence is required before a dedicated public polyline clipping API.

### 22. Bounds and convex-polygon specializations remain deferred

Liang-Barsky-style bounds clipping and Cyrus-Beck-style convex clipping remain
valid algorithmic references and possible future optimizations.

They do not receive separate public APIs from this ADR because the concrete
consumer requires general valid polygons and does not justify additional
surface area.

### 23. Generic polygon clipping/overlay is not promoted

This ADR does not authorize public polygon:

- intersection;
- difference;
- symmetric difference;
- generic overlay.

The existing polygon-union arrangement may be implementation evidence for
future work, but each additional public operation requires its own consumer and
design gate.

## Public API

The accepted public spelling is:

~~~d
enum SegmentPolygonClipStatus : ubyte
{
    notComputed,
    success,
    unrepresentableConstruction,
}

struct SegmentPolygonClipResult
{
    @property SegmentPolygonClipStatus status() const;
    @property bool succeeded() const;
    @property size_t length() const;
    @property bool empty() const;
    Segment2!double opIndex(size_t index) const;
}

SegmentPolygonClipResult clipSegmentToPolygon(T)(
    Segment2!T segment,
    scope Polygon2View!T polygon
) @safe;
~~~

The result type is deliberately non-templated because the accepted
`IntersectionScalar!T` policy currently maps every supported input scalar to
`double`.

`SegmentPolygonClipResult.init` has
`SegmentPolygonClipStatus.notComputed`.

`length`, `empty`, and indexing require `succeeded == true`.

Successful components are returned in query traversal order.

The function name is deliberately directional and constructive:

~~~text
clipSegmentToPolygon
~~~

It distinguishes the operation from:

- `classifySegmentPolygonRelationship`, which reports exact existential facts;
- generic set-theoretic intersection, which could include isolated points;
- polygon overlay operations.

No `try` prefix is used because representability is reported through the
checked result status rather than a Boolean/out-parameter pair.

## Verification requirements

Production implementation must be verified against at least:

- wholly exterior;
- wholly interior;
- proper crossing;
- multiple crossings in a concave polygon;
- polygon holes;
- winding reversal;
- redundant collinear polygon vertices;
- isolated tangency omitted;
- isolated vertex touch omitted;
- positive-length boundary overlap retained;
- boundary-only segment retained;
- degenerate query -> successful empty;
- empty polygon -> successful empty;
- rational proper crossing;
- query reversal;
- binary64 endpoint collapse -> unrepresentable;
- binary64 inter-component gap collapse -> unrepresentable;
- DMD and LDC;
- independent oracle differential.

The existing #58 BigInt/rational oracle and 125,686-query differential are
research evidence and should be retained or adapted as verification oracles.

## Consequences

### Positive

- consumer-backed clipping construction is added without widening into generic
  mixed-dimensional overlay;
- repeated relationship queries keep their allocation-free hot path;
- exact topology remains authoritative;
- binary64 construction failures are explicit;
- result ownership is simple for consumers;
- private exact-event machinery gains a justified second use;
- future low-level workspace optimization remains possible without redefining
  semantics.

### Negative

- constructive clipping allocates in the initial API;
- exact O(n) event storage is required internally;
- successful construction can fail for representability even when exact
  topology exists;
- isolated point intersections are intentionally not returned by the
  constructive clipping API.

### Deferred

- public exact partition API;
- caller-managed/reusable workspace API;
- polyline clipping;
- bounds-specific clipping;
- convex-polygon-specific clipping;
- generic mixed-dimensional segment/polygon set intersection;
- polygon intersection/difference/symmetric difference.

## Internal refactor boundary

Production implementation may extract the exact event-point subset currently
housed under polygon-union naming into geometry-neutral internal modules.

The shared subset is limited to concepts already proven identical by #58:

- exact represented/rational event point storage;
- lifting represented input points into that exact point domain;
- promotion of `ExactProperIntersection` into the exact point domain;
- exact point equality and lexicographic comparison;
- exact ordering along a represented source segment;
- insertion of touch/proper-crossing/overlap endpoints for a segment pair;
- allocation-free exact event sort and deduplication over caller-owned
  internal storage.

The refactor must not move or generalize:

- polygon face/region labeling;
- half-edge embedding;
- polygon cycle tracing;
- polygon component/hole reconstruction;
- polygon-union materialization policy;
- public API;
- any code into `euclid-core-d` without independent cross-repository consumer
  evidence.

Exact module/file names are implementation details; this ADR freezes the
semantic boundary, not a directory spelling.

## Exit gate

ADR-0024 is Accepted with issue #71's design contract frozen.

Production implementation proceeds through a separate Feature issue and an
independent Verification issue before merge to `develop`.