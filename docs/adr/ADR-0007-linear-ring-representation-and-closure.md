# ADR-0007: Linear Ring Representation and Closure Semantics

**Status:** Accepted
**Date:** 2026-09-10

## Context

ADR-0003 establishes a view-first model for variable-size geometry.

`PolylineView` is the first implementation of that model. It provides a
non-owning, read-only view over contiguous `Point2` storage, with lifetime
relationships enforced through DIP1000.

A linear ring has similar storage requirements, but its geometry introduces
additional semantic questions that must be decided before implementation:

- whether closure is stored explicitly or implied;
- whether the first vertex may be repeated as the final stored vertex;
- how empty and degenerate rings behave;
- how segments are enumerated;
- whether traversal orientation is normalized;
- whether cyclic rotations or reversals are considered equal;
- whether ring simplicity is a representation invariant.

These decisions affect later signed-area and polygon APIs.

## Decision

### 1. Use a non-owning read-only view

The initial ring abstraction will be:

    LinearRingView!T

It will follow the ownership and lifetime model established for
`PolylineView`.

Its backing storage is a contiguous ordered sequence of `Point2!T` values
owned externally.

The view:

- does not allocate;
- does not copy point data;
- does not transfer ownership;
- does not permit mutation through the view;
- aliases the caller's backing storage;
- requires the backing storage to remain valid for the lifetime of the view.

The initial representation is expected to use:

    const(Point2!T)[]

with the same compiler-enforced DIP1000 lifetime model used by
`PolylineView`.

An owning `LinearRing` type is not introduced by this ADR.

### 2. Closure is implicit

The stored point sequence contains the vertices of the ring.

The first vertex is not repeated merely to encode closure.

For stored vertices:

    A, B, C

the represented closed traversal is:

    A -> B
    B -> C
    C -> A

The closing segment from the final stored vertex to the first stored vertex
is therefore implicit.

This avoids storing one logical vertex twice and gives the ring a direct
cyclic representation.

### 3. Construction does not normalize the supplied sequence

`LinearRingView` is a view, not an input-normalization facility.

It does not:

- remove a repeated final vertex;
- reorder vertices;
- reverse traversal;
- rotate the starting vertex;
- remove duplicate vertices;
- remove collinear vertices.

If the caller supplies:

    A, B, C, A

all four points are stored vertices of the view.

The final `A` is therefore an actual repeated vertex, not a special closure
marker. The implicit closing segment is still formed from that final vertex
back to the first vertex.

Adapters for external formats that use explicitly repeated closure
coordinates should remove that representation-specific closing coordinate
before constructing the canonical geo-d ring view.

Such format adaptation does not belong in `geo-d`.

### 4. Degenerate rings remain representable

The type does not require a geometrically valid simple ring.

Any number of stored vertices is representable.

The structural semantics are:

- zero vertices: empty ring, zero segments;
- one vertex: one degenerate segment from the vertex to itself;
- two vertices: two opposite directed segments;
- three or more vertices: one closing cyclic segment per stored vertex.

Therefore:

    segmentCount == 0                 when length == 0
    segmentCount == length            when length > 0

This keeps the ring representation total and avoids embedding polygon
validity rules into the storage abstraction.

A geometrically useful non-degenerate ring normally requires stronger
conditions, but those conditions belong to validation or algorithms rather
than to the basic view type.

### 5. Segment indexing follows stored traversal order

For a non-empty ring with `n` stored vertices, segment `i` is:

    points[i] -> points[(i + 1) % n]

for:

    0 <= i < n

The final segment therefore closes the ring.

Segment order preserves the traversal order supplied by the caller.

No segment range abstraction is required initially. Indexed segment access
is sufficient for the first implementation and for signed-area evaluation.

### 6. Traversal orientation is preserved

`LinearRingView` does not impose clockwise or counter-clockwise orientation.

The order supplied by the caller is preserved exactly.

The library will not automatically reverse a ring.

This is important because later signed-area computation must retain the sign
associated with traversal orientation.

Any API that explicitly requests orientation normalization must be a
separate operation with explicit semantics.

### 7. Stored-sequence identity remains distinct from geometric equivalence

The initial type does not define cyclic or orientation-independent geometric
equivalence.

The following sequences are distinct stored representations:

    A, B, C
    B, C, A
    A, C, B

even where they trace the same geometric boundary up to rotation or
reversal.

No automatic canonical starting vertex is selected.

If cyclic-equivalence or reversal-equivalence is required later, it will be
provided as an explicit algorithm rather than hidden inside the basic value
semantics.

Exact coordinate equality remains the geo-d default. No epsilon is
introduced.

### 8. Simplicity is not a representation invariant

A `LinearRingView` may contain:

- repeated vertices;
- zero-length segments;
- collinear vertices;
- self-intersections;
- non-finite coordinates where the underlying `Point2` representation
  permits them.

The view itself only represents an ordered cyclic sequence.

Properties such as:

- simplicity;
- non-degeneracy;
- finite coordinates;
- minimum distinct vertex count;
- non-zero area;

are algorithmic or validation concerns.

This preserves the distinction between representation and geometric
validity.

### 9. Scalar domain follows Point2

`LinearRingView!T` uses the same scalar domain as `Point2!T`:

    int
    long
    float
    double
    real

Individual algorithms may support a narrower scalar domain where their
numerical contracts require it.

The view representation itself does not narrow that domain.

### 10. Initial API remains minimal

The first implementation should expose only the operations required to
establish the representation:

    construction from compatible contiguous storage
    length
    empty
    indexed point access
    segmentCount
    indexed segment access

No mutable ring view is introduced.

No allocation, normalization, validation, range abstraction, or owning
container is introduced.

## Consequences

### Positive

The representation is compact and allocation-free.

There is no duplicated closure coordinate in the canonical geo-d
representation.

Traversal orientation remains explicit and observable.

Signed-area computation can operate directly on the cyclic sequence without
special treatment of a stored closing duplicate.

Degenerate input remains representable, allowing validation to remain
separate from storage.

The model aligns closely with `PolylineView` and therefore keeps the
variable-size API conceptually small.

### Negative

External formats that explicitly repeat the first coordinate at the end of a
ring require an adapter before using the canonical geo-d representation.

Two rings that trace the same boundary with different starting vertices are
not automatically considered equivalent.

The representation permits geometrically invalid rings.

Users requiring valid polygon boundaries must therefore invoke appropriate
validation once such functionality exists.

## Rejected alternatives

### Explicitly store the closing vertex

Rejected because it duplicates one logical vertex and makes segment and
vertex counts representation-dependent.

### Silently trim a repeated final vertex

Rejected because a view should not silently reinterpret or normalize the
supplied storage.

Normalization belongs in an explicit conversion or adapter.

### Require at least three vertices

Rejected because minimum geometric validity is not a necessary storage
invariant.

Allowing degenerate values keeps the type total and consistent with other
geo-d primitives.

### Reject self-intersecting or repeated-vertex rings during construction

Rejected because such validation is algorithmic, potentially more
expensive, and independent of ownership/view semantics.

### Automatically normalize orientation

Rejected because traversal direction is meaningful and later determines the
sign of signed area.

### Treat cyclic rotations as ordinary equality

Rejected for the initial representation because doing so would introduce
non-trivial geometric equivalence semantics into a small storage view.

## Follow-up

After this ADR is accepted:

1. implement the minimal `LinearRingView`;
2. verify lifetime behaviour with DMD and LDC;
3. test empty, singleton, two-vertex and ordinary rings;
4. test implicit closing segment construction;
5. test zero-copy aliasing and read-only access;
6. implement signed area as a separate algorithmic slice;
7. define ring validity predicates only when required by a concrete
   consumer;
8. define Polygon only after ring representation and validity requirements
   are sufficiently understood.

The numerical follow-up already recorded for polyline-length accumulation
remains independent of this decision.
