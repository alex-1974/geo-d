# geo-d

`geo-d` is a small, reusable 2D Euclidean geometry library for D.

It provides coordinate-system-agnostic geometry value types, non-owning
geometry views, metric operations, robust computational-geometry predicates,
polygon operations, topology validation, and polyline simplification.

`geo-d` deliberately assigns no CRS, geographic, geodetic, unit, or
Earth-model semantics to coordinates. It is intended to remain useful both
inside and outside GIS software.

## Status

The first public release of `geo-d` was `v0.1.0`.

`v2.0.0` is the current stable API release.

It aligns `geo-d` with the independent `geo3-d` sibling library while
`geo-d` remains exclusively a coordinate-system-agnostic 2D Euclidean
geometry library.

The frozen v2 package surface contains 45 package exports and 151 audited
public declarations. Supported v1 source forms remain available in v2 as
deprecated compatibility aliases or forwarding overloads where documented.

`v1.0.0` remains the historical stable v1 API baseline with 41 package-level
names exported through `import geo;`.

The API is intentionally small. New functionality is added only when concrete
consumer requirements and research justify extending the geometry model.

The shared declaration contracts required by both dimensional siblings are
provided by the independently versioned `euclid-core-d` package. The current
v2 integration state resolves released `euclid-core-d 0.1.0` through the
public DUB registry rather than through a workspace-relative dependency.

The migration focuses on dimensional naming, shared operation families, UFCS
and argument consistency, common declaration identity where required, and
source-compatible deprecation of v1 forms. It is not a general expansion of
`geo-d` into 3D or a blanket feature-expansion milestone.

See:

- [`ADR-0019`](docs/adr/ADR-0019-geo-d-v2-api-family-migration.md);
- [`ADR-0020`](docs/adr/ADR-0020-shared-euclidean-contract-core.md);
- [`docs/v2-api-conventions.md`](docs/v2-api-conventions.md);
- [`docs/v2-public-api-audit.md`](docs/v2-public-api-audit.md);
- the v2 section of [`ROADMAP.md`](ROADMAP.md).

### v1 compatibility in v2

Canonical v2 documentation and new code use:

~~~text
Polyline2View
LinearRing2View
Polygon2View
Orientation2
~~~

The corresponding v1 spellings remain available in v2 as deprecated
compatibility aliases:

~~~text
PolylineView     -> Polyline2View
LinearRingView   -> LinearRing2View
PolygonView      -> Polygon2View
Orientation      -> Orientation2
~~~

The canonical v2 `tryPointSegmentDistance` order is segment-first. The v1
point-first form remains a deprecated forwarding overload.

Historical v1 documentation retains the v1 names where historically correct.

## Features

### Core geometry

- `Point2!T`
- `Vector2!T`
- `Bounds2!T`
- `Segment2!T`

`Point2` and `Vector2` are distinct affine concepts. The public algebra
therefore permits operations such as point-minus-point and point-plus-vector,
while deliberately rejecting meaningless operations such as point-plus-point
or point scaling.

### Geometry views

Variable-size geometry is represented through non-owning, read-only views:

- `Polyline2View!T`
- `LinearRing2View!T`
- `Polygon2View!T`

Views do not allocate or copy their backing point storage. The caller retains
ownership of that storage.

### Scalar model

The core geometry model supports exactly:

~~~d
int
long
float
double
real
~~~

Unsigned integers, small integer types, arbitrary numeric-like types, and
qualified scalar template parameters are outside the public scalar contract.

There are no implicit conversions between different geometry scalar types.

Checked explicit conversion is available through `tryConvert`.

Floating-point to integer quantisation is explicit through:

- `rounded`
- `floored`
- `ceiled`
- `truncated`

### Metric operations

The metric API includes:

- `distance`
- `squaredDistance`
- `segmentLength`
- `polylineLength`
- `tryNearestPoint`
- `tryPointSegmentDistance`

Metric computation precision is separate from storage precision:

~~~text
int     -> double
long    -> double
float   -> double
double  -> double
real    -> real
~~~

This mapping is exposed as `MetricScalar!T`.

### Robust topology predicates

The topology-sensitive API includes:

- `orientation`
- `segmentIntersectionKind`
- `trySegmentIntersectionPoint`
- `trySegmentIntersectionOverlap`

Robust topology is currently supported for:

~~~text
int
long
float
double
~~~

`real` remains part of the core scalar model but robust topology support for
it is deliberately deferred.

Topology decisions do not use a global epsilon.

### Area and polygon operations

The library provides:

- `signedArea`
- `polygonArea`
- `tryClassifyPointInPolygon`

`Polygon2View` uses structural ring order:

~~~text
ring 0      exterior
ring 1..n   holes
~~~

Ring orientation is not used to infer exterior versus hole semantics.

### Topology validation

Representation and validation are separate concerns.

Geometry views can represent malformed input without silently rewriting or
rejecting it. Callers can explicitly validate topology through:

- `validateRing`
- `validatePolygon`
- `RingValidationResult`
- `PolygonValidationResult`

Validation covers ring simplicity and polygon relationships including ring
contact and hole containment rules.

### Polyline simplification

Douglas-Peucker simplification is available for `Polyline2View` through:

- `douglasPeuckerWorkspaceSize`
- `trySimplifyDouglasPeuckerInto`

The implementation is iterative and:

- writes to caller-provided destination storage;
- uses caller-provided workspace;
- performs no allocation;
- performs no recursion;
- preserves input point order;
- returns a subsequence of the original points;
- uses deterministic tie-breaking.

This is ordinary metric polyline simplification.

It does **not** claim to preserve ring or polygon topology.
Topology-preserving simplification is a separate problem and will require a
separate API and semantic contract.

## Basic usage

~~~d
import geo;

alias P = Point2!double;
alias S = Segment2!double;

auto a = P(0.0, 0.0);
auto b = P(3.0, 4.0);

assert(distance(a, b) == 5.0);

auto segment = S(a, b);

double d;

assert(
    tryPointSegmentDistance(
        segment,
        P(0.0, 0.0),
        d
    )
);

assert(d == 0.0);

assert(
    orientation(
        P(0.0, 0.0),
        P(1.0, 0.0),
        P(0.0, 1.0)
    ) == Orientation2.left
);
~~~

The package-level module exports the intended public API:

~~~d
import geo;
~~~

Individual modules may also be imported explicitly.

## Bounds

`Bounds2.init` represents an empty bounds rather than an origin-sized bounds.

This permits natural incremental accumulation without accidentally including
`(0, 0)`.

For floating-point bounds:

- NaN coordinates are rejected;
- infinities are permitted when ordering remains valid;
- empty and non-empty bounds are distinct states.

Axis-aligned bounds of stored geometry are computed explicitly with:

~~~text
tryBounds
~~~

`tryBounds` is provided for:

- `Segment2`;
- `Polyline2View`;
- `LinearRing2View`;
- `Polygon2View`.

Empty variable-size geometry produces empty bounds successfully.

For floating-point geometry, any stored NaN coordinate causes failure and the
output remains `Bounds2.init`. Infinite coordinates are permitted.

Polygon bounds are representation bounds: every stored ring contributes,
without implicit topology validation.

The operation performs no allocation. Segment bounds are O(1); polyline and
ring bounds are O(n); polygon bounds are O(total stored vertices).

## Non-finite values

Floating-point `Point2`, `Vector2`, and `Segment2` values may represent NaN or
infinity.

Representability does not imply that every algorithm accepts such values.

Topology-sensitive algorithms impose their own numerical validity
requirements.

## Ownership and allocation

Small geometry primitives are value types.

Variable-size geometry is initially represented through non-owning views.

The library follows these principles:

- explicit ownership and lifetime;
- views before copies;
- no hidden deep copies;
- no hidden allocation in low-level numerical operations;
- caller-owned output and workspace where variable temporary storage is
  required.

Most low-level operations are designed to satisfy:

~~~text
pure
nothrow
@safe
@nogc
~~~

where their semantics permit it.

Higher-level topology validation may allocate where variable-size bookkeeping
is required.

## Numerical model

`geo-d` deliberately separates several numerical concerns.

Ordinary value algebra follows the corresponding D scalar arithmetic.

Metric operations calculate numerical quantities such as lengths and
distances.

Topology-sensitive predicates use robust or exact techniques where necessary
to determine the mathematical relationship represented by the input
coordinates.

There is no global epsilon controlling equality, orientation, intersection,
or point-in-polygon classification.

Detailed numerical and semantic contracts are documented in the architecture
decision records under `docs/adr/`.

## Scope

`geo-d` does not provide:

- coordinate reference systems;
- EPSG or other authority databases;
- map projections;
- ellipsoidal geodesy;
- latitude/longitude semantics;
- geometry file formats;
- GDAL or PROJ bindings;
- spatial indexes;
- raster processing.

Those concerns belong in separate libraries.

Within the wider `d-geospatial-workspace` ecosystem, active complementary
projects include `geodesy-d`, `imagery-d`, and `osm-d`. Planned or candidate
domains include `locationref-d`, `proj-d`, `spatial-d`, and a possible future
`raster-d` extraction from `imagery-d`.

`geo-d` remains independently usable and versioned.

## Building

Build the library with:

~~~sh
dub build
~~~

Run tests with DMD:

~~~sh
dub test --compiler=dmd --force
~~~

Run tests with LDC:

~~~sh
dub test --compiler=ldc2 --force
~~~

Build the release configuration with LDC:

~~~sh
dub build --build=release --compiler=ldc2 --force
~~~

The package currently builds with DIP1000 enabled.

DMD and LDC are the required compiler families.

The minimum supported D frontend version is:

~~~text
2.111.0
~~~

This requirement applies to the D frontend used by supported compiler
families. Newer frontend versions are covered by the current DMD and LDC CI
targets.

## Installation

Install the current stable release from the public DUB registry with:

~~~sh
dub add geo-d
~~~

Then import the supported package module:

~~~d
import geo;
~~~

The canonical examples in this documentation use the v2 API.

DMD and LDC are both supported:

~~~sh
dub build --compiler=dmd
dub build --compiler=ldc2
~~~

For v2 examples and task-oriented guidance, see
[`docs/getting-started.md`](docs/getting-started.md).

Release verification includes a clean post-tag consumer test against the
published DUB package after the release tag has been indexed. Repository path
dependencies are not a substitute for that registry verification.

The shared declaration dependency is independently published and resolved as:

~~~text
euclid-core-d ~>0.1.0
~~~

## Documentation

The generated public API reference for the current stable release is published
at:

https://alex-1974.github.io/geo-d/

Published release documentation is also retained at version-specific paths:

~~~text
https://alex-1974.github.io/geo-d/v2.0.0/
https://alex-1974.github.io/geo-d/v1.0.0/
~~~

The root documentation is built from the current stable release tag rather
than from the development state of `main`. Available documentation versions
are listed at:

https://alex-1974.github.io/geo-d/versions.html

Architecture decisions are maintained under:

~~~text
docs/adr/
~~~

Additional implementation and numerical notes are available in:

~~~text
docs/README.md
benchmarks/README.md
~~~

The repository-level `DESIGN_PRINCIPLES.md` documents the engineering
principles adopted by this library.

When developed inside `d-geospatial-workspace`, additional workspace
context may be available locally under `.workspace/`. That directory is not
part of the repository or published package.

## License

`geo-d` is licensed under the MIT License.

See `LICENSE`.
