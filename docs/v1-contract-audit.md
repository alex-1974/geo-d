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
| Scalar constraints | Pending |
| Allocation guarantees | Pending |
| Complexity guarantees | Pending |

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

Further scalar-domain, allocation, and complexity audits remain separate
release-preparation tasks.
