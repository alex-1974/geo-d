# d-geospatial Roadmap

**Status:** Foundation complete; `geodesy-d` architecture starting  
**Scope:** Independent reusable D libraries only

## Objective

The goal of `d-geospatial` is to establish a small set of high-quality, independently useful D libraries for geometry, geodesy, spatial computing, raster processing and geospatial data.

The roadmap deliberately favours **depth before breadth**.

Libraries should not be created merely because a future application might need them.

A new package should appear only when:

- its domain is sufficiently understood;
- its boundaries can be stated clearly;
- it provides independent value;
- and there is enough real work to justify maintaining another repository.

# Phase 0 — Shared foundation

## Architecture and policy

- [x] Define workspace purpose.
- [x] Separate reusable libraries from applications.
- [x] Define independent repository model.
- [x] Define shared `DESIGN_PRINCIPLES.md`.
- [x] Establish hardlink strategy for shared workspace documentation (`README.md`, `ROADMAP.md`, `DESIGN_PRINCIPLES.md`).
- [x] Define repository naming policy.
- [x] Define D module namespace policy.
- [x] Define compiler policy.
- [x] Define licence strategy.
- [x] Define minimum CI/quality expectations.
- [x] Define the `geo-d` / `geodesy-d` / `georef-d` / `proj-d` responsibility boundary.
- [x] Finalise workspace `README.md`.
- [x] Finalise workspace `ROADMAP.md`.

## Agreed conventions

### Licence

```text
MIT
```

Each independent library repository carries its own MIT `LICENSE`.

### Naming

```text
Repository / DUB       Module root

geodesy-d              geodesy
geo-d                  geo
georef-d               georef
raster-d               raster
spatial-d              spatial
proj-d                  proj
gdal-d                  gdal
osm-d                   osm
```

### Compiler policy

Required:

```text
DMD
LDC
```

Best effort:

```text
GDC
```

CI normally follows current stable DMD and LDC releases.

Initial shared language baseline:

```text
D frontend 2.112.1
```

The language baseline advances when the required compiler matrix permits it.

### Minimum CI baseline

Every active library must support:

```text
dub test
```

CI should at minimum verify:

- DMD tests/build;
- LDC tests/build;
- LDC release build;
- expected repository/documentation structure.

Benchmarks, fuzzing, property tests and specialised interoperability tests are added according to the domain.

## Remaining workspace tooling

- [x] Implement `link-shared-docs.sh`.
- [ ] Implement `check-workspace.sh`.
- [ ] Implement `run-all-tests.sh`.
- [ ] Implement `run-all-benchmarks.sh`.
- [ ] Implement `show-status.sh`.

`check-workspace.sh` should eventually verify, where relevant:

- shared `README.md`, `ROADMAP.md` and `DESIGN_PRINCIPLES.md` hardlinks;
- required repository files;
- Git state;
- DUB package health;
- supported compiler availability;
- package/module naming consistency.

Phase 0 policy work is complete. Tooling may continue incrementally while library development begins.

# Phase 1 — Fundamental libraries

The first development wave should contain only libraries whose usefulness is broad and whose domain boundaries are reasonably clear.

Initial candidates:

```text
geodesy-d
geo-d
raster-d
spatial-d
```

They do not need to start simultaneously.

The first library should be selected according to the first concrete implementation task.


## `geodesy-d`

### Initial goal

Provide a small, dependency-light, pure-D foundation for geodetic mathematics without requiring the PROJ runtime for bounded mathematical operations.

### Initial scope

First vertical slice:

```text
Angle
Latitude
Longitude
Ellipsoid
GeodeticCoordinate
GeocentricCoordinate / ECEF
geodetic ↔ geocentric conversion
```

Subsequent scope, only after the core is verified:

```text
3-parameter geocentric translation
7-parameter Helmert transformation
Transverse Mercator
UTM
direct/inverse ellipsoidal geodesics
```

### Explicit boundary

`geodesy-d` owns mathematical operations whose semantics depend on the Earth, a reference ellipsoid, geographic/geocentric coordinates or a map projection.

It does **not** own:

- general Euclidean geometry or polygon topology;
- EPSG/authority databases;
- WKT or PROJJSON parsing;
- automatic CRS/transformation discovery;
- transformation grid management;
- MGRS, Geohash or Plus Code encodings.

Those responsibilities belong respectively to `geo-d`, `proj-d` and `georef-d`.

### Design questions

- scalar policy and supported floating-point types;
- angle storage and degree/radian construction semantics;
- latitude/longitude normalisation versus validation;
- canonical ellipsoid representation;
- coordinate value types and ellipsoidal-height / shared linear-unit semantics;
- error semantics for invalid/undefined inputs;
- numerical accuracy and convergence policy;
- `@safe`, `@nogc`, `nothrow` and CTFE expectations;
- reference-source and cross-validation policy.

### Reference hierarchy

For geodetic algorithms, prefer authoritative specifications and primary numerical references. Typical validation sources include:

1. IOGP / EPSG Guidance Note 7-2 and EPSG method definitions;
2. primary algorithm publications such as Karney where applicable;
3. GeographicLib as a trusted numerical reference for geodesics;
4. PROJ as an independent interoperability and cross-validation implementation.

### Architecture documentation

- [x] `docs/README.md` — library scope and documentation map.
- [x] ADR-0001 — scope and architectural boundaries.
- [ ] ADR-0002 — core type, unit, scalar, and ellipsoid model (proposed; open items remain).
- [x] `docs/REFERENCES.md` — reference and numerical-validation policy.

### Quality gates

Before a stable API:

- authoritative reference vectors for each operation;
- edge cases at poles, equator and longitude boundaries where applicable;
- forward/inverse round-trip tests;
- randomised cross-validation against trusted implementations where practical;
- explicit accuracy/error documentation;
- no broad `@fastmath` policy without algorithm-specific proof and benchmarks;
- compiler coverage with DMD and LDC.

## `geo-d`

### Initial goal

Provide a small, robust, coordinate-system-agnostic Euclidean geometry foundation suitable for GIS and non-GIS applications.

### Initial scope

Candidate types:

```text
Point2
Vector2
Bounds / Box
Segment
Polyline
LinearRing
Polygon
```

Candidate algorithms:

```text
distance
squared distance
nearest point
segment intersection
bounding box
orientation
signed area
point in polygon
polyline length
simplification
```

### Design questions

- coordinate and scalar genericity;
- point/vector semantics versus primitive coordinate types;
- geometry ownership versus geometry views;
- polygon/ring representation;
- numerical robustness;
- allocation policy;
- interoperability conventions.


### Current implementation status

The fixed-size 2D geometry foundation is substantially implemented and
verified.

Completed:

- [x] `Point2` and `Vector2`
- [x] explicit scalar and conversion policy
- [x] `Bounds2`
- [x] `Segment2`
- [x] distance and squared distance
- [x] segment length
- [x] nearest point on a segment
- [x] robust orientation for `int`
- [x] robust orientation for `long`
- [x] robust orientation for `float`
- [x] robust orientation for `double`
- [x] independent `BigInt` oracle and property verification
- [x] exact segment-intersection classification
- [x] exact positive-length segment-overlap construction
- [x] correctly rounded unique-point segment-intersection construction

Segment intersection keeps exact topology separate from geometric
construction. Proper crossings use bounded exact arithmetic internally
and are rounded to binary64 only for the final point coordinates.

Deliberately deferred:

- [ ] robust orientation for `real` — requires a platform-aware backend
- [ ] segment-intersection support for `real` — follows the future robust
      `real` predicate backend

Next structural slice:

- [ ] define ownership and view semantics for variable-size linear geometry
- [ ] `Polyline` / `PolylineView`
- [ ] `LinearRing`
- [ ] signed area

`Polygon` should follow the variable-size ownership/view decision rather
than precede it.

### Quality gates

Before a stable API:

- extensive unit tests;
- degenerate-geometry tests;
- property tests where useful;
- numerical reference cases;
- performance baselines;
- documented complexity;
- memory/ownership documentation.

## `raster-d`

### Initial goal

Provide a reusable raster abstraction and a focused set of efficient raster-processing algorithms.

### Initial scope

Candidate concepts:

```text
RasterBuffer
RasterView
shape
strides
ROI
channel
pixel/layout description
```

Candidate operations:

```text
crop/view
copy
sampling
resize
normalisation
convolution
Gaussian blur
Sobel
Scharr
gradient magnitude
histogram
threshold
basic morphology
```

### Architecture questions

- multidimensional view representation;
- relationship to existing D numerical libraries;
- contiguous versus strided representations;
- channel-layout semantics;
- colour-space responsibilities;
- caller-provided output buffers;
- SIMD/vectorisation strategy;
- threading policy.

A generic multidimensional-array implementation should not be invented merely for this package if a suitable existing D abstraction can be used.

### Quality gates

- allocation behaviour documented per major operation;
- zero-copy operations tested as such;
- contiguous/strided correctness tests;
- benchmark suite for core kernels;
- large-raster tests;
- comparison against trusted numerical references.

## `spatial-d`

### Initial goal

Provide reusable high-performance spatial indexes and queries independent of GIS-specific object models.

### First step

Before writing a new index implementation:

- survey existing D spatial-index packages;
- audit their APIs and maintenance status;
- test correctness;
- benchmark representative workloads.

Reusing or improving an existing implementation is preferable when it meets the project standards.

### Possible scope

```text
Box
RTree
PackedRTree / STR tree
SpatialHash
nearest queries
intersection queries
bulk build
mutable updates
```

### Representative workloads

Benchmarks should include:

- 10³ objects;
- 10⁵ objects;
- 10⁶+ objects where practical;
- random distributions;
- clustered geographic distributions;
- viewport queries;
- nearest-object queries;
- update-heavy workloads.

# Phase 2 — Native geospatial integration

Only after the fundamental D-side abstractions are sufficiently understood should native integration packages solidify around them.

Candidates:

```text
proj-d
gdal-d
```

## `proj-d`

### Goal

Provide a small, idiomatic and safe D interface to PROJ.

### Candidate scope

```text
CRS
Transformation
forward()
inverse()
transform()
```

### Principles

- deterministic native-resource lifetime;
- raw C API available but isolated;
- no requirement for the basic geometry library itself to depend on PROJ;
- explicit coordinate semantics;
- preserve useful native error information.

### Exit criteria

- common EPSG transformations tested;
- round-trip numerical tests;
- thread-safety behaviour documented;
- native resource leaks tested.

## `gdal-d`

### Goal

Provide a modern D interface to GDAL without mechanically reproducing the entire upstream API.

### Initial raster scope

```text
Dataset
RasterBand
DatasetInfo
GeoTransform
CRS metadata
windowed reads
resampling
NoData
overview access
```

Particular emphasis should be placed on efficient reading into caller-owned memory where GDAL permits it.

### Later scope

Vector support may be added if justified by real consumers.

It should not be included merely for API completeness.

### Quality gates

- deterministic handle ownership;
- malformed/error-path tests;
- GeoTIFF test fixtures;
- windowed-I/O benchmarks;
- large-raster tests;
- no unnecessary intermediate copies in common workflows.

# Phase 3 — Geospatial domain libraries

Once the lower layers have proven themselves in real use, higher-level geospatial packages may be added.

Primary candidates:

```text
georef-d
osm-d
```


## `georef-d`

### Goal

Provide compact and discrete geographic reference/coding systems without turning them into CRS or geometry abstractions.

### Initial candidates

```text
MGRS
Geohash
Open Location Code / Plus Codes
```

MGRS may depend on the UTM implementation from `geodesy-d`. Geohash and Open Location Code should remain independent unless a real shared abstraction emerges.

### Important boundary

`georef-d` encodes or decodes geographic locations/references. It does not provide:

- address geocoding;
- a CRS/authority database;
- map projection infrastructure beyond what is consumed from `geodesy-d`;
- general Euclidean geometry.

No common `SpatialCode` interface should be introduced merely because several encodings live in the same package; common abstractions must be earned through real reuse.

## `osm-d`

### Goal

Provide efficient reusable OpenStreetMap data and format support.

### Initial scope

```text
Node
Way
Relation
Tag
Member
Object metadata
```

Formats:

```text
OSM XML
OSM PBF
```

Later, if justified:

```text
OSC
OSM API interaction
```

### Performance objectives

Large OSM datasets should not require one independently heap-allocated class object per primitive.

The design should investigate:

- compact storage;
- streaming;
- block-oriented processing;
- dense-node decoding;
- parallel decompression;
- callback/sink APIs;
- optional materialisation.

### Important boundary

`osm-d` must not become an editor framework.

Excluded from the core library:

- GUI;
- rendering;
- toolbars;
- editing modes;
- presets UI;
- application state.

Reusable OSM validation or editing primitives may become separate modules or libraries only when independent value has been demonstrated.

# Phase 4 — Advanced reusable algorithms

Some algorithms motivated by geospatial editing may eventually justify independent libraries.

Candidate:

```text
smarttrace-d
```

This phase is intentionally conditional.

## `smarttrace-d`

### Admission requirement

The package should only be created if tracing functionality can be formulated as a genuinely reusable algorithmic library.

Possible general model:

```text
cost field
    +
start
    +
target
    +
constraints
        ↓
candidate path
        +
confidence/evidence
```

Potential components:

```text
A*
Dijkstra
Live Wire
edge-derived cost fields
curvature penalties
multi-source cost fusion
confidence estimation
```

Raster-specific preprocessing may belong in `raster-d`.

OSM-specific interpretation should remain outside the generic tracing core.

If the functionality remains specific to one editor, `smarttrace-d` should not be created.

# Phase 5 — Maturity

Libraries approaching general public usefulness should graduate through explicit maturity levels.

Suggested informal states:

```text
experimental
development
stable
mature
```

These states are descriptive and independent of Semantic Versioning.

## Stable-library expectations

A stable library should have:

- documented public API;
- clear ownership and error semantics;
- Ddoc coverage;
- realistic examples;
- test suite;
- regression tests;
- representative benchmarks where performance matters;
- CI for supported compilers;
- changelog;
- documented minimum compiler version;
- semantic versioning;
- migration notes for breaking releases.

# Cross-library priorities

## Safety

Progressively increase useful:

```text
@safe
const
immutable
scope
return
```

coverage.

Unsafe FFI and low-level memory code should remain small and reviewable.

## Performance

Maintain performance baselines before aggressive optimisation.

Relevant metrics may include:

```text
latency
throughput
allocations
memory usage
scaling
```

## Fuzzing

Prioritise fuzzing for:

- file-format decoders;
- binary parsers;
- geometry edge cases;
- raster dimensions and offsets;
- native interoperability boundaries.

## Documentation

Architectural decisions should be recorded while the reasoning is still known.

Do not rely on commit history to explain important design choices.

## Real consumers

Library APIs should be exercised by real programs.

A demanding consuming application is valuable because it exposes:

- awkward APIs;
- hidden allocation;
- ownership mistakes;
- scaling problems;
- missing abstractions.

Application requirements may motivate libraries but must not dictate application-specific public APIs.

# Things deliberately not planned

`d-geospatial` currently does **not** aim to develop:

- a GUI toolkit;
- a general application framework;
- a logging framework;
- a dependency-injection system;
- a new general-purpose multidimensional-array framework;
- a replacement for GDAL;
- a full replacement for PROJ's CRS/authority/grid infrastructure;
- a general machine-learning framework;
- a monolithic GIS SDK.

If a mature external project solves the difficult part well, interoperability is preferred.

# Near-term sequence

The current intended sequence is:

```text
1. Shared foundation                         DONE
       ↓
2. geodesy-d architecture and core           CURRENT
       ↓
3. Verify geodetic core against references
       ↓
4. Extend geodesy-d only through validated operations
       ↓
5. Start geo-d / raster-d / spatial-d as concrete work justifies
       ↓
6. Add proj-d / gdal-d native integration
       ↓
7. Add georef-d and other domain libraries when their dependencies are stable
```

The first active library is therefore `geodesy-d`. Its first implementation milestone is deliberately limited to angle/coordinate/ellipsoid types and geodetic ↔ geocentric conversion.

`geo-d`, `raster-d` and `spatial-d` remain first-wave libraries, but their exact order should be driven by concrete technical work rather than by this roadmap.

# Success criterion

`d-geospatial` succeeds if its libraries become useful **even to D developers who have no interest in the application that originally motivated them**.

The intended result is not one large geospatial product.

It is a set of independent D libraries that are individually worth using.

### Helmert 7P architecture

- [x] ADR-0003: explicit EPSG 1032/1033 rotation conventions
- [x] EPSG 1033 Position Vector implementation
- [x] EPSG 1032 Coordinate Frame implementation
- [x] convention-equivalence reference tests
- [x] initial PROJ differential validation harness


### Validation expansion

- [x] deterministic PROJ/cct cross-validation harness for EPSG 9602/1031/1032/1033
- [x] broaden PROJ differential matrix with reproducible generated vectors
- [ ] run validation in CI where PROJ is available
- [ ] establish measured accuracy envelopes before v0.1


### geodesy-d v0.1 baseline consolidation

- [x] DMD/LDC GitHub Actions workflow defined
- [x] separate PROJ extended-validation workflow defined
- [x] explicit v0.1 readiness checklist
- [x] resolve `Ellipsoid.init` semantics — invalid sentinel, ADR-0004
- [x] public API audit — external compile contract + docs/API.md
- [x] documentation audit — Ddoc + release-facing docs contract
- [x] CHANGELOG.md and CONTRIBUTING.md added
- [x] package minimum D frontend 2.111.0 declared in dub.sdl
- [ ] observe remote CI green
- [ ] tag v0.1.0
