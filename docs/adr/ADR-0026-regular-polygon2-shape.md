# ADR-0026 — Analytic compile-time-cardinality regular polygons

**Status:** Accepted  
**Date:** 2026-11-07

## Context

`Polygon2View` represents the existing general polygon model: arbitrary
vertices, variable cardinality and caller-owned storage. A regular pentagon,
hexagon or octagon is a different concept. Its useful invariants are geometric
and its vertex count is known at compile time.

## Decision

Add:

```d
RegularPolygon2!(T, N)
```

where `N >= 3`. The value stores only centre, circumradius and starting
rotation. It does not own or cache a polygon ring. Vertices are generated on
explicit request into caller-owned `Point2!(MetricScalar!T)[]` storage.

Vertices are emitted counter-clockwise, start at the supplied rotation in
radians, and are not repeated at the end. Direct side length, perimeter and
area use `MetricScalar!T`. Construction rejects non-finite centre, radius or
rotation values and negative radii; zero radius is valid.

The common aliases are:

```d
Pentagon2!T
Hexagon2!T
Heptagon2!T
Octagon2!T
```

`Polygon2View` remains the general irregular/variable-size polygon type.
`Triangle2` remains the general three-point shape and is not replaced by the
regular-polygon specialization for `N == 3`.

## Consequences

- The distinction between arbitrary polygons and regular shapes is visible in
  the type name.
- Fixed cardinality is available to compile-time code without hidden
  allocation.
- The analytic representation avoids storing a redundant ring.
- Polygon topology validation and variable-size polygon algorithms remain on
  the existing view types.
