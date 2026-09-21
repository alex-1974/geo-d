# geo-d v2 API conventions

## Status

Normative API-family conventions for the `geo-d` v2 integration.

This document summarizes the public API grammar established by:

- `docs/adr/ADR-0019-geo-d-v2-api-family-migration.md`;
- `docs/adr/ADR-0020-shared-euclidean-contract-core.md`;
- the complete v1-to-v2 review in `docs/v2-public-api-audit.md`.

It does not itself add geometry functionality or declare the v2 API frozen.

Where this document conflicts with an accepted ADR, the ADR governs.

## Library family

The Euclidean geometry family consists of independent sibling libraries:

```text
geo-d       coordinate-system-agnostic Euclidean 2D geometry
geo3-d      coordinate-system-agnostic Euclidean 3D geometry
```

Their public module roots are:

```d
import geo;
import geo3;
```

Neither sibling depends on the other.

The family follows:

> Symmetry where the mathematics is symmetric; specialization where it is not.

A similar name or API shape is not sufficient reason to invent a dimensional
counterpart.

New public API remains consumer-driven and research-gated.

## Dimension-bearing type names

The dimension belongs in the public name of a geometry type when the type is
intrinsically dimension-specific.

Canonical 2D names include:

```text
Point2
Vector2
Segment2
Bounds2
Polyline2View
LinearRing2View
Polygon2View
Orientation2
```

Corresponding established or plausible family names use the same grammar:

```text
Point2            Point3
Vector2           Vector3
Segment2          Segment3
Bounds2           Bounds3
Polyline2View     Polyline3View
LinearRing2View   LinearRing3View
Orientation2      Orientation3
```

Representation qualifiers follow the dimensional geometry name:

```text
Polyline2View
LinearRing2View
```

not:

```text
PolylineView2
LinearRingView2
```

The public family does not use a generic dimension parameter merely for
implementation reuse:

```d
Point!(T, N)
```

is not the public geometry model.

Internal generic helpers remain possible when justified by concrete
implementation, numerical, or benchmark evidence.

## Dimension-specific concepts

API-family symmetry does not override mathematical semantics.

`Polygon2View` is a two-dimensional polygon representation.

Its existence does not imply:

```text
Polygon3View
```

A planar surface embedded in 3D requires an explicit semantic design and a
real consumer before public API is introduced.

Likewise, current polygon-area and point-in-polygon semantics remain 2D.

A 3D ring representation or validation operation may be meaningful without
implying 3D polygon-area semantics or a planarity requirement.

## Operation names

Operations normally keep dimension-neutral names when they form a genuine
mathematical family.

Dimension-neutral names used by the current API or established family
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
simplify(...)
```

This list defines naming vocabulary, not a requirement that every listed
operation exist in both dimensions.

The dimension is normally expressed by argument type and, where appropriate,
argument arity.

Do not introduce operation names such as:

```text
distance2
distance3
orientation2
orientation3
```

solely to encode dimension in the function name.

A dimension-neutral name does not require the operation to exist in every
dimension. A counterpart is introduced only when its semantics and consumer
need are established.

## Orientation

The canonical 2D affine operation is:

```d
orientation(a, b, c)
```

for three 2D points.

Its result type is:

```text
Orientation2
```

with the established values:

```text
right      = -1
collinear  =  0
left       = +1
```

The existing initialization consequence remains part of the contract:

```text
Orientation2.init == Orientation2.right
```

The plausible affine 3D family form is:

```d
orientation(a, b, c, d)
```

for four 3D points, with a dimension-specific `Orientation3` result describing
the oriented tetrahedral / volume relation.

A three-point 3D cross product is not the affine orientation operation.

Conceptual vector-space orientation examples in workspace documentation do
not by themselves authorize additional public overloads.

## Free functions and UFCS

Geometry algorithms normally remain free functions.

The ordinary free-function form is canonical.

Where the mathematics provides a natural first argument, parameter ordering
should also produce useful D UFCS.

For example:

```d
segmentLength(segment);
segment.segmentLength();

tryNearestPoint(segment, point, result);
segment.tryNearestPoint(point, result);
```

Argument order must not be distorted merely to obtain UFCS syntax.

Related operation families should use the same natural receiver where
possible.

## Point-to-segment distance

The canonical v2 order of `tryPointSegmentDistance` is:

```d
tryPointSegmentDistance(segment, point, result);
```

which permits:

```d
segment.tryPointSegmentDistance(point, result);
```

The v1 order:

```d
tryPointSegmentDistance(point, segment, result);
```

remains only as a deprecated forwarding overload.

The compatibility overload must not contain an independent implementation.

## v1 compatibility names

The v2 canonical names replace the following v1 names:

```text
PolylineView     -> Polyline2View
LinearRingView   -> LinearRing2View
PolygonView      -> Polygon2View
Orientation      -> Orientation2
```

The v1 names remain deprecated compatibility aliases throughout the promised
v2 compatibility period unless retaining one would introduce ambiguity or
incorrect semantics.

Canonical v2 documentation, examples, and new consumer code use the
dimension-explicit names.

Historical v1 documentation and explicit migration/compatibility discussion
may continue to use the old names where historically correct.

## Root-package compatibility

A canonical v2 consumer must be able to write:

```d
import geo;
```

under strict deprecation checking without receiving a deprecation error merely
because compatibility aliases exist.

The root package therefore exports the canonical declaration and defines its
deprecated v1 alias locally.

Conceptually:

```d
public import geo.polyline_view : Polyline2View;

deprecated("Use Polyline2View")
alias PolylineView = Polyline2View;
```

The root package must not obtain these compatibility names by publicly
importing deprecated module-level aliases.

## Shared declaration identity

`geo-d` and `geo3-d` remain independent public sibling libraries.

A small shared support package, `euclid-core-d`, provides the common
declaration origin for neutral contracts that require one D declaration
identity in both siblings.

`euclid-core-d` is a separate DUB package, but it is not a third
consumer-facing geometry API.

The current shared-contract set is:

```text
isGeoScalar
MetricScalar
IntersectionScalar
SegmentIntersectionKind
RingValidationIssue
RingValidationResult
douglasPeuckerWorkspaceSize
```

`AreaScalar` remains owned by `geo-d`.

A declaration belongs in the shared core only when:

1. it is dimension-neutral;
2. both siblings genuinely require the same public contract;
3. one common D declaration identity is required for correct simultaneous
   sibling use; and
4. moving it does not create a generic dimension-independent geometry model.

Implementation reuse, duplicated source text, or aesthetic symmetry alone are
not sufficient reasons.

## Shared core is not a third public geometry API

Ordinary consumers should reason about:

```text
geo.*
geo3.*
```

not about:

```text
euclid_core.*
```

`euclid-core-d` exists to provide common declaration identity, not to become a
general-purpose geometry package or a public N-dimensional abstraction.

It must not absorb unrelated domain responsibilities from geodesy, CRS,
imagery, OSM, location referencing, raster processing, or spatial indexing.

## Documentation facade

Runtime declaration identity and documentation ownership are separate
concerns.

For shared declarations, `geo-d` may use:

```text
private selective import
runtime alias to the shared declaration
version(D_Ddoc) local documentation declaration
```

so that runtime builds retain common declaration identity while generated
documentation presents the expected `geo.*` API.

The same principle applies to `geo3-d`.

Generated public documentation must not expose `euclid_core.*` as the
preferred consumer vocabulary.

A `version(D_Ddoc)` facade must preserve the documented public semantics and
layout requirements relevant to that declaration, even where the
documentation-only nominal declaration is not identical to the runtime
declaration.

## Dependency and tooling rule

The intended dependency structure is:

```text
             euclid-core-d
                /     \
               /       \
            geo-d     geo3-d
```

There is no `geo-d -> geo3-d` or `geo3-d -> geo-d` dependency.

A local DUB path used during workspace development is not part of the public
architecture.

Tools invoking DMD or LDC directly must resolve dependency import paths
through DUB rather than hard-coding the workspace location of
`euclid-core-d`.

Release packaging must use an appropriate package dependency rather than
requiring the workspace directory layout.

## Compatibility lifecycle

The intended compatibility lifecycle is:

```text
v1.x    existing v1 API
v2.0    canonical v2 API plus deprecated v1 compatibility
v2.x    deprecated v1 compatibility remains functional
v3.0    earliest normal removal point
```

Deprecated compatibility is tested separately from canonical v2 usage.

Canonical consumer tests must not depend on deprecated names or signatures.

## API expansion

The v2 family migration does not authorize speculative API.

In particular, family symmetry alone does not justify:

```text
Polygon3View
3D polygon area
generic N-dimensional geometry
new intersection frameworks
new owning geometry containers
new simplification variants
```

Future additions require a concrete consumer or research result and the same
correctness, API, memory, numerical, and performance review applied elsewhere
in `geo-d`.

## Freeze

These conventions describe the intended v2 API family but do not themselves
freeze it.

The v2 freeze occurs only after the remaining documentation, durable consumer
proofs, complete local verification, CI, and shared-dependency release
packaging gates have passed.
