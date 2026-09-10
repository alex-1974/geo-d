# ADR-0010: Polygon area semantics

- Status: Accepted
- Date: 2026-09-10

## Context

`LinearRingView` has an orientation-sensitive `signedArea` operation.

For a simple ring:

- counter-clockwise traversal produces positive signed area;
- clockwise traversal produces negative signed area.

`PolygonView`, however, does not infer ring roles from orientation.

By definition:

- ring 0 is the exterior ring;
- subsequent rings are interior rings.

ADR-0009 deliberately permits either winding direction for exterior and
interior rings and performs no orientation normalization.

Polygon area semantics must therefore not depend on a particular winding
convention.

The implementation must also preserve the numerical guarantees already
established for ring signed area. In particular, polygon area must not be
computed by first rounding each ring independently to binary64 and then
combining those rounded values.

## Decision

Polygon area is determined by explicit ring role.

Conceptually, the exact polygon area measure is:

    abs(exterior exact area)
        - sum(abs(interior exact area))

Ring orientation does not affect the result.

Reversing the vertex order of any individual ring therefore does not change
its contribution to polygon area.

The empty polygon has area +0.

## API direction

Polygon area shall be a distinct operation from ring `signedArea`.

The preferred public API is:

    AreaScalar!T polygonArea(T)(PolygonView!T polygon)

for the scalar types supported by exact area arithmetic.

The existing:

    signedArea(LinearRingView!T)

retains its orientation-sensitive meaning.

`polygonArea` is intentionally not named `signedArea`, because the sign of
the polygon result does not encode polygon winding.

## Numerical semantics

For `int`, `long`, `float`, and `double` input, the result type is `double`.

The exact contribution of every ring shall be retained until all exterior
and interior contributions have been combined.

Only the final polygon result is rounded to IEEE binary64.

The rounding mode is round-to-nearest, ties-to-even, independent of the
active floating-point environment.

The implementation must therefore not be equivalent to:

    abs(signedArea(exterior))
        - sum(abs(signedArea(hole)))

because that expression rounds every ring separately before combining the
results.

Instead, the implementation shall reuse or expose internal exact ring-area
accumulation so that all ring contributions are combined exactly before one
final binary64 rounding.

## Exact ring contribution

Each ring contributes the magnitude of its exact algebraic area.

For a ring whose exact twice-area determinant sum is `S`:

    exterior contribution = +abs(S)
    interior contribution = -abs(S)

The common dyadic scale is preserved during polygon accumulation.

No floating-point absolute-value operation participates in the exact
calculation.

## Orientation invariance

For a topologically valid polygon, reversing any ring changes the sign of
that ring's ordinary `signedArea`, but must not change `polygonArea`.

Thus:

    polygonArea(exterior CCW, hole CW)

and:

    polygonArea(exterior CW, hole CCW)

produce the same result.

The same remains true when only one individual ring is reversed.

## Degenerate and invalid representation

`PolygonView` remains a permissive representation.

`polygonArea` does not perform topological validation.

Degenerate rings, repeated vertices, self-intersections, overlapping holes,
holes outside the exterior ring, and other invalid polygon structures remain
representable.

For such inputs, `polygonArea` is defined as the algebraic role-based measure:

    abs(exterior algebraic area)
        - sum(abs(interior algebraic area))

It does not compute the area of the geometric union or repair invalid
topology.

Consequently, invalid polygon representations may produce a negative result
when the summed interior-ring magnitudes exceed the exterior-ring magnitude.

The result is not clamped to zero.

A negative result therefore does not represent a valid geometric polygon
area; it is the exact role-based measure of the supplied representation.

Topological validation remains a separate operation.

## Self-intersecting rings

A self-intersecting ring retains the algebraic cancellation semantics of
ring signed area.

Its polygon contribution is the magnitude of that exact algebraic result.

No decomposition into simple components is performed.

## Non-finite coordinates

If any ring contains a non-finite coordinate, `polygonArea` returns NaN.

This applies even when that ring is degenerate or its algebraic contribution
would otherwise cancel.

## Overflow and underflow

Finite input coordinates may produce a polygon result whose magnitude is too
large for binary64.

In that case the correctly rounded result may be positive or negative
infinity according to the exact role-based result.

A sufficiently small non-zero exact result may round to signed zero.

Exact zero shall produce positive zero.

A rounded zero result does not imply that the exact polygon measure was zero.

## Complexity and allocation

`polygonArea` shall be:

- O(total number of stored ring vertices);
- allocation-free;
- bounded in auxiliary storage;
- `pure`;
- `nothrow`;
- `@safe`;
- `@nogc`.

No point or ring data is copied.

## Implementation direction

The existing ring-area implementation should be refactored so that its exact
triangle-fan accumulation is available internally without performing the
final binary64 rounding.

Conceptually:

    exactRingArea(ring)
        -> signed exact dyadic accumulator

Then:

    signedArea(ring)
        -> exactRingArea(ring)
        -> round once

and:

    polygonArea(polygon)
        -> exactRingArea(exterior)
        -> absolute exact magnitude
        -> subtract absolute exact magnitude of every hole
        -> round once

This refactoring must not change the existing public `signedArea` semantics.

## Alternatives considered

### Sum ring signed areas

An orientation-sensitive formulation:

    sum(signedArea(ring))

was rejected.

It would require a winding convention for exterior and interior rings,
contradicting ADR-0009.

It would also make polygon area change when an otherwise identical ring is
reversed.

### Sum absolute rounded ring areas

Computing:

    abs(signedArea(exterior))
        - sum(abs(signedArea(hole)))

was rejected as the numerical model.

Each ring would be rounded independently before combination, permitting
double-rounding and cancellation errors that are avoidable with the existing
exact arithmetic infrastructure.

### Normalize ring orientation first

Automatically reversing rings into a conventional winding order was rejected.

`PolygonView` is a non-owning representation and performs no hidden
normalization or copying.

Orientation normalization, if ever required, belongs to a separate explicit
operation.

### Clamp negative results to zero

Clamping was rejected because it would hide information about invalid input
and would silently turn an exact algebraic result into a repaired value.

Validation and repair remain separate concerns.

## Consequences

Polygon area is invariant under ring reversal while ring `signedArea`
remains orientation-sensitive.

The exterior/interior distinction already encoded by `PolygonView` becomes
the sole source of polygon ring role.

The exact-area implementation will need a small internal refactoring so ring
accumulators can be reused before final rounding.

No new approximate arithmetic path is introduced.

Valid polygons produce the conventional non-negative polygon area.

Invalid polygon representations remain deterministic and may produce
negative role-based measures rather than being silently normalized or
rejected.