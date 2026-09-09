# ADR-0001 — Scope and boundaries of `geo-d`

**Status:** Accepted  
**Date:** 2026-09-09

## Context

`d-geospatial` consists of independent, reusable D libraries. Each library must represent a coherent domain, remain independently useful, and avoid dependencies that exist only for incidental code sharing.

`geo-d` is intended to provide the fundamental geometry layer of this library family.

Earlier workspace documentation described `geo-d` broadly enough to include geographic coordinate semantics and transformation adapters. Subsequent architectural work established a sharper separation between generic Euclidean geometry, geodesy, geographic referencing, coordinate-reference-system infrastructure, raster processing, and spatial indexing.

Without an explicit boundary, `geo-d` risks becoming a generic GIS utility package rather than a small geometry library.

This ADR defines that boundary. It deliberately does not define the scalar model, numerical robustness policy, ownership model for aggregate geometries, or detailed API contracts. Those decisions belong in subsequent ADRs.

## Decision

### 1. Domain

`geo-d` owns **coordinate-reference-system-independent Euclidean geometry**.

Its geometry types describe mathematical positions, displacements, extents, and geometric relationships. They do not assign geographic meaning to coordinate values.

For example:

```d
Point2!double(1.0, 2.0)
```

represents a point in a two-dimensional Euclidean space.

`geo-d` does not know whether those numbers represent metres, millimetres, pixels, arbitrary simulation units, or some other consumer-defined unit.

Units and external coordinate semantics remain the responsibility of the caller or a higher-level domain library.

### 2. Initial dimensional scope

The initial public geometry model is explicitly **two-dimensional**.

The foundational types are:

```text
Point2
Vector2
Bounds2
Segment2
```

The `2` suffix is intentional. It preserves room for later `Point3`, `Vector3`, `Bounds3`, or related types without pretending that an N-dimensional abstraction is already required.

`geo-d` will not introduce a generic `Point!(T, N)` or equivalent N-dimensional foundation in its initial design.

Three-dimensional geometry may be added later when concrete consumers demonstrate a sufficiently clear requirement. Such an extension requires a separate architectural decision.

### 3. Initial algorithmic domain

The first implementation slice may contain operations directly associated with the foundational value types, including:

```text
point/vector algebra
squared distance
distance
bounds construction
bounds extension
bounds containment
segment length
nearest point on a segment
orientation
```

The existence, scalar requirements, failure semantics, and numerical contracts of individual operations are defined by later ADRs and API design.

In particular, this ADR does not prescribe how floating-point orientation must be made robust.

### 4. Geometry that belongs to `geo-d` but is deferred

The following concepts are within the long-term domain of a generic Euclidean geometry library, but are not part of the first implementation slice:

```text
segment intersection
Polyline
PolylineView or equivalent borrowed representation
LinearRing
Polygon
signed area
point-in-polygon
polyline length
simplification
clipping
```

Their inclusion in the domain does not commit them to `v0.1.0`.

Aggregate geometry must not be introduced until ownership and borrowing semantics have been defined.

Topology-sensitive algorithms must not be introduced until the numerical robustness policy has been defined.

### 5. Earth and geodesy are outside `geo-d`

`geo-d` does not contain or interpret:

```text
Earth models
ellipsoids
Latitude
Longitude
ellipsoidal height
geocentric / ECEF coordinates
geodesics
geodetic datum transformations
```

Earth- and ellipsoid-dependent mathematics belongs to `geodesy-d`.

`geo-d` must not depend on `geodesy-d`.

`geodesy-d` does not need to be modified or made dependent on `geo-d` merely to support this library.

### 6. Geographic referencing is outside `geo-d`

Systems whose purpose is to identify, reference, encode, or partition geographic locations do not belong to `geo-d`.

Examples include:

```text
MGRS
geohash
geographic grid references
location coding systems
```

Such concepts belong to `georef-d` or another explicitly specialised library.

### 7. CRS infrastructure is outside `geo-d`

`geo-d` does not own:

```text
CRS definitions
EPSG authorities
coordinate operations
projection definitions
datum databases
transformation grids
PROJ contexts
PROJ pipelines
```

These belong to `proj-d` or other specialised CRS infrastructure.

A transformation library may use or adapt `geo-d` value types where that produces a genuine conceptual layering, but CRS semantics must never be embedded into `Point2` or another fundamental `geo-d` type.

Interoperability should be implemented through higher-level APIs or adapters rather than by adding CRS responsibilities to the geometry core.

### 8. Raster processing is outside `geo-d`

Raster storage, raster views, pixel layout, sampling, convolution, image processing, and related raster operations belong to `raster-d`.

A raster consumer may use `Point2`, `Vector2`, `Bounds2`, or related geometry where useful, but `geo-d` must not acquire raster semantics as a consequence.

Pixel coordinates and array indices are not automatically equivalent to generic Euclidean points.

### 9. Spatial indexing is outside `geo-d`

`geo-d` owns geometry.

`spatial-d` owns **data structures and algorithms whose primary purpose is spatial indexing and search**.

Examples belonging to `spatial-d` include:

```text
R-tree
packed R-tree / STR tree
spatial hash
spatial search structures
bulk index construction
mutable index maintenance
nearest-object search infrastructure
```

This boundary applies even when such indexes internally operate on bounding boxes.

`Bounds2` is a geometric value and therefore belongs to `geo-d`.

An R-tree over bounds is a spatial index and therefore belongs to `spatial-d`.

Whether `spatial-d` eventually depends directly on `geo-d`, uses an adapter, or accepts a more generic bounds interface is a decision for `spatial-d`; it is not imposed by this ADR.

### 10. Formats and I/O are outside `geo-d`

`geo-d` does not parse or serialise GIS or geometry file formats merely because those formats contain geometry.

Shapefile, GeoJSON, WKB/WKT, OSM, GDAL datasets, and similar format concerns belong in specialised packages or adapters unless a later use case demonstrates a compelling independent geometry-format abstraction.

The geometry model must remain independent of where geometry came from.

### 11. Dependency policy

The foundational `geo-d` package should have the smallest practical dependency set.

Its core must not require:

```text
GDAL
PROJ
GEOS
a GUI framework
a logging framework
another d-geospatial package
```

solely to provide ordinary Euclidean geometry.

The D standard library may be used where appropriate.

Any future external dependency must provide substantial domain value and requires deliberate justification.

### 12. Ownership boundary

The foundational types

```text
Point2
Vector2
Bounds2
Segment2
```

are small value types.

The storage and borrowing model for variable-sized geometries such as polylines, rings, and polygons is explicitly deferred to a separate ADR.

No aggregate geometry API may introduce hidden deep copies as an accidental implementation detail.

### 13. Numerical boundary

This ADR establishes the mathematical domain but does not establish a universal numerical policy.

In particular, it does not decide:

```text
floating-point-only versus integer-capable scalars
mixed-scalar operations
implicit or explicit conversions
NaN and infinity policy
approximate equality
orientation robustness
exact predicates
adaptive precision
intersection tolerances
```

These questions are resolved by the core-type/scalar and numerical-robustness ADRs.

`geo-d` will not introduce a global epsilon-based approximate equality as a substitute for algorithm-specific numerical reasoning.

### 14. Public API philosophy

The public API should remain deliberately small.

Public concepts must correspond to stable geometry concepts rather than temporary implementation details.

Fundamental value operations should be inexpensive and predictable. Hidden allocation must be avoided.

Where technically appropriate, pure computational operations should support strong D contracts such as:

```d
@safe
pure
nothrow
@nogc
```

The precise guarantees are defined per API rather than imposed indiscriminately by this scope ADR.

### 15. Application independence

`geo-d` must remain equally meaningful in:

```text
GIS
CAD
simulation
robotics
games
scientific computing
numerical software
```

No public API may assume a map editor, GIS workflow, Earth model, display system, or particular application.

Applications are consumers of `geo-d`, not part of its specification.

## Architectural relationship

The intended conceptual separation is:

```text
geo-d
    generic Euclidean geometry

geodesy-d
    Earth- and ellipsoid-dependent mathematics

georef-d
    geographic referencing and location coding

raster-d
    raster representation and raster algorithms

spatial-d
    spatial indexes and spatial-query infrastructure

proj-d
    CRS, authority, grid and coordinate-operation infrastructure
```

Dependencies between these libraries are allowed only when they express genuine conceptual layering.

No common runtime or mandatory foundation package is introduced.

## Consequences

`geo-d` remains small enough to be useful outside GIS.

Generic Euclidean geometry can evolve without importing Earth, CRS, raster, indexing, or native-GIS concerns.

Higher-level libraries can use the geometry types without making those higher-level semantics part of the geometry model.

Some interoperability code may exist in adapters rather than in the fundamental packages themselves. This duplication of small boundary code is preferable to coupling unrelated domains.

The initial library is intentionally limited to 2D. A future 3D API will require evidence from real consumers rather than speculative genericity.

The scalar model, `.init` semantics, finite-value policy, conversion rules, Point/Vector algebra, aggregate ownership model, and robust-predicate strategy remain open decisions.

## Alternatives considered

### A broad generic GIS geometry package

Rejected because it would mix Euclidean geometry with geographic coordinates, CRS infrastructure, transformations, and application-specific interoperability.

### Geographic semantics directly in `Point2`

Rejected because the same mathematical geometry types should remain usable in CAD, simulation, robotics, games, and other non-geographic domains.

### A generic N-dimensional geometry foundation from the start

Rejected as premature generalisation. The immediate requirements are two-dimensional, while a fully generic dimensional architecture would constrain the public API before concrete 3D or N-dimensional requirements are known.

### Spatial indexes inside `geo-d`

Rejected because geometric representation and spatial indexing are distinct domains with different data structures, performance concerns, and evolution paths.

### A shared `common-d` or geometry foundation package below `geo-d`

Rejected. `geo-d` itself is already the fundamental Euclidean geometry domain. Incidental helpers do not justify another package.

## Follow-up decisions

The next architecture decisions are:

```text
ADR-0002 — Core type and scalar model
ADR-0003 — Geometry ownership and views
ADR-0004 — Numerical robustness
```

ADR-0002 must be resolved before implementation of the foundational public value types.

ADR-0003 must be resolved before introducing variable-sized geometries.

ADR-0004 must be resolved before topology-sensitive intersection and polygon algorithms become part of the stable API.