# ADR-0009: Polygon representation and ring composition

- Status: Accepted
- Date: 2026-09-10

## Context

`geo-d` represents variable-size linear geometry through non-owning,
read-only views.

`PolylineView` and `LinearRingView` borrow contiguous point storage from an
external owner. Their lifetime semantics are enforced through DIP1000.

A polygon introduces a second level of variable-size structure:

- one exterior ring;
- zero or more interior rings.

The polygon representation must preserve the existing view-first design,
must not require hidden allocation or copying, and must remain usable with
rings backed by independent point-storage regions.

Two principal representations were considered.

A flat representation could borrow one packed point array plus ring
boundaries or offsets.

A view-of-views representation could instead borrow a contiguous array of
`LinearRingView` descriptors, with each descriptor borrowing its own point
storage.

The latter is substantially more compositional, but it requires confidence
that nested borrowing remains safe under the lifetime model used by
`geo-d`.

Compiler probes were therefore performed with both DMD and LDC using
DIP1000.

The probes established that:

- a locally used polygon view over local ring descriptors is accepted;
- returning such a polygon when the local descriptor array would escape is
  rejected;
- assigning a ring that borrows local point storage into non-scope
  heap-backed descriptor storage is rejected;
- a polygon whose ring descriptors and point storage are both safely
  heap-backed may escape.

Both supported compilers exhibited the required behavior.

## Decision

The initial polygon representation shall be a non-owning, read-only
view-of-views.

Conceptually:

    PolygonView!T
        |
        +-- contiguous sequence of LinearRingView!T
                |
                +-- ring 0      exterior ring
                +-- ring 1..n   interior rings

The polygon view borrows the ring-descriptor sequence.

Each `LinearRingView` in that sequence independently borrows its own
contiguous point sequence.

No polygon construction step shall require repacking the points of
different rings into one common point buffer.

## Ring roles

For a polygon containing at least one ring:

    rings[0]

is the exterior ring.

All subsequent rings:

    rings[1 .. $]

are interior rings.

The representation does not infer ring role from orientation.

The order supplied by the caller is authoritative.

An empty ring-descriptor sequence represents an empty polygon.

## Ring representation

Polygon rings retain the semantics defined for `LinearRingView`.

In particular:

- closure remains implicit;
- an explicitly repeated final vertex is preserved and is not normalized
  away;
- vertex order is preserved;
- ring orientation is not normalized;
- degenerate rings remain representable;
- repeated vertices remain representable;
- zero-length segments remain representable;
- self-intersecting rings remain representable;
- non-finite coordinates remain representable where allowed by the
  underlying point and ring representation.

Polygon construction is therefore a representation operation, not a
topological-validation operation.

## Orientation

The polygon representation imposes no required winding order.

Clockwise and counter-clockwise exterior rings are both representable.

Clockwise and counter-clockwise interior rings are both representable.

Algorithms that require or interpret orientation must do so explicitly.

A future validation or normalization facility may diagnose or transform
orientation, but ordinary `PolygonView` construction shall not.

## Validity

Topological polygon validity is outside the representation invariant.

In particular, `PolygonView` does not by construction require that:

- the exterior ring is simple;
- interior rings are simple;
- interior rings lie inside the exterior ring;
- interior rings do not cross the exterior ring;
- interior rings do not intersect each other;
- rings have a minimum number of distinct points;
- rings have non-zero area;
- exterior and interior rings use opposite orientation.

These properties belong to explicit validation algorithms.

This separation permits `PolygonView` to represent imported, intermediate,
degenerate, or invalid geometry without hidden repair or information loss.

## Lifetime model

`PolygonView` follows the lifetime principles already established for
variable-size geometry.

The initial view:

- does not own ring descriptors;
- does not own point storage;
- does not allocate;
- does not deep-copy;
- does not permit mutation through the view.

The backing ring-descriptor sequence must remain valid for the complete
lifetime of the polygon view.

The point storage referenced by every contained `LinearRingView` must also
remain valid for the complete period in which that ring can be accessed
through the polygon.

The public constructor shall use the same DIP1000-oriented borrowing model
as the other variable-size views.

Compiler probes with DMD and LDC are part of the rationale for selecting
this nested-view representation.

## Storage independence

Different rings may refer to different point-storage allocations.

For example, a polygon may be assembled without copying from:

    exterior storage
    hole A storage
    hole B storage

by creating one `LinearRingView` for each storage region and then exposing
their descriptor sequence through `PolygonView`.

This capability is intentional.

A packed common point buffer is not a prerequisite for polygon geometry.

## Scalar model

`PolygonView!T` uses the scalar domain of `LinearRingView!T` and
`Point2!T`.

The representation itself does not impose additional numerical
restrictions.

Algorithms operating on polygons may support narrower scalar domains where
their numerical requirements demand it.

In particular, the existing deferral of robust `real` arithmetic remains
an algorithm-level issue rather than a polygon-representation issue.

## Initial API direction

The initial public API should remain small.

It should provide enough functionality to:

- construct a polygon view from a borrowed contiguous ring-descriptor
  sequence;
- inspect whether the polygon is empty;
- obtain the number of rings;
- access a ring by index;
- identify or access the exterior ring when present;
- iterate or otherwise access the interior-ring range without allocation.

Exact API spelling shall be chosen during implementation according to D
type and lifetime behavior.

No owning `Polygon` type is introduced by this decision.

The name `Polygon` remains available for a future owning representation if
one is justified.

## Algorithms

Polygon algorithms shall build on the existing ring abstraction rather
than introducing a second internal ring representation.

Likely subsequent operations include:

- polygon signed area;
- point-in-polygon classification;
- bounds;
- topological validation;
- orientation inspection;
- later clipping or other constructive operations.

The representation ADR does not define the numerical semantics of those
algorithms.

Algorithms requiring additional semantic decisions shall receive their own
design treatment where appropriate.

## Alternatives considered

### Flat points plus ring offsets

A polygon could borrow:

    Point2!T[] points
    size_t[] ringOffsets

This provides compact packed storage and simple direct borrow relationships.

It was not selected as the primary geometry abstraction because it would
make packed storage a requirement of polygon construction.

Independent existing rings would have to be copied or repacked before they
could be viewed as one polygon.

It would also duplicate part of the abstraction already provided by
`LinearRingView`.

A packed representation may still be introduced later as an owning,
serialization-oriented, columnar, or performance-oriented storage type.

It does not define the semantic polygon interface.

### Owning polygon

An owning polygon could own the descriptor sequence and possibly all point
storage.

This was rejected for the initial implementation because ownership policy
is not yet required by the geometry layer and would introduce allocation
and copying decisions prematurely.

The view-first model remains consistent with the rest of variable-size
`geo-d`.

### Exterior ring plus separate holes member

A polygon could store the exterior ring separately from a holes sequence.

This makes the semantic distinction explicit, but introduces special
storage and lifetime handling for the first ring.

Using one ordered ring sequence is simpler and preserves the original ring
ordering directly.

The first element already provides an unambiguous exterior-ring role.

## Consequences

The selected representation is compositional with `LinearRingView` and
allows zero-copy construction from independently stored rings.

Nested borrowing relies on DIP1000 behavior and therefore remains subject
to the same compiler and build-policy requirements as the existing
variable-size view types.

Polygon representation remains deliberately permissive. Invalid or
degenerate polygons can exist as values, while algorithms that require
valid topology must validate their preconditions explicitly.

No hidden normalization, orientation repair, allocation, or deep copy is
introduced.

Packed polygon storage remains possible in the future without changing the
semantic role of `PolygonView`.