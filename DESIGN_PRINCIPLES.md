# geo-d — Design Principles

This document defines the engineering and architectural principles specific to `geo-d`.

The library may be developed inside the wider `d-geospatial` workspace, but it is an independent repository and DUB package.

Workspace-wide context may be available locally under:

~~~text
.workspace/
~~~

That local workspace context is not part of the public `geo-d` package or repository contract.

## 1. Purpose

`geo-d` provides small, reusable, coordinate-system-agnostic two-dimensional Euclidean geometry primitives and algorithms for D.

Coordinates have no implicit:

- coordinate reference system;
- geographic meaning;
- geodetic meaning;
- unit;
- Earth model.

The library must remain useful outside GIS applications.

## 2. Scope boundaries

`geo-d` owns general Euclidean geometry concepts such as:

- points;
- vectors;
- bounds;
- segments;
- polylines;
- rings;
- polygons;
- Euclidean metric operations;
- computational-geometry predicates;
- topology validation;
- geometry algorithms whose semantics do not depend on a CRS or Earth model.

It does not own:

- CRS definitions or authority databases;
- EPSG lookup;
- projection discovery;
- map projections;
- ellipsoidal geodesy;
- latitude/longitude semantics;
- raster processing;
- spatial indexing;
- GIS file-format bindings.

Integration with other libraries should use ordinary value conversion or thin adapters rather than moving foreign semantics into `geo-d`.

## 3. Small public API

Public API surface is a long-term compatibility commitment.

New functions and types should be added only when:

- their semantics can be stated clearly;
- a concrete use case demonstrates their value;
- they belong inside the scope of `geo-d`;
- their ownership and numerical behaviour are understood.

Conventional presence in another geometry library is not sufficient justification.

Depth is preferred over breadth.

## 4. Strong geometry semantics

Geometry types should represent mathematical concepts rather than merely convenient groups of coordinates.

In particular:

- `Point2` is an affine point;
- `Vector2` is a displacement;
- points and vectors remain distinct types;
- invalid affine algebra should be rejected at compile time.

The API should not expose operations solely because the underlying scalar fields could technically perform them.

## 5. Explicit scalar model

The supported core scalar set is deliberately finite and explicit.

For `v0.1`:

~~~text
int
long
float
double
real
~~~

Supporting a new scalar category requires understanding its effect on:

- geometry algebra;
- promotion;
- conversion;
- overflow;
- robust predicates;
- metric computation;
- API attributes.

Generic numeric support must not be introduced speculatively.

## 6. Explicit conversion

Different geometry scalar types do not implicitly convert.

Potentially lossy operations must make their numerical semantics visible.

Floating-point-to-integer quantisation must explicitly distinguish operations such as:

- round;
- floor;
- ceil;
- truncate.

Ordinary primitive casts must not silently define geometry conversion semantics.

## 7. Exact equality is not approximate geometry

The fundamental `==` operation means exact value equality.

There is no library-wide epsilon redefining equality.

Approximate comparison, where useful, must be a separate operation with explicitly documented semantics.

## 8. No global epsilon for topology

Topology-sensitive predicates must not determine mathematical relationships through one global floating-point tolerance.

Operations such as:

- orientation;
- segment intersection;
- point-on-boundary classification;
- point-in-polygon classification;
- topology validation;

must use numerical methods appropriate to their required guarantees.

A tolerance may be part of an algorithm whose mathematical definition actually contains one, such as metric simplification.

That is distinct from using epsilon to guess topology.

## 9. Robust topology and geometric construction are separate

A topological answer and a constructed coordinate are not the same thing.

For example:

~~~text
Does an intersection exist?
        !=
What floating-point coordinate should represent it?
~~~

Authoritative topology predicates must not be replaced by tests against rounded construction results.

Construction may round a mathematically exact result to a documented output representation without weakening the corresponding topology operation.

## 10. Representation and validation are separate

Geometry values and views may represent input that is not topologically valid.

Construction must not silently:

- repair geometry;
- reorder rings;
- remove intersections;
- normalise winding;
- change polygon roles;
- discard degenerate input.

Validation is an explicit operation.

This separation is necessary for:

- parsers;
- editors;
- diagnostics;
- interchange;
- repair tools;
- inspection of malformed external data.

## 11. Polygon roles are structural

Polygon ring role must not be inferred implicitly from winding direction.

For `PolygonView`:

~~~text
ring 0      exterior
ring 1..n   holes
~~~

Orientation remains a geometric property of a ring, not its polygon role.

Algorithms must document independently whether winding affects their result.

## 12. Explicit ownership and lifetime

Ownership must be visible in the type and API design.

A view does not own its backing storage.

Variable-size geometry should prefer non-owning views when an owning abstraction is not necessary.

The caller remains responsible for the lifetime of backing storage.

DIP1000 should be used where it materially strengthens compiler-enforced borrowing guarantees.

## 13. Views before unnecessary copies

Algorithms should normally accept views of existing geometry rather than require callers to duplicate data into library-owned containers.

Copying a lightweight geometry view should remain cheap.

Algorithms must not hide deep copies behind apparently lightweight operations.

If future owning aggregate types are introduced, existing view-based algorithms should remain independently usable.

## 14. Allocation must be explicit

Low-level geometry and numerical algorithms should avoid hidden allocation.

When variable-size temporary storage is needed and caller management is practical, prefer:

- caller-provided destination buffers;
- caller-provided workspaces;
- explicit size-query functions.

An algorithm may allocate when that is genuinely the clearest design, but allocation behaviour must be part of its documented contract.

`@nogc` must reflect reality rather than aspiration.

## 15. Preserve useful execution contracts

Low-level operations should provide strong D attributes where their semantics permit:

~~~text
pure
nothrow
@safe
@nogc
~~~

Existing guarantees must not be removed casually.

An attribute is part of the API contract once consumers can rely on it.

Do not distort an algorithm merely to obtain an attribute that its natural semantics do not support.

## 16. Numerical representation and computation are different concerns

Coordinate storage type does not automatically determine the best computation type.

Metric operations may use a computation representation different from coordinate storage.

Robust predicates may require:

- wider intermediate values;
- exact integer arithmetic;
- floating-point expansions;
- dyadic arithmetic;
- adaptive or certified filters.

These implementation strategies should remain internal unless callers genuinely need them.

## 17. Ordinary algebra does not promise overflow-free mathematics

Ordinary point and vector algebra follows the documented behaviour of the corresponding D scalar operations.

Robust computational-geometry predicates may use stronger internal arithmetic when mathematical correctness requires it.

Do not force every simple value operation through expensive exact arithmetic merely because topology algorithms require exactness.

## 18. Deterministic behaviour matters

Given the same geometry and scalar representation, algorithms should produce deterministic results where practical.

This includes deterministic choices for:

- tie-breaking;
- canonical overlap endpoints;
- simplification output;
- validation diagnostics where ordering is defined.

Determinism improves reproducibility, testing, debugging, and downstream processing.

## 19. Degenerate geometry is part of the domain

Degenerate cases must be designed rather than ignored.

Examples include:

- zero-length segments;
- empty views;
- singleton polylines;
- collinear points;
- touching rings;
- geometrically collapsed results.

A type should not use a legitimate degenerate geometry as an invalid sentinel when the two concepts need different semantics.

## 20. Non-finite values require explicit policy

Representability and algorithm validity are distinct.

Core floating-point value types may represent NaN and infinities when their value semantics permit it.

Individual algorithms must define whether such inputs are accepted.

Types with stronger invariants, such as `Bounds2`, may reject values that would invalidate their ordered representation.

NaN must not silently acquire an unrelated geometric meaning such as "empty".

## 21. Complexity and workspace requirements are API properties

For algorithms operating on variable-size geometry, document meaningful complexity characteristics.

Where relevant, this includes:

- time complexity;
- destination size requirements;
- workspace size requirements;
- allocation behaviour;
- recursion;
- mutation or aliasing constraints.

Do not hide unexpectedly expensive behaviour behind a trivial-looking API.

## 22. Optimisation must preserve semantics

Correctness comes before micro-optimisation.

Performance-sensitive numerical paths should be benchmarked.

Optimisations must preserve established:

- topology semantics;
- rounding semantics;
- determinism;
- safety;
- ownership behaviour.

If an optimisation requires changing one of these contracts, that is an API/design change rather than merely an implementation optimisation.

## 23. Measure before claiming

Performance claims should be supported by measurement.

Benchmarks should focus on operations where implementation choices materially affect runtime.

Benchmark results should not be used to justify weaker numerical semantics unless such a trade-off is explicitly designed as a separate API.

## 24. Independent verification for difficult numerical code

Robust numerical algorithms should be tested independently of the implementation strategy whenever practical.

Useful techniques include:

- `BigInt` or other independent exact oracles;
- property tests;
- argument permutation;
- endpoint reversal;
- full-range signed integer inputs;
- arbitrary finite floating-point bit patterns;
- subnormal values;
- extreme exponents;
- known rounding boundaries.

Tests that merely reproduce the production algorithm through similar arithmetic are insufficient for high-risk numerical code.

## 25. Compiler diversity is part of verification

DMD and LDC are required compiler families.

The minimum supported D frontend is:

~~~text
2.111.0
~~~

CI should cover:

- the documented minimum;
- current DMD;
- current LDC.

Cross-compiler testing is particularly important for floating-point and template-heavy numerical code.

GDC support is best effort unless explicitly promoted to a stronger contract.

## 26. Architecture decisions precede semantic drift

Significant public semantic decisions should be documented in ADRs.

An ADR is normally appropriate for changes involving:

- geometry representation;
- scalar policy;
- ownership;
- topology;
- robustness;
- rounding;
- validation;
- error semantics;
- algorithm guarantees.

Implementation should not accidentally establish a permanent public contract before the underlying design question has been considered.

## 27. Dependencies must justify themselves

`geo-d` should remain dependency-light.

A dependency must provide enough value to justify:

- maintenance cost;
- build complexity;
- supply-chain surface;
- version constraints;
- portability impact.

Do not introduce a large GIS runtime for basic Euclidean geometry.

Test-only dependencies or standard-library facilities used as independent verification tools do not imply production coupling.

## 28. Framework neutrality

`geo-d` must not depend on:

- GUI frameworks;
- application data models;
- editor state;
- database schemas;
- one particular geometry file format.

Consumers should be able to use the library in command-line tools, servers, desktop software, numerical applications, or unrelated domains without adopting an application framework.

## 29. Interoperability through simple boundaries

Interoperability should favour:

- simple value conversion;
- views;
- lightweight adapters;
- explicit foreign-memory handling.

A geometry algorithm should not care whether coordinates originally came from:

- GDAL;
- PROJ;
- OSM;
- a database;
- a simulation;
- generated data;
- an in-memory calculation.

Origin of data must not become an unnecessary dependency.

## 30. Future features must earn their place

Potential future work such as:

- clipping;
- owning aggregate geometry;
- additional relationships;
- topology-preserving simplification;
- robust `real` predicates;

should be added when requirements are concrete enough to define a sound API.

Do not generalise merely to make the library appear complete.

## Guiding principle

`geo-d` should prefer:

~~~text
small API
    +
strong geometry semantics
    +
explicit ownership
    +
robust topology
    +
predictable numerical behaviour
    +
visible allocation
    +
independent verification
~~~

over:

~~~text
large API
    +
implicit conversion
    +
hidden allocation
    +
epsilon-based topology
    +
silent geometry repair
    +
speculative abstraction
~~~

A small geometry library whose behaviour can be trusted is more valuable than a broad one whose semantics depend on undocumented assumptions.