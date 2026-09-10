# ADR-0013: Polyline simplification

- Status: Accepted
- Date: 2026-09-10

## Context

geo-d requires coordinate-system-agnostic polyline simplification.

Simplification is a metric approximation operation. It is distinct from
topological validation and from topology-preserving polygon simplification.

The initial implementation should provide a small reusable primitive without
introducing owning geometry types or hidden allocation.

## Decision

The first simplification algorithm is the standard Douglas-Peucker algorithm
for PolylineView.

Topology-preserving simplification of LinearRingView and PolygonView is a
separate future facility.

## Public operation

The intended public API is:

    size_t douglasPeuckerWorkspaceSize(size_t pointCount)
        pure nothrow @safe @nogc;

    bool trySimplifyDouglasPeuckerInto(T, R)(
        scope PolylineView!T polyline,
        R tolerance,
        scope Point2!T[] destination,
        scope size_t[] workspace,
        out size_t written
    )
        pure nothrow @safe @nogc
    if (
        isGeoScalar!T &&
        is(R == MetricScalar!T)
    );

The destination and workspace buffers are caller-owned.

The destination must provide at least polyline.length elements.

The required workspace size is:

    max(polyline.length - 2, 0)

and can be obtained with douglasPeuckerWorkspaceSize().

On success, written contains the number of output points and the simplified
polyline occupies:

    destination[0 .. written]

No heap allocation is hidden by the operation.

## Output geometry

Douglas-Peucker simplification only selects vertices from the input.

It does not construct interpolated coordinates.

The output is therefore an ordered subsequence of the input vertices.

For a polyline containing at least two points, the first and last input
vertices are always retained.

## Degenerate inputs

An empty polyline produces zero output points.

A singleton polyline is copied unchanged.

A two-point polyline is copied unchanged.

Repeated coordinates are permitted because PolylineView is a permissive
representation. Simplification does not perform implicit validation or repair.

## Tolerance

Tolerance is expressed in MetricScalar!T.

It must be finite and non-negative.

A section may be replaced by its baseline when every intermediate point has
distance less than or equal to the tolerance.

A tolerance of zero is not defined as an unconditional no-op. Intermediate
vertices whose computed distance to the section baseline is zero may be
removed.

## Distance semantics

Douglas-Peucker uses Euclidean point-to-segment distance.

Point-to-segment distance is provided by the reusable
tryPointSegmentDistance() metric primitive rather than by constructing a
rounded nearest point and measuring from it.

Integral coordinate differences must retain the overflow-safe handling already
used by geo.metric.

Metric computation is not an exact topological predicate.

## Scalar domain

The initial scalar domain follows MetricScalar and PolylineView:

    int
    long
    float
    double
    real

## Failure semantics

trySimplifyDouglasPeuckerInto() returns false when:

- tolerance is negative or non-finite;
- any input coordinate is non-finite;
- destination is smaller than polyline.length;
- workspace is smaller than douglasPeuckerWorkspaceSize(polyline.length); or
- a required metric computation cannot be represented finitely in
  MetricScalar!T.

On failure, written is zero.

No partial output is part of the public result contract.

The initial API does not promise support for overlapping input and destination
storage. Callers must use non-overlapping destination storage.

## Determinism

When more than one intermediate point has the same maximum computed distance,
the first point in stored order is selected as the split point.

This makes output deterministic.

## Topology

The operation provides no topology-preservation guarantee.

It may introduce or remove segment intersections.

It must not be used as a topology-preserving simplifier for rings or polygons.

LinearRingView and PolygonView simplification require a separate design.

## Allocation and lifetime

The implementation is iterative.

It does not use recursion and therefore does not expose the call stack to the
O(n) worst-case nesting depth of Douglas-Peucker.

The caller supplies both output storage and an explicit size_t workspace.

The workspace contains the end indices of deferred right-hand sections.
Only one index is required per pending section.

For n input points the maximum required workspace length is:

    max(n - 2, 0)

No heap allocation is performed.

The intended implementation contract is:

    pure
    nothrow
    @safe
    @nogc

## Complexity

Standard Douglas-Peucker has input-dependent running time.

The straightforward implementation has:

    O(n^2) worst-case time
    O(n) caller-supplied auxiliary workspace

The output buffer has O(n) capacity because simplification may retain every
input point.

## Consequences

geo-d gains a simple metric polyline simplifier without coupling basic
simplification to polygon topology.

The allocation contract remains explicit.

A later topology-preserving simplifier can build on the robust intersection
and validation infrastructure without changing the semantics of this
operation.
