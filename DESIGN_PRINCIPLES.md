# d-geospatial — Shared Design Principles

**Version:** 0.2  
**Status:** Initial shared design contract

## 1. Purpose

`d-geospatial` is a workspace for a family of **independent D libraries** concerned with geometry, geodesy, spatial data, raster processing, geospatial formats, algorithms, and related infrastructure.

It is **not a framework**, not a monolithic SDK, and not a single versioned software stack.

Each library:

- is independently usable,
- is independently versioned,
- has its own Git repository,
- has its own DUB package,
- has its own tests and documentation,
- may have its own release cadence,
- and should remain useful outside the application or project that originally motivated it.

These principles define a shared engineering philosophy. They do not require a shared runtime or common base package.

---

## 2. Normative language

The terms **MUST**, **SHOULD**, and **MAY** are used deliberately.

- **MUST**: required unless a documented exception exists.
- **SHOULD**: expected default; deviations require a technical reason.
- **MAY**: optional.

A library MAY deviate from these principles when its domain requires it, but such deviations SHOULD be documented.

---

# 3. Library independence

A library MUST represent a coherent domain of its own.

It MUST NOT depend on another `d-geospatial` library merely to share:

- utility functions,
- error helpers,
- traits,
- string helpers,
- logging infrastructure,
- or other incidental implementation details.

Dependencies are justified when they reflect a real conceptual layering.

Good:

```text
specialised library
        ↓
fundamental domain library
```

Bad:

```text
library A ─┐
library B ─┼─→ common-d
library C ─┘
```

solely because several libraries happen to need a few similar helpers.

There is deliberately no mandatory `common`, `core`, or `foundation` package.

A repeated abstraction SHOULD only become an independent package after genuine reuse has demonstrated that it represents a domain of its own.

---

# 4. Dependency discipline

Dependencies SHOULD point from specialised functionality toward more fundamental functionality.

Fundamental libraries SHOULD have the smallest practical dependency set.

Large native runtimes MUST NOT become dependencies of lower-level libraries merely for convenience.

For example, a generic geometry library should not require a GIS runtime solely to perform basic geometry operations.

Optional interoperability SHOULD normally be implemented in:

- specialised libraries,
- optional configurations,
- or adapter modules.

Circular dependencies between libraries MUST be avoided.

---

# 5. Application independence

A reusable library MUST model its actual domain rather than the application that first required it.

Bad:

```d
auto getCurrentEditorMap();
```

Better:

```d
auto query(Bounds bounds);
```

Bad:

```d
traceOsmRoad(...);
```

for an otherwise generic path-search library.

Better:

```d
trace(CostField field, Point start, Point target);
```

with OSM-specific behaviour implemented at a higher layer.

Applications are reference consumers of the libraries, not their specification.

---

# 6. Explicit ownership and lifetime

Ownership MUST be visible in API design.

Types that own resources or memory SHOULD be distinguishable from types that merely view or borrow them.

Preferred conceptual distinction:

```text
Buffer / Storage / Owner

          versus

View / Span / Reference
```

A view MUST NOT imply ownership.

Copying a lightweight view SHOULD be cheap.

Deep copies MUST NOT occur unexpectedly.

Operations that allocate or materialise new storage SHOULD make this apparent through:

- naming,
- return type,
- documentation,
- or API structure.

Resource lifetime MUST be deterministic where required by the underlying resource.

---

# 7. Views before copies

Where the domain allows it, APIs SHOULD prefer views over unnecessary copying.

Typical examples include:

- slices,
- subregions,
- crops,
- subsets,
- windows,
- channels,
- ranges,
- transformed logical views.

A zero-copy operation SHOULD remain zero-copy unless materialisation is explicitly requested.

Where repeated computation is expected, libraries SHOULD provide destination-oriented APIs when practical:

```d
operationInto(source, destination);
```

This allows callers to control allocation and reuse memory.

---

# 8. Memory layout is part of the contract

Libraries dealing with structured numerical or binary data MUST distinguish between relevant memory-layout properties.

Examples include:

- contiguous versus strided data,
- owning versus borrowed storage,
- aligned versus unaligned memory,
- logical shape versus physical layout.

A logical view MUST NOT be assumed to satisfy the layout requirements of an external API.

Foreign-function boundaries MUST verify the required:

- size,
- alignment,
- stride,
- contiguity,
- datatype,
- and lifetime.

Unchecked layout assumptions are correctness bugs, not merely performance issues.

---

# 9. Data-oriented design where appropriate

Large datasets and performance-sensitive algorithms SHOULD favour representations that improve:

- locality,
- predictable memory access,
- low allocation count,
- vectorisation,
- efficient iteration.

For suitable domains, representations such as

```text
ids[]
x[]
y[]
flags[]
offsets[]
```

may be preferable to millions of separately heap-allocated objects.

Object-oriented interfaces MAY still be provided where they improve usability.

Public API design and internal data representation do not have to be identical.

---

# 10. Allocation policy

Allocation is allowed.

**Hidden and unnecessary allocation is not.**

Performance-sensitive operations SHOULD document whether they:

- allocate,
- may allocate,
- or do not allocate.

Hot paths SHOULD permit memory reuse where practical.

`@nogc` SHOULD be used where it provides concrete value, particularly in:

- numerical kernels,
- spatial queries,
- tight decoding loops,
- geometry operations,
- raster operations.

`@nogc` MUST NOT become a dogma that makes ordinary APIs significantly worse without measurable benefit.

---

# 11. Safety

Public APIs SHOULD be `@safe` wherever reasonably possible.

Unsafe operations MUST be kept within small, reviewable boundaries.

Preferred structure:

```text
public @safe API
       ↓
small @trusted implementation boundary
       ↓
pointer arithmetic / C API / system operation
```

`@trusted` MUST only be used when the implementation establishes the invariants promised to `@safe` callers.

Raw pointers and native handles SHOULD normally remain internal implementation details.

---

# 12. Bounds and validation

Ranges, offsets, slices, indices, and dimensions MUST be validated where invalid values can compromise correctness or memory safety.

Libraries MUST NOT depend on unchecked pointer arithmetic when bounded representations are practical.

Malformed external input is not a programmer error.

Assertions SHOULD be used for internal invariants.

Malformed data, invalid user input, and external failures SHOULD use the library's normal error mechanism.

---

# 13. Error semantics

Every library MUST have a deliberate and documented error model.

Equivalent classes of failure SHOULD be represented consistently.

Libraries SHOULD avoid arbitrary mixtures of:

```text
null
false
-1
errno
exceptions
```

for similar errors.

The error model SHOULD distinguish, where relevant:

- malformed or invalid input,
- unavailable data,
- resource exhaustion,
- I/O or operating-system errors,
- foreign-library failures,
- programmer invariant violations.

Foreign-library errors SHOULD be translated at the interoperability boundary while preserving useful diagnostic information.

Error handling SHOULD be simple enough that callers can use it correctly.

---

# 14. Native interoperability

D's C interoperability SHOULD be used as a strength.

Mature external libraries SHOULD be reused when they solve a complex problem well.

We SHOULD NOT reimplement major established systems merely to avoid a native dependency.

At the same time, raw C interfaces SHOULD normally be separated from the idiomatic public D API.

Preferred layering:

```text
native library
     ↓
raw binding
     ↓
idiomatic D wrapper
     ↓
application/library API
```

The wrapper SHOULD handle:

- lifetime,
- ownership,
- cleanup,
- common datatype conversion,
- error translation,
- safe common operations.

Advanced callers MAY be given access to raw bindings where useful.

---

# 15. RAII for external resources

Resources requiring explicit release SHOULD use deterministic lifetime management.

Examples include:

- file handles,
- native datasets,
- transformation contexts,
- GPU resources,
- inference sessions,
- native buffers.

Copying MUST be disabled when duplicate ownership would be invalid.

Garbage collection MUST NOT be the sole mechanism responsible for releasing scarce native resources.

---

# 16. Avoid unnecessary abstraction

Genericity is useful when it serves real reuse.

It is not a goal in itself.

D templates SHOULD be used when they produce a clearer or more reusable API.

Libraries SHOULD avoid template complexity that causes:

- excessive compile time,
- unreadable diagnostics,
- difficult documentation,
- unnecessary code generation,

without delivering practical value.

Prefer the smallest abstraction that correctly models the problem.

---

# 17. Strong domain semantics

Types SHOULD make materially different concepts difficult to confuse.

Where useful, distinguish concepts such as:

```text
geographic coordinates
projected coordinates
screen coordinates
pixel coordinates
tile coordinates
array indices
distances
angles
```

Conversions between materially different domains SHOULD be explicit.

Raw primitive types MAY be used internally where performance requires them.

Public APIs SHOULD favour semantic correctness over accidental convenience.

## 17.1 Geometry, geodesy, georeferencing and CRS boundaries

The workspace deliberately separates four related but distinct domains:

- **`geo-d`** provides coordinate-system-agnostic Euclidean geometry. Its coordinates carry no implicit geographic, geodetic, CRS, unit or Earth-model semantics.
- **`geodesy-d`** provides pure-D mathematical types and algorithms whose meaning depends on the Earth, a reference ellipsoid, geographic/geocentric coordinates, frame transformations or map projections.
- **`georef-d`** provides compact or discrete geographic reference/coding systems such as MGRS, Geohash and Open Location Code.
- **`proj-d`** provides integration with PROJ for the broader CRS/authority ecosystem, including CRS definitions, operation selection, authority metadata, grids and related native infrastructure.

Examples of intended ownership:

```text
Point2 / Vector2 / Polygon         → geo-d
Latitude / Longitude / Ellipsoid   → geodesy-d
ECEF / Helmert / UTM               → geodesy-d
MGRS / Geohash / Plus Code         → georef-d
EPSG database / WKT / grid shifts  → proj-d
```

A map projection result MAY be adapted to a `geo-d` point, but `geo-d` MUST NOT acquire Earth or CRS semantics merely to support that integration.

`geodesy-d` MUST NOT grow into a second PROJ by accumulating authority databases, automatic CRS discovery, WKT parsing or transformation-grid management. Conversely, using PROJ for complete CRS infrastructure does not prohibit a bounded, independently useful pure-D implementation of well-specified geodetic mathematics.

Dependencies between these libraries SHOULD remain optional or one-directional and MUST reflect genuine conceptual layering. Adapters are preferred where direct coupling is unnecessary.

---

# 18. Numerical policy

Precision SHOULD match the domain.

Libraries MUST NOT silently reduce precision when doing so can materially affect correctness.

Likewise, higher precision SHOULD NOT be used automatically where it creates substantial cost without benefit.

The chosen numerical representation SHOULD be documented for important domain types.

Conversions that may lose precision SHOULD be visible to the caller where practical.

---

# 19. Performance is an API property

Performance-sensitive libraries MUST be designed so important operations can be measured independently.

Relevant APIs SHOULD make it possible to benchmark:

- parsing,
- queries,
- transformations,
- kernels,
- allocation,
- rendering preparation,
- or other major operations

without unrelated work being inseparably mixed into the same call.

The cost of an operation SHOULD not be surprising from its API.

An innocent-looking property access SHOULD NOT unexpectedly perform an expensive full-data transformation without clear documentation.

---

# 20. Measure before claiming

Performance claims MUST be supported by measurements.

Performance-sensitive libraries SHOULD maintain reproducible benchmarks.

Measurements MAY include:

- throughput,
- latency,
- allocations,
- peak memory,
- scaling with dataset size,
- build/compiler differences.

Release-mode LDC builds SHOULD normally be part of performance evaluation.

Optimisations SHOULD be motivated by profiling or known algorithmic behaviour.

---

# 21. Complexity documentation

Algorithms whose scaling materially affects usability SHOULD document their expected computational complexity.

Examples:

```text
view creation                 O(1)
linear raster operation       O(n)
range query                   O(log n + k)
materialisation               O(n)
```

Users should be able to understand whether an operation is intended for:

```text
10 elements
10,000 elements
10,000,000 elements
```

without reading its implementation.

---

# 22. Correctness before micro-optimisation

Priority order:

1. correctness,
2. clear invariants,
3. appropriate data structures and algorithms,
4. measurable performance,
5. low-level optimisation.

Fundamental architectural decisions that affect asymptotic complexity, ownership, and memory layout SHOULD be considered early.

Micro-optimisations SHOULD follow evidence.

---

# 23. Concurrency

Threading behaviour MUST be documented.

Libraries SHOULD NOT create hidden worker threads unless doing so is intrinsic to their domain.

Applications SHOULD normally retain control over scheduling.

Independent operations SHOULD be designed so callers can parallelise them where practical.

Shared mutable global state SHOULD be avoided.

Thread safety MUST NOT be implied when it is not provided.

---

# 24. Determinism

Algorithms SHOULD be deterministic for identical inputs unless nondeterminism is:

- intrinsic,
- beneficial,
- or explicitly requested.

This is particularly valuable for:

- geometry,
- spatial indexing,
- parsing,
- raster processing,
- tests,
- benchmarks.

Parallel implementations SHOULD preserve deterministic externally visible behaviour where reasonably practical.

---

# 25. Framework neutrality

General libraries MUST NOT require a particular:

- GUI toolkit,
- application framework,
- event loop,
- logging system,
- dependency injection framework.

A raster-processing library must remain usable from a command-line application.

A parser must remain usable on a headless server.

A geometry library must not depend on a GUI representation.

---

# 26. Logging

Libraries SHOULD NOT write routine diagnostic output directly to stdout or stderr.

Errors SHOULD be communicated through the documented error mechanism.

When diagnostics are useful, libraries MAY expose:

- structured diagnostic objects,
- callbacks,
- optional tracing hooks.

The caller decides how and where diagnostics are displayed or logged.

---

# 27. API surface

Public APIs SHOULD be deliberately small.

Implementation details MUST NOT become public merely because doing so is convenient during development.

A smaller stable API gives more freedom to improve internal implementation later.

Public types SHOULD represent domain concepts, not temporary implementation accidents.

---

# 28. Versioning

Each library has its own version.

Semantic Versioning SHOULD be used for published packages.

Before `1.0`, breaking API changes are acceptable when they materially improve the design.

Such changes MUST be documented.

After `1.0`:

```text
PATCH  compatible fixes
MINOR  compatible functionality
MAJOR  incompatible API change
```

Deprecation SHOULD be preferred to immediate removal when practical.

---

# 29. Compiler support

Libraries SHOULD target modern D rather than indefinitely preserving obsolete compiler compatibility.

Primary compilers:

```text
DMD
LDC
```

GDC support is desirable where practical.

Each library MUST document its supported compiler/frontend range.

CI SHOULD test the declared compiler matrix.

Compiler compatibility requirements SHOULD NOT prevent worthwhile language or safety improvements indefinitely.

---

# 30. BetterC

BetterC compatibility is optional.

A library MAY support BetterC where it follows naturally from its domain and implementation.

BetterC MUST NOT distort an otherwise superior normal-D API unless BetterC is an explicit goal of that library.

Low-level modules or numerical kernels MAY support BetterC independently of the rest of a package.

---

# 31. Testing

Tests are part of the deliverable.

Every library MUST contain appropriate automated tests.

At minimum:

- normal behaviour,
- boundary cases,
- invalid input where relevant,
- regression tests for fixed bugs.

Depending on domain, libraries SHOULD additionally use:

- property-based tests,
- fuzzing,
- numerical reference tests,
- interoperability tests,
- large-input tests,
- cross-platform tests.

A bug fix SHOULD normally add a test that would have caught the defect.

---

# 32. Real-world fixtures

Synthetic data is necessary but not always sufficient.

Libraries dealing with real-world formats or data SHOULD include small representative fixtures where licensing permits.

Examples may include:

- geospatial files,
- raster samples,
- binary format fragments,
- malformed inputs,
- edge-case geometries.

Large datasets SHOULD normally remain outside Git.

Fixture provenance and licensing MUST be documented.

---

# 33. Documentation

Documentation is part of the library, not an optional finishing step.

Every published library SHOULD contain at least:

```text
README.md
CHANGELOG.md
ROADMAP.md
CONTRIBUTING.md
DESIGN_PRINCIPLES.md
LICENSE
```

Nontrivial libraries SHOULD additionally document relevant topics such as:

```text
docs/
├── architecture.md
├── memory-model.md
├── performance.md
└── adr/
```

Public D symbols SHOULD have useful Ddoc documentation.

Documentation SHOULD explain both:

- how the API is used,
- and why important architectural choices were made.

---

# 34. Examples

Examples SHOULD represent realistic usage rather than only trivial syntax demonstrations.

A useful example should help answer:

> How would I actually use this library in a small real program?

Examples SHOULD remain small enough to understand independently.

---

# 35. Architecture decisions

Significant design decisions SHOULD be recorded as ADRs.

An ADR is appropriate when a decision:

- materially constrains future architecture,
- chooses between significant alternatives,
- introduces or removes a major dependency,
- defines a persistent representation,
- or intentionally breaks compatibility.

ADRs SHOULD explain:

1. context,
2. decision,
3. alternatives considered,
4. consequences.

Library-specific architectural decisions belong in that library's repository.

---

# 36. External dependencies must justify themselves

Every dependency introduces:

- maintenance burden,
- supply-chain risk,
- compatibility constraints,
- packaging complexity,
- build complexity.

Dependencies SHOULD therefore provide substantial value.

Do not import a large framework for a trivial operation.

Do not reimplement a mature specialist library merely to eliminate a justified dependency.

A bounded pure-D implementation of a well-specified mathematical operation MAY nevertheless be justified when it provides substantial independent value such as:

- deployment without a native runtime;
- `@safe` / `@nogc` integration;
- transparent numerical behaviour;
- CTFE or constrained-runtime use;
- substantially simpler distribution for consumers that need only the mathematical kernel.

Such a library MUST keep its scope bounded and SHOULD validate against authoritative specifications and mature independent implementations. It SHOULD NOT duplicate large authority databases, resource ecosystems or operation-selection machinery without a compelling reason.

The trade-off MUST be evaluated in context.

---

# 37. Adapters over unnecessary coupling

When two independent libraries integrate naturally, a thin adapter is preferable to forcing either library to depend on the other unnecessarily.

Conceptually:

```text
Library A       Library B
    │               │
    └──── adapter ──┘
```

This preserves independent usability and keeps dependency graphs small.

---

# 38. No premature universality

Reusable does not mean infinitely generic.

A library SHOULD implement:

- established requirements of its domain,
- needs demonstrated by real consumers,
- abstractions supported by concrete use cases.

Speculative generalisation SHOULD be avoided.

Breadth should be earned gradually.

---

# 39. Quality over feature count

A smaller set of operations that are:

- correct,
- tested,
- documented,
- composable,
- efficient,

is preferable to a broad API containing partially implemented features.

Feature count is not a measure of maturity.

---

# 40. Replaceability

Higher-level libraries SHOULD depend on domain abstractions rather than incidental origins of data.

For example, an algorithm consuming a raster view should not care whether the pixels originated from:

- GDAL,
- PNG,
- an in-memory calculation,
- or a machine-learning output.

Likewise, geometry algorithms should not require objects to originate from one specific file format.

Replaceability improves testing, reuse, and long-term architecture.

---

# 41. Global principles versus local decisions

This document contains principles that are intended to apply across the `d-geospatial` library family.

It deliberately does **not** prescribe library-specific technical choices such as:

- a particular multidimensional-array package,
- a particular spatial index,
- a particular file-format parser,
- a particular native GIS library,
- a particular ML runtime,
- a particular GUI toolkit.

Such decisions belong in the relevant library's architecture documentation or ADRs.

This distinction is intentional:

```text
DESIGN_PRINCIPLES.md
        │
        └── shared engineering rules

library ADRs
        │
        └── concrete implementation decisions
```

---

# 42. Shared file and versioning

The workspace maintains three canonical shared documents at its root:

```text
d-geospatial/README.md
d-geospatial/ROADMAP.md
d-geospatial/DESIGN_PRINCIPLES.md
```

Each participating library repository contains the same three files at its own repository root:

```text
<library>/README.md
<library>/ROADMAP.md
<library>/DESIGN_PRINCIPLES.md
```

Within the local `d-geospatial` workspace these files are hardlinked to the canonical root copies. Git repositories still version their copies independently.

Git does not preserve hardlink relationships, so workspace tooling SHOULD restore the links after clone, checkout, or repository creation.

Changes to these shared principles SHOULD be:

1. made intentionally,
2. versioned in this document,
3. reviewed for impact on all participating libraries,
4. committed into each affected library repository.

A historical library commit must therefore retain the version of the design principles under which it was developed.

---

# 43. Deviations

A principle MAY be violated when a library has a compelling domain-specific reason.

The deviation SHOULD be documented in:

```text
docs/architecture.md
```

or an ADR.

The documentation should state:

- which principle is being deviated from,
- why,
- what alternatives were considered,
- what consequences follow.

A documented exception is preferable to forcing a poor design merely for superficial consistency.

---

# Guiding idea

The goal is **not** to make every library look identical.

The goal is to make independent D libraries whose behaviour is unsurprising because they share the same assumptions about:

- ownership,
- lifetime,
- safety,
- memory,
- errors,
- dependencies,
- interoperability,
- performance,
- testing,
- and API quality.

They should fit together naturally while remaining valuable on their own.