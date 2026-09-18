# geo-d Roadmap

`geo-d` is a small, robust, coordinate-system-agnostic 2D Euclidean
geometry library for D.

The roadmap follows a depth-before-breadth principle: implemented
functionality should have explicit semantics, strong numerical behaviour,
tests, and documented ownership characteristics before the public API is
expanded further.

`v1.0.0` is the current stable API baseline. There is no committed post-v1
feature milestone; new API remains driven by concrete consumers and must
respect the source-compatibility policy defined for the `1.x` series.

Features listed beyond the stable v1 release are candidates rather than
commitments.

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

- [x] evaluate compensated accumulation for long polylines

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

Robust `real` support requires a platform-aware backend. It is an explicitly
deferred post-v1 capability and is not a `v1.0.0` release blocker.

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

This follows the same explicitly deferred robust-`real` policy and is not a
`v1.0.0` release blocker.

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
- [x] tag `v0.1.0`


## v1.0.0 — Library maturity target

`v1.0.0` marks API and engineering maturity rather than simply a larger
feature set.

Before `v1.0.0`, the existing public functionality must be comprehensively
documented, independently consumable, benchmarked, and performance-audited.

New geometry features are not a prerequisite for `v1.0.0` unless required
by concrete consumers.

**API freeze status:** complete. The supported v1 public API was frozen at
`api-freeze-v1.0.0` with 41 top-level public names. Post-freeze work may
improve documentation, verification, performance evidence, CI, and release
packaging without silently expanding that API.

### Documentation maturity

Required:

- [x] document every public module, type, enum, template, function, method,
      and property with Ddoc-compatible documentation
- [x] document semantics, valid input domain, failure behaviour,
      degeneracies, non-finite handling, allocation behaviour, and relevant
      complexity
- [x] document numerical guarantees separately from implementation details
- [x] provide documented `unittest` examples for representative public APIs
- [x] ensure documentation examples are compiled during verification
- [x] generate complete API reference documentation automatically
- [x] evaluate `ddox` and `adrdox` and select one publication path
- [x] publish navigable API documentation
- [x] make documentation generation part of CI
- [x] verify that exported public API is not left undocumented

Source-level Ddoc comments are the authoritative API documentation.
Generated HTML documentation is a derived publication artifact.

### Installation and onboarding

Required:

- [x] document installation through the public DUB registry
- [x] document supported compiler/frontend versions
- [x] document DMD and LDC usage
- [x] document `dub add geo-d`
- [x] provide a minimal working example using only `import geo;`
- [x] verify the MWE against the published DUB package
- [x] provide task-oriented examples for:
  - point/vector algebra
  - metric operations
  - orientation
  - segment intersection
  - polyline views
  - rings and polygons
  - area
  - point-in-polygon classification
  - topology validation
  - Douglas-Peucker simplification
- [x] clearly explain view ownership and lifetime semantics
- [x] clearly explain robust topology versus rounded geometric construction
- [x] clearly explain supported scalar domains and current `real` limitations

`README.md` should remain a concise landing page. Detailed guides belong
under `docs/`.

### Benchmark coverage

Before `v1.0.0`, every computationally meaningful public algorithm family
must have benchmark coverage.

Required benchmark areas:

- [x] scalar conversion and quantisation
- [x] bounds operations where computationally meaningful
- [x] metric primitives
- [x] polyline length
- [x] nearest-point and point-to-segment distance
- [x] orientation
- [x] segment-intersection classification
- [x] segment-intersection construction
- [x] signed ring area
- [x] polygon-area core arithmetic
- [x] point-in-polygon classification
- [x] ring validation
- [x] polygon validation
- [x] Douglas-Peucker simplification

Benchmark workloads should distinguish where meaningful:

- ordinary representative inputs;
- degenerate inputs;
- numerically difficult inputs;
- exact-arithmetic slow paths;
- varying geometry sizes;
- integer and floating-point scalar domains.

Existing intersection and area benchmarks form the initial baseline and
should be integrated into one consistent benchmark framework.

### Benchmark methodology

Benchmark results must contain enough context to be reproducible.

Record at least:

- geo-d commit;
- compiler and frontend version;
- DMD or LDC;
- compiler flags;
- operating system;
- CPU;
- workload;
- iteration or sample count;
- geometry/input size;
- timing unit.

Benchmarks must:

- use monotonic timing;
- prevent dead-code elimination;
- include warm-up where appropriate;
- use repeated measurements rather than one isolated timing;
- distinguish throughput from latency where relevant.

Absolute timings are machine-, compiler-, and build-dependent and are not
part of the public API contract.

### Performance audit and optimisation

Every computationally meaningful public algorithm family must receive an
explicit performance review before `v1.0.0`.

For each area:

1. establish a reproducible baseline;
2. identify dominant costs by profiling or focused component benchmarks;
3. inspect allocation and copying behaviour;
4. inspect algorithmic complexity;
5. compare DMD and LDC behaviour;
6. identify redundant or avoidable work;
7. optimise only where measurements justify the change;
8. rerun semantic and numerical verification;
9. record before/after benchmark results.

Performance optimisation must preserve established semantics unless a
different API contract is explicitly designed.

In particular, optimisation must not weaken existing guarantees for:

- robust topology;
- correctly-rounded construction;
- deterministic behaviour;
- ownership and lifetime;
- `@safe`;
- `@nogc`;
- `pure`;
- `nothrow`;

where those guarantees apply.

### Performance acceptance criteria

`v1.0.0` does not require arbitrary universal timing thresholds.

It does require:

- [x] no known accidental asymptotic regression
- [x] no avoidable hidden allocation on low-level paths
- [x] no unnecessary deep copy
- [x] no known major redundant exact-arithmetic work
- [x] documented scaling behaviour for variable-size algorithms
- [x] DMD performance baselines
- [x] LDC performance baselines
- [x] investigation of substantial compiler-specific differences
- [x] explicit justification for intentionally expensive robust paths

Correctness remains more important than raw throughput.

### Numerical and API hardening

Before `v1.0.0`:

- [x] resolve or explicitly defer compensated `polylineLength`
      accumulation
- [x] resolve the long-term policy for robust `real` support
- [x] audit all public scalar constraints for consistency
- [x] audit all public failure semantics
- [x] audit all public allocation guarantees
- [x] audit all public complexity guarantees
- [x] audit all symbols exported through `import geo;`
- [x] define source-compatibility expectations for the `1.x` series
- [x] define a public API deprecation policy

### v1.0.0 release gate

`v1.0.0` may be tagged only when:

- [x] API documentation is complete and published
- [x] installation instructions are verified from a clean environment
- [x] MWEs compile against the public DUB package
- [x] benchmark coverage spans all computational public API families
- [x] DMD and LDC performance baselines are recorded
- [x] all computational public API families have completed a performance
      audit
- [x] identified high-value optimisations are completed or explicitly
      deferred
- [x] unit and property verification passes
- [x] minimum-compiler CI passes
- [x] current DMD CI passes
- [x] current LDC CI passes
- [x] external-consumer tests pass
- [x] documentation generation passes
- [x] repository state is release-clean

Pre-tag public-registry verification resolved `geo-d ~main` from the public
DUB registry and successfully built and ran the documented minimal consumer
with both DMD and LDC. The exact `v1.0.0` registry version is smoke-tested
again after the release tag has been indexed.

## Post-v1 maturity and consumer audit

The first post-v1 phase is an audit of portability, documentation maturity,
ecosystem expectations, and concrete consumer requirements.

This phase does not commit `geo-d` to implementing the conventional feature
set of larger geometry libraries.

New public API remains consumer-driven and research-gated.

The purpose of the audit is to identify:

- portability gaps;
- public documentation and example gaps;
- capabilities commonly expected from reusable 2D geometry libraries;
- concrete geometry requirements of downstream consumers;
- opportunities for stronger independent verification.

Any resulting API proposal must still pass the ordinary `1.x`
source-compatibility, scope, semantic, numerical, and ownership review.

### Cross-platform and cross-architecture portability

The current Linux x86-64 compiler matrix remains the baseline.

Expand verification to other operating systems and architectures supported
by practical CI infrastructure.

Initial targets:

- [x] Linux x86-64
- [x] Linux ARM64
- [x] Windows x86-64
- [x] macOS x86-64
- [x] macOS ARM64
- [ ] evaluate Windows ARM64 when the GitHub-hosted runner and D toolchain
      provide a sufficiently stable combination

Portability verification completed on commit `4b3b246` with the existing
Linux x86-64 compiler gate and `LDC latest` portability jobs for Linux ARM64,
Windows x86-64, macOS x86-64, and macOS ARM64. Unit tests, the external
consumer test, and the release build passed on every verified target.

Windows ARM64 remains a separate toolchain investigation rather than a
verified target.

For additional platforms, prefer `LDC latest` as the first portability
probe. Broader compiler combinations should be added only where they provide
useful independent evidence rather than creating a redundant Cartesian
product.

Each supported CI target should, where practical:

- [ ] run the library unit tests
- [ ] run the external consumer test
- [ ] build the release configuration
- [ ] build or otherwise verify public documentation where relevant

The portability audit must pay particular attention to assumptions involving:

- D `real` representation and precision;
- floating-point evaluation behaviour;
- the explicit binary64 rounding backend;
- exact integer arithmetic helpers;
- integer width and data layout;
- compiler-specific intrinsics or code generation;
- alignment and ABI assumptions.

Architectures not covered by ordinary GitHub-hosted runners should be
identified explicitly rather than silently treated as verified.

Potential later portability probes include:

- 32-bit targets;
- big-endian targets;
- additional Unix-like operating systems.

These are research targets rather than current support commitments.

### Public API executable-example audit

Audit the complete supported public API exported through `import geo;`.

The audit covers:

- the 41 frozen v1 top-level public names;
- public methods and properties of exported types;
- templates and overload families;
- failure-oriented APIs whose correct use is not obvious from the signature.

For every user-facing public declaration, determine whether it has an
appropriate documented `unittest` example that appears in the generated
DDox documentation.

The desired state is:

- [x] inventory every public declaration requiring an example
- [ ] add documented `unittest` examples where useful
- [ ] ensure examples use the supported consumer surface through
      `import geo;`
- [ ] ensure every example is compiled as part of ordinary verification
- [ ] verify that DDox actually publishes the example
- [ ] add automated documentation-example coverage checking where practical

Tiny accessors, enum members, or closely related overloads do not require
artificial duplicate examples when one documented example clearly
demonstrates the complete public API family.

Any omission should therefore be deliberate and auditable rather than
accidental.

The existing representative documented unittests remain valid; this audit
raises the post-v1 goal from representative coverage to systematic public
API example coverage.


The baseline inventory is recorded in
`docs/public-api-example-audit.md`. The DDox output generated from commit
`4b3b246` contains 92 public symbol pages: seven already render an `Example`,
31 are classified for a dedicated example, and 54 are deliberately covered
by an owning type or API-family example. Completing the inventory does not
mark the example implementation or DDox-verification tasks complete.


Baseline audit of the documentation generated from commit `4b3b246` found
92 public DDox symbol pages. Seven currently contain a rendered `Example`
section:

- `polygonArea`;
- `tryConvert`;
- `trySegmentIntersectionPoint`;
- `distance`;
- `orientation`;
- `tryClassifyPointInPolygon`;
- `trySimplifyDouglasPeuckerInto`.

This count is a baseline, not the target coverage metric. The next step is
to classify the complete public surface by whether a declaration needs its
own example, is adequately represented by an API-family example, or is
sufficiently trivial that a separate example would add no useful information.

### Geometry-library landscape inventory

Inventory comparable and influential geometry libraries before selecting
new `geo-d` functionality.

Research should include both D libraries and mature libraries in other
ecosystems.

Candidate reference implementations include:

- D geometry and mathematical libraries;
- Boost.Geometry;
- GEOS and JTS;
- CGAL;
- Rust `geo`;
- Clipper2;
- other focused libraries where they provide useful evidence for a specific
  algorithm family.

The inventory should record more than function names.

For each relevant capability, compare where practical:

- geometry model;
- public operation;
- scalar model;
- numerical robustness;
- degenerate-input semantics;
- non-finite handling;
- ownership and allocation model;
- mutating versus non-mutating design;
- algorithmic complexity;
- topology guarantees;
- error or failure representation.

The result should be a capability matrix, not a feature wish list.

### General ecosystem capability-gap analysis

Use the library inventory to determine whether important generally expected
2D Euclidean geometry capabilities are absent from `geo-d`.

Every identified capability should be classified as one of:

~~~text
already covered
deliberately out of scope
useful but currently unproven
research candidate
consumer-backed candidate
~~~

Areas worth investigating may include, but are not limited to:

- additional vector operations;
- additional bounds operations;
- line and projection primitives;
- nearest-point operations on aggregate geometry;
- ring perimeter;
- ring orientation queries;
- centroid calculation;
- convex hull;
- geometry-to-geometry distance;
- affine transformations;
- additional geometric relationships;
- clipping and overlay;
- buffer or offset operations.

Presence in another library is not sufficient justification for addition to
`geo-d`.

Large algorithm families such as polygon overlay, buffering, or generalized
topological relationships require substantially stronger evidence and design
work than small primitive operations.

### OSM-editor consumer analysis

Treat the planned D OSM editor as a concrete downstream consumer of
`geo-d`.

Do not copy the geometry utility surface of an existing editor wholesale.

Instead:

1. identify real editor workflows;
2. decompose each workflow into coordinate-system-agnostic Euclidean
   geometry operations;
3. determine whether `geo-d` already provides those operations;
4. separate geometry requirements from OSM model, CRS, projection, spatial
   indexing, rendering, and UI concerns;
5. turn missing geometry primitives into explicit consumer requirements.

Relevant editor workflows may include:

- snapping to ways and segments;
- nearest-segment discovery once candidate geometry is known;
- projecting a point onto a line or segment;
- line and segment intersection;
- angle and direction operations;
- area orientation;
- polygon or area editing;
- clipping or overlap operations;
- geometry validation and repair support.

The analysis should examine established OSM editors, including JOSM, as
research references while preserving the architectural boundaries of the
D geospatial workspace.

Requirements belonging to `osm-d`, `proj-d`, `spatial-d`, `imagery-d`, or
other sibling libraries must not migrate into `geo-d` merely because an
editor needs them.

### Independent differential and property verification

Expand independent verification where external implementations or
mathematical properties provide useful oracles.

Potential techniques include:

- differential testing against mature geometry implementations;
- randomized property testing;
- metamorphic testing;
- permutation and reversal invariants;
- cross-compiler comparison;
- cross-architecture comparison;
- exact arithmetic reference implementations.

External geometry libraries may be used as research or test oracles without
becoming runtime dependencies of `geo-d`.

Differences must be investigated semantically: disagreement does not by
itself establish which implementation is correct when libraries define
degenerate cases or topology differently.

### Post-v1 API decision gate

The audit may produce API candidates, but it does not itself authorize API
expansion.

A candidate public addition should follow this sequence:

~~~text
research and/or concrete consumer requirement
                    |
                    v
              geo-d scope check
                    |
                    v
        semantic and numerical design
                    |
                    v
          1.x compatibility analysis
                    |
                    v
       ADR when architecturally relevant
                    |
                    v
          implementation and evidence
~~~

Small additions are not exempt from this process merely because they appear
conventional.

The preferred outcome remains the smallest public API that makes `geo-d`
broadly useful while preserving explicit semantics, numerical robustness,
predictable memory behaviour, and clear workspace boundaries.


## Post-v1 numerical work

### Robust `real` topology

Investigate a platform-aware exact or certified arithmetic backend for:

- orientation;
- segment intersection;
- other topology-sensitive predicates.

No public assumption may be made about the representation, precision, or
layout of D `real`.

## Candidate future geometry

These are possible future areas, not a committed version plan.

### Bounds operations

Potential additions include operations demonstrated by real consumers,
such as:

- bounds union;
- bounds intersection;
- extent and size queries.

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

Post-v1, the next feature should be selected by a concrete consumer
requirement rather than simply by choosing the next conventional item from
a geometry-library checklist.
