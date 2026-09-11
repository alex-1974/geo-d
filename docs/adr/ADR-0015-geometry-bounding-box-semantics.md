# ADR-0015: Geometry bounding-box semantics

**Status:** Proposed  
**Date:** 2026-09-12

## Context

`geo-d` provides `Bounds2` as the axis-aligned bounds type for two-dimensional Euclidean geometry.

`Bounds2` already defines the fundamental value semantics required for this role:

- an explicit empty state;
- non-empty bounds with component-wise `min <= max`;
- degenerate non-empty bounds where `min == max`;
- exact point containment;
- bounds intersection;
- extension by points and other bounds;
- floating-point bounds may contain infinities;
- NaN coordinates are rejected.

The original `geo-d` foundation scope also identifies bounding-box computation as a fundamental geometry algorithm.

The current public API, however, does not provide a common operation for computing the bounds of the existing geometry types:

- `Segment2`;
- `PolylineView`;
- `LinearRingView`;
- `PolygonView`.

Callers can reproduce this operation manually with `Bounds2.tryExtend()`, but doing so requires them to duplicate library-level decisions concerning:

- empty geometry;
- NaN handling;
- infinities;
- polygon ring composition;
- failure-state behaviour.

This is a fundamental operation of the existing geometry model and should be resolved before the `v1.0.0` public-API freeze.

## Decision

`geo-d` will provide one overloaded public operation named:

```d
tryBounds
```

for the geometry types whose bounds require computation:

```d
bool tryBounds(T)(
    Segment2!T segment,
    out Bounds2!T result
);

bool tryBounds(T)(
    scope PolylineView!T polyline,
    out Bounds2!T result
);

bool tryBounds(T)(
    scope LinearRingView!T ring,
    out Bounds2!T result
);

bool tryBounds(T)(
    scope PolygonView!T polygon,
    out Bounds2!T result
);
```

The operation will support the complete `geo-d` scalar domain:

```text
int
long
float
double
real
```

Bounding-box computation does not depend on the robust-topology predicate domain and therefore does not exclude `real`.

All overloads are intended to be:

```d
pure nothrow @safe @nogc
```

They perform no allocation.

## Naming

The operation is named `tryBounds`, rather than `boundingBox`, `envelope`, or `extent`.

This keeps terminology aligned with the existing public type:

```d
Bounds2
```

The `try` prefix communicates that the operation may fail when an input contains NaN.

No `.bounds` property will be added to the view types.

For `PolylineView`, `LinearRingView`, and `PolygonView`, computing bounds requires traversal of the stored geometry and is therefore O(n). Exposing such work through a property would make its cost insufficiently visible.

## Result semantics

### Successful non-empty input

For non-empty geometry containing no NaN coordinate, `tryBounds` returns `true`.

`result` is the smallest closed axis-aligned `Bounds2!T` containing every stored point belonging to the input geometry.

No coordinate conversion is performed.

The result therefore remains in the input scalar domain.

### Successful empty input

An empty variable-size geometry has empty bounds.

Therefore:

```d
PolylineView!T.init
LinearRingView!T.init
PolygonView!T.init
```

all produce:

```d
Bounds2!T.init
```

and `tryBounds` returns `true`.

An empty input is not an error.

This preserves the set-like relationship:

```text
empty geometry
    →
empty bounds
```

### NaN input

If any coordinate considered by the operation is NaN:

```d
tryBounds(...)
```

returns `false`.

On failure:

```d
result == Bounds2!T.init
```

must hold.

Failure is transactional: callers must never observe a partially accumulated bounds.

An implementation should therefore accumulate into a local `Bounds2!T` and assign it to the output parameter only after the complete input has been accepted.

### Infinite coordinates

Positive and negative infinity are valid stored geometry coordinates where the underlying geometry type permits them.

They do not cause `tryBounds` to fail.

The resulting `Bounds2` may therefore itself be non-finite.

This follows the existing `Bounds2` contract, which distinguishes NaN from infinity.

## Geometry-specific semantics

### `Segment2`

Both stored endpoints participate in the bounds calculation.

Endpoint order has no effect on the result.

A degenerate segment:

```text
a == b
```

produces a degenerate non-empty bounds containing that single point.

### `PolylineView`

Every stored point participates in the bounds calculation.

Segments do not need to be inspected separately because every polyline segment is fully contained in the axis-aligned bounds of its endpoints.

An empty polyline produces empty bounds.

A singleton polyline produces a degenerate non-empty bounds.

### `LinearRingView`

Every stored vertex participates in the bounds calculation.

The implicit closing segment does not require separate treatment because its endpoints are already stored vertices.

Ring validity is irrelevant to bounds computation.

Consequently, bounds can be computed for:

- empty rings;
- singleton rings;
- two-vertex rings;
- self-intersecting rings;
- otherwise topologically invalid rings.

No topology validation is performed implicitly.

### `PolygonView`

Every stored vertex of every stored ring participates in the bounds calculation.

This includes:

- the exterior ring;
- every interior ring.

The operation deliberately computes the bounds of the supplied representation rather than assuming valid polygon topology.

Therefore a topologically invalid interior ring located partly or completely outside the exterior ring still contributes to the result.

No call to:

```d
validatePolygon()
```

is implied or performed.

This is consistent with the existing separation between representation, computation, and topology validation in `geo-d`.

## Point and bounds overloads

No `tryBounds(Point2!T, ...)` overload is introduced.

The existing operation:

```d
Bounds2!T.tryFromPoint(...)
```

already expresses that construction directly and without ambiguity.

No `tryBounds(Bounds2!T, ...)` overload is introduced because it would only reproduce the input value.

The new API therefore addresses actual geometry traversal rather than creating redundant aliases for existing `Bounds2` operations.

## Numerical semantics

Bounding-box computation uses exact comparisons in the original scalar domain.

It performs no metric computation, interpolation, orientation predicate, coordinate construction, or tolerance-based comparison.

No epsilon is introduced.

For finite coordinates, every returned bound coordinate is exactly one of the input coordinates.

For floating-point input, signed zero follows the ordinary scalar comparison and assignment behaviour used by `Bounds2`.

The operation makes no claim that geometrically equivalent inputs with different signed-zero representations produce bit-identical corner representations beyond the guarantees already provided by `Bounds2`.

## Complexity

### `Segment2`

```text
time:   O(1)
space:  O(1)
```

### `PolylineView`

For `n` stored points:

```text
time:   O(n)
space:  O(1)
```

### `LinearRingView`

For `n` stored vertices:

```text
time:   O(n)
space:  O(1)
```

### `PolygonView`

For `n` total stored vertices across all rings:

```text
time:   O(n)
space:  O(1)
```

No overload allocates memory.

## API placement

The implementation belongs with bounds-related geometry operations.

The public package module:

```d
import geo;
```

will re-export `tryBounds`.

The operation is part of the supported stable public API once accepted and released.

## Required tests

Before acceptance, tests must cover at least:

### Scalar domain

All overloads for:

```text
int
long
float
double
real
```

### Segment

- ordinary segment;
- reversed endpoints;
- horizontal segment;
- vertical segment;
- degenerate segment;
- finite floating-point input;
- infinite coordinates;
- NaN rejection.

### Polyline

- empty;
- singleton;
- two points;
- ordinary multi-point input;
- repeated points;
- extreme integral coordinates;
- infinities;
- NaN at the first point;
- NaN after previously valid points;
- failure leaves `result == Bounds2.init`.

### Linear ring

- empty;
- singleton;
- two vertices;
- ordinary ring;
- implicit closing edge does not alter the vertex-derived result;
- topologically invalid ring still has computable bounds;
- infinities;
- NaN failure.

### Polygon

- empty polygon;
- exterior ring only;
- exterior plus holes;
- extrema contributed by an interior ring;
- invalid interior ring outside the exterior contributes to bounds;
- empty constituent ring;
- infinities;
- NaN in exterior;
- NaN in a later interior ring;
- failure remains transactional.

### General invariants

For every successful non-empty result:

```d
foreach (stored point)
    assert(result.contains(point));
```

Where practical, deterministic property tests should additionally verify that:

- point order does not affect the resulting bounds;
- segment endpoint reversal does not affect the result;
- ring traversal reversal does not affect the result;
- polygon ring order does not affect the result;
- extending an initially empty `Bounds2` over the same stored points produces an equal result.

## Performance validation

Bounding-box computation is a simple linear reduction and should have very low constant overhead.

Before the `v1.0.0` freeze, a benchmark should cover at least:

```text
PolylineView     10
PolylineView     100
PolylineView     1,000
PolylineView     10,000+

PolygonView      representative multi-ring input
```

The benchmark should verify linear scaling and ensure that abstraction through the public views does not introduce material overhead relative to a direct coordinate loop.

No special low-level optimization is required unless measurement identifies a meaningful deficit.

## Alternatives considered

### Require callers to use `Bounds2.tryExtend`

Rejected.

Although composition is possible, bounding-box computation is part of the explicitly intended fundamental geometry functionality. Requiring every caller to reproduce empty-input, NaN, polygon-ring, and transactional-failure semantics would unnecessarily duplicate library policy.

### Add `.bounds` properties to geometry views

Rejected.

For variable-size views the operation is O(n), while property syntax suggests inexpensive value access.

The public API should make traversal cost visible.

### Add separate names for every geometry type

For example:

```text
segmentBounds
polylineBounds
ringBounds
polygonBounds
```

Rejected.

The operation has the same semantic meaning for each geometry and D overload resolution can express this directly.

A single `tryBounds` family produces a smaller and more composable API.

### Validate rings or polygons before computing bounds

Rejected.

Bounds are representation-level geometry and do not require valid topology.

Implicit topology validation would:

- change the meaning of the operation;
- greatly increase its cost;
- couple independent API families;
- reject geometries whose axis-aligned bounds are nevertheless perfectly well-defined.

### Use a non-failing `bounds()` operation returning NaN or empty on invalid input

Rejected.

NaN coordinates are not valid `Bounds2` coordinates, and treating malformed floating-point input as ordinary empty geometry would conflate two distinct states.

The established `try...` error style is explicit and preserves the distinction.

## Consequences

### Positive

- completes the only missing algorithm explicitly identified in the original fundamental `geo-d` scope;
- provides consistent bounds semantics across all current geometry containers;
- reuses the existing `Bounds2` value model;
- introduces no new data type;
- introduces no allocation;
- works across the complete scalar domain including `real`;
- keeps topology validation separate;
- exposes operation cost clearly;
- provides a natural primitive for future `spatial-d` consumers.

### Negative

- adds another public function family before the v1 API freeze;
- PolygonView traversal must inspect all rings rather than using only the exterior ring;
- the API must permanently preserve the chosen empty-, infinity-, and NaN-handling semantics after v1.

### Neutral

This decision does not add:

- bounds containment of another bounds;
- bounds intersection construction;
- bounds union helpers;
- ring perimeter;
- polygon perimeter;
- point-to-polyline distance;
- clipping;
- spatial indexing.

Those operations remain independent future API decisions.

## v1.0.0 impact

Acceptance and implementation of this ADR closes the remaining fundamental bounding-box gap identified by the public-API completeness audit.

After this operation is implemented, tested, documented, benchmarked, and re-exported through:

```d
import geo;
```

no further fundamental geometry operation is currently considered necessary before the `v1.0.0` API freeze.

Subsequent compatible functionality may be added after v1 when justified by real consumers.