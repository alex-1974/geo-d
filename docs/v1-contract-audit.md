# geo-d v1 public contract audit

This document records the explicit contract audits required before the
`v1.0.0` release.

The supported public API is the surface frozen by `api-freeze-v1.0.0`:
41 top-level names exported through `import geo;`, together with the public
members of those exported aggregate types.

This document audits observable public contracts rather than internal
implementation structure.

## Audit status

| Contract area | Status |
| --- | --- |
| Failure semantics | Complete |
| Scalar constraints | Complete |
| Allocation guarantees | Complete |
| Complexity guarantees | Complete |

## Failure semantics

Status: **complete**

The audit reviewed public documentation, implementation behaviour, and
verification for all public operations with failure-like behaviour.

The public API deliberately uses several distinct mechanisms. They are not
interchangeable:

- recoverable failure reported as `false`;
- diagnostic validation results;
- documented numeric sentinel results such as NaN;
- explicit preconditions for operations whose inputs are outside their
  supported domain;
- normal D bounds semantics for invalid view indexing;
- normal IEEE floating-point propagation where failure is not part of the
  operation's contract.

### Recoverable `bool` failure

| API | Failure condition | Observable state on failure |
| --- | --- | --- |
| `tryConvert` | target conversion is not permitted by the documented range/value rules | result is the corresponding `*.init` value |
| `Bounds2.tryFromPoint` | point contains NaN | result is `Bounds2.init` |
| `Bounds2.tryFromMinMax` | NaN or reversed bounds | result is `Bounds2.init` |
| `Bounds2.tryExtend` | point contains NaN | existing bounds remains unchanged |
| `tryBounds` | any participating coordinate is NaN | result is `Bounds2.init` |
| `tryPointSegmentDistance` | non-finite input or required metric computation cannot remain finite | result is zero |
| `tryNearestPoint` | non-finite input or required metric computation/construction cannot remain finite | result is `Point2.init` |
| `trySegmentIntersectionPoint` | intersection is not exactly one point | result is `Point2.init` |
| `trySegmentIntersectionOverlap` | intersection is not a positive-length overlap | result is `Segment2.init` |
| `tryClassifyPointInPolygon` | query or stored polygon coordinate is non-finite | location is `PointPolygonLocation.outside` |
| `trySimplifyDouglasPeuckerInto` | invalid tolerance/input, insufficient buffers, or failed metric computation | `written` is zero; destination contents are unspecified |

The conversion overloads for `Point2`, `Vector2`, and `Segment2` all use the
same transactional result convention.

`tryBounds` treats empty variable-size geometry as successful empty geometry;
emptiness is not failure.

`trySegmentIntersectionPoint` and `trySegmentIntersectionOverlap` distinguish
geometric non-applicability from invalid input. For floating-point input,
finite endpoints are a precondition of the robust intersection domain rather
than a recoverable `false` case.

### Failure-state verification

Failure-state tests use non-default sentinels where necessary so that a test
proves the documented state transition rather than merely observing default
initialization.

Relevant verification includes:

- conversion result reset for point, vector, and segment conversion;
- transactional `Bounds2` construction and extension;
- transactional geometry bounds computation;
- nearest-point failure reset;
- point-to-segment distance reset for both non-finite input and finite input
  whose required metric difference exceeds the finite computation range;
- unique-point and overlap intersection result reset;
- point-in-polygon failure reset after both immediate and later-ring failure;
- simplification `written == 0` failure semantics.

### Validation results are not call failures

`validateRing` and `validatePolygon` return diagnostic result objects.

Invalid geometry therefore does not represent failure of the function call.
The returned issue enumeration and diagnostic indices describe the detected
topological problem.

`RingValidationResult.init` and `PolygonValidationResult.init` represent valid
results.

An empty ring is invalid because it has too few vertices. An empty polygon is
valid.

### Numeric sentinel behaviour

`signedArea` and `polygonArea` return NaN when any participating stored
coordinate is non-finite.

This is a documented numeric result convention rather than recoverable
`bool` failure.

The non-`try` metric operations `distance`, `squaredDistance`,
`segmentLength`, and `polylineLength` follow their documented floating-point
arithmetic semantics. NaN and infinity are not converted into a separate
failure channel.

The explicit quantisation operations likewise operate in their documented
floating-point domain rather than introducing a `bool` failure API.

### Preconditions and bounds semantics

Robust floating-point orientation requires finite coordinates.

Robust floating-point segment-intersection predicates and construction require
finite segment endpoints. Violation is outside the supported predicate
contract rather than a recoverable failure result.

`Bounds2.min` and `Bounds2.max` require a non-empty bounds.

View element and segment access uses normal D bounds semantics. In particular:

- `PolylineView` point indices must be below `length`;
- `PolylineView.segment` indices must be below `segmentCount`;
- `LinearRingView` point indices must be below `length`;
- `LinearRingView.segment` indices must be below `segmentCount`;
- `PolygonView` ring indices must be below `length`;
- `PolygonView.exterior` requires a non-empty polygon;
- `PolygonView.hole` indices must be below `holeCount`.

These access violations are not represented by recoverable `false` results.

### Failure-semantics conclusion

No contradictory public failure convention was found.

Every operation that exposes recoverable failure documents the condition and
the observable output/state after failure.

Operations that instead use validation diagnostics, numeric sentinel values,
preconditions, normal bounds semantics, or IEEE floating-point propagation
document that distinction.

The audit found and closed concrete verification gaps before completion:

- polygon-view lifetime verification;
- conversion edge and failure-state verification;
- point-in-polygon failure-state verification;
- finite-input metric failure-state verification.

Further allocation and complexity audits remain separate
release-preparation tasks.


## Scalar constraints

Status: **complete**

The audit reviewed the scalar constraints of the frozen public API and the
public members of its exported geometry and result types.

### General geo-d scalar domain

The general public scalar domain is exactly:

```text
int
long
float
double
real
```

`isGeoScalar` deliberately excludes:

- narrower signed and unsigned integral types;
- `uint` and `ulong`;
- `bool` and character types;
- qualified scalar types;
- enums;
- user-defined numeric-like types.

The core geometry and view types consistently use this general domain:

- `Point2`;
- `Vector2`;
- `Segment2`;
- `Bounds2`;
- `PolylineView`;
- `LinearRingView`;
- `PolygonView`.

Geometry bounds and checked conversion likewise support the complete general
scalar domain.

### Metric scalar domain

Metric operations support the complete general scalar domain.

Their computation type is:

```text
int     -> double
long    -> double
float   -> double
double  -> double
real    -> real
```

The public `MetricScalar` template exposes this policy directly.

Metric operations therefore preserve `real` computation rather than silently
reducing it to binary64.

Douglas-Peucker simplification follows the metric scalar domain because its
decisions are explicitly based on computed metric distances rather than exact
topological predicates.

### Robust and exact scalar domain

The current robust/exact public domain is:

```text
int
long
float
double
```

`real` is deliberately excluded from:

- `orientation`;
- segment-intersection classification;
- segment-intersection point construction;
- segment-intersection overlap construction;
- `signedArea`;
- `polygonArea`;
- point-in-polygon classification;
- ring validation;
- polygon validation.

The narrower domain is intentional rather than accidental.

These operations depend on exact or certified numerical guarantees for which
geo-d currently has complete backends for fixed-width signed integers,
binary32, and binary64.

### `real` policy

ADR-0016 defines the long-term policy.

`real` remains a first-class scalar for representation and metric algorithms,
but robust/exact operations must not accept it until a platform-aware backend
can preserve their established mathematical guarantees.

In particular, geo-d will not claim robust `real` support by:

- converting inputs to `double`;
- using ordinary uncertified floating-point predicates;
- introducing an epsilon-based fallback.

### Verification

The external consumer test verifies the public scalar boundary through only:

```d
import geo;
```

It contains positive compile-time checks for representative `real` operations
in the general and metric domains and negative compile-time checks proving
that `real` remains unavailable to the robust/exact families.

The same external consumer is exercised under the supported CI compiler
matrix.

### Scalar-constraint conclusion

No contradictory public scalar constraint was found.

The difference between the five-type general geometry domain and the
four-type robust/exact domain is explicit, documented, and verified.

Future robust `real` support is governed by ADR-0016 rather than by silently
widening template constraints.

## Allocation guarantees

Status: **complete**

The audit reviewed allocation behaviour for the frozen public API and the
public members of its exported types.

### Value types and views

`Point2`, `Vector2`, `Segment2`, and `Bounds2` are direct value types.

Their public value operations do not allocate.

`PolylineView`, `LinearRingView`, and `PolygonView` are non-owning views.
Construction does not allocate or copy the referenced geometry storage.

The caller retains ownership of:

- point storage referenced by polyline and ring views;
- ring-descriptor storage referenced by polygon views;
- point storage referenced transitively by those ring descriptors.

### Allocation-free algorithm families

The following public computational families perform no allocation:

- checked conversion and explicit quantisation;
- `Bounds2` operations;
- `tryBounds`;
- metric primitives;
- `polylineLength`;
- nearest-point and point-to-segment distance;
- orientation;
- segment-intersection classification and construction;
- signed ring area;
- polygon area;
- point-in-polygon classification;
- ring validation;
- Douglas-Peucker workspace sizing;
- Douglas-Peucker simplification.

Where these operations are declared `@nogc`, the compiler attribute reinforces
the documented allocation contract.

`trySimplifyDouglasPeuckerInto` does not allocate internal dynamic storage.
Destination and traversal workspace are supplied by the caller.

### Polygon-validation exception

`validatePolygon` deliberately does not promise `@nogc`.

Connected-interior validation may allocate temporary storage for:

- touching-ring contact records;
- union-find parent and rank storage;
- per-contact bookkeeping.

This allocation is part of the documented public contract rather than hidden
allocation on an otherwise allocation-free path.

Temporary storage depends on the number of rings and touching ring pairs and
is covered by the corresponding complexity contract.

### Allocation conclusion

No undocumented allocation was found in a public API family.

The dominant low-level geometry and predicate paths are allocation-free.

`validatePolygon` is the intentional public exception and documents its
temporary-storage behaviour explicitly.

No public view performs an implicit deep copy.

## Complexity guarantees

Status: **complete**

The audit reviewed asymptotic time and auxiliary-space behaviour for the
frozen public API.

Trivial value construction, field access, view indexing, and similarly direct
constant-time operations do not require repetitive per-member complexity
sections under the geo-d Ddoc policy.

### Constant-time operations

The following public operation families are O(1) in time and use O(1)
auxiliary space:

- core affine and value operations;
- `Bounds2` value operations;
- checked conversion;
- explicit quantisation;
- segment bounds computation;
- metric primitives on points and segments;
- nearest-point computation;
- point-to-segment distance;
- orientation;
- segment-intersection classification;
- segment-intersection point construction;
- segment-intersection overlap construction;
- Douglas-Peucker workspace-size calculation.

The exact/robust implementation of a constant-size predicate may contain
multiple internal numerical stages, but those stages operate on bounded-size
representations. They therefore do not change the public asymptotic
complexity.

### Linear traversal

For `n` participating stored points or vertices:

- polyline bounds computation is O(n) time and O(1) auxiliary space;
- ring bounds computation is O(n) time and O(1) auxiliary space;
- polygon bounds computation is O(n) time and O(1) auxiliary space over all
  stored vertices;
- `polylineLength` is O(n) time and O(1) auxiliary space;
- `signedArea` is O(n) time and O(1) auxiliary space;
- `polygonArea` is O(n) time and O(1) auxiliary space over all stored
  vertices;
- point-in-polygon classification is O(n) time and O(1) auxiliary space over
  all stored vertices.

### Topology validation

For a ring containing `n` stored vertices:

```text
validateRing
    time   O(n^2)
    space  O(1)
```

For polygon validation, let `n` be the total number of stored vertices, `r`
the number of rings, and `c` the number of touching ring pairs.

The public worst-case contract is:

```text
validatePolygon
    time   O(n^2 log n)
    temporary storage O(r + c)
    worst-case auxiliary storage O(n^2)
```

The non-constant storage is required by connected-interior validation.

### Douglas-Peucker simplification

For `n` stored input points:

```text
trySimplifyDouglasPeuckerInto
    worst-case time O(n^2)
```

The caller-provided traversal workspace requires at most:

```text
max(n - 2, 0)
```

`size_t` elements.

Beyond caller-owned destination and workspace storage, the algorithm uses
O(1) auxiliary storage and performs no allocation.

### Complexity conclusion

No undocumented asymptotic public algorithm was found.

Every non-trivial public algorithm has an explicit complexity contract.

Variable-size operations identify the input dimension governing their cost.

The frozen v1 API contains no known accidental asymptotic behaviour that
contradicts its documented contract.
