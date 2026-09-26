module geo.internal.exact_coordinate;

import geo.internal.dyadic :
    DyadicCoordinateMagnitude,
    DyadicProductMagnitude,
    SignedDyadicCoordinate,
    SignedDyadicDifference,
    SignedDyadicProduct,
    dyadicCoordinateLimbs,
    dyadicProductLimbs;

import geo.internal.fixed_uint :
    UIntFixed,
    addUnsigned,
    compareUnsigned,
    multiplyUnsigned,
    subtractUnsigned;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Geometry-neutral exact rational-coordinate construction support.
 *
 * A constructed coordinate is represented as:
 *
 *     numerator
 *     ----------- * 2^-1074
 *     denominator
 *
 * where the numerator is signed and the denominator is positive.
 *
 * The fixed width below is justified by the established exact-construction
 * range proofs, including ADR-0022's Line2 intersection/projection bounds.
 */


/*
 * 66 coordinate/difference limbs + 132 product limbs.
 *
 * 198 * 32 = 6336 bits.
 */
enum size_t exactCoordinateNumeratorLimbs =
    dyadicProductLimbs +
    dyadicCoordinateLimbs;


alias ExactCoordinateNumeratorMagnitude =
    UIntFixed!exactCoordinateNumeratorLimbs;


/*
 * Signed exact numerator for one constructed coordinate.
 *
 * Canonical zero has sign == 0 and zero magnitude.
 */
struct SignedExactCoordinateNumerator
{
    int sign;
    ExactCoordinateNumeratorMagnitude magnitude;
}


/*
 * Exact signed product:
 *
 *     dyadic coordinate * dyadic product
 */
SignedExactCoordinateNumerator multiplyCoordinateProduct(
    ref const SignedDyadicCoordinate coordinate,
    ref const SignedDyadicProduct product
)
    pure nothrow @safe @nogc
{
    SignedExactCoordinateNumerator result;

    if (
        coordinate.sign == 0 ||
        product.sign == 0
    )
    {
        return result;
    }

    result.sign =
        coordinate.sign == product.sign
            ? 1
            : -1;

    result.magnitude =
        multiplyUnsigned(
            coordinate.magnitude,
            product.magnitude
        );

    return result;
}


/*
 * Exact signed product:
 *
 *     dyadic coordinate difference * dyadic product
 */
SignedExactCoordinateNumerator multiplyDifferenceProduct(
    ref const SignedDyadicDifference difference,
    ref const SignedDyadicProduct product
)
    pure nothrow @safe @nogc
{
    SignedExactCoordinateNumerator result;

    if (
        difference.sign == 0 ||
        product.sign == 0
    )
    {
        return result;
    }

    result.sign =
        difference.sign == product.sign
            ? 1
            : -1;

    result.magnitude =
        multiplyUnsigned(
            difference.magnitude,
            product.magnitude
        );

    return result;
}


/*
 * Exact signed addition in the established 198-limb numerator domain.
 *
 * Callers are responsible for using this only where their range proof
 * establishes that the exact result fits this width.
 */
SignedExactCoordinateNumerator addExactCoordinateNumerators(
    ref const SignedExactCoordinateNumerator lhs,
    ref const SignedExactCoordinateNumerator rhs
)
    pure nothrow @safe @nogc
{
    if (
        lhs.sign == 0 ||
        lhs.magnitude.isZero
    )
    {
        return rhs;
    }

    if (
        rhs.sign == 0 ||
        rhs.magnitude.isZero
    )
    {
        return lhs;
    }

    SignedExactCoordinateNumerator result;

    if (lhs.sign == rhs.sign)
    {
        result.sign = lhs.sign;

        result.magnitude =
            addUnsigned(
                lhs.magnitude,
                rhs.magnitude
            );

        return result;
    }

    const int comparison =
        compareUnsigned(
            lhs.magnitude,
            rhs.magnitude
        );

    if (comparison == 0)
        return result;

    if (comparison > 0)
    {
        result.sign = lhs.sign;

        result.magnitude =
            subtractUnsigned(
                lhs.magnitude,
                rhs.magnitude
            );
    }
    else
    {
        result.sign = rhs.sign;

        result.magnitude =
            subtractUnsigned(
                rhs.magnitude,
                lhs.magnitude
            );
    }

    return result;
}


/*
 * Negates a signed exact numerator.
 */
void negateExactCoordinateNumerator(
    ref SignedExactCoordinateNumerator value
)
    pure nothrow @safe @nogc
{
    if (value.sign != 0)
        value.sign = -value.sign;
}


/*
 * Exact overflow midpoint for binary64 round-to-nearest, ties-to-even.
 *
 *     double.max = 2^1024 - 2^971
 *
 * The midpoint between double.max and the conceptual next value 2^1024 is:
 *
 *     2^1024 - 2^970
 *
 * In the common 2^-1074 coordinate scale:
 *
 *     2^2098 - 2^2044
 *   = (2^54 - 1) << 2044
 *
 * Equality rounds upward to infinity, therefore a finite result requires a
 * strict comparison below this midpoint.
 */
private DyadicCoordinateMagnitude binary64OverflowMidpoint()
    pure nothrow @safe @nogc
{
    DyadicCoordinateMagnitude result;

    foreach (bit; 2044 .. 2098)
    {
        result.limb[
            bit / 32
        ] |=
            1U << (bit % 32);
    }

    return result;
}


/*
 * True exactly when the represented rational coordinate rounds to a finite
 * binary64 result under round-to-nearest, ties-to-even.
 */
bool roundsToFiniteBinary64(
    ref const SignedExactCoordinateNumerator numerator,
    ref const DyadicProductMagnitude denominator
)
    pure nothrow @safe @nogc
{
    assert(!denominator.isZero);

    if (
        numerator.sign == 0 ||
        numerator.magnitude.isZero
    )
    {
        return true;
    }

    const auto midpoint =
        binary64OverflowMidpoint();

    const auto scaledMidpoint =
        multiplyUnsigned(
            denominator,
            midpoint
        );

    return
        compareUnsigned(
            numerator.magnitude,
            scaledMidpoint
        ) < 0;
}


static assert(
    exactCoordinateNumeratorLimbs == 198
);


/*
 * CTFE regression for the exact binary64 finite/overflow boundary.
 */
private bool finiteBoundarySelfCheck(uint denominatorValue)
    pure nothrow @safe @nogc
{
    ExactCoordinateNumeratorMagnitude unit;
    unit.limb[0] = 1;

    DyadicProductMagnitude denominator;
    denominator.limb[0] = denominatorValue;

    const auto midpoint =
        binary64OverflowMidpoint();

    const auto threshold =
        multiplyUnsigned(
            denominator,
            midpoint
        );

    SignedExactCoordinateNumerator below;
    below.sign = 1;
    below.magnitude =
        subtractUnsigned(
            threshold,
            unit
        );

    SignedExactCoordinateNumerator equal;
    equal.sign = 1;
    equal.magnitude = threshold;

    SignedExactCoordinateNumerator above;
    above.sign = 1;
    above.magnitude =
        addUnsigned(
            threshold,
            unit
        );

    if (!roundsToFiniteBinary64(below, denominator))
        return false;

    if (roundsToFiniteBinary64(equal, denominator))
        return false;

    if (roundsToFiniteBinary64(above, denominator))
        return false;

    below.sign = -1;
    equal.sign = -1;
    above.sign = -1;

    if (!roundsToFiniteBinary64(below, denominator))
        return false;

    if (roundsToFiniteBinary64(equal, denominator))
        return false;

    if (roundsToFiniteBinary64(above, denominator))
        return false;

    SignedExactCoordinateNumerator zero;

    if (!roundsToFiniteBinary64(zero, denominator))
        return false;

    return true;
}


static assert(finiteBoundarySelfCheck(1));
static assert(finiteBoundarySelfCheck(3));


@safe unittest
{
    import geo.internal.dyadic :
        decodeDyadicCoordinate,
        multiplyDyadicDifferences,
        subtractDyadicCoordinates;

    const auto zero =
        decodeDyadicCoordinate(0);

    const auto one =
        decodeDyadicCoordinate(1);

    const auto two =
        decodeDyadicCoordinate(2);

    const auto unitDifference =
        subtractDyadicCoordinates(
            one,
            zero
        );

    const auto unitProduct =
        multiplyDyadicDifferences(
            unitDifference,
            unitDifference
        );

    auto positive =
        multiplyCoordinateProduct(
            two,
            unitProduct
        );

    assert(positive.sign == 1);
    assert(!positive.magnitude.isZero);

    auto negative = positive;
    negateExactCoordinateNumerator(negative);

    assert(negative.sign == -1);
    assert(
        negative.magnitude.limb ==
        positive.magnitude.limb
    );

    const auto sum =
        addExactCoordinateNumerators(
            positive,
            negative
        );

    assert(sum.sign == 0);
    assert(sum.magnitude.isZero);

    const auto differenceProduct =
        multiplyDifferenceProduct(
            unitDifference,
            unitProduct
        );

    assert(differenceProduct.sign == 1);
    assert(!differenceProduct.magnitude.isZero);
}
