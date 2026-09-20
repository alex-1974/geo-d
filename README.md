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

`v1.0.0` establishes the stable v1 public API. The supported package-level
surface is frozen at 41 top-level names exported through `import geo;`.

The API is intentionally small. New functionality is added when concrete use
cases justify extending the geometry model and must follow the project's
source-compatibility and deprecation policy.

Development toward `v2.0.0` intentionally reopens API design to align
`geo-d` with the planned separate `geo3-d` sibling library. `geo-d` remains
exclusively a coordinate-system-agnostic 2D Euclidean geometry library.

The v2 migration focuses on dimensional naming, shared operation families,
UFCS and argument consistency, and source-compatible deprecation of v1 forms
where practical. It is not a general expansion of `geo-d` into 3D or a
blanket feature-expansion milestone.

See
[`ADR-0019`](docs/adr/ADR-0019-geo-d-v2-api-family-migration.md)
and the v2 section of [`ROADMAP.md`](ROADMAP.md).

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

- `PolylineView!T`
- `LinearRingView!T`
- `PolygonView!T`

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

`PolygonView` uses structural ring order:

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

Douglas-Peucker simplification is available for `PolylineView` through:

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
        P(0.0, 0.0),
        segment,
        d
    )
);

assert(d == 0.0);

assert(
    orientation(
        P(0.0, 0.0),
        P(1.0, 0.0),
        P(0.0, 1.0)
    ) == Orientation.left
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
- `PolylineView`;
- `LinearRingView`;
- `PolygonView`.

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

For a `geo-d` release available through the public DUB registry, add the
package to a DUB project with:

~~~sh
dub add geo-d
~~~

Then import the supported package module:

~~~d
import geo;
~~~

DMD and LDC are both supported:

~~~sh
dub build --compiler=dmd
dub build --compiler=ldc2
~~~

For a complete minimal program and task-oriented examples, see
[`docs/getting-started.md`](docs/getting-started.md).

Public-registry installation and the minimal example are independently
verified as part of release preparation; a repository path dependency does
not replace that verification.

## Documentation

The generated public API reference is published at:

https://alex-1974.github.io/geo-d/

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
