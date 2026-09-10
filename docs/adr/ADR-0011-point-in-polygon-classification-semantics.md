# ADR-0011: Point-in-polygon classification semantics

- Status: Accepted
- Date: 2026-09-10

## Context

`geo-d` now provides:

- exact orientation predicates;
- exact segment-intersection topology;
- `LinearRingView`;
- `PolygonView`;
- correctly rounded ring and polygon area.

The next polygon operation is classification of a point relative to a
polygon.

A boolean `contains` result is insufficient because a point may lie exactly
on a polygon boundary.

Boundary handling must be explicit and exact. No tolerance or global epsilon
shall participate in the classification.

`PolygonView` also deliberately permits degenerate, self-intersecting, and
otherwise topologically invalid ring structures. Point classification must
therefore have deterministic representation-level semantics without silently
validating or repairing the polygon.

## Decision

Point-in-polygon classification has three geometric results:

    outside
    boundary
    inside

The public result type shall be:

    enum PointPolygonLocation : ubyte
    {
        outside,
        boundary,
        inside
    }

Boundary is a first-class result and is never implicitly treated as either
inside or outside.

A later convenience operation may implement a particular `contains`
policy from this classification, but that policy is not part of the core
classification operation.

## API direction

The initial public API shall follow the form:

    bool tryClassifyPointInPolygon(T)(
        scope PolygonView!T polygon,
        Point2!T point,
        out PointPolygonLocation location
    )

The operation returns `true` when classification is numerically defined.

It returns `false` when classification cannot be performed because the query
point or any stored polygon coordinate is non-finite.

When the operation returns `false`, the output classification must not be
interpreted.

The `try` form keeps numerical failure separate from the three geometric
locations.

## Scalar model

Initial support is:

    int
    long
    float
    double

The query point and polygon must use the same scalar type.

Mixed scalar classification is not performed implicitly.

`real` remains deferred until `geo-d` has a platform-aware robust predicate
backend for that scalar.

## Finite-coordinate requirement

For integer inputs, all representable coordinates are numerically valid.

For `float` and `double`, the query point and every stored polygon vertex
must be finite.

NaN and positive or negative infinity are not classified as geometric
locations.

The operation therefore returns `false` if any required coordinate is
non-finite.

This is distinct from topological invalidity. A finite self-intersecting or
degenerate polygon remains classifiable according to the deterministic
semantics below.

## Boundary semantics

A query point is `boundary` when it lies exactly on any segment represented
by any stored polygon ring.

This includes:

- an ordinary exterior edge;
- an ordinary interior-ring edge;
- a ring vertex;
- a zero-length segment;
- a singleton ring's point segment;
- either directed segment of a two-vertex ring;
- edges belonging to self-intersecting or otherwise invalid rings.

Boundary testing is exact for the supported scalar domain.

No epsilon, distance threshold, or approximate equality is used.

Boundary has precedence over `inside` and `outside`.

Consequently, if a point lies on any stored ring edge, the result is
`boundary` even when the supplied polygon representation is topologically
invalid.

## Ring interior semantics

After boundary has been excluded, the interior state of an individual ring
is determined by the even-odd rule.

Conceptually, cast a horizontal ray from the query point toward positive x.

The point is inside the ring when the ray crosses ring edges an odd number of
times.

It is outside the ring when the number of crossings is even.

The implementation shall not construct an infinite ray or compute
floating-point intersection coordinates.

Instead it shall use exact orientation predicates and a half-open crossing
rule.

## Half-open crossing rule

Vertex crossings must be counted exactly once.

For a directed segment from `a` to `b`, with query point `p`, a crossing is
eligible when either:

    a.y <= p.y < b.y

or:

    b.y <= p.y < a.y

Horizontal segments therefore do not generate ray crossings.

Boundary testing is performed before crossing classification, so horizontal
boundary segments and exact vertex hits are still detected.

For an upward eligible edge:

    a.y <= p.y < b.y

the positive-x ray crosses the edge when:

    orientation(a, b, p) == left

For a downward eligible edge:

    b.y <= p.y < a.y

the positive-x ray crosses the edge when:

    orientation(a, b, p) == right

This formulation avoids division and does not construct an approximate
intersection coordinate.

## Ring reversal

The even-odd rule is invariant under reversal of ring traversal.

Reversing an otherwise identical ring therefore does not change point
classification.

This is consistent with ADR-0009, which does not assign semantic ring roles
from winding order.

## Polygon role semantics

Polygon classification uses explicit ring roles.

Ring zero is the exterior ring.

Subsequent rings are interior rings.

For a point that is not on any stored ring boundary:

- it must be inside the exterior ring to be inside the polygon;
- if it is inside any interior ring, it is outside the polygon;
- otherwise it is inside.

Conceptually:

    inside polygon
        =
        inside exterior
        AND
        NOT inside any interior ring

Ring orientation has no effect.

## Empty polygon

An empty `PolygonView` contains no exterior ring.

Every finite query point is therefore classified as:

    outside

## Degenerate exterior rings

An exterior ring with fewer than three effective vertices has no even-odd
interior.

After exact boundary testing, all other points are classified as outside that
ring and therefore outside the polygon.

Examples:

- empty exterior ring: no interior;
- singleton exterior ring: its single point may be boundary, everything else
  is outside;
- two-vertex exterior ring: points on the represented segment are boundary,
  everything else is outside.

No minimum ring size is imposed by representation.

## Degenerate interior rings

Degenerate interior rings likewise have no even-odd interior.

They may still contribute boundary points.

Otherwise they do not remove any polygon interior.

## Self-intersecting rings

Self-intersecting rings are interpreted with the same even-odd rule.

No attempt is made to decompose them into simple rings.

Their classification is therefore deterministic, but it must not be confused
with validation of a topologically valid polygon.

This choice is representation-level semantics for invalid input.

## Invalid polygon relationships

`tryClassifyPointInPolygon` does not validate relationships between rings.

In particular, it does not require that:

- interior rings lie within the exterior ring;
- interior rings are mutually disjoint;
- rings are simple;
- rings have non-zero area;
- ring orientations follow a winding convention.

Boundary still has global precedence across all stored rings.

After boundary exclusion, role-based classification is applied:

    inside exterior
        AND
        outside every interior ring

Consequently:

- overlapping holes behave as the union of their even-odd interiors;
- a point inside any hole is outside;
- a hole lying outside the exterior does not create polygon interior;
- a boundary belonging to such an invalidly placed hole is still reported as
  boundary of the supplied polygon representation.

These semantics are deterministic and do not imply topological validity.

## Exactness

For supported finite scalar inputs, all topological decisions shall be exact.

The implementation shall use the robust orientation machinery already
provided by `geo-d`.

No decision may depend on:

- floating-point ray/edge division;
- computed intersection x coordinates;
- tolerance thresholds;
- epsilon-expanded boundaries.

Integer overflow must not affect classification.

## Complexity

Classification shall require:

    O(total stored polygon segments)

time in the worst case.

The operation shall use bounded auxiliary storage and perform no allocation.

The target attributes are:

    pure
    nothrow
    @safe
    @nogc

## Early exit

Boundary detection has semantic precedence.

An implementation may use early exits only when doing so cannot hide a
boundary result from another stored ring.

In particular, finding that a point is outside the exterior ring is not by
itself sufficient to return immediately if unexamined rings may still contain
the point on one of their boundaries.

Implementations may organize boundary and interior checks in one or more
passes provided the observable semantics remain identical.

## Convenience containment operations

A boolean containment operation is deliberately not defined by this ADR.

Possible policies include:

    inside only

or:

    inside or boundary

Neither is universally correct for all callers.

A future convenience API should therefore make its boundary policy explicit
or be trivially derived from `PointPolygonLocation`.

The exact three-way classifier remains the authoritative operation.

## Alternatives considered

### Boolean contains

Rejected because it collapses the exact boundary state into an arbitrary
policy decision.

### Winding-number classification

A non-zero winding rule can also classify self-intersecting rings and is
invariant under complete ring reversal.

It was not selected for the initial implementation because even-odd
classification is simpler, does not assign semantic weight to traversal
winding, and aligns directly with explicit exterior/interior ring roles.

Topologically valid simple rings produce the same interior classification
under either rule.

### Floating-point ray intersection

Computing an edge/ray intersection coordinate and comparing its x value with
the query point was rejected.

It introduces avoidable rounding behavior into a topological predicate when
the decision can instead be expressed through exact orientation signs.

### Epsilon boundary tests

Rejected.

There is no global tolerance in `geo-d`, and a tolerance-based boundary would
make topology scale-dependent and non-deterministic.

Approximate proximity is a metric operation, not polygon topology.

### Treat invalid geometry as an error

Rejected for the representation-level classifier.

`PolygonView` deliberately permits invalid or degenerate structures.

Finite invalid geometry therefore receives deterministic classification
semantics.

Explicit topology validation remains a separate future operation.

### Add an `invalid` classification value

Rejected.

`outside`, `boundary`, and `inside` describe geometric location.

Non-finite numerical input is a failure to classify, not a fourth geometric
location.

The `try` API expresses that distinction directly.

## Consequences

Point-in-polygon classification preserves exact boundary information.

Ring orientation remains irrelevant to polygon semantics.

The classifier can be implemented entirely from existing exact predicate
infrastructure without division or allocation.

Finite invalid polygon representations remain deterministically
classifiable.

Non-finite floating-point geometry is reported separately through the
`try` result.

Topological validation remains independent from classification.