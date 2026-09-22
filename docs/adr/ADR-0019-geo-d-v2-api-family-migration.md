# ADR-0019: geo-d v2 API-family migration

**Status:** Accepted

**Date:** 2026-09-20
**Amended:** 2026-09-21 — the migration decisions were updated from the
pre-implementation design state to the implemented v2 integration state.

**Freeze recorded:** 2026-09-22 — all v2 integration and packaging gates
completed and the public API was frozen for v2.0.0 release preparation.

## Context

`geo-d` v2 aligns the established two-dimensional API with the independent
`geo3-d` three-dimensional sibling library.

This is an intentional reopening of API design rather than an expansion of
`geo-d` into a 3D library.

`geo-d` remains exclusively responsible for coordinate-system-independent
Euclidean 2D geometry. `geo3-d` is a separate repository and DUB package.
Neither sibling depends on the other.

The workspace-level API-family rule is:

> Symmetry where the mathematics is symmetric; specialization where it is not.

The v2 migration therefore standardizes shared vocabulary and API structure
without inventing dimensional counterparts whose mathematics or consumer need
has not been established.

The complete v1 public surface, including public type members and overloads
rather than only package-level exports, has been audited before the v2 freeze.
That inventory remains the historical v1 input to the migration rather than
being rewritten into a v2 inventory.

## Decision

### 1. Dimension-explicit type names

Dimension-bearing geometry types use an explicit dimensional suffix.

Existing dimension-explicit types remain canonical:

```text
Point2
Vector2
Segment2
Bounds2
```

The previously dimension-implicit aggregate and result types migrate as:

```text
PolylineView     -> Polyline2View
LinearRingView   -> LinearRing2View
PolygonView      -> Polygon2View
Orientation      -> Orientation2
```

The corresponding shared-family vocabulary is:

```text
geo-d                         geo3-d
------------------------------------------------
Point2                        Point3
Vector2                       Vector3
Segment2                      Segment3
Bounds2                       Bounds3
Polyline2View                 Polyline3View
LinearRing2View               LinearRing3View
Orientation2                  Orientation3
```

A dimensional counterpart is not introduced merely for symmetry.

In particular, `Polygon2View` remains a two-dimensional concept. No
`Polygon3View` is implied by this ADR. Planar surfaces embedded in 3D require
their own consumer-driven semantic design.

The public API does not introduce a generic form such as:

```d
Point!(T, N)
```

merely to share implementation between dimensions.

### 2. Dimension-neutral operation names

Operations normally retain a dimension-neutral name when the mathematical
operation forms a genuine family.

Dimension-neutral operation names used by the current API and the family
design include:

```d
distance(...)
squaredDistance(...)
segmentLength(...)
polylineLength(...)
tryNearestPoint(...)
tryBounds(...)
tryConvert(...)
orientation(...)
validateRing(...)
```

as well as the existing simplification family.

This naming convention does not itself require every operation to acquire a
3D overload. A dimensional counterpart is introduced only when its
mathematics is well defined and a concrete consumer or research result
justifies it.

Dimension is normally expressed by argument type and, where mathematically
appropriate, argument arity rather than by names such as `distance2`,
`distance3`, `orientation2`, or `orientation3`.

### 3. Orientation family

The canonical 2D affine orientation operation remains:

```d
orientation(a, b, c)
```

and returns `Orientation2`.

Its established value contract is preserved:

```text
right      = -1
collinear  =  0
left       = +1
```

including the existing default-initialization consequence:

```text
Orientation2.init == Orientation2.right
```

The plausible affine 3D family member is:

```d
orientation(a, b, c, d)
```

returning a dimension-specific `Orientation3` result for the oriented
tetrahedral / volume relation.

A three-point 3D cross product is not the same operation as affine
orientation and is not introduced by this migration.

Workspace documentation may use vector-space orientation forms as conceptual
family examples. Such examples do not by themselves authorize additional
`geo-d` public overloads.

### 4. UFCS and canonical argument order

Public geometry algorithms remain free functions.

Where the mathematics provides a natural receiver, parameter order should
also provide predictable D UFCS without distorting the ordinary free-function
form.

For segment/point metric operations the canonical receiver is the segment:

```d
tryNearestPoint(segment, point, result);
segment.tryNearestPoint(point, result);

tryPointSegmentDistance(segment, point, result);
segment.tryPointSegmentDistance(point, result);
```

The canonical v2 `tryPointSegmentDistance` order is therefore:

```text
segment, point, result
```

The v1 point-first form remains as a deprecated forwarding overload:

```text
point, segment, result
```

It contains no independent implementation.

### 5. v1 compatibility surface

Where the old API can be retained without semantic error or overload
ambiguity, v2 keeps it as deprecated compatibility surface.

The renamed v1 types remain available as deprecated aliases:

```d
PolylineView
LinearRingView
PolygonView
Orientation
```

Their canonical replacements are respectively:

```d
Polyline2View
LinearRing2View
Polygon2View
Orientation2
```

The intended lifecycle remains:

```text
v1.x    existing API
v2.0    canonical v2 API + deprecated v1 compatibility
v2.x    deprecated compatibility remains functional
v3.0    earliest normal removal point
```

Deprecated APIs alias or forward to the canonical implementation rather than
maintaining independent implementations.

Canonical documentation, examples, and new consumer code use only v2 names
and signatures.

Compatibility tests remain separate from canonical v2 tests.

### 6. Root-package compatibility aliases

The root package must permit a canonical consumer to write:

```d
import geo;
```

under strict deprecation checking without failing merely because deprecated
compatibility names exist elsewhere in the package.

For renamed types, `geo/package.d` therefore exports the canonical type and
declares the deprecated v1 compatibility alias locally.

Conceptually:

```d
public import geo.polyline_view : Polyline2View;

deprecated("Use Polyline2View")
alias PolylineView = Polyline2View;
```

The same pattern applies to `LinearRingView`, `PolygonView`, and
`Orientation`.

The root package does not obtain those compatibility names by publicly
importing deprecated module-level aliases.

### 7. Shared declaration identity

Some neutral contracts must have one declaration identity when `geo` and
`geo3` are imported into the same D program.

Those contracts are owned by the small shared `euclid-core-d` package and are
surfaced through the sibling libraries.

The shared-core architecture, admission rule, documentation facade, and
dependency constraints are defined by ADR-0020.

Shared implementation alone is not sufficient justification for moving a
declaration into the core.

`AreaScalar` remains owned by `geo-d` because its current semantics are
two-dimensional rather than a shared declaration-identity requirement.

### 8. Documentation identity

The public documentation surface remains expressed in terms of `geo.*` and,
for the sibling library, `geo3.*`.

Internal `euclid_core.*` declaration ownership must not leak into ordinary
public API documentation merely because runtime declaration identity is
shared.

The runtime/documentation facade mechanism is defined by ADR-0020.

### 9. No feature expansion implied

This migration does not authorize speculative geometry API.

In particular, it does not introduce merely for family symmetry:

```text
3D polygon semantics
3D area
generic N-dimensional public geometry types
generic intersection frameworks
new simplification variants
new owning geometry containers
```

Future API remains consumer-driven and research-gated.

## Compatibility consequences

The canonical v2 surface adds dimension-explicit names while retaining
supported v1 source forms as deprecated compatibility aliases or forwarding
overloads.

The frozen v1 inventory remains the migration input and is not rewritten to
match the resulting v2 declaration count.

The resulting v2 surface and both audit fingerprints are recorded in
`docs/v2-public-api-audit.md`.

## Freeze condition

Acceptance of this ADR does not itself declare the v2 API frozen.

The migration research and implementation have resolved:

- the complete v1 declaration disposition;
- dimension-explicit naming;
- UFCS receiver and argument-order review;
- 2D orientation semantics and a plausible affine 3D counterpart;
- deprecated compatibility aliases and forwarding overloads;
- simultaneous `geo` / `geo3` coexistence;
- the common-declaration-identity requirement;
- the shared-core architecture;
- the public-documentation facade strategy.

The integration state has already provided local evidence for:

- canonical v2 consumers compiling without deprecated API;
- deprecated v1 compatibility behaviour;
- generated DDox exposing the intended sibling-owned symbols without core
  leakage;
- the public API auditor matching the intended v2 surface;
- DMD and LDC test and release verification;
- simultaneous `geo` / `geo3` coexistence.

These results are implementation evidence, not a declaration that the v2 API
is already frozen.

Those final integration conditions have now been completed:

- permanent project documentation is aligned with the implemented decisions;
- the cross-repository family/coexistence proof is retained as the durable
  `tests/family-consumer/` verification package;
- the complete verification gate has been rerun after integration;
- current CI evidence exists for the frozen integration state;
- `euclid-core-d v0.1.0` is published and consumed through a versioned public
  DUB dependency.

The v2 public API is therefore frozen for v2.0.0 release preparation.

The freeze is recorded separately from the release because subsequent work may
still improve verification, documentation, packaging, or fix defects without
changing the frozen public contract.

Any change to the frozen public API requires the freeze to be explicitly
reopened and the complete API and integration audit to be repeated.
