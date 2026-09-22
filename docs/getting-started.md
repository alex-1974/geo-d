# Getting started with geo-d

`geo-d` is a coordinate-system-agnostic 2D Euclidean geometry library for D.

The supported package-level import is:

```d
import geo;
```

Applications should normally use that package module rather than depend on
implementation modules.

This guide follows the canonical v2 API.

`v2.0.0` is the current stable release. The v1 view and orientation spellings
remain available in v2 as deprecated compatibility aliases where documented.

## Installation from the DUB registry

Create or enter a DUB project and add the released package:

```sh
dub init my-geometry-app
cd my-geometry-app
dub add geo-d
```

DUB records the dependency in the application's package configuration.

The examples below use the canonical v2 API.

The repository release process separately verifies installation and a
release-matched minimal consumer against the actually published DUB package
after the release tag has been indexed. Repository path dependencies are not
a substitute for that registry verification.

## DMD and LDC

DMD and LDC are the supported compiler families.

Build with DMD:

```sh
dub build --compiler=dmd
```

Run with DMD:

```sh
dub run --compiler=dmd
```

Build with LDC:

```sh
dub build --compiler=ldc2
```

Run with LDC:

```sh
dub run --compiler=ldc2
```

For performance-sensitive release builds, LDC is the primary performance
compiler used by the project:

```sh
dub build --build=release --compiler=ldc2
```

The minimum supported D frontend version is documented in the repository
README and enforced by CI.

## Minimal program

A complete program can use only the package-level `geo` import:

```d
import geo;

void main()
{
    alias P = Point2!double;

    auto a = P(0.0, 0.0);
    auto b = P(3.0, 4.0);

    assert(distance(a, b) == 5.0);

    assert(
        orientation(
            P(0.0, 0.0),
            P(1.0, 0.0),
            P(0.0, 1.0)
        ) == Orientation2.left
    );
}
```

The repository-local external-consumer test also depends on `geo-d` as a
separate DUB package, imports only `geo`, and verifies the current repository
integration state.

Release verification separately tests a release-matched clean consumer
against the published registry package after the release tag has been
indexed.

## Point and vector algebra

Points and vectors are deliberately different affine concepts.

```d
import geo;

alias P = Point2!double;
alias V = Vector2!double;

auto origin = P(1.0, 2.0);
auto offset = V(3.0, 4.0);

auto moved = origin + offset;
auto displacement = moved - origin;

assert(displacement == offset);
```

Point-plus-point and scalar multiplication of a point are intentionally not
part of the affine API.

## Metric operations

Metric operations compute Euclidean quantities independently of topology.

```d
import geo;

alias P = Point2!double;
alias S = Segment2!double;

auto a = P(0.0, 0.0);
auto b = P(3.0, 4.0);

assert(distance(a, b) == 5.0);

auto segment = S(a, b);

assert(segmentLength(segment) == 5.0);
```

`MetricScalar!T` exposes the computation type used by metric operations.

## Orientation

Topology-sensitive orientation is explicit and does not use a global epsilon.

```d
import geo;

alias P = Point2!double;

auto result =
    orientation(
        P(0.0, 0.0),
        P(2.0, 0.0),
        P(1.0, 1.0)
    );

assert(result == Orientation2.left);
```

Robust topology currently supports `int`, `long`, `float`, and `double`.
Robust topology for `real` is deliberately deferred.

## Segment intersection

Intersection classification is separate from geometric point construction.

```d
import geo;

alias P = Point2!double;
alias S = Segment2!double;

auto first =
    S(
        P(0.0, 0.0),
        P(2.0, 2.0)
    );

auto second =
    S(
        P(0.0, 2.0),
        P(2.0, 0.0)
    );

auto kind =
    segmentIntersectionKind(
        first,
        second
    );
```

Use `segmentIntersectionKind()` for topology. Use
`trySegmentIntersectionPoint()` or `trySegmentIntersectionOverlap()` when a
geometric result is required.

## Polyline views

Variable-size geometry uses non-owning read-only views.

```d
import geo;

alias P = Point2!double;
alias V = Polyline2View!double;

P[] points = [
    P(0.0, 0.0),
    P(1.0, 0.0),
    P(2.0, 1.0),
    P(3.0, 1.0)
];

auto polyline =
    V(
        points[]
    );

auto length =
    polylineLength(
        polyline
    );
```

The view does not own, copy, or extend the lifetime of `points`. The backing
storage must remain valid while the view is used.

## Rings and polygons

A linear ring stores its vertices without duplicating the first vertex at the
end. Closure is implicit.

```d
import geo;

alias P = Point2!double;
alias R = LinearRing2View!double;
alias G = Polygon2View!double;

P[] exteriorPoints = [
    P(0.0, 0.0),
    P(10.0, 0.0),
    P(10.0, 10.0),
    P(0.0, 10.0)
];

auto exterior =
    R(
        exteriorPoints[]
    );

R[] rings = [
    exterior
];

auto polygon =
    G(
        rings[]
    );
```

For `Polygon2View`, ring 0 is the exterior and subsequent rings are holes.
Winding direction does not assign those roles.

Both `LinearRing2View` and `Polygon2View` are non-owning. In the example above,
both `exteriorPoints` and `rings` must outlive their corresponding views.

## Area

Ring area is signed. Polygon area uses structural exterior/hole roles.

```d
import geo;

alias P = Point2!double;
alias R = LinearRing2View!double;
alias G = Polygon2View!double;

P[] exteriorPoints = [
    P(0.0, 0.0),
    P(4.0, 0.0),
    P(4.0, 3.0),
    P(0.0, 3.0)
];

auto exterior =
    R(
        exteriorPoints[]
    );

auto ringArea =
    signedArea(
        exterior
    );

R[] rings = [
    exterior
];

auto polygon =
    G(
        rings[]
    );

auto area =
    polygonArea(
        polygon
    );
```

Area computation does not implicitly validate or repair topology.

## Point-in-polygon classification

Classification distinguishes outside, boundary, and inside.

```d
import geo;

alias P = Point2!double;
alias R = LinearRing2View!double;
alias G = Polygon2View!double;

P[] exteriorPoints = [
    P(0.0, 0.0),
    P(10.0, 0.0),
    P(10.0, 10.0),
    P(0.0, 10.0)
];

auto exterior =
    R(
        exteriorPoints[]
    );

R[] rings = [
    exterior
];

auto polygon =
    G(
        rings[]
    );

PointPolygonLocation location;

assert(
    tryClassifyPointInPolygon(
        polygon,
        P(5.0, 5.0),
        location
    )
);
```

Point classification does not implicitly validate polygon topology.

## Topology validation

Representation and validation are separate operations.

```d
import geo;

alias P = Point2!double;
alias R = LinearRing2View!double;
alias G = Polygon2View!double;

P[] exteriorPoints = [
    P(0.0, 0.0),
    P(10.0, 0.0),
    P(10.0, 10.0),
    P(0.0, 10.0)
];

auto exterior =
    R(
        exteriorPoints[]
    );

auto ringValidation =
    validateRing(
        exterior
    );

R[] rings = [
    exterior
];

auto polygon =
    G(
        rings[]
    );

auto polygonValidation =
    validatePolygon(
        polygon
    );
```

Validation reports topology rather than silently modifying the represented
geometry.

## Douglas-Peucker simplification

Douglas-Peucker simplification uses caller-provided destination and workspace
storage.

```d
import geo;

alias P = Point2!double;
alias V = Polyline2View!double;

P[] input = [
    P(0.0, 0.0),
    P(1.0, 0.1),
    P(2.0, 0.0),
    P(3.0, 0.1),
    P(4.0, 0.0)
];

auto polyline =
    V(
        input[]
    );

auto output =
    new P[input.length];

auto workspace =
    new size_t[
        douglasPeuckerWorkspaceSize(
            input.length
        )
    ];

size_t written;

assert(
    trySimplifyDouglasPeuckerInto(
        polyline,
        0.2,
        output[],
        workspace[],
        written
    )
);

auto simplified =
    output[0 .. written];
```

The simplifier performs no internal allocation. The allocations in this
example are caller-owned setup. Callers may instead reuse existing buffers.

Douglas-Peucker simplification is metric simplification only; it does not
claim topology preservation for rings or polygons.

## v1 source compatibility in v2

Code migrating from v1 may continue to use these deprecated aliases during
the v2 line:

~~~text
PolylineView     -> Polyline2View
LinearRingView   -> LinearRing2View
PolygonView      -> Polygon2View
Orientation      -> Orientation2
~~~

New code should use the right-hand canonical v2 names.

The canonical v2 point-to-segment distance call is:

~~~d
tryPointSegmentDistance(segment, point, result);
~~~

The former v1 point-first order remains available only as a deprecated
forwarding overload.

## Ownership and lifetime summary

The variable-size geometry types are views:

```text
Polyline2View
LinearRing2View
Polygon2View
```

They are non-owning and read-only.

The caller remains responsible for the backing storage and its lifetime.
Creating a view does not copy the underlying points.

This is intentional: geometry algorithms can operate over existing storage
without hidden ownership transfer or deep copies.

## Numerical model summary

The core storage scalar domain is:

```text
int
long
float
double
real
```

Metric operations use `MetricScalar!T`.

Robust topology currently supports:

```text
int
long
float
double
```

Robust topology for `real` is deliberately deferred because D `real` is
platform-dependent.

Topology classification and geometric construction are also deliberately
separate. A robust topological decision must not be inferred from a rounded
constructed coordinate.

For the detailed numerical contracts, see `README.md`, `docs/README.md`, and
the ADRs under `docs/adr/`.
