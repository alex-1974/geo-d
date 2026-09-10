# Changelog

All notable changes to `geo-d` are documented in this file.

The project follows Semantic Versioning for published releases.

## [0.1.0] - 2026-09-11

Initial public release.

### Added

- Core 2D geometry value types:
  - `Point2`
  - `Vector2`
  - `Bounds2`
  - `Segment2`
- Explicit affine point/vector algebra.
- Core scalar support for `int`, `long`, `float`, `double`, and `real`.
- Checked explicit geometry scalar conversion through `tryConvert`.
- Explicit floating-point-to-integer quantisation through `rounded`, `floored`, `ceiled`, and `truncated`.
- Empty-state semantics and invariant-preserving construction for `Bounds2`.
- Non-owning read-only geometry views:
  - `PolylineView`
  - `LinearRingView`
  - `PolygonView`
- Metric operations:
  - `distance`
  - `squaredDistance`
  - `segmentLength`
  - `polylineLength`
  - `tryNearestPoint`
  - `tryPointSegmentDistance`
- `MetricScalar` policy separating coordinate storage precision from metric computation precision.
- Robust orientation predicates for `int`, `long`, `float`, and `double`.
- Exact segment-intersection classification.
- Exact positive-length segment-overlap construction.
- Correctly rounded binary64 construction of unique segment-intersection points.
- Signed linear-ring area using exact determinant accumulation followed by one final binary64 rounding.
- Polygon area with structural exterior/hole ring roles independent of winding direction.
- Exact three-way point-in-polygon classification with `outside`, `boundary`, and `inside` semantics.
- Explicit ring topology validation with structured diagnostics.
- Explicit polygon topology validation including inter-ring relationships, hole containment, nested-hole detection, and connected-interior validation.
- Iterative Douglas-Peucker polyline simplification using caller-provided destination storage and workspace.
- Architecture decision records defining the public semantic and numerical contracts.
- Numerical verification using independent oracle and property-style tests where appropriate.
- Performance benchmarks for exact and robust numerical paths.
- GitHub Actions coverage for DMD tests, LDC tests, and an LDC release build.

### Design constraints

- No global epsilon is used to define computational topology.
- Geometry representation is kept separate from topology validation.
- Robust topology is kept separate from rounded geometric construction.
- Variable-size geometry uses non-owning views rather than hidden ownership or deep copies.
- Low-level operations avoid hidden allocation.
- Douglas-Peucker simplification applies to polylines only and does not claim ring or polygon topology preservation.
- Robust topology support for D `real` is intentionally deferred pending a platform-aware numerical backend.