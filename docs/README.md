# geo-d technical documentation

This directory contains the architectural and numerical documentation for
`geo-d`.

The repository `README.md` provides the public introduction and usage
overview. `ROADMAP.md` tracks release preparation and possible future work.
This document describes the current technical model in more detail.

## Documentation map

Architecture decisions are recorded under:

~~~text
docs/adr/
~~~

The ADRs define the stable semantic contracts for:

- library scope and boundaries;
- scalar and core geometry types;
- ownership and non-owning views;
- numerical robustness;
- segment intersection;
- ring and polygon representation;
- area semantics;
- point-in-polygon classification;
- topology validation;
- polyline simplification.

Performance-specific material is documented under:

~~~text
benchmarks/
~~~

Public API documentation conventions are defined in:

~~~text
docs/ddoc-style.md
~~~

This guide defines the documentation contract for symbols exposed through
`import geo;`, including semantics, input domains, failure behaviour,
allocation, complexity, numerical guarantees, and examples.


## Core geometry model

The foundational value types are:

~~~text
Point2
Vector2
Bounds2
Segment2
~~~

Supported core scalar types are:

~~~text
int
long
float
double
real
~~~

`Point2` represents an affine point and `Vector2` represents displacement.
They deliberately have different algebra.

Geometry values with different scalar types do not implicitly convert.

Explicit conversion is provided through checked conversion helpers and
explicit floating-point quantisation operations.

`Bounds2.init` is empty rather than a degenerate bounds at the origin.

## Variable-size geometry

Variable-size geometry is represented initially through non-owning,
read-only views:

~~~text
PolylineView
LinearRingView
PolygonView
~~~

The caller owns the backing storage.

The views do not copy point data and are designed around explicit borrowing
and DIP1000 lifetime checking.

`PolygonView` is a view over `LinearRingView` descriptors. Its rings need not
share one contiguous point-storage region.

Ring roles are structural:

~~~text
ring 0      exterior
ring 1..n   holes
~~~

Winding direction does not assign polygon ring roles.

## Metric operations

The metric computation type is exposed as `MetricScalar!T`:

~~~text
int     -> double
long    -> double
float   -> double
double  -> double
real    -> real
~~~

Public metric operations include:

- `distance`;
- `squaredDistance`;
- `segmentLength`;
- `polylineLength`;
- `tryNearestPoint`;
- `tryPointSegmentDistance`.

Metric calculations are deliberately separate from topology predicates.

## Numerical robustness

`geo-d` does not use one global epsilon for computational topology.

Ordinary value algebra follows the normal arithmetic behaviour of the
corresponding D scalar type.

Topology-sensitive algorithms instead use exact or certified arithmetic
where their semantic contract requires it.

Robust topology support currently covers:

~~~text
int
long
float
double
~~~

A platform-aware robust backend for `real` is deliberately deferred.

Representability and algorithm validity are distinct concepts. Floating
`Point2`, `Vector2`, and `Segment2` values may contain non-finite values even
though a particular topology algorithm may reject them.

## Robust orientation

`orientation(a, b, c)` returns one of:

~~~text
Orientation.right
Orientation.collinear
Orientation.left
~~~

The numerical strategies are:

| Scalar | Strategy |
|---|---|
| `int` | exact over the complete `int` domain |
| `long` | exact over the complete `long` domain |
| `float` | exact promotion into the binary64 robust backend |
| `double` | certified binary64 filter with exact fallbacks |
| `real` | deferred |

For `double`, increasingly expensive internal stages are used only when
necessary:

~~~text
certified binary64 filter
        |
        v uncertain
exact floating-point expansion
        |
        v unsupported exponent range
exact fixed-width dyadic fallback
~~~

The exact arithmetic implementation is internal and is not itself part of
the public API contract.

Verification includes an independent `std.bigint.BigInt` oracle in unittest
builds.

## Segment intersection

Segment intersection deliberately separates topology from geometric
construction.

Public operations are:

~~~text
segmentIntersectionKind
trySegmentIntersectionOverlap
trySegmentIntersectionPoint
~~~

`segmentIntersectionKind` is the authoritative topological classification.

Positive-length overlap construction selects exact endpoints from the input
geometry.

Unique intersection-point construction treats endpoint contacts and
T-junctions separately from proper crossings.

Proper crossings are constructed through exact bounded arithmetic and
rounded only when the final binary64 point coordinates are produced.

Conceptually:

~~~text
exact orient2d determinants
        |
        v
exact barycentric weights
        |
        v
exact weighted rational coordinates
        |
        v
round-to-nearest, ties-to-even
        |
        v
Point2!double
~~~

A rounded construction result must not be substituted for exact topology
classification.

## Signed area

Linear-ring signed area is based on exact determinant accumulation for the
supported non-`real` scalar domains.

The accumulated exact result is converted to binary64 only once.

This avoids repeated floating-point rounding during vertex accumulation.

Signed area remains algebraic. Ring orientation determines the sign but does
not by itself determine polygon role.

Self-intersecting rings therefore retain algebraic cancellation semantics;
validity is handled separately by topology validation.

## Polygon area

Polygon area uses structural ring roles rather than winding direction.

Conceptually:

~~~text
abs(exterior exact area)
    - sum(abs(hole exact area))
~~~

Ring contributions are combined before the final rounding step.

Area calculation does not implicitly:

- validate topology;
- normalise winding;
- repair rings;
- reinterpret ring roles.

## Point-in-polygon classification

Point classification uses explicit three-way semantics:

~~~text
outside
boundary
inside
~~~

Boundary detection is exact for the supported robust scalar domains.

Interior classification uses even-odd semantics and does not depend on ring
orientation.

Polygon classification treats a point as inside when it is inside the
exterior ring and not inside a hole, subject to explicit boundary handling.

Representation and classification remain separate from topology validation.

## Topology validation

Validation is explicit rather than embedded into geometry construction.

Public entry points are:

~~~text
validateRing
validatePolygon
~~~

Ring validation detects conditions including:

- insufficient cardinality;
- non-finite coordinates;
- zero-length edges;
- self-intersections;
- self-overlaps.

Polygon validation additionally examines relationships between rings,
including:

- crossings;
- overlaps;
- distinct contact points;
- hole containment;
- nested holes;
- connected polygon interior.

Tangential contacts are permitted when the resulting topology satisfies the
polygon validity contract.

`validateRing` is designed for:

~~~text
pure
nothrow
@safe
@nogc
~~~

`validatePolygon` requires variable-size temporary bookkeeping for its
connected-interior analysis and therefore does not promise `@nogc`.

## Douglas-Peucker simplification

Plain metric Douglas-Peucker simplification is provided for `PolylineView`.

Public operations are:

~~~text
douglasPeuckerWorkspaceSize
trySimplifyDouglasPeuckerInto
~~~

The implementation:

- is iterative;
- does not recurse;
- performs no allocation;
- uses caller-provided destination storage;
- uses caller-provided workspace;
- returns an ordered subsequence of input points;
- retains first and last points for ordinary multi-point input;
- uses deterministic tie-breaking.

It deliberately does not claim topology preservation.

Ring and polygon simplification require a separate future design because
they must preserve constraints such as closure, self-intersection rules,
hole containment, and inter-ring relationships.

## Geometry bounds

Axis-aligned bounds of existing geometry are computed with:

~~~text
tryBounds
~~~

The operation supports:

~~~text
Segment2
PolylineView
LinearRingView
PolygonView
~~~

Its semantics are representation-based rather than topology-validating.

For variable-size geometry:

- empty geometry succeeds with `Bounds2.init`;
- every stored coordinate contributes;
- polygon rings are all considered regardless of topology validity;
- NaN causes transactional failure;
- infinities are permitted;
- no allocation is performed.

Complexity is:

~~~text
Segment2        O(1)
PolylineView    O(n)
LinearRingView  O(n)
PolygonView     O(total stored vertices)
~~~

The traversal cost is intentionally exposed through the `tryBounds` operation
rather than hidden behind a property access.

## Execution properties

Low-level numerical operations are designed to provide the strongest useful
contracts permitted by their semantics, commonly:

~~~text
pure
nothrow
@safe
@nogc
~~~

These attributes are API guarantees where declared, not merely stylistic
goals.

Higher-level algorithms may relax `@nogc` when variable-size temporary state
is inherently useful and explicit.

## Verification

Numerical and topology verification includes, where applicable:

- full-range signed integer coordinates;
- arbitrary finite binary32 and binary64 bit patterns;
- subnormal values;
- maximum finite binary64 values;
- exact collinearity;
- near-degenerate configurations;
- permutation invariants;
- endpoint-reversal invariants;
- independent `BigInt` oracle comparison;
- DMD and LDC execution.

Benchmarks are maintained for numerical paths where exact arithmetic may
materially affect runtime cost.

## Open numerical work

Two numerical topics remain deliberately open without blocking `v0.1.0`.

### Robust `real` topology

Supporting topology-sensitive operations for `real` requires an implementation
that does not assume a particular representation, precision, size, or
alignment for D `real`.

### Polyline-length accumulation

`polylineLength` currently uses sequential accumulation in
`MetricScalar!T`.

Compensated techniques such as Neumaier or Kahan summation should be
evaluated for long or heterogeneous polylines before changing the current
implementation.

Any replacement must be justified by measured numerical benefit and should
preserve the existing execution contracts where practical.

## Design rule

Numerical construction, robust topology, geometry representation, validation,
and ownership are separate concerns in `geo-d`.

Keeping these concerns separate is intentional. It prevents convenience
APIs from silently weakening topology guarantees, introducing hidden
allocation, or changing geometry semantics.

## Generated API documentation

Public API documentation is rendered with `ddox`.

Generate it from the repository root with:

~~~sh
./tools/build-docs.sh
~~~

The generated site is written to:

~~~text
build/ddox/site/
~~~

Generated documentation is build output and is not committed to the
repository.

The documentation build includes only the public modules directly under
`source/geo/`. Implementation modules under `source/geo/internal/` are
deliberately excluded.

The generated documentation entry point is:

~~~text
build/ddox/site/index.html
~~~

## Performance

Performance goals, benchmarking methodology, C/C++ comparison rules, and
optimisation workflow are documented in
[`performance.md`](performance.md).

