# Changelog

All notable changes to `geo-d` are documented in this file.

The project follows Semantic Versioning for published releases.

## [Unreleased]

### Changed

- Aligned repository documentation with the `d-geospatial-workspace`
  reorganization and current sibling-library boundaries.
- Made benchmark helpers resolve the repository location relative to their
  scripts while retaining an explicit path override.
- Refreshed benchmark documentation to reflect the completed v1 coverage.

## [1.0.0] - 2026-09-13

First stable release.

The supported v1 package-level API is frozen at 41 top-level names exported
through `import geo;`.

### Added

- Geometry-wide `tryBounds` support for segments, polylines, linear rings,
  and polygons with explicit empty and NaN semantics.
- Complete task-oriented getting-started documentation.
- Public navigable ddox API documentation published through GitHub Pages.
- External-consumer verification of the frozen package-level API.
- Complete benchmark coverage for every computational public API family.

### Changed

- `polylineLength` now uses compensated accumulation while preserving its
  public type and execution contracts.
- Ordinary-range nearest-point and point-to-segment metric operations use a
  measured fast path while retaining scaled full-range handling.
- Point-in-polygon classification avoids unnecessary robust orientation work
  through a y-range edge prefilter.
- Ring and polygon validation use bounding-box broad-phase filters to avoid
  unnecessary exact segment-contact work.
- Robust binary64 orientation internals were hardened and benchmarked against
  direct C/C++ reference implementations.

### Stability and verification

- Defined source-compatibility expectations and deprecation policy for the
  `1.x` series.
- Audited public failure semantics, scalar domains, allocation behaviour, and
  algorithmic complexity.
- Recorded DMD and LDC performance baselines for all computational API
  families.
- CI verifies the minimum supported D frontend, current DMD, current LDC,
  external package consumption, release builds, and generated public API
  documentation.
- Clean public-registry consumer verification succeeds with both DMD and LDC.
- Robust topology for D `real` remains intentionally deferred; this is an
  explicit v1 scalar-domain limitation rather than an unfinished release
  requirement.

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