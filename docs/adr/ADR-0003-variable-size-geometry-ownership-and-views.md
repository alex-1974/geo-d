# ADR-0003: Variable-size geometry ownership and views

**Status:** Accepted  
**Date:** 2026-09-10

## Context

The initial geo-d foundation consists of fixed-size value types such as
Point2, Vector2, Bounds2 and Segment2.

The next geometry layer requires variable-size sequences of points,
starting with polylines and later extending to linear rings and
polygons.

Variable-size geometry introduces ownership and lifetime questions that
do not exist for the fixed-size types:

- who owns the point storage;
- whether constructing a geometry copies its input;
- whether copying a geometry copies or aliases its storage;
- whether algorithms require allocation;
- whether geometry may refer to externally owned storage;
- how mutation and aliasing are exposed;
- how borrowed data can be processed without hidden copies;
- how lifetime requirements are represented in the public API.

D dynamic arrays are slices and therefore naturally support efficient
views, but a slice by itself does not express geometric meaning or
ownership semantics.

Introducing an owning Polyline type immediately would additionally force
geo-d to choose an allocation and copy model before such a model is
required by a concrete consumer.

The workspace design principles prefer explicit ownership and lifetime,
views before copies, no hidden deep copies or allocations, and @nogc
interfaces where those contracts are real.

## Decision

### View-first variable-size geometry

The first variable-size geometry abstraction shall be a non-owning,
read-only PolylineView.

PolylineView represents a contiguous ordered sequence of Point2 values
owned by some external storage.

Creating or copying a PolylineView shall:

- not allocate;
- not copy point data;
- not transfer ownership;
- preserve the original point order.

Copying a PolylineView copies only the view descriptor. Both copies
refer to the same underlying point sequence.

### Read-only geometry views

PolylineView shall not permit mutation of the referenced points through
the view.

The initial API shall not introduce a mutable polyline view.

If future algorithms require in-place mutation, mutable views shall be
designed explicitly rather than weakening the read-only semantics of the
basic geometry view.

### Lifetime

The storage referenced by a PolylineView must remain valid for the
entire lifetime of the view and every operation using it.

The caller retains ownership of that storage.

D lifetime annotations such as scope and return shall be used where
they correctly strengthen this contract and are supported by the
required compilers.

The published geo-d package does not require consumers to enable DIP1000
package-wide. These escape relationships are compiler-enforced in dedicated
positive/negative compile fixtures run explicitly with `-preview=dip1000`.

The initial `PolylineView` lifetime model was verified with both DMD
and LDC: a local backing array may be viewed within its lifetime, while
returning a view that refers to local stack storage is rejected in
`@safe` code.

Such annotations must be verified with DMD and LDC before being treated
as part of the public safety contract.

The implementation shall not use raw pointers merely to circumvent
slice lifetime rules.

### Contiguous storage

The initial PolylineView represents contiguous Point2 storage.

This matches D slices directly and provides:

- constant-time indexed access;
- cache-friendly sequential traversal;
- allocation-free subviews;
- simple interoperability with existing arrays and slices;
- straightforward segment iteration.

Supporting arbitrary ranges, linked structures or callback-backed point
sources is outside the initial scope.

Algorithms requiring such inputs may materialize or adapt them outside
geo-d.

### Valid polyline sizes

A PolylineView may contain any number of points.

In particular:

- zero points represent an empty polyline;
- one point represents a singleton polyline;
- two or more points define one or more consecutive segments.

This keeps the representation total and avoids hidden validation during
view construction.

Algorithms shall define their natural result for empty and singleton
inputs where possible.

For example, a polyline containing fewer than two points has zero
segments and zero geometric length.

Algorithms that genuinely require a stronger precondition shall state
that precondition explicitly.

### Exact sequence semantics

PolylineView is an ordered geometry.

Equality, if exposed, shall compare the point sequences by:

- equal length;
- equal points at corresponding positions;
- the exact scalar equality semantics already defined by geo-d.

Storage identity is not geometric equality.

No tolerance or implicit epsilon is introduced.

### Scalar model

PolylineView shall use the existing geo-d scalar policy.

The view representation itself may support every scalar accepted by the
core Point2 type.

Individual algorithms may support a narrower scalar domain when their
numerical backend requires it.

For example, robust predicates may continue to defer real even though a
PolylineView!real can represent point storage.

### Algorithms consume views

Variable-size read-only algorithms should primarily operate on geometry
views rather than owning containers.

Where appropriate, such algorithms should remain:

- pure;
- nothrow;
- @safe;
- @nogc.

Algorithms shall not make hidden defensive copies of view storage.

If an operation requires temporary allocation, that fact must be
explicit in its API and documentation.

### Subviews

A contiguous subsequence of a PolylineView may itself be represented as
a PolylineView without allocation or copying.

Subview semantics shall preserve the same external ownership and
lifetime requirements as the original view.

### Owning Polyline is deferred

The name Polyline is reserved for a possible future owning geometry
type.

It shall not be introduced merely as a wrapper around a mutable D
dynamic array.

Before an owning Polyline is added, geo-d must explicitly decide:

- allocation strategy;
- ownership transfer rules;
- copy semantics;
- move semantics where relevant;
- mutability;
- whether copies share or duplicate storage;
- construction from external slices;
- whether construction may allocate;
- conversion to PolylineView;
- interaction with @nogc code.

In particular, construction from an arbitrary point slice must not
perform an undocumented deep copy.

An owning type may later use GC-managed immutable storage, explicit
allocation, reference counting or another strategy, but that choice is
not made by this ADR.

### LinearRing and Polygon

LinearRing should follow the same view-oriented ownership model where
practical.

However, ring-specific questions are separate from storage ownership,
including:

- implicit versus explicitly duplicated closure;
- minimum vertex count;
- treatment of degenerate rings;
- canonical representation;
- orientation conventions.

Those semantics shall be fixed before LinearRing becomes a stable public
type.

Polygon representation shall follow both the variable-size ownership
decision and the later LinearRing decision.

Polygon shall therefore not precede the view and ring foundations.

## Initial API direction

The initial implementation should remain deliberately small.

PolylineView is expected to provide only the basic operations needed to
act as a geometry view, such as:

- construction from compatible contiguous point storage;
- length;
- empty;
- indexed read access;
- access to the read-only vertex sequence where lifetime semantics
  remain explicit;
- segment count.

Additional convenience API should be added only when required by actual
algorithms or consumers.

A deduction helper may be provided if it materially improves ordinary D
usage without obscuring ownership semantics.

## Consequences

### Positive

Variable-size algorithms can operate directly on existing point storage
without allocation.

Ownership remains outside the geometry view and is therefore explicit.

The core algorithms can remain usable in @nogc contexts.

Large geometries can be passed and copied cheaply because only the view
descriptor is copied.

Sub-geometries can be represented without allocation.

The design does not prematurely commit geo-d to the D garbage collector,
reference counting or a custom allocator.

### Negative

PolylineView does not own its data and therefore cannot by itself keep
externally managed storage alive.

Users must understand the lifetime relationship between a view and its
backing storage.

A persistent owning geometry remains unavailable until its ownership
model is designed separately.

Some APIs accepting arbitrary ranges will require adaptation to
contiguous point storage.

### Neutral

The view type has value semantics as a descriptor but reference
semantics with respect to its backing storage.

This distinction is intentional and must remain explicit in
documentation.

## Alternatives considered

### Introduce an owning dynamic-array Polyline immediately

Rejected for the initial implementation.

A D dynamic array aliases its backing storage when copied. Wrapping one
without an explicit ownership policy would make the type appear more
value-like than its storage semantics actually are.

Making construction always deep-copy would instead introduce hidden
allocation unless every copying operation were explicit.

### Use bare point slices as the public geometry API

Rejected.

Slices already provide the required low-level representation but do not
communicate that the sequence is a polyline or provide a stable place
for geometry-specific invariants and operations.

A distinct PolylineView keeps geometry semantics explicit while
remaining lightweight.

### Require at least two points

Rejected.

Empty and singleton sequences are useful intermediate states and have
well-defined behaviour for many algorithms.

Rejecting them would add validation and exceptional construction paths
without strengthening the storage model.

Algorithms that require at least one segment can state that
precondition themselves.

### Provide mutable and immutable views immediately

Rejected.

Read-only views cover the initial geometry algorithms and provide a
simpler aliasing contract.

Mutable views should be introduced only when a concrete in-place
algorithm requires them.

## Implementation sequence

1. Implement the minimal PolylineView representation.
2. Verify lifetime and safety behaviour with DMD and LDC.
3. Add deterministic unit tests for empty, singleton and multi-point
   views.
4. Add allocation-free segment traversal or equivalent minimal support.
5. Implement polyline length using the existing metric layer.
6. Define LinearRing representation and closure semantics.
7. Implement signed area.
8. Revisit an owning Polyline only when a concrete ownership use case
   requires it.
9. Design Polygon only after the ring and ownership models are stable.

## Revisit conditions

This ADR should be revisited if:

- a major consumer requires geo-d to own variable-size geometry;
- non-contiguous geometry becomes a common requirement;
- D lifetime annotations prove insufficient for the intended safe view
  API;
- mutable in-place geometry algorithms become important;
- the chosen view representation prevents required interoperability.
