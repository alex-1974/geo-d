# Structured 2D shapes — v4 design slice

Status: accepted v4 first slice; Dunia consumer validation remains deferred.

## Goal

Make structured Euclidean shapes a first-class v4 design direction for
`geo-d`, with Dunia as the first intended consumer. A structured shape keeps
its natural invariants and is lowered to a ring or polygon only when a
consumer needs discrete boundary geometry.

The first vertical slice is `Circle2`; the second slice adds axis-aligned
`Rect2` and fixed-cardinality `Triangle2`. `RegularPolygon2!(T, N)` is now
admitted as the fixed-cardinality regular-shape slice. Oriented rectangles,
`Ellipse2`, and `Arc2` remain deliberately staged.

## Canonical local vertices and placement

Shapes are defined without world coordinates or world orientation. Whenever a
shape has discrete vertices, it nevertheless has a canonical local frame so
that construction, vertex access, placement and polygonization use the same
nomenclature.

The library does not require alphabetic vertex names in the API. The normative
form is `vertex(1)`, `vertex(2)`, `vertex(3)`, and so on. If a mathematical
description uses `A`, `B`, `C`, those names mean `vertex(1)`, `vertex(2)`,
`vertex(3)` respectively. Internal arrays may remain zero-based.

The documentation follows the established mathematical notation convention:
vertices are written with upper-case Latin letters (`A`, `B`, `C`, ...), while
edges or triangle sides are written with lower-case letters or endpoint pairs
(`a`, `b`, `c`, `AB`, `BC`, ...). In a triangle, the lower-case side name is
opposite the corresponding upper-case vertex when that notation is used.
These are documentation labels; the code-level API remains explicit through
`vertex(index)` and names such as `length.ab`.

This follows the usual school and engineering geometry notation and the
lettering/typography principles of DIN 1338. DIN 1338 governs mathematical
formula notation and typesetting; it does not by itself prescribe one universal
vertex ordering for every geometric software model. geo-d therefore makes the
local start vertex and traversal direction explicit for each shape family.

For 2D shapes, the canonical order is counter-clockwise in the local frame.
The first vertex and local axes are shape-specific and are part of the public
contract:

- `Rect2`: `vertex(1)` is the local `(-x, -y)` corner; the following vertices
  are `(+x, -y)`, `(+x, +y)`, and `(-x, +y)`;
- `Triangle2`: the local origin is the first vertex, the second vertex lies on
  the positive local X axis, and the third lies on the positive local side of
  that directed edge;
- `RegularPolygon2`: `vertex(1)` lies on the local positive X axis and the
  remaining vertices advance counter-clockwise by `2π / N`;
- `Circle2`: the only intrinsic anchor is its centre; a polygonization segment
  count determines the discrete approximation and its first vertex follows
  the documented local positive-X convention.

Placement maps this canonical local frame to a target coordinate system. It
does not change the intrinsic shape parameters. A screen coordinate system
with a downward Y axis must therefore apply an explicit reflection or
orientation transform; it must not silently reinterpret the canonical order.

The future 3D contract follows the same principle. Vertices remain indexed in
the local frame, while axis-extreme names such as local min/max X, Y and Z
are used to explain box vertices; view-dependent names such as
`topLeftFront` are not normative.

For layered 3D bodies such as prisms and boxes, the documentation may use the
standard mathematical layering convention: the base layer is labelled first
(`A`, `B`, `C`, `D`, ...), the corresponding parallel layer follows in the
same order (`E`, `F`, `G`, `H`, ...), and corresponding vertices are connected
(`A-E`, `B-F`, ...). A distinguished apex is documented as `S` when a shape
family has one. This convention does not replace the indexed API and is not
applied to arbitrary polyhedra without a shape-specific contract.

## First slice: `Circle2`

Conceptual representation:

```d
struct Circle2(T)
{
    Point2!T center;
    T radius;
}
```

The representation is a compact value type with no allocation and no hidden
polygon storage. The accepted public spelling is documented by ADR-0025.

### Required contract

- supported scalar domains are decided explicitly; integral radii are valid
  only if the derived operations have a documented computation policy;
- radius must be finite and non-negative for a successful checked
  construction;
- NaN and non-finite center/radius inputs are rejected unless a later design
  explicitly defines a different analytic policy;
- zero radius is a valid degenerate circle only if containment, bounds and
  lowering semantics are specified consistently;
- equality is exact value equality; no global epsilon is introduced;
- all direct value/property operations are `@safe`, `nothrow`, `@nogc` and
  allocation-free where the existing scalar contract permits;
- checked construction must distinguish invalid input from an unrepresentable
  derived result where that distinction matters.

## Initial operations

The first API review should cover only operations justified by the invariant
representation:

- center and radius access;
- diameter;
- axis-aligned bounds;
- area and circumference with an explicit computation-scalar policy;
- point containment/classification with an explicit boundary policy;
- closest point or distance only if Dunia's first workflow needs it;
- explicit lowering to a polygon/ring approximation.

No generic curve hierarchy, implicit tolerance, or automatic polygonization is
part of the first slice.

## Polygonization

Lowering must be visibly approximate. Candidate forms are separate overloads
or a small policy value, for example:

```d
toPolygon(circle, SegmentCount(64));
toPolygon(circle, MaximumRadialError!double(0.01));
```

The exact API must document:

- whether the result is inscribed, circumscribed, or otherwise bounded;
- starting angle and winding order;
- treatment of zero radius;
- minimum segment count and overflow/representability failure;
- output ownership and allocation;
- whether the result is a `LinearRing`/polygon view or an owning result.

The approximation criterion must never be hidden behind an exact-looking
conversion.

## Rectangle relationship

`Bounds2` already represents axis-aligned closed bounds and must not be
duplicated as a nominal `Rect2` without additional invariants or operations.
The design gate should compare:

- axis-aligned rectangle as a semantic shape;
- `Bounds2` as an envelope/query primitive;
- oriented rectangle as a distinct candidate if Dunia needs rotation.

The axis-aligned slice does not resolve the separate oriented-rectangle
question or replace the #172 contract review.

The current `Rect2` slice is intentionally axis-aligned and constructed from
finite minimum/maximum corners. It adds rectangle semantics—width, height,
centre, area, perimeter, containment, bounds and ordered corners—without
replacing `Bounds2` as the envelope primitive. Oriented rectangles remain a
separate future contract.

## Triangle2 slice

`Triangle2!T` stores exactly three finite points and keeps degenerate
collinear input representable. It provides point access, absolute area,
axis-aligned bounds and caller-owned point export. Non-degenerate triangle
predicates, centres and construction families require a later numerical
decision rather than being implied by the value type.

## RegularPolygon2 slice

`RegularPolygon2!(T, N)` is an analytic regular polygon with compile-time
cardinality. It stores only centre, circumradius and starting rotation; it
does not store a polygonal ring. Vertices are emitted explicitly into
caller-owned `Point2!(MetricScalar!T)[]` storage in counter-clockwise order.
`N` must be at least three.

The general type is supplemented by `Pentagon2`, `Hexagon2`, `Heptagon2` and
`Octagon2` aliases. This type is distinct from `Polygon2View`: the latter is
the general variable-size polygon representation and does not imply regularity.

## Dunia vertical slice

Dunia must provide one concrete workflow before production promotion, such as
creating or editing a circular feature. The consumer record must identify:

- input interaction and branch/selection policy;
- whether the editor stores `Circle2` or immediately lowers to polygon data;
- required precision and approximation criterion;
- ownership and mutation boundary;
- failure/degeneracy presentation;
- whether direct analytic operations avoid unnecessary polygonization.

Dunia policy and UI state remain outside `geo-d`; `geo-d` supplies only the
Euclidean value, operations, and explicit lowering.

## Gates

1. Accept the scalar, validity, boundary, area/circumference and lowering
   contracts in an ADR or equivalent design decision.
2. Add independent unit/property tests for invariants, transformations,
   degenerate inputs, finite-value boundaries and lowering determinism.
3. Add DMD/LDC consumer probes and a Dunia integration fixture.
4. Benchmark direct analytic operations separately from polygonization and
   compare allocations and result consumption.
5. Promote only the smallest accepted API; keep the remaining family in
   research.

## Staged family decision

| Candidate | v4 decision |
|---|---|
| `Circle2` | first implementation slice |
| axis-aligned `Rect2` | implemented second slice; refine against `Bounds2`/#172 |
| oriented rectangle | admit only with Dunia need |
| `Triangle2` | implemented minimal value slice; derived centres/constructions deferred |
| `Ellipse2` | research/deferred |
| `Arc2` | research/deferred |
| `RegularPolygon2!(T, N)` | implemented fixed-cardinality regular shape |
