# Changelog

All notable changes to `geo-d` are documented in this file.

The project follows Semantic Versioning for published releases.

## [Unreleased]

### Changed

- Versioned GitHub Pages API documentation is built reproducibly from release
  tags. The documentation root follows the current stable release, while
  historical releases remain available at version-specific paths.

## [2.0.0] - 2026-09-22

### Added

- Added the normative `docs/v2-api-conventions.md` specification for the
  2D/3D Euclidean API family.
- Added ADR-0020 defining `euclid-core-d` as the narrowly scoped common
  declaration origin for neutral contracts shared by `geo-d` and `geo3-d`.
- Added reproducible v2 public-surface auditing while preserving the frozen
  v1 audit baseline.
- Added a durable cross-repository `geo-d` / `geo3-d` family consumer that
  pins the verified sibling and Core versions and checks common declaration
  identity for all seven shared contracts.

### Changed

- Aligned the v2 API with the independent `geo3-d` sibling through
  dimension-explicit geometry type names and dimension-neutral operation
  families.
- Renamed the canonical view types to `Polyline2View`, `LinearRing2View`, and
  `Polygon2View`, with their v1 names retained as deprecated compatibility
  aliases.
- Renamed the canonical orientation result type to `Orientation2` while
  preserving its established value and initialization semantics.
- Standardised `tryPointSegmentDistance` on the segment-first canonical v2
  order and retained the v1 point-first form as a deprecated forwarding
  overload.
- Moved the common declaration origin of `isGeoScalar`, `MetricScalar`,
  `IntersectionScalar`, `SegmentIntersectionKind`, `RingValidationIssue`,
  `RingValidationResult`, and `douglasPeuckerWorkspaceSize` to
  `euclid-core-d`.
- Kept `AreaScalar` owned by `geo-d`; no speculative 3D area or
  `Polygon3View` API was introduced.
- Preserved canonical `import geo;` under strict deprecation checking by
  defining root compatibility aliases locally.
- Updated direct compiler tooling to resolve dependency import paths through
  DUB instead of hard-coding the shared-core workspace path.
- Replaced the temporary workspace-relative `euclid-core-d` dependency with
  the released public DUB dependency `~>0.1.0`.
- Aligned repository documentation with the `d-geospatial-workspace`
  reorganization and current sibling-library boundaries.
- Made benchmark helpers resolve the repository location relative to their
  scripts while retaining an explicit path override.
- Refreshed benchmark documentation to reflect the completed v1 coverage.

### Verification

- Completed declaration-by-declaration disposition of all 146 frozen v1
  public audit declarations.
- Reproduced the implemented v2 surface at 45 package exports and 151 public
  audit declarations with zero unresolved members.
- Verified simultaneous `geo` / `geo3` use and common declaration identity
  locally.
- Verified registry-backed simultaneous `geo` / `geo3` consumption with no
  direct Core override, exactly one resolved `euclid-core-d 0.1.0` instance,
  and all seven shared declaration identities preserved.
- Verified canonical v2 consumers without deprecated API and supported v1
  compatibility forms separately.
- Verified generated public documentation without unintended
  `euclid_core.*` leakage.
- Verified DMD and LDC tests and release builds for the integrated v2 state.
- Verified the post-packaging integration state through the complete GitHub
  Actions matrix on `14af8146625c75f72a6649651a2e1cf241afa5c2`.
- Promoted the temporary family/coexistence probe into ordinary compiler CI;
  the durable test passes with DMD 2.111.0, current DMD, and current LDC.
- Completed all v2 API freeze gates.

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