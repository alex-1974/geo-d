module geo.internal.dyadic_round;

import geo.internal.fixed_uint :
    UIntFixed;

import std.bitmanip :
    DoubleRep;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Correctly rounded conversion of an exact signed dyadic value:
 *
 *     sign * magnitude * 2^binaryExponent
 *
 * to IEEE binary64 using round-to-nearest, ties-to-even.
 *
 * No floating-point arithmetic participates in the rounding decision.
 */


/*
 * Number of significant bits in a fixed-width unsigned integer.
 *
 * Zero has bit length zero.
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
 * Returns whether one exact bit is set.
 *
 * Bits outside the fixed-width value are zero.
 */
private bool bitIsSet(size_t Limbs)(
    ref const UIntFixed!Limbs value,
    size_t index
)
    pure nothrow @safe @nogc
{
    const size_t wordIndex =
        index / 32;

    if (wordIndex >= Limbs)
        return false;

    const uint bitIndex =
        cast(uint)(index % 32);

    return (
        value.limb[wordIndex] &
        (1u << bitIndex)
    ) != 0;
}


/*
 * Returns true when any bit in:
 *
 *     [0, bitCount)
 *
 * is set.
 */
private bool anyBitsBelow(size_t Limbs)(
    ref const UIntFixed!Limbs value,
    size_t bitCount
)
    pure nothrow @safe @nogc
{
    const size_t fullWords =
        bitCount / 32;

    const size_t wordsToInspect =
        fullWords < Limbs
            ? fullWords
            : Limbs;

    foreach (i; 0 .. wordsToInspect)
    {
        if (value.limb[i] != 0)
            return true;
    }

    if (fullWords >= Limbs)
        return false;

    const uint remainder =
        cast(uint)(bitCount % 32);

    if (remainder == 0)
        return false;

    const uint mask =
        (1u << remainder) - 1u;

    return (
        value.limb[fullWords] &
        mask
    ) != 0;
}


/*
 * Returns the low 64 bits.
 *
 * Callers use this only where all significant bits are known to fit.
 */
private ulong lowUInt64(size_t Limbs)(
    ref const UIntFixed!Limbs value
)
    pure nothrow @safe @nogc
{
    ulong result =
        value.limb[0];

    static if (Limbs > 1)
    {
        result |=
            cast(ulong) value.limb[1] <<
            32;
    }

    return result;
}


/*
 * Returns:
 *
 *     floor(value / 2^shift)
 *
 * as ulong.
 *
 * Callers guarantee that the retained quotient fits in 64 bits.
 */
private ulong shiftedRightToUInt64(size_t Limbs)(
    ref const UIntFixed!Limbs value,
    size_t shift
)
    pure nothrow @safe @nogc
{
    ulong result = 0;

    foreach (i; 0 .. 64)
    {
        const size_t sourceBit =
            shift + i;

        if (sourceBit < shift)
            break;

        if (bitIsSet(value, sourceBit))
        {
            result |=
                1UL << i;
        }
    }

    return result;
}


/*
 * Divides by 2^shift and rounds the integer result using
 * round-to-nearest, ties-to-even.
 *
 * Callers guarantee that the rounded result fits in ulong.
 */
private ulong roundedRightShiftToUInt64(size_t Limbs)(
    ref const UIntFixed!Limbs value,
    size_t shift
)
    pure nothrow @safe @nogc
{
    if (shift == 0)
        return shiftedRightToUInt64(
            value,
            0
        );

    ulong result =
        shiftedRightToUInt64(
            value,
            shift
        );

    const bool guard =
        bitIsSet(
            value,
            shift - 1
        );

    if (!guard)
        return result;

    const bool sticky =
        anyBitsBelow(
            value,
            shift - 1
        );

    /*
     * Greater than half rounds upward.
     *
     * Exactly half rounds toward the even retained significand.
     */
    if (
        sticky ||
        (result & 1UL) != 0
    )
    {
        ++result;
    }

    return result;
}


/*
 * Constructs one binary64 value directly from its IEEE fields.
 */
private double makeBinary64(
    bool negative,
    ushort rawExponent,
    ulong fraction
)
    pure nothrow @safe @nogc
{
    assert(rawExponent <= 0x7ff);
    assert(fraction < (1UL << 52));

    DoubleRep result;

    result.sign =
        negative;

    result.exponent =
        rawExponent;

    result.fraction =
        fraction;

    return result.value;
}


/*
 * Signed zero.
 */
private double signedZero(
    bool negative
)
    pure nothrow @safe @nogc
{
    return makeBinary64(
        negative,
        0,
        0
    );
}


/*
 * Signed infinity.
 */
private double signedInfinity(
    bool negative
)
    pure nothrow @safe @nogc
{
    return makeBinary64(
        negative,
        cast(ushort) 0x7ff,
        0
    );
}


/**
 * Correctly rounds an exact signed dyadic value to IEEE binary64.
 *
 * The exact input value is:
 *
 *     sign * magnitude * 2^binaryExponent
 *
 * sign:
 *
 *     -1 negative
 *      0 zero
 *      1 positive
 *
 * A zero magnitude always produces positive zero when sign == 0.
 *
 * Non-zero values are rounded using round-to-nearest, ties-to-even.
 * Underflow preserves the sign of a non-zero exact value.
 *
 * Overflow produces signed infinity.
 */
double roundSignedDyadicToBinary64(size_t Limbs)(
    int sign,
    ref const UIntFixed!Limbs magnitude,
    int binaryExponent
)
    pure nothrow @safe @nogc
{
    assert(
        sign >= -1 &&
        sign <= 1
    );

    const size_t bits =
        bitLength(magnitude);

    if (bits == 0)
    {
        assert(sign == 0);

        return signedZero(false);
    }

    assert(
        sign == -1 ||
        sign == 1
    );

    const bool negative =
        sign < 0;

    /*
     * Unbiased exponent of the most-significant exact bit.
     */
    long exponent =
        cast(long)(bits - 1) +
        cast(long) binaryExponent;


    /*
     * Values whose most-significant bit lies below the normal range
     * are rounded directly onto the binary64 subnormal lattice:
     *
     *     integer * 2^-1074
     */
    if (exponent < -1022)
    {
        const long scaleToSubnormal =
            cast(long) binaryExponent +
            1074;

        ulong significand;

        if (scaleToSubnormal >= 0)
        {
            /*
             * In this branch exponent < -1022 guarantees that the
             * shifted result occupies at most 52 significant bits.
             */
            assert(bits <= 64);
            assert(scaleToSubnormal <= 63);

            significand =
                lowUInt64(magnitude) <<
                cast(uint) scaleToSubnormal;
        }
        else
        {
            const size_t shift =
                cast(size_t)(
                    -scaleToSubnormal
                );

            significand =
                roundedRightShiftToUInt64(
                    magnitude,
                    shift
                );
        }


        /*
         * Complete underflow.
         *
         * The exact input was non-zero, so preserve its sign.
         */
        if (significand == 0)
        {
            return signedZero(
                negative
            );
        }


        /*
         * Rounding just below the normal boundary may produce the
         * smallest normal binary64 value.
         */
        if (significand == (1UL << 52))
        {
            return makeBinary64(
                negative,
                cast(ushort) 1,
                0
            );
        }

        assert(
            significand <
            (1UL << 52)
        );

        return makeBinary64(
            negative,
            0,
            significand
        );
    }


    /*
     * Any exact value whose leading bit is already above the largest
     * binary64 normal exponent necessarily overflows.
     */
    if (exponent > 1023)
    {
        return signedInfinity(
            negative
        );
    }


    /*
     * Construct a 53-bit normalized significand.
     */
    ulong significand;

    if (bits <= 53)
    {
        const size_t shift =
            53 - bits;

        assert(bits <= 64);
        assert(shift <= 52);

        significand =
            lowUInt64(magnitude) <<
            cast(uint) shift;
    }
    else
    {
        const size_t shift =
            bits - 53;

        significand =
            roundedRightShiftToUInt64(
                magnitude,
                shift
            );
    }


    /*
     * Rounding can carry a 53-bit significand into the next binade.
     */
    if (significand == (1UL << 53))
    {
        significand >>= 1;
        ++exponent;
    }

    if (exponent > 1023)
    {
        return signedInfinity(
            negative
        );
    }

    assert(exponent >= -1022);

    assert(
        significand >=
        (1UL << 52)
    );

    assert(
        significand <
        (1UL << 53)
    );

    const ushort rawExponent =
        cast(ushort)(
            exponent + 1023
        );

    const ulong fraction =
        significand -
        (1UL << 52);

    return makeBinary64(
        negative,
        rawExponent,
        fraction
    );
}


@safe unittest
{
    /*
     * Canonical exact zero.
     */
    {
        UIntFixed!1 zero;

        const double result =
            roundSignedDyadicToBinary64(
                0,
                zero,
                -2149
            );

        DoubleRep representation;
        representation.value = result;

        assert(!representation.sign);
        assert(representation.exponent == 0);
        assert(representation.fraction == 0);
    }


    /*
     * Exact ordinary values.
     */
    {
        UIntFixed!1 one;
        one.limb[0] = 1;

        assert(
            roundSignedDyadicToBinary64(
                1,
                one,
                0
            ) == 1.0
        );

        UIntFixed!1 three;
        three.limb[0] = 3;

        assert(
            roundSignedDyadicToBinary64(
                1,
                three,
                -1
            ) == 1.5
        );

        assert(
            roundSignedDyadicToBinary64(
                -1,
                three,
                -1
            ) == -1.5
        );
    }


    /*
     * Normal halfway case with an even lower candidate:
     *
     *     1 + 2^-53
     *
     * rounds to exactly 1.
     */
    {
        UIntFixed!2 value;

        value.limb[0] = 1;
        value.limb[1] = 1u << 21;

        const double result =
            roundSignedDyadicToBinary64(
                1,
                value,
                -53
            );

        DoubleRep representation;
        representation.value = result;

        assert(representation.exponent == 1023);
        assert(representation.fraction == 0);
    }


    /*
     * Normal halfway case with an odd lower candidate:
     *
     *     1 + 3 * 2^-53
     *
     * rounds upward to the even significand.
     */
    {
        UIntFixed!2 value;

        value.limb[0] = 3;
        value.limb[1] = 1u << 21;

        const double result =
            roundSignedDyadicToBinary64(
                1,
                value,
                -53
            );

        DoubleRep representation;
        representation.value = result;

        assert(representation.exponent == 1023);
        assert(representation.fraction == 2);
    }


    /*
     * Smallest positive subnormal.
     */
    {
        UIntFixed!1 one;
        one.limb[0] = 1;

        const double result =
            roundSignedDyadicToBinary64(
                1,
                one,
                -1074
            );

        DoubleRep representation;
        representation.value = result;

        assert(!representation.sign);
        assert(representation.exponent == 0);
        assert(representation.fraction == 1);
    }


    /*
     * Exactly half of the smallest subnormal ties to positive zero.
     */
    {
        UIntFixed!1 one;
        one.limb[0] = 1;

        const double result =
            roundSignedDyadicToBinary64(
                1,
                one,
                -1075
            );

        DoubleRep representation;
        representation.value = result;

        assert(!representation.sign);
        assert(representation.exponent == 0);
        assert(representation.fraction == 0);
    }


    /*
     * Negative non-zero underflow preserves negative zero.
     */
    {
        UIntFixed!1 one;
        one.limb[0] = 1;

        const double result =
            roundSignedDyadicToBinary64(
                -1,
                one,
                -1075
            );

        DoubleRep representation;
        representation.value = result;

        assert(representation.sign);
        assert(representation.exponent == 0);
        assert(representation.fraction == 0);
    }


    /*
     * 1.5 times the smallest subnormal ties to the even value 2.
     */
    {
        UIntFixed!1 three;
        three.limb[0] = 3;

        const double result =
            roundSignedDyadicToBinary64(
                1,
                three,
                -1075
            );

        DoubleRep representation;
        representation.value = result;

        assert(representation.exponent == 0);
        assert(representation.fraction == 2);
    }


    /*
     * Smallest positive normal value.
     */
    {
        UIntFixed!1 one;
        one.limb[0] = 1;

        const double result =
            roundSignedDyadicToBinary64(
                1,
                one,
                -1022
            );

        DoubleRep representation;
        representation.value = result;

        assert(representation.exponent == 1);
        assert(representation.fraction == 0);
    }


    /*
     * Largest finite binary64 value:
     *
     *     (2^53 - 1) * 2^971
     */
    {
        UIntFixed!2 value;

        value.limb[0] =
            uint.max;

        value.limb[1] =
            (1u << 21) - 1u;

        const double result =
            roundSignedDyadicToBinary64(
                1,
                value,
                971
            );

        DoubleRep representation;
        representation.value = result;

        assert(representation.exponent == 0x7fe);

        assert(
            representation.fraction ==
            (1UL << 52) - 1UL
        );
    }


    /*
     * The halfway point between the largest finite value and overflow
     * rounds to infinity under ties-to-even:
     *
     *     (2^54 - 1) * 2^970
     */
    {
        UIntFixed!2 value;

        value.limb[0] =
            uint.max;

        value.limb[1] =
            (1u << 22) - 1u;

        const double result =
            roundSignedDyadicToBinary64(
                1,
                value,
                970
            );

        DoubleRep representation;
        representation.value = result;

        assert(representation.exponent == 0x7ff);
        assert(representation.fraction == 0);
    }
}
