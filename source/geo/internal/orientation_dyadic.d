module geo.internal.orientation_dyadic;

import std.bitmanip : DoubleRep;
import std.math.traits : isFinite;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Final exact fallback for binary64 orient2d.
 *
 * Every finite IEEE binary64 value is represented exactly as an
 * integer multiple of 2^-1074.
 *
 * Therefore orientation can be reduced to exact fixed-width integer
 * arithmetic. No floating-point multiplication or subtraction is
 * required in this fallback.
 *
 * This path is expected to be rare. The normal path remains:
 *
 *     certified floating filter
 *         ->
 *     expansion fallback
 *         ->
 *     this full-range dyadic fallback
 */


/*
 * Maximum exact integer coordinate magnitude in units of 2^-1074:
 *
 *     double.max * 2^1074
 *
 * requires 2098 bits.
 *
 * A difference of two signed coordinates may require 2099 bits.
 *
 * 66 x 32 = 2112 bits, therefore 66 uint limbs are sufficient.
 */
private enum size_t coordinateLimbs = 66;


/*
 * A product of two coordinate differences requires at most:
 *
 *     2099 + 2099 = 4198 bits.
 *
 * 132 x 32 = 4224 bits.
 */
private enum size_t productLimbs =
    2 * coordinateLimbs;


/*
 * Fixed-width unsigned integer using little-endian base-2^32 limbs.
 *
 * This is intentionally local to orient2d. It is not a general-purpose
 * arbitrary-precision integer abstraction.
 */
private struct UIntFixed(size_t Limbs)
{
    uint[Limbs] limb;


    @property bool isZero() const
        pure nothrow @safe @nogc
    {
        foreach (value; limb)
        {
            if (value != 0)
                return false;
        }

        return true;
    }
}


private alias CoordinateMagnitude =
    UIntFixed!coordinateLimbs;

private alias ProductMagnitude =
    UIntFixed!productLimbs;


/*
 * Exact signed integer represented as sign + unsigned magnitude.
 */
private struct SignedCoordinate
{
    int sign;
    CoordinateMagnitude magnitude;
}


private struct SignedDifference
{
    int sign;
    CoordinateMagnitude magnitude;
}


private struct SignedProduct
{
    int sign;
    ProductMagnitude magnitude;
}


/*
 * Unsigned fixed-width comparison.
 *
 * Returns:
 *
 *     -1 lhs < rhs
 *      0 lhs == rhs
 *      1 lhs > rhs
 */
private int compareUnsigned(size_t Limbs)(
    ref const UIntFixed!Limbs lhs,
    ref const UIntFixed!Limbs rhs
)
    pure nothrow @safe @nogc
{
    size_t index = Limbs;

    while (index > 0)
    {
        --index;

        if (lhs.limb[index] < rhs.limb[index])
            return -1;

        if (lhs.limb[index] > rhs.limb[index])
            return 1;
    }

    return 0;
}


/*
 * Exact fixed-width unsigned addition.
 *
 * The caller guarantees that the mathematical result fits.
 */
private UIntFixed!Limbs addUnsigned(size_t Limbs)(
    ref const UIntFixed!Limbs lhs,
    ref const UIntFixed!Limbs rhs
)
    pure nothrow @safe @nogc
{
    UIntFixed!Limbs result;

    ulong carry = 0;

    foreach (index; 0 .. Limbs)
    {
        const ulong sum =
            cast(ulong) lhs.limb[index] +
            cast(ulong) rhs.limb[index] +
            carry;

        result.limb[index] =
            cast(uint) sum;

        carry =
            sum >> 32;
    }

    /*
     * The chosen coordinate width is sufficient for every possible
     * signed binary64 coordinate difference.
     */
    assert(carry == 0);

    return result;
}


/*
 * Exact fixed-width unsigned subtraction.
 *
 * Precondition:
 *
 *     lhs >= rhs
 */
private UIntFixed!Limbs subtractUnsigned(size_t Limbs)(
    ref const UIntFixed!Limbs lhs,
    ref const UIntFixed!Limbs rhs
)
    pure nothrow @safe @nogc
{
    assert(
        compareUnsigned(lhs, rhs) >= 0
    );

    UIntFixed!Limbs result;

    ulong borrow = 0;

    foreach (index; 0 .. Limbs)
    {
        const ulong lhsValue =
            cast(ulong) lhs.limb[index];

        const ulong rhsValue =
            cast(ulong) rhs.limb[index] +
            borrow;

        if (lhsValue >= rhsValue)
        {
            result.limb[index] =
                cast(uint)(
                    lhsValue - rhsValue
                );

            borrow = 0;
        }
        else
        {
            /*
             * Compute:
             *
             *     lhs + 2^32 - rhs
             *
             * without constructing 2^32 as uint.
             */
            result.limb[index] =
                cast(uint)(
                    (0x1_0000_0000UL +
                     lhsValue) -
                    rhsValue
                );

            borrow = 1;
        }
    }

    assert(borrow == 0);

    return result;
}


/*
 * Places one binary64 mantissa at the requested bit position.
 *
 * mantissa uses at most 53 bits.
 *
 * The destination is initially zero, so bitwise OR is sufficient.
 */
private void setShiftedMantissa(
    ref CoordinateMagnitude result,
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

    if (base + 1 < coordinateLimbs)
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

        assert(base + 1 < coordinateLimbs);

        result.limb[base + 1] |=
            cast(uint) shiftedUpper;

        if (base + 2 < coordinateLimbs)
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


/*
 * Exact finite binary64 -> signed integer conversion in units of
 * 2^-1074.
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
 * Therefore after division by 2^-1074:
 *
 *     integer =
 *         mantissa
 *         << (rawExponent - 1)
 */
private SignedCoordinate decodeCoordinate(
    double value
)
    pure nothrow @safe @nogc
{
    assert(isFinite(value));

    DoubleRep representation;

    representation.value = value;

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
        mantissa = fraction;
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

    SignedCoordinate result;

    if (mantissa == 0)
    {
        /*
         * +0 and -0 represent the same mathematical coordinate.
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


/*
 * Exact signed difference:
 *
 *     lhs - rhs
 */
private SignedDifference subtractCoordinates(
    ref const SignedCoordinate lhs,
    ref const SignedCoordinate rhs
)
    pure nothrow @safe @nogc
{
    SignedDifference result;

    if (lhs.sign == 0)
    {
        result.sign =
            -rhs.sign;

        result.magnitude =
            rhs.magnitude;

        return result;
    }

    if (rhs.sign == 0)
    {
        result.sign =
            lhs.sign;

        result.magnitude =
            lhs.magnitude;

        return result;
    }

    if (lhs.sign != rhs.sign)
    {
        /*
         * Examples:
         *
         *     (+A) - (-B) = +(A+B)
         *     (-A) - (+B) = -(A+B)
         */
        result.sign =
            lhs.sign;

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
    {
        result.sign = 0;
        return result;
    }

    if (comparison > 0)
    {
        result.sign =
            lhs.sign;

        result.magnitude =
            subtractUnsigned(
                lhs.magnitude,
                rhs.magnitude
            );
    }
    else
    {
        result.sign =
            -lhs.sign;

        result.magnitude =
            subtractUnsigned(
                rhs.magnitude,
                lhs.magnitude
            );
    }

    return result;
}


/*
 * Exact 66-limb x 66-limb multiplication using base-2^32 arithmetic.
 *
 * Each inner accumulator is bounded by:
 *
 *     (2^32 - 1)^2
 *   + (2^32 - 1)
 *   + (2^32 - 1)
 *
 * = 2^64 - 1
 *
 * so ulong is exactly sufficient.
 */
private ProductMagnitude multiplyUnsigned(
    ref const CoordinateMagnitude lhs,
    ref const CoordinateMagnitude rhs
)
    pure nothrow @safe @nogc
{
    ProductMagnitude result;

    foreach (i; 0 .. coordinateLimbs)
    {
        ulong carry = 0;

        foreach (j; 0 .. coordinateLimbs)
        {
            const size_t index =
                i + j;

            const ulong accumulated =
                cast(ulong) lhs.limb[i] *
                    cast(ulong) rhs.limb[j]
                + cast(ulong)
                    result.limb[index]
                + carry;

            result.limb[index] =
                cast(uint) accumulated;

            carry =
                accumulated >> 32;
        }

        const size_t carryIndex =
            i + coordinateLimbs;

        assert(
            carryIndex <
            productLimbs
        );

        /*
         * This position has not yet received a final carry from the
         * current outer iteration.
         */
        result.limb[carryIndex] =
            cast(uint) carry;
    }

    return result;
}


private SignedProduct multiplyDifferences(
    ref const SignedDifference lhs,
    ref const SignedDifference rhs
)
    pure nothrow @safe @nogc
{
    SignedProduct result;

    if (lhs.sign == 0 ||
        rhs.sign == 0)
    {
        result.sign = 0;
        return result;
    }

    result.sign =
        lhs.sign == rhs.sign
            ? 1
            : -1;

    result.magnitude =
        multiplyUnsigned(
            lhs.magnitude,
            rhs.magnitude
        );

    return result;
}


/*
 * Exact sign of:
 *
 *     p - q
 *
 * without materializing the potentially one-bit-wider determinant.
 */
private int productDifferenceSign(
    ref const SignedProduct p,
    ref const SignedProduct q
)
    pure nothrow @safe @nogc
{
    if (p.sign == 0)
        return -q.sign;

    if (q.sign == 0)
        return p.sign;

    if (p.sign != q.sign)
        return p.sign;

    const int comparison =
        compareUnsigned(
            p.magnitude,
            q.magnitude
        );

    if (comparison == 0)
        return 0;

    return p.sign > 0
        ? comparison
        : -comparison;
}


/**
 * Exact orient2d sign for every finite binary64 input.
 *
 * Returns:
 *
 *     sign < 0  -> right
 *     sign == 0 -> collinear
 *     sign > 0  -> left
 *
 * Preconditions:
 *
 *     all six coordinates are finite.
 *
 * No floating-point arithmetic is used after decoding the inputs.
 */
int orientationDyadicExact(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy
)
    pure nothrow @safe @nogc
{
    assert(isFinite(ax));
    assert(isFinite(ay));
    assert(isFinite(bx));
    assert(isFinite(by));
    assert(isFinite(cx));
    assert(isFinite(cy));

    const auto aX =
        decodeCoordinate(ax);

    const auto aY =
        decodeCoordinate(ay);

    const auto bX =
        decodeCoordinate(bx);

    const auto bY =
        decodeCoordinate(by);

    const auto cX =
        decodeCoordinate(cx);

    const auto cY =
        decodeCoordinate(cy);

    const auto bAx =
        subtractCoordinates(
            bX,
            aX
        );

    const auto bAy =
        subtractCoordinates(
            bY,
            aY
        );

    const auto cAx =
        subtractCoordinates(
            cX,
            aX
        );

    const auto cAy =
        subtractCoordinates(
            cY,
            aY
        );

    const auto p =
        multiplyDifferences(
            bAx,
            cAy
        );

    const auto q =
        multiplyDifferences(
            bAy,
            cAx
        );

    return productDifferenceSign(
        p,
        q
    );
}


@safe unittest
{
    /*
     * Basic semantics.
     */
    assert(
        orientationDyadicExact(
            0.0, 0.0,
            10.0, 0.0,
            5.0, 1.0
        ) > 0
    );

    assert(
        orientationDyadicExact(
            0.0, 0.0,
            10.0, 0.0,
            5.0, -1.0
        ) < 0
    );

    assert(
        orientationDyadicExact(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 5.0
        ) == 0
    );


    /*
     * One ulp either side of the diagonal.
     */
    assert(
        orientationDyadicExact(
            0.0, 0.0,
            10.0, 10.0,
            5.0,
            0x1.4000000000001p+2
        ) > 0
    );

    assert(
        orientationDyadicExact(
            0.0, 0.0,
            10.0, 10.0,
            5.0,
            0x1.3ffffffffffffp+2
        ) < 0
    );


    /*
     * Smallest positive binary64 subnormal.
     *
     * The exact determinant is:
     *
     *     2^-1074 * 2^-1074
     *   = 2^-2148
     *
     * which cannot be represented by binary64, but its sign remains
     * exact here.
     */
    enum double minSubnormal =
        0x0.0000000000001p-1022;

    assert(
        orientationDyadicExact(
            0.0, 0.0,
            minSubnormal, 0.0,
            0.0, minSubnormal
        ) > 0
    );


    /*
     * Maximum finite coordinates.
     *
     * The determinant magnitude overflows binary64 immediately in a
     * naive implementation.
     */
    assert(
        orientationDyadicExact(
            0.0, 0.0,
            double.max, 0.0,
            0.0, double.max
        ) > 0
    );


    /*
     * Coordinate subtraction may itself exceed binary64 range.
     */
    assert(
        orientationDyadicExact(
            -double.max, 0.0,
             double.max, 0.0,
             0.0, 1.0
        ) > 0
    );


    /*
     * Exact collinearity across the complete finite exponent range.
     */
    assert(
        orientationDyadicExact(
            -double.max,
            -double.max,

             double.max,
             double.max,

             0.0,
             0.0
        ) == 0
    );


    /*
     * Signed zero has no geometric effect.
     */
    assert(
        orientationDyadicExact(
            -0.0, +0.0,
             1.0,  0.0,
             0.0,  1.0
        ) > 0
    );


    /*
     * Cyclic permutations preserve sign.
     */
    {
        const int abc =
            orientationDyadicExact(
                1.0, 2.0,
                8.0, 3.0,
                4.0, 9.0
            );

        const int bca =
            orientationDyadicExact(
                8.0, 3.0,
                4.0, 9.0,
                1.0, 2.0
            );

        const int acb =
            orientationDyadicExact(
                1.0, 2.0,
                4.0, 9.0,
                8.0, 3.0
            );

        assert(abc > 0);
        assert(bca == abc);
        assert(acb == -abc);
    }


    /*
     * Decoder boundary checks.
     */
    {
        const auto zero =
            decodeCoordinate(0.0);

        const auto negativeZero =
            decodeCoordinate(-0.0);

        assert(zero.sign == 0);
        assert(negativeZero.sign == 0);

        const auto smallest =
            decodeCoordinate(
                minSubnormal
            );

        assert(smallest.sign == 1);
        assert(smallest.magnitude.limb[0] == 1);

        foreach (
            index;
            1 .. coordinateLimbs
        )
        {
            assert(
                smallest.magnitude
                    .limb[index] == 0
            );
        }
    }
}
