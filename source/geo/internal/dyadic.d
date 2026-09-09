module geo.internal.dyadic;

import geo.internal.fixed_uint :
    UIntFixed;

import std.bitmanip :
    DoubleRep;

import std.math.traits :
    isFinite;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact dyadic representation of finite binary64 coordinates.
 *
 * Every finite IEEE binary64 value can be represented exactly as:
 *
 *     integer * 2^-1074
 *
 * The integer magnitude therefore needs at most 2098 bits.
 *
 * 66 x 32 = 2112 bits, which is sufficient for every finite double.
 *
 * This module provides representation and decoding only. It deliberately
 * does not implement general signed arithmetic or rational arithmetic.
 */


enum size_t dyadicCoordinateLimbs = 66;


alias DyadicCoordinateMagnitude =
    UIntFixed!dyadicCoordinateLimbs;


/**
 * Exact signed dyadic coordinate represented in units of 2^-1074.
 *
 * sign:
 *
 *     -1 negative
 *      0 zero
 *      1 positive
 */
struct SignedDyadicCoordinate
{
    int sign;
    DyadicCoordinateMagnitude magnitude;
}


/*
 * Places one binary64 mantissa at the requested bit position.
 *
 * The mantissa uses at most 53 bits.
 *
 * The destination is initially zero, so bitwise OR is sufficient.
 */
private void setShiftedMantissa(
    ref DyadicCoordinateMagnitude result,
    ulong mantissa,
    uint shift
)
    pure nothrow @safe @nogc
{
    assert(mantissa != 0);
    assert(shift <= 2045);

    const size_t base =
        shift / 32;

    const uint offset =
        shift % 32;

    const uint lower =
        cast(uint) mantissa;

    const uint upper =
        cast(uint)(mantissa >> 32);

    const ulong shiftedLower =
        cast(ulong) lower << offset;

    result.limb[base] |=
        cast(uint) shiftedLower;

    if (base + 1 < dyadicCoordinateLimbs)
    {
        result.limb[base + 1] |=
            cast(uint)(
                shiftedLower >> 32
            );
    }

    if (upper != 0)
    {
        const ulong shiftedUpper =
            cast(ulong) upper << offset;

        assert(
            base + 1 <
            dyadicCoordinateLimbs
        );

        result.limb[base + 1] |=
            cast(uint) shiftedUpper;

        if (
            base + 2 <
            dyadicCoordinateLimbs
        )
        {
            result.limb[base + 2] |=
                cast(uint)(
                    shiftedUpper >> 32
                );
        }
        else
        {
            assert(
                (shiftedUpper >> 32) == 0
            );
        }
    }
}


/**
 * Decodes one finite binary64 value exactly as a signed integer
 * multiple of 2^-1074.
 *
 * For subnormals:
 *
 *     value = fraction * 2^-1074
 *
 * For normals:
 *
 *     value =
 *         (2^52 + fraction)
 *         * 2^(rawExponent - 1075)
 *
 * Therefore, in units of 2^-1074:
 *
 *     integer =
 *         mantissa << (rawExponent - 1)
 *
 * Positive and negative zero both produce sign == 0.
 */
SignedDyadicCoordinate decodeBinary64Coordinate(
    double value
)
    pure nothrow @safe @nogc
{
    assert(isFinite(value));

    DoubleRep representation;

    representation.value =
        value;

    const ulong fraction =
        representation.fraction;

    const uint rawExponent =
        representation.exponent;

    ulong mantissa;
    uint shift;

    if (rawExponent == 0)
    {
        /*
         * Zero or subnormal.
         */
        mantissa =
            fraction;

        shift = 0;
    }
    else
    {
        mantissa =
            (1UL << 52) |
            fraction;

        shift =
            rawExponent - 1;
    }

    SignedDyadicCoordinate result;

    if (mantissa == 0)
    {
        /*
         * +0 and -0 are the same mathematical coordinate.
         */
        result.sign = 0;
        return result;
    }

    result.sign =
        representation.sign
            ? -1
            : 1;

    setShiftedMantissa(
        result.magnitude,
        mantissa,
        shift
    );

    return result;
}


@safe unittest
{
    /*
     * Both signed zeros normalize to exact dyadic zero.
     */
    {
        const auto positive =
            decodeBinary64Coordinate(
                0.0
            );

        const auto negative =
            decodeBinary64Coordinate(
                -0.0
            );

        assert(positive.sign == 0);
        assert(negative.sign == 0);

        assert(
            positive.magnitude.isZero
        );

        assert(
            negative.magnitude.isZero
        );
    }


    /*
     * The smallest positive binary64 subnormal is exactly one unit of
     * the common 2^-1074 coordinate scale.
     */
    {
        enum double smallest =
            0x0.0000000000001p-1022;

        const auto value =
            decodeBinary64Coordinate(
                smallest
            );

        assert(value.sign == 1);
        assert(
            value.magnitude.limb[0] ==
            1
        );

        foreach (
            index;
            1 .. dyadicCoordinateLimbs
        )
        {
            assert(
                value.magnitude
                    .limb[index] == 0
            );
        }
    }


    /*
     * Sign is separated from magnitude.
     */
    {
        const auto positive =
            decodeBinary64Coordinate(
                1.0
            );

        const auto negative =
            decodeBinary64Coordinate(
                -1.0
            );

        assert(positive.sign == 1);
        assert(negative.sign == -1);

        assert(
            positive.magnitude.limb ==
            negative.magnitude.limb
        );
    }


    /*
     * The complete finite binary64 range fits in the fixed coordinate
     * width.
     */
    {
        const auto maximum =
            decodeBinary64Coordinate(
                double.max
            );

        const auto minimum =
            decodeBinary64Coordinate(
                -double.max
            );

        assert(maximum.sign == 1);
        assert(minimum.sign == -1);

        assert(
            !maximum.magnitude.isZero
        );

        assert(
            maximum.magnitude.limb ==
            minimum.magnitude.limb
        );
    }
}
