# geo-d Roadmap

`geo-d` is a small, robust, coordinate-system-agnostic 2D Euclidean
geometry library for D.

The roadmap follows a depth-before-breadth principle: implemented
functionality should have explicit semantics, strong numerical behaviour,
tests, and documented ownership characteristics before the public API is
expanded further.

Features listed beyond the current release target are candidates rather
than commitments. New API should be driven by concrete consumers.

## v0.1.0 — Initial public foundation

The first release establishes the core geometry, numerical, ownership, and
topology model.

### Core value types

Completed:

- [x] `Point2`
- [x] `Vector2`
- [x] `Bounds2`
- [x] `Segment2`
- [x] explicit scalar policy
- [x] affine point/vector algebra
- [x] checked scalar conversion
- [x] explicit floating-point-to-integer quantisation
- [x] empty-bounds semantics
- [x] explicit non-finite-value policy

Supported core scalar types:

~~~text
int
long
float
double
real
~~~

### Variable-size geometry views

Completed:

- [x] `PolylineView`
- [x] `LinearRingView`
- [x] `PolygonView`
- [x] non-owning read-only representation
- [x] caller-owned backing storage
- [x] explicit borrowing and DIP1000 lifetime checking

Owning variable-size containers are not required for the initial release.

### Metric operations

Completed:

- [x] `distance`
- [x] `squaredDistance`
- [x] `segmentLength`
- [x] `polylineLength`
- [x] `tryNearestPoint`
- [x] `tryPointSegmentDistance`
- [x] explicit `MetricScalar` computation-type policy

Tracked numerical follow-up:

- [ ] evaluate compensated accumulation for long polylines

The existing sequential `polylineLength` accumulation remains valid API.
Any change to the accumulation strategy must preserve the established result
type and execution contracts.

### Robust orientation

Completed for:

- [x] `int`
- [x] `long`
- [x] `float`
- [x] `double`

The implementation uses exact or certified arithmetic as required rather
than a global epsilon.

Verification includes an independent `BigInt` oracle in unittest builds.

Deferred:

- [ ] robust orientation for `real`

Robust `real` support requires a platform-aware backend and is not a
`v0.1.0` requirement.

### Segment intersection

Completed:

- [x] exact intersection classification
- [x] positive-length overlap construction
- [x] unique intersection-point construction
- [x] correctly rounded binary64 proper-crossing coordinates
- [x] degenerate-segment handling
- [x] argument-order and endpoint-order invariance tests

Topology and geometric construction remain separate operations.

Supported robust scalar domains:

~~~text
int
long
float
double
~~~

Deferred:

- [ ] segment-intersection support for `real`

### Ring and polygon area

Completed:

- [x] signed linear-ring area
- [x] polygon area
- [x] exact determinant accumulation
- [x] one final binary64 rounding for supported non-`real` area computation
- [x] orientation-independent polygon ring roles

`PolygonView` assigns ring roles structurally:

~~~text
ring 0      exterior
ring 1..n   holes
~~~

Area computation does not silently validate or normalise topology.

### Point-in-polygon classification

Completed:

- [x] explicit outside / boundary / inside classification
- [x] exact boundary detection
- [x] even-odd classification
- [x] orientation-independent behaviour
- [x] deterministic behaviour for representable invalid geometry
- [x] polygon-with-holes classification

### Topology validation

Completed:

- [x] ring validation
- [x] polygon validation
- [x] structured validation results
- [x] insufficient-cardinality detection
- [x] non-finite-coordinate detection
- [x] zero-length-edge detection
- [x] self-intersection detection
- [x] self-overlap detection
- [x] inter-ring crossing and overlap detection
- [x] ring-contact rules
- [x] hole containment
- [x] nested-hole detection
- [x] connected-interior validation

Validation remains explicitly separate from representation and ordinary
geometry algorithms.

### Polyline simplification

Completed:

- [x] Douglas-Peucker simplification
- [x] iterative implementation
- [x] caller-provided destination storage
- [x] caller-provided workspace
- [x] allocation-free simplification path
- [x] no recursion
- [x] deterministic tie-breaking
- [x] ordered output subsequence

The current simplifier applies only to `PolylineView`.

It deliberately does not claim topology preservation for rings or polygons.

## v0.1.0 release preparation

Required before tagging the first public release.

### API and architecture

- [x] ADR-0001 — scope and boundaries
- [x] ADR-0002 — core type and scalar model
- [x] ADR-0003 — variable-size geometry ownership and views
- [x] ADR-0004 — numerical robustness
- [x] ADR-0005 — segment intersection semantics
- [x] ADR-0006 — segment intersection construction
- [x] ADR-0007 — linear-ring representation and closure
- [x] ADR-0008 — signed-area numerical semantics
- [x] ADR-0009 — polygon representation and ring composition
- [x] ADR-0010 — polygon-area semantics
- [x] ADR-0011 — point-in-polygon semantics
- [x] ADR-0012 — ring and polygon topology validation
- [x] ADR-0013 — polyline simplification

### Repository documentation

- [x] finalise repository-specific `README.md`
- [x] update technical documentation under `docs/`
- [x] finalise repository-specific `DESIGN_PRINCIPLES.md`
- [x] populate `CHANGELOG.md`
- [x] populate or deliberately remove empty `CONTRIBUTING.md`
- [x] document the actual minimum supported D frontend/compiler version
- [x] finalise DUB package metadata

### Release verification

- [x] verify minimum supported D frontend
- [x] encode the supported frontend requirement where appropriate
- [x] add minimum-version CI coverage
- [x] pass current DMD tests
- [x] pass current LDC tests
- [x] pass LDC release build
- [x] pass external/public API compile probes
- [x] pass DIP1000 lifetime probes
- [x] run `git diff --check`
- [x] confirm clean repository state
- [x] run GitHub Actions successfully on the release candidate
- [ ] tag `v0.1.0`

## Post-v0.1 numerical work

### Robust `real` topology

Investigate a platform-aware exact or certified arithmetic backend for:

- orientation;
- segment intersection;
- other topology-sensitive predicates.

No public assumption may be made about the representation, precision, or
layout of D `real`.

### Polyline-length accumulation

Evaluate compensated accumulation techniques such as Neumaier or Kahan
summation.

Evaluation should cover:

- long polylines;
- heterogeneous segment lengths;
- `double` metric results;
- `real` metric results;
- DMD performance;
- LDC performance;
- preservation of `pure`, `nothrow`, `@safe`, and `@nogc` where applicable.

A more complicated accumulation strategy should only replace sequential
addition if measurements demonstrate a worthwhile numerical improvement.

## Candidate future geometry

These are possible future areas, not a committed version plan.

### Bounds operations

Potential additions include operations demonstrated by real consumers,
such as:

- bounds union;
- bounds intersection;
- extent and size queries;
- geometry-to-bounds helpers.

The API should preserve the established empty-bounds identities and NaN
invariants.

### Clipping

Potential future work includes:

- segment clipping;
- polyline clipping;
- polygon clipping.

Polygon clipping should not be introduced without an explicit topology and
robustness design.

### Topology-preserving simplification

Ring or polygon simplification requires semantics distinct from ordinary
Douglas-Peucker polyline simplification.

Any future API must define:

- validity preservation;
- ring closure;
- self-intersection prevention;
- hole containment;
- inter-ring relationships;
- collapse behaviour;
- degenerate output;
- numerical predicate requirements.

It must not be presented as a trivial extension of the current polyline
simplifier.

### Additional geometric relationships

Possible additions should be selected from concrete use cases and may
include:

- point-to-ring relationships;
- segment-to-polygon relationships;
- geometry equality or equivalence operations;
- other low-level Euclidean predicates.

Approximate equality must not become a global replacement for exact value
equality or robust topology predicates.

### Owning aggregate geometry

Owning forms of polylines, rings, or polygons may be introduced if repeated
consumers demonstrate that the library should provide them.

Any owning type must preserve the current separation between:

- storage ownership;
- read-only views;
- algorithms.

Views should remain usable independently of owning containers.

## Performance and verification

Performance work is expected where robust arithmetic or large geometry
makes cost significant.

Existing benchmark areas include:

- segment intersection;
- exact intersection construction;
- signed area;
- exact-area arithmetic.

Future optimisation must preserve numerical semantics unless a different
contract is explicitly designed and documented.

Useful verification techniques include:

- independent arithmetic oracles;
- property testing;
- permutation and reversal invariants;
- degenerate-input tests;
- full-range integral tests;
- arbitrary finite floating-point bit patterns;
- subnormal and extreme-value tests;
- DMD/LDC cross-compiler verification.

## Scope boundaries

`geo-d` remains a Euclidean geometry library.

It does not own:

- coordinate reference systems;
- EPSG or other authority databases;
- projection discovery;
- map projections;
- ellipsoidal geodesy;
- geographic coordinate semantics;
- raster processing;
- spatial indexes;
- geospatial file-format bindings.

Those concerns belong in separate libraries.

## Development principle

The roadmap is intentionally conservative.

A smaller API with explicit semantics, robust numerical behaviour,
predictable allocation, and strong verification is preferred over broad
feature coverage.

After `v0.1.0`, the next feature should be selected by a concrete consumer
requirement rather than simply by choosing the next conventional item from
a geometry-library checklist.
