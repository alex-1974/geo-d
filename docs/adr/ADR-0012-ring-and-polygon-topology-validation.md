# ADR-0012: Ring and polygon topology validation

- Status: Accepted
- Date: 2026-09-10

## Context

`geo-d` deliberately separates geometry representation from topological
validity.

`LinearRingView` can represent:

- empty rings;
- rings with too few vertices;
- repeated vertices;
- zero-length edges;
- self-touching rings;
- self-crossing rings;
- overlapping ring segments;
- non-finite floating-point coordinates.

`PolygonView` can additionally represent arbitrary relationships between an
exterior ring and interior rings.

Existing algorithms such as `signedArea`, `polygonArea`, and
`tryClassifyPointInPolygon` define deterministic behaviour for many such
representations without implicitly validating or repairing them.

Topology validation shall remain a separate operation.

`geo-d` already provides exact segment-intersection topology for:

    int
    long
    float
    double

with the public classification:

    none
    point
    overlap

where `point` means that the intersection contains exactly one geometric
point and `overlap` means that the intersection contains a segment of
positive geometric length.

Validation shall reuse this robust topology rather than introduce an
independent approximate intersection implementation.

## Decision

Ring validation and polygon validation are separate layers.

A polygon is valid only if each constituent ring is valid and the
relationships between those rings satisfy polygon topology constraints.

Validation does not normalize, repair, reorder, reverse, or copy geometry.

## Scalar domain

Initial validation support is:

    int
    long
    float
    double

`real` remains deferred until the robust predicate backend supports it.

Validation performs no implicit mixed-scalar conversion.

## Validation result model

Validation returns structured diagnostic information rather than only a
boolean.

A valid result has issue `none`.

The result shall identify relevant ring, vertex, or segment indices where
practical.

The public validation API provides:

    RingValidationIssue
    RingValidationResult
    validateRing()

    PolygonValidationIssue
    PolygonValidationResult
    validatePolygon()

Both result types expose a convenience `valid` property.

`RingValidationResult` reports applicable vertex or edge indices using
`primaryIndex` and `secondaryIndex`.

`PolygonValidationResult` reports applicable ring and edge indices using:

    primaryRingIndex
    secondaryRingIndex
    primaryEdgeIndex
    secondaryEdgeIndex

For polygon failures caused by an invalid constituent ring, the detailed
`RingValidationResult` is retained in `ringResult`.

`size_t.max` denotes a diagnostic index that does not apply to the reported
issue.

## Ring validation

A non-empty valid `LinearRingView` represents one simple closed polygonal
curve.

Because `LinearRingView` is implicitly closed, the stored point sequence
does not repeat the first vertex at the end.

### Empty ring

An empty ring is not a valid standalone polygon boundary.

It is reported as a ring validation failure.

This does not prevent an empty `PolygonView` from being a valid empty
polygon representation.

### Minimum size

A valid ring requires at least three stored vertices.

Fewer than three stored vertices is invalid.

### Finite coordinates

Every stored coordinate must be finite.

For `int` and `long`, this is always satisfied.

For `float` and `double`, NaN and positive or negative infinity make the
ring invalid.

Non-finite coordinates are reported as validation issues rather than
numerical execution failures.

Topology predicates are not invoked on non-finite geometry.

### Implicit closure

`LinearRingView` closes the stored sequence implicitly:

    v[0] -> v[1] -> ... -> v[n-1] -> v[0]

A caller must therefore not store an additional closing copy of the first
vertex.

For example:

    A B C

represents the triangle:

    A -> B -> C -> A

while:

    A B C A

contains an additional implicit edge:

    A -> A

and is invalid because that final edge has zero length.

Import adapters for formats that explicitly repeat the first coordinate at
the end are responsible for removing that duplicate before constructing the
canonical `LinearRingView`.

### Zero-length edges

Every implicit ring edge must have distinct endpoints.

Consecutive repeated points are therefore invalid.

The implicit closing edge is subject to the same rule.

### Simplicity

A valid ring is simple.

Two adjacent ring segments may intersect only at their one shared endpoint.

This includes the first and final implicit segments, which are adjacent
through the ring closure.

Adjacent segments must not overlap.

They must not share any geometric point other than their expected common
endpoint.

Two non-adjacent ring segments must be disjoint.

Therefore any point intersection or positive-length overlap between
non-adjacent segments makes the ring invalid.

This rejects:

- proper self-crossings;
- non-adjacent vertex touches;
- vertex-on-edge self-touches;
- repeated non-adjacent vertices;
- collinear segment overlaps;
- retraced portions of the boundary.

### Orientation

Ring orientation does not affect validity.

Clockwise and counterclockwise traversals of the same valid ring are equally
valid.

### Area

A separate non-zero-area criterion is not required for basic ring validity.

A ring satisfying the minimum-size, non-zero-edge, and simplicity
requirements already represents a non-degenerate simple closed polygonal
curve.

No floating-point area threshold or epsilon participates in ring
validation.

## Ring validation issues

The initial diagnostic model should distinguish at least:

    none
    tooFewVertices
    nonFiniteCoordinate
    zeroLengthEdge
    selfIntersection
    selfOverlap

`selfIntersection` includes a forbidden single-point intersection between
ring segments.

`selfOverlap` identifies a positive-length overlap.

More detailed distinctions such as proper crossing versus self-touch may be
added if implementation experience demonstrates that they are useful to
callers, but they are not necessary to determine ring validity.

## Polygon validation

An empty `PolygonView` is a valid empty polygon.

A non-empty polygon consists of:

- ring 0: exterior boundary;
- rings 1..n: interior boundaries.

Ring roles are determined by descriptor position, not orientation.

Every constituent ring must first satisfy ring validation.

## Exterior ring

A non-empty polygon requires one valid exterior ring.

Failure of the exterior ring makes the polygon invalid.

## Interior rings

Every interior ring must independently be a valid ring.

A polygon validation result shall identify which interior ring failed and
retain the corresponding ring-level issue where practical.

## Ring orientation

Polygon validity does not depend on ring orientation.

Exterior and interior rings are not identified or validated by winding
direction.

## Inter-ring boundary relationships

Different polygon rings must never cross.

Different polygon rings must never overlap along a segment of positive
length.

Two different rings may touch tangentially at one geometric point.

The same pair of rings may not share two distinct geometric points.

Consequently, for each pair of polygon rings:

    no intersection
        potentially valid

    one tangential point
        potentially valid

    proper crossing
        invalid

    more than one distinct point contact
        invalid

    positive-length overlap
        invalid

A single segment-pair result of `SegmentIntersectionKind.point` is not by
itself sufficient to establish that two rings touch tangentially.

The validator must determine the topology of the complete local ring
neighbourhood at the contact point.

## Hole containment

Every interior ring must lie in the polygon region bounded by the exterior
ring.

An interior ring may touch the exterior boundary at one tangential point.

Except for such an allowed contact, the interior ring must lie strictly
inside the exterior.

A hole located wholly outside the exterior is invalid.

A hole crossing from inside to outside the exterior is invalid.

## Hole relationships

The interiors of distinct holes must not overlap.

One hole must not contain another hole.

Two holes may touch tangentially at one point if all other polygon validity
conditions remain satisfied.

They may not cross, overlap along a segment, or share multiple distinct
points.

## Connected polygon interior

The interior of a valid polygon must be connected.

Allowed point contacts between rings must therefore not form a topology that
splits the polygon interior into multiple connected components.

Examples of invalid configurations include a sequence of touching holes that
forms a barrier from one part of the exterior boundary to another and thereby
separates the polygon interior.

Point-contact validity therefore cannot be decided solely from independent
segment-pair intersection counts.

The complete ring-contact topology must be considered.

## Self-touching rings

A self-touching ring is invalid even when the self-touch could be interpreted
as creating multiple polygonal regions.

`geo-d` does not use self-touching exterior or interior rings as an implicit
encoding of additional shells or holes.

Such geometry must instead be represented using separate valid rings or, in
a future higher-level model, multiple polygons.

## Exactness

For finite supported scalar inputs, all topological validity decisions shall
be exact.

Validation shall use the existing robust orientation and segment-intersection
machinery.

No validity decision may depend on:

- epsilon thresholds;
- approximate point equality;
- rounded segment intersection coordinates;
- floating-point distance tests;
- floating-point ray/segment division.

Constructed intersection coordinates are not required merely to determine
validity.

## Segment-intersection reuse

`SegmentIntersectionKind` remains the authoritative primitive classifier for
closed segment intersection:

    none
    point
    overlap

For ring validation:

- the expected shared endpoint of adjacent segments is allowed;
- any additional adjacent-segment intersection is invalid;
- any intersection between non-adjacent segments is invalid.

For polygon inter-ring validation:

- `none` requires no further contact handling;
- `overlap` is invalid;
- `point` requires additional exact local-topology analysis to distinguish
  tangential contact from crossing.

The validator shall not infer tangent-versus-crossing semantics from rounded
constructed intersection coordinates.

## Complexity

The first correct implementation may use pairwise segment comparisons.

For a ring with `n` segments, this gives:

    O(n^2)

worst-case time.

For a polygon with `N` total segments, initial full topology validation may
likewise require:

    O(N^2)

worst-case time.

This is acceptable for the initial correctness-oriented implementation.

The API and semantics shall not depend on that implementation strategy.

Future spatial indexing or sweep-line acceleration may reduce complexity
without changing observable validity semantics.

Auxiliary allocation requirements shall be made explicit before
implementation.

The preferred baseline remains bounded storage and `@nogc`, but connected
interior analysis may require a carefully designed temporary topology
representation. `@nogc` shall not be promised until that representation is
designed and verified.

## Diagnostic ordering

A geometry may contain multiple independent validation errors.

The initial validator may report the first detected error.

Detection order must be deterministic for identical stored geometry.

The public API shall not imply that every error is enumerated.

A future exhaustive diagnostic operation may report multiple issues without
changing the basic validity semantics.

## Empty polygon

An empty `PolygonView` is valid.

This is distinct from a non-empty polygon whose exterior ring is empty,
which is invalid.

## Representation versus validation

Construction of `LinearRingView` and `PolygonView` continues to accept
representations that fail these validity rules.

Existing representation-level algorithms retain their previously defined
semantics.

Validation does not become an implicit precondition for:

- `signedArea`;
- `polygonArea`;
- `tryClassifyPointInPolygon`.

Callers that require valid simple-feature polygon topology must invoke
validation explicitly.

## Alternatives considered

### Make views valid by construction

Rejected.

Views are lightweight borrowed representations and deliberately do not
perform hidden O(n) or O(n^2) work during construction.

### Boolean-only validation

Rejected.

A boolean loses information needed to diagnose malformed imported geometry
and to test topology implementation precisely.

### Reject every contact between different rings

Rejected.

A single tangential point contact between otherwise valid rings can
represent valid polygon topology.

The validator therefore distinguishes tangent contact from crossing rather
than imposing a stronger no-touch rule.

### Allow self-touching rings

Rejected for the initial model.

A canonical ring represents one simple closed boundary.

Encoding multiple regions through self-touching traversal creates ambiguous
representation semantics and complicates downstream algorithms.

### Determine validity from polygon area

Rejected.

Area is not sufficient to establish topological simplicity, containment, or
connectedness.

### Epsilon-based topology

Rejected.

Topology is exact in `geo-d`; proximity belongs to metric algorithms.

## Implemented API and algorithm

The accepted implementation exposes `validateRing()` and `validatePolygon()`
as the only public validation entry points. Intermediate polygon-validation
stages remain package-internal implementation details.

Ring validation performs exact pairwise edge-topology checks and uses O(n^2)
time with O(1) auxiliary storage.

Polygon validation proceeds conceptually through four stages:

1. validate every constituent ring;
2. screen every pair of rings for crossings, positive-length overlaps, and
   more than one distinct geometric contact point;
3. validate exterior/interior containment and reject nested interior rings;
4. verify that the polygon interior remains connected.

A single tangential contact between different rings is permitted. Several
rings may also meet at the same geometric point provided the resulting
polygon interior remains connected.

Connected-interior validation represents the remaining touch topology as a
bipartite incidence graph whose nodes are polygon rings and exact geometric
contact points. Multiple ring pairs meeting at the same point therefore share
one contact-point node.

The polygon interior is connected exactly when this incidence graph is
acyclic. A cycle represents a closed boundary barrier and is reported as
`disconnectedInterior`.

All topology decisions use exact predicates in the supported scalar domain.
No epsilon, rounded intersection coordinate, or floating-point distance test
participates in validity.

The supported scalar domain is:

    int
    long
    float
    double

`real` remains deferred.

The public polygon issue categories are:

    none
    invalidExteriorRing
    invalidInteriorRing
    interRingCrossing
    interRingOverlap
    multipleRingContacts
    interiorRingOutsideExterior
    nestedInteriorRings
    disconnectedInterior

The public ring issue categories are:

    none
    tooFewVertices
    nonFiniteCoordinate
    zeroLengthEdge
    selfIntersection
    selfOverlap

## Consequences

`geo-d` gains an explicit boundary between permissive geometry
representation and strict topological validity.

Ring validity can be built directly from existing exact segment topology.

Polygon validity requires a second layer that analyzes relationships between
already valid rings.

The existing `SegmentIntersectionKind` API is sufficient as the primitive
intersection classifier, but point contacts between different rings require
additional exact neighbourhood analysis.

The initial implementation may prioritize correctness over asymptotic
performance.

Acceleration structures can be introduced later without changing the
validation contract.