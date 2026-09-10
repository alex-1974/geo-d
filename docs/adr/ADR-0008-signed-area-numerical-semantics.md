# ADR-0008: Signed Area Numerical Semantics

**Status:** Accepted
**Date:** 2026-09-10

## Context

ADR-0007 defines `LinearRingView` as an ordered cyclic sequence with
implicit closure.

The next required algorithm is signed planar area.

The familiar shoelace expression is:

    2 A = sum(x_i * y_(i+1) - y_i * x_(i+1))

but a direct implementation is not sufficient for geo-d.

In particular:

- multiplication in `int` or `long` may overflow before conversion;
- converting integer coordinates before multiplication loses information;
- floating-point coordinate products may overflow even where translated
  geometry is well-conditioned;
- large coordinate offsets can introduce avoidable cancellation;
- ordinary or compensated floating-point summation still rounds every term;
- a rounded area result must not silently become a robustness predicate.

geo-d already contains exact fixed-width dyadic arithmetic for finite
`int`, `long`, `float` and `double` coordinates. It is used by robust
orientation and segment-intersection construction.

Signed area should build on the same numerical model.

## Decision

### 1. Provide signed algebraic area

The initial public operation will conceptually be:

    AreaScalar!T signedArea(T)(LinearRingView!T ring)

The result represents the algebraic signed area of the stored cyclic
traversal.

For a simple non-degenerate ring in the usual Cartesian coordinate system:

- counter-clockwise traversal has positive area;
- clockwise traversal has negative area.

Reversing traversal negates the exact signed area.

No automatic orientation normalization is performed.

### 2. Define a dedicated area result scalar

The initial supported input scalar domain is:

    int
    long
    float
    double

For all four input types:

    AreaScalar!T == double

`real` is deliberately deferred.

This mirrors the existing decision to defer robust exact processing of
`real` until a platform-aware backend is available.

The representation type `LinearRingView!real` remains valid; only this
algorithm is initially unavailable for it.

`AreaScalar` is a semantic area API concept and must not reuse an unrelated
alias merely because its current type mapping happens to be identical.

### 3. Define the mathematical result before defining the implementation

For a ring with vertices:

    p_0, p_1, ..., p_(n-1)

and `n >= 3`, define twice the signed area as the exact triangle-fan sum:

    2 A =
        sum(
            det(
                p_i - p_0,
                p_(i+1) - p_0
            )
        )

for:

    i = 1 .. n - 2

This is algebraically equivalent to the closed shoelace formula.

The formulation is useful because each term is exactly the same
two-dimensional determinant already represented by geo-d's exact
orientation arithmetic.

For:

    n == 0
    n == 1
    n == 2

the exact signed area is zero.

Repeated vertices and zero-length segments contribute naturally according
to the same formula.

An explicitly repeated final vertex is not treated specially. ADR-0007
continues to define it as an ordinary stored vertex.

### 4. Compute the finite supported-domain result exactly before rounding

For finite coordinates in the supported scalar domain, the semantic result
is obtained as though:

1. every coordinate were interpreted exactly;
2. every determinant term were computed exactly;
3. all determinant terms were summed exactly;
4. the exact sum were divided by two exactly;
5. the final mathematical area were rounded once to binary64.

No intermediate floating-point rounding is part of the semantic contract.

For binary64 output, final rounding is:

    round to nearest, ties to even

and must not depend on the process floating-point rounding environment.

This gives `signedArea()` a deterministic numerical meaning independent of
the particular evaluation order chosen by a compiler.

### 5. Reuse exact dyadic determinant semantics

For:

    int
    long
    float
    double

each finite coordinate is exactly representable by the existing dyadic
coordinate model.

Each triangle-fan determinant is therefore an exact signed dyadic value.

The implementation should reuse the existing exact determinant machinery
rather than perform coordinate products in the public input scalar type.

This prevents signed integer overflow and avoids loss of information from
premature conversion to `double`.

### 6. Accumulate the complete area exactly

The implementation must not merely round every exact determinant to
`double` and then sum those rounded values.

It must preserve the exact signed determinant sum until the final area
rounding step.

A bounded fixed-width accumulator is feasible because:

- every exact determinant has a statically bounded magnitude;
- a D slice contains at most `size_t.max` elements;
- the additional accumulation width required by an arbitrary view length is
  therefore statically bounded as well.

The required accumulator width is statically bounded.

`orientationDeterminantDyadic()` stores every exact determinant magnitude
in `dyadicProductLimbs` 32-bit limbs. Therefore each magnitude is strictly
smaller than:

    2^(32 * dyadicProductLimbs)

A ring view cannot contain more than `size_t.max` vertices. Consequently
the absolute sum of all triangle-fan determinants is strictly smaller than:

    2^(32 * dyadicProductLimbs + size_t.sizeof * 8)

A sufficient compile-time accumulator width is therefore:

    areaAccumulatorExtraLimbs =
        ceil((size_t.sizeof * 8) / 32)

    areaAccumulatorLimbs =
        dyadicProductLimbs +
        areaAccumulatorExtraLimbs

On a 64-bit target this gives:

    132 determinant limbs
      2 accumulation limbs
    ---
    134 accumulator limbs

or 4288 bits.

This bound is independent of the actual ring length and therefore permits
allocation-free exact accumulation with fixed inline storage.

The determinant sum is represented in units of `2^-2148`. Division by two
does not require integer division: the same exact integer magnitude can be
interpreted directly in units of `2^-2149` for the final area.

The precise internal accumulator representation is an implementation
detail and may change without affecting the public API.

No heap allocation is required by this numerical contract.

### 7. Compensated summation is not the semantic model

Kahan, Neumaier, pairwise, or other compensated floating-point summation
may be useful implementation techniques for a future certified fast path.

They do not define the result.

The reference semantic result remains the exact algebraic area rounded once
to `AreaScalar!T`.

A future optimization may use floating-point arithmetic when it can
certify that it produces the same correctly rounded result and fall back to
the exact path otherwise.

This separates numerical semantics from implementation performance.

### 8. Preserve correct signed-zero behaviour

If the exact area is zero, the result is positive zero.

If a non-zero exact area is too small in magnitude to produce a non-zero
binary64 result, correctly rounded signed zero is preserved:

- tiny positive exact area may produce `+0.0`;
- tiny negative exact area may produce `-0.0`.

This follows the final correctly-rounded numerical construction semantics.

### 9. A rounded area is not a robustness predicate

`signedArea()` must not be used internally as the authoritative test for:

- exact zero area;
- ring degeneracy;
- clockwise versus counter-clockwise traversal;
- polygon validity.

For floating-point input, an exactly non-zero area can round to zero.

Therefore:

    signedArea(ring) == 0

does not imply that the exact algebraic area is zero.

If geo-d later requires an exact area-sign or ring-orientation predicate,
that operation must use exact predicate semantics and expose a separate API.

This follows the existing geo-d distinction between robust predicates and
rounded geometric constructions.

### 10. Self-intersecting rings produce algebraic signed area

`LinearRingView` does not require simplicity.

For self-intersecting traversal, `signedArea()` returns the algebraic signed
area defined by the exact cyclic determinant sum.

Different lobes may therefore contribute with opposite signs and cancel.

The result must not be interpreted as the unsigned area of the geometric
set enclosed by arbitrary invalid linework.

Polygon validity and repair remain separate concerns.

### 11. Non-finite coordinates produce NaN

`Point2!float` and `Point2!double` may represent NaN and infinity.

If any stored coordinate in a ring is non-finite, `signedArea()` returns
`double.nan`.

The operation does not attempt to assign geometric area semantics to
non-finite coordinates.

This keeps the public function total without introducing hidden validation,
exceptions, or allocation.

Empty rings contain no non-finite coordinates and therefore return positive
zero.

### 12. Finite coordinates do not imply a finite double result

The exact area of finite binary64 coordinates can exceed the finite
binary64 result range.

If correct final rounding overflows the `AreaScalar` range, the result may
therefore be positive or negative infinity.

This is distinct from non-finite input, which produces NaN.

### 13. Preserve the geo-d execution contracts

The initial implementation should remain:

    pure
    nothrow
    @safe
    @nogc

It must perform no heap allocation and no hidden geometry copy.

Runtime complexity is linear in the number of stored vertices.

Auxiliary storage is bounded independently of vertex count.

## Consequences

### Positive

Integer coordinate products cannot overflow silently.

No precision is lost by converting integer coordinates before area
evaluation.

Finite `float` and `double` input receives one deterministic numerical
meaning based on exact input values.

Large coordinate offsets do not force a numerically inferior raw
coordinate-product implementation.

The result is independent of compiler expression reassociation and ambient
floating-point rounding mode.

The existing exact orientation arithmetic gains a second coherent use.

Future fast paths may be added without changing public semantics.

### Negative

The exact reference implementation is more complex than a direct shoelace
loop.

It will probably be slower than ordinary floating-point accumulation for
large ordinary rings.

Additional exact accumulation and rounding machinery is required.

`real` is not supported by the initial signed-area algorithm.

Correctly rounded zero cannot serve as an exact degeneracy test, so a
separate predicate will be required if that capability is needed.

## Rejected alternatives

### Direct arithmetic in the input scalar

Rejected because `int` and `long` products can overflow and floating-point
products can lose information unnecessarily.

### Convert every coordinate to double and use shoelace

Rejected because conversion can lose integer information before the area
calculation and every arithmetic operation rounds in binary64.

### Ordinary sequential floating-point summation

Rejected as the semantic model because rounding occurs at every term and
the result depends on accumulation details.

### Kahan or Neumaier summation as the public numerical contract

Rejected as the semantic model because compensated summation reduces error
but does not define the correctly rounded exact result.

It remains a possible optimization technique inside a certified fast path.

### Use signedArea() as the ring-orientation predicate

Rejected because a non-zero exact floating-point geometry can produce a
rounded zero area.

Predicate semantics must remain separate from construction semantics.

### Support real immediately with a weaker algorithm

Rejected because the same API should not silently provide a weaker
numerical contract merely because the input scalar is platform-dependent.

Robust `real` support requires a dedicated platform-aware backend.

### Reject degenerate or self-intersecting rings

Rejected because ADR-0007 deliberately separates representation from
validity.

Signed area has a well-defined algebraic result for those stored
traversals.

## Verification requirements

Before this ADR is marked Accepted, the implementation plan must demonstrate
that exact accumulation and final rounding can be bounded without dynamic
allocation.

The implementation test suite should eventually cover at least:

- empty ring;
- singleton ring;
- two-vertex ring;
- ordinary CCW triangle;
- ordinary CW triangle;
- traversal reversal;
- repeated vertices;
- explicitly repeated final vertex;
- collinear ring;
- self-intersecting cancellation;
- full-range `int`;
- full-range `long`;
- `float` input with `double` result;
- ordinary `double`;
- very large translated coordinates;
- near-zero exact area;
- positive and negative underflow to signed zero;
- result overflow to infinity from finite coordinates;
- NaN input;
- positive infinity input;
- negative infinity input;
- rejection of `real`;
- independence from floating-point rounding mode;
- comparison against an independent exact oracle.

## Follow-up

After this ADR is accepted:

1. define `AreaScalar`;
2. implement or generalize exact signed fixed-width accumulation;
3. implement exact dyadic scaling and binary64 rounding for area;
4. implement `signedArea(LinearRingView!T)`;
5. add an independent exact test oracle;
6. verify DMD and LDC;
7. benchmark ordinary and adversarial rings;
8. investigate a certified floating-point fast path only if benchmarks
   justify it;
9. define a separate exact area-sign or ring-orientation predicate when a
   concrete consumer requires one;
10. proceed toward Polygon only after the area and ring contracts are
    stable.
