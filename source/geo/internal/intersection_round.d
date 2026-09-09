module geo.internal.intersection_round;

import geo.internal.fixed_uint :
    UIntFixed,
    compareUnsigned,
    subtractUnsigned;

import geo.internal.intersection_exact :
    IntersectionNumeratorMagnitude,
    SignedIntersectionNumerator,
    intersectionNumeratorLimbs;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    dyadicProductLimbs;

import std.bitmanip :
    DoubleRep;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Correctly rounded binary64 construction of one exact intersection
 * coordinate.
 *
 * ExactProperIntersection represents a coordinate as:
 *
 *     numerator
 *     ----------- * 2^-1074
 *     denominator
 *
 * This module converts that exact rational value to IEEE binary64
 * using round-to-nearest, ties-to-even.
 *
 * No floating-point arithmetic participates in the rounding decision.
 */


/*
 * Returns the number of significant bits in a fixed-width unsigned
 * integer. Zero has bit length zero.
 */
private size_t bitLength(size_t Limbs)(
    ref const UIntFixed!Limbs value
)
    pure nothrow @safe @nogc
{
    for (size_t i = Limbs; i != 0; --i)
    {
        uint word =
            value.limb[i - 1];

        if (word == 0)
            continue;

        size_t bits = 0;

        while (word != 0)
        {
            word >>= 1;
            ++bits;
        }

        return
            (i - 1) * 32 +
            bits;
    }

    return 0;
}


/*
 * Widens denominator and shifts it left inside numerator storage.
 *
 * The exact-intersection bounds guarantee that every shift used by
 * this module fits in IntersectionNumeratorMagnitude.
 */
private IntersectionNumeratorMagnitude shiftedDenominator(
    ref const DyadicProductMagnitude denominator,
    size_t shift
)
    pure nothrow @safe @nogc
{
    IntersectionNumeratorMagnitude result;

    const size_t wordShift =
        shift / 32;

    const uint bitShift =
        cast(uint)(shift % 32);

    foreach (i; 0 .. dyadicProductLimbs)
    {
        const uint word =
            denominator.limb[i];

        if (word == 0)
            continue;

        const size_t target =
            i + wordShift;

        assert(
            target <
            intersectionNumeratorLimbs
        );

        const ulong shifted =
            cast(ulong) word <<
            bitShift;

        result.limb[target] |=
            cast(uint) shifted;

        const uint upper =
            cast(uint)(shifted >> 32);

        if (upper != 0)
        {
            assert(
                target + 1 <
                intersectionNumeratorLimbs
            );

            result.limb[target + 1] |=
                upper;
        }
    }

    return result;
}


/*
 * Exact multiplication by two inside numerator storage.
 */
private IntersectionNumeratorMagnitude doubled(
    ref const IntersectionNumeratorMagnitude value
)
    pure nothrow @safe @nogc
{
    IntersectionNumeratorMagnitude result;

    uint carry = 0;

    foreach (i; 0 .. intersectionNumeratorLimbs)
    {
        const uint word =
            value.limb[i];

        result.limb[i] =
            (word << 1) |
            carry;

        carry =
            word >> 31;
    }

    /*
     * Exact proper-intersection coordinate bounds leave sufficient
     * headroom for every remainder doubled by this module.
     */
    assert(carry == 0);

    return result;
}


/*
 * Computes:
 *
 *     round(
 *         numerator /
 *         (denominator * 2^denominatorShift)
 *     )
 *
 * with round-to-nearest, ties-to-even.
 *
 * The caller guarantees that the unrounded quotient is below 2^53,
 * so the rounded result fits in at most 54 bits. A value of exactly
 * 2^53 is possible after rounding and is handled by normalisation.
 */
private ulong roundedQuotient(
    ref const IntersectionNumeratorMagnitude numerator,
    ref const DyadicProductMagnitude denominator,
    size_t denominatorShift
)
    pure nothrow @safe @nogc
{
    IntersectionNumeratorMagnitude remainder =
        numerator;

    ulong quotient = 0;


    /*
     * Only the 53 binary64 significand bits can contribute to the
     * retained quotient.
     */
    for (int bit = 52; bit >= 0; --bit)
    {
        const auto divisor =
            shiftedDenominator(
                denominator,
                denominatorShift +
                    cast(size_t) bit
            );

        if (
            compareUnsigned(
                remainder,
                divisor
            ) >= 0
        )
        {
            remainder =
                subtractUnsigned(
                    remainder,
                    divisor
                );

            quotient |=
                1UL << bit;
        }
    }


    const auto divisor =
        shiftedDenominator(
            denominator,
            denominatorShift
        );

    const auto twiceRemainder =
        doubled(remainder);

    const int halfComparison =
        compareUnsigned(
            twiceRemainder,
            divisor
        );


    /*
     * Round to nearest, ties to even.
     */
    if (
        halfComparison > 0 ||
        (
            halfComparison == 0 &&
            (quotient & 1UL) != 0
        )
    )
    {
        ++quotient;
    }

    return quotient;
}


/*
 * Constructs binary64 directly from sign, exponent and fraction bits.
 */
private double makeBinary64(
    bool negative,
    uint exponent,
    ulong fraction
)
    pure nothrow @safe @nogc
{
    assert(exponent <= 0x7ff);
    assert(fraction < (1UL << 52));

    DoubleRep representation;

    representation.sign =
        negative;

    representation.exponent =
        cast(ushort) exponent;

    representation.fraction =
        fraction;

    return representation.value;
}


/**
 * Correctly rounds one exact proper-intersection coordinate to
 * binary64.
 *
 * Rounding mode is fixed by the algorithm:
 *
 *     round to nearest, ties to even
 *
 * and does not depend on the process floating-point environment.
 *
 * The denominator must be positive.
 */
double roundIntersectionCoordinate(
    ref const SignedIntersectionNumerator numerator,
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
        return 0.0;
    }

    assert(
        numerator.sign == -1 ||
        numerator.sign == 1
    );

    const bool negative =
        numerator.sign < 0;


    /*
     * A binary64 value is normal exactly when:
     *
     *     |x| >= 2^-1022
     *
     * Since:
     *
     *     |x| =
     *         numerator / denominator * 2^-1074
     *
     * this is equivalent to:
     *
     *     numerator / denominator >= 2^52
     */
    const auto minimumNormalThreshold =
        shiftedDenominator(
            denominator,
            52
        );

    if (
        compareUnsigned(
            numerator.magnitude,
            minimumNormalThreshold
        ) < 0
    )
    {
        /*
         * Subnormal domain.
         *
         * binary64 subnormal values are integral multiples of 2^-1074,
         * so directly round numerator / denominator to the nearest
         * subnormal significand.
         */
        const ulong significand =
            roundedQuotient(
                numerator.magnitude,
                denominator,
                0
            );

        if (significand < (1UL << 52))
        {
            return makeBinary64(
                negative,
                0,
                significand
            );
        }

        /*
         * Rounding across the subnormal/normal boundary yields exactly
         * the smallest normal binary64 value.
         */
        assert(
            significand ==
            (1UL << 52)
        );

        return makeBinary64(
            negative,
            1,
            0
        );
    }


    /*
     * Normal domain.
     *
     * Let:
     *
     *     k = floor(log2(numerator / denominator))
     *
     * Then k >= 52 and:
     *
     *     2^k <= numerator/denominator < 2^(k+1)
     *
     * Retaining 53 significand bits therefore means rounding:
     *
     *     numerator /
     *         (denominator * 2^(k - 52))
     */
    const size_t numeratorBits =
        bitLength(
            numerator.magnitude
        );

    const size_t denominatorBits =
        bitLength(
            denominator
        );

    assert(
        numeratorBits >=
        denominatorBits
    );

    size_t k =
        numeratorBits -
        denominatorBits;

    const auto candidate =
        shiftedDenominator(
            denominator,
            k
        );

    if (
        compareUnsigned(
            numerator.magnitude,
            candidate
        ) < 0
    )
    {
        assert(k != 0);
        --k;
    }

    assert(k >= 52);

    const size_t shift =
        k - 52;

    ulong significand =
        roundedQuotient(
            numerator.magnitude,
            denominator,
            shift
        );

    assert(
        significand >=
        (1UL << 52)
    );

    assert(
        significand <=
        (1UL << 53)
    );


    /*
     * Rounding can carry out of the 53-bit significand.
     */
    if (
        significand ==
        (1UL << 53)
    )
    {
        significand >>= 1;
        ++k;
    }


    /*
     * Exact intersection points lie in the closed convex hull of finite
     * input endpoints, so a valid construction cannot round beyond
     * finite binary64.
     *
     * rawExponent =
     *
     *     (k - 1074) + 1023
     *   = k - 51
     */
    assert(k >= 52);
    assert(k <= 2097);

    const uint exponent =
        cast(uint)(
            k - 51
        );

    assert(
        exponent >= 1 &&
        exponent <= 2046
    );

    const ulong fraction =
        significand -
        (1UL << 52);

    return makeBinary64(
        negative,
        exponent,
        fraction
    );
}


@safe unittest
{
    /*
     * Convenience denominator = 1.
     */
    DyadicProductMagnitude one;
    one.limb[0] = 1;


    /*
     * Smallest positive subnormal:
     *
     *     1 * 2^-1074
     */
    {
        SignedIntersectionNumerator numerator;

        numerator.sign = 1;
        numerator.magnitude.limb[0] = 1;

        assert(
            roundIntersectionCoordinate(
                numerator,
                one
            ) ==
            0x0.0000000000001p-1022
        );
    }


    /*
     * Exactly half of the smallest subnormal:
     *
     *     0.5 * 2^-1074
     *
     * Tie between zero (even) and one subnormal unit (odd), therefore
     * round to +0.
     */
    {
        SignedIntersectionNumerator numerator;
        numerator.sign = 1;
        numerator.magnitude.limb[0] = 1;

        DyadicProductMagnitude denominator;
        denominator.limb[0] = 2;

        const double result =
            roundIntersectionCoordinate(
                numerator,
                denominator
            );

        assert(result == 0.0);

        DoubleRep representation;
        representation.value = result;

        assert(!representation.sign);
    }


    /*
     * Negative half-subnormal rounds to negative zero while preserving
     * the exact sign.
     */
    {
        SignedIntersectionNumerator numerator;
        numerator.sign = -1;
        numerator.magnitude.limb[0] = 1;

        DyadicProductMagnitude denominator;
        denominator.limb[0] = 2;

        const double result =
            roundIntersectionCoordinate(
                numerator,
                denominator
            );

        assert(result == 0.0);

        DoubleRep representation;
        representation.value = result;

        assert(representation.sign);
    }


    /*
     * 1.5 subnormal units is exactly halfway between mantissas 1 and 2.
     * Ties-to-even chooses 2.
     */
    {
        SignedIntersectionNumerator numerator;
        numerator.sign = 1;
        numerator.magnitude.limb[0] = 3;

        DyadicProductMagnitude denominator;
        denominator.limb[0] = 2;

        assert(
            roundIntersectionCoordinate(
                numerator,
                denominator
            ) ==
            0x0.0000000000002p-1022
        );
    }


    /*
     * 2.5 subnormal units is halfway between mantissas 2 and 3.
     * Ties-to-even chooses 2.
     */
    {
        SignedIntersectionNumerator numerator;
        numerator.sign = 1;
        numerator.magnitude.limb[0] = 5;

        DyadicProductMagnitude denominator;
        denominator.limb[0] = 2;

        assert(
            roundIntersectionCoordinate(
                numerator,
                denominator
            ) ==
            0x0.0000000000002p-1022
        );
    }


    /*
     * Tie at the subnormal/normal boundary:
     *
     *     2^52 - 0.5
     *
     * max-subnormal has an odd mantissa, min-normal an even
     * significand, so ties-to-even chooses min-normal.
     */
    {
        SignedIntersectionNumerator numerator;
        numerator.sign = 1;

        const ulong magnitude =
            (1UL << 53) - 1;

        numerator.magnitude.limb[0] =
            cast(uint) magnitude;

        numerator.magnitude.limb[1] =
            cast(uint)(
                magnitude >> 32
            );

        DyadicProductMagnitude denominator;
        denominator.limb[0] = 2;

        assert(
            roundIntersectionCoordinate(
                numerator,
                denominator
            ) ==
            0x1p-1022
        );
    }


    /*
     * Exact 1.0:
     *
     *     2^1074 / 1 * 2^-1074
     */
    {
        SignedIntersectionNumerator numerator;
        numerator.sign = 1;

        enum size_t bit = 1074;

        numerator.magnitude.limb[
            bit / 32
        ] =
            1U << (bit % 32);

        assert(
            roundIntersectionCoordinate(
                numerator,
                one
            ) ==
            1.0
        );
    }


    /*
     * Normal midpoint directly above 1.0:
     *
     *     1 + 2^-53
     *
     * This is exactly halfway between 1.0 and the next binary64 value.
     * 1.0 has the even significand and must win.
     */
    {
        SignedIntersectionNumerator numerator;
        numerator.sign = 1;

        numerator.magnitude.limb[
            1074 / 32
        ] |=
            1U << (1074 % 32);

        numerator.magnitude.limb[
            1021 / 32
        ] |=
            1U << (1021 % 32);

        assert(
            roundIntersectionCoordinate(
                numerator,
                one
            ) ==
            1.0
        );
    }


    /*
     * Next normal midpoint:
     *
     *     1 + 3 * 2^-53
     *
     * The lower candidate has an odd significand, therefore the tie
     * rounds upward to the even candidate.
     */
    {
        SignedIntersectionNumerator numerator;
        numerator.sign = 1;

        numerator.magnitude.limb[
            1074 / 32
        ] |=
            1U << (1074 % 32);

        numerator.magnitude.limb[
            1022 / 32
        ] |=
            1U << (1022 % 32);

        numerator.magnitude.limb[
            1021 / 32
        ] |=
            1U << (1021 % 32);

        assert(
            roundIntersectionCoordinate(
                numerator,
                one
            ) ==
            0x1.0000000000002p+0
        );
    }


    /*
     * Exact largest finite binary64 value.
     *
     * Its exact dyadic integer representation is:
     *
     *     (2^53 - 1) << 2045
     */
    {
        SignedIntersectionNumerator numerator;
        numerator.sign = 1;

        enum ulong mantissa =
            (1UL << 53) - 1;

        enum size_t shift = 2045;

        foreach (bit; 0 .. 53)
        {
            if (
                (
                    mantissa >>
                    bit
                ) &
                1UL
            )
            {
                const size_t target =
                    shift + bit;

                numerator.magnitude.limb[
                    target / 32
                ] |=
                    1U <<
                    (target % 32);
            }
        }

        assert(
            roundIntersectionCoordinate(
                numerator,
                one
            ) ==
            double.max
        );
    }
}
