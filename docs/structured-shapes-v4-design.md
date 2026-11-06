# Structured 2D shapes — v4 design slice

Status: design proposal; no public API is admitted by this document alone.

## Goal

Make structured Euclidean shapes a first-class v4 design direction for
`geo-d`, with Dunia as the first intended consumer. A structured shape keeps
its natural invariants and is lowered to a ring or polygon only when a
consumer needs discrete boundary geometry.

The first vertical slice is `Circle2`. The family is deliberately staged:
`Rect2`/oriented rectangles, `Triangle2`, `Ellipse2`, `Arc2`, and persistent
regular polygons require separate evidence and contracts.

## First slice: `Circle2`

Conceptual representation:

```d
struct Circle2(T)
{
    Point2!T center;
    T radius;
}
```

The final field visibility, constructor spelling, and result types remain API
design decisions. The representation must be a compact value type with no
allocation and no hidden polygon storage.

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

No rectangle implementation is admitted before this comparison and #172 are
resolved.

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
| axis-aligned `Rect2` | resolve against `Bounds2`/#172 |
| oriented rectangle | admit only with Dunia need |
| `Triangle2` | follow-up design slice |
| `Ellipse2` | research/deferred |
| `Arc2` | research/deferred |
| persistent `RegularPolygon2` | construction family first, type deferred |
