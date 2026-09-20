# ADR-0019: geo-d v2 API-family migration

**Status:** Accepted

**Date:** 2026-09-20

## Context

`geo-d` v2 aligns the established two-dimensional API with the planned `geo3-d` three-dimensional sibling library.

This is an intentional reopening of API design rather than an expansion of `geo-d` into a 3D library.

`geo-d` remains exclusively responsible for coordinate-system-independent Euclidean 2D geometry.

## Decision

### Objective

The v2 API should make dimension, representation, overload structure, parameter ordering, and UFCS behaviour predictable across the future `geo-d` / `geo3-d` family.

The complete v1 public surface, including public type members and overloads rather than only package-level exported names, must be audited against the shared 2D/3D API conventions before the v2 API is frozen.

### Dimensional type names

Types whose current names omit their intrinsically two-dimensional nature should be reviewed for explicit dimensional naming.

Initial migration candidates are:

```text
PolylineView     -> Polyline2View
LinearRingView   -> LinearRing2View
PolygonView      -> Polygon2View
```

The existing names should remain available as deprecated compatibility aliases throughout the v2 line where D permits this without changing semantics or creating ambiguity.

Canonical documentation and new code should use only the v2 names.

### Operation families

Operations should normally retain dimension-independent names.

The v2 audit should prefer overload families such as:

```d
distance(...)
orientation(...)
tryBounds(...)
tryNearestPoint(...)
```

rather than introducing dimension-numbered function names.

Where useful, 2D overloads should be designed so that the corresponding future 3D overload has the same operation name and analogous argument structure.

### UFCS and argument order

Every public free-function family must be reviewed for natural UFCS use.

The free-function form remains canonical, but related operations should use a consistent natural receiver when possible.

For example, point/segment operations should be reviewed together:

```d
tryNearestPoint(segment, point, result);
segment.tryNearestPoint(point, result);
```

If `tryPointSegmentDistance` is standardized to the same receiver:

```d
tryPointSegmentDistance(segment, point, result);
segment.tryPointSegmentDistance(point, result);
```

the existing v1 argument order may remain as a deprecated forwarding overload when overload resolution remains unambiguous.

### Orientation

`orientation` requires a dedicated v2 audit because its operation name can naturally form a shared 2D/3D overload family while its result semantics may be dimension-specific.

The audit must distinguish:

```text
operation name
argument arity
result type
result-value terminology
robust determinant implementation
```

The operation name should remain `orientation` unless evidence requires otherwise.

The result type and enumerator vocabulary must be chosen according to mathematical semantics rather than superficial dimensional symmetry.

### Deprecation policy

Where a v1 API can be preserved without ambiguity or incorrect semantics, v2 should retain it as deprecated compatibility surface.

The preferred lifecycle is:

```text
v1.x    existing API
v2.0    new canonical API + deprecated v1 compatibility names/signatures
v2.x    deprecated compatibility remains functional
v3.0    earliest normal removal point for v1 compatibility surface
```

Deprecated APIs must forward to or alias the canonical implementation rather than maintain an independent implementation.

New documentation, examples, tests intended to demonstrate the preferred API, and new consumer code must use only the canonical v2 surface.

Separate compatibility tests should verify that deprecated v1 source forms continue to compile for as long as they are promised.

A deprecated name or overload must not be retained when doing so would preserve incorrect semantics, create ambiguous overload resolution, or prevent a coherent v2 API. Such exceptions require an explicit migration note.

### v2 freeze condition

The v2 API must not be frozen until:

```text
the full v1 public surface has been audited;
the 2D/3D naming grammar is applied consistently;
UFCS and argument ordering are reviewed;
orientation semantics are resolved;
deprecated compatibility coverage is defined;
canonical v2 consumer tests compile without deprecation warnings; and
the corresponding plausible geo3-d signatures have been written down for every shared concept.
```

No `geo3-d` implementation is required for the `geo-d` v2 freeze.

A compile-only or design-level 3D API model is sufficient to validate symmetry.
