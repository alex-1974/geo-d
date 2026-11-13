module geo.internal.orientation_dyadic;

import geo.internal.dyadic :
    SignedDyadicCoordinate,
    SignedDyadicProduct,
    decodeBinary64Coordinate,
    decodeDyadicCoordinate,
    dyadicCoordinateLimbs,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

import geo.internal.fixed_uint :
    UIntFixed,
    compareUnsigned,
    multiplyUnsigned;

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


/*
 * A product of two coordinate differences requires at most:
 *
 *     2099 + 2099 = 4198 bits.
 *
 * 132 x 32 = 4224 bits.
 */


/*
 * Exact signed integer represented as sign + unsigned magnitude.
 */

/**
 * Exact orient2d determinant for supported geo-d scalar coordinates.
 *
 * Computes:
 *
 *     (bx - ax) * (cy - ay)
 *       -
 *     (by - ay) * (cx - ax)
 *
 * The returned value is exact and represented as a signed fixed-width
 * dyadic product in units of 2^-2148.
 *
 * Supported scalar types:
 *
 *     int
 *     long
 *     float
 *     double
 *
 * Floating-point coordinates must be finite.
 *
 * This function intentionally returns the exact determinant rather
 * than only its sign. Robust orientation consumes the sign; geometric
 * construction may additionally consume the exact magnitude.
 */
/*
 * Exact orient2d determinant from coordinates that are already decoded into
 * the common dyadic domain.
 *
 * This package-internal entry point exists for construction hot paths that
 * deliberately hoist scalar decoding out of repeated edge work. The ordinary
 * scalar wrapper below remains unchanged.
 */
package(geo)
SignedDyadicProduct orientationDeterminantDyadicDecoded(
    ref const SignedDyadicCoordinate aX,
    ref const SignedDyadicCoordinate aY,
    ref const SignedDyadicCoordinate bX,
    ref const SignedDyadicCoordinate bY,
    ref const SignedDyadicCoordinate cX,
    ref const SignedDyadicCoordinate cY
)
    pure nothrow @safe @nogc
{
    const auto bAx =
        subtractDyadicCoordinates(
            bX,
            aX
        );

    const auto bAy =
        subtractDyadicCoordinates(
            bY,
            aY
        );

    const auto cAx =
        subtractDyadicCoordinates(
            cX,
            aX
        );

    const auto cAy =
        subtractDyadicCoordinates(
            cY,
            aY
        );

    const auto p =
        multiplyDyadicDifferences(
            bAx,
            cAy
        );

    const auto q =
        multiplyDyadicDifferences(
            bAy,
            cAx
        );

    return
        subtractDyadicProducts(
            p,
            q
        );
}


SignedDyadicProduct orientationDeterminantDyadic(T)(
    T ax,
    T ay,
    T bx,
    T by,
    T cx,
    T cy
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    static if (
        is(T == float) ||
        is(T == double)
    )
    {
        assert(isFinite(ax));
        assert(isFinite(ay));
        assert(isFinite(bx));
        assert(isFinite(by));
        assert(isFinite(cx));
        assert(isFinite(cy));
    }

    const auto aX =
        decodeDyadicCoordinate(ax);

    const auto aY =
        decodeDyadicCoordinate(ay);

    const auto bX =
        decodeDyadicCoordinate(bx);

    const auto bY =
        decodeDyadicCoordinate(by);

    const auto cX =
        decodeDyadicCoordinate(cx);

    const auto cY =
        decodeDyadicCoordinate(cy);

    const auto bAx =
        subtractDyadicCoordinates(
            bX,
            aX
        );

    const auto bAy =
        subtractDyadicCoordinates(
            bY,
            aY
        );

    const auto cAx =
        subtractDyadicCoordinates(
            cX,
            aX
        );

    const auto cAy =
        subtractDyadicCoordinates(
            cY,
            aY
        );

    const auto p =
        multiplyDyadicDifferences(
            bAx,
            cAy
        );

    const auto q =
        multiplyDyadicDifferences(
            bAy,
            cAx
        );

    return subtractDyadicProducts(
        p,
        q
    );
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
    const auto determinant =
        orientationDeterminantDyadic(
            ax,
            ay,
            bx,
            by,
            cx,
            cy
        );

    return determinant.sign;
}


/* Exact sign path for coordinates that are all zero or subnormal. */
package(geo) int orientationSubnormalExact(
    double ax, double ay, double bx, double by, double cx, double cy
)
    pure nothrow @safe @nogc
{
    DoubleRep[6] representations;
    representations[0].value = ax;
    representations[1].value = ay;
    representations[2].value = bx;
    representations[3].value = by;
    representations[4].value = cx;
    representations[5].value = cy;

    long[6] values;
    foreach (i, ref representation; representations)
    {
        assert(representation.exponent == 0);
        const long magnitude = cast(long) representation.fraction;
        values[i] = representation.sign ? -magnitude : magnitude;
    }

    alias Word = UIntFixed!2;
    alias Product = UIntFixed!4;

    Product product(long lhs, long rhs)
        pure nothrow @safe @nogc
    {
        if (lhs == 0 || rhs == 0)
            return Product.init;

        const ulong lhsMagnitude = cast(ulong)(lhs < 0 ? -lhs : lhs);
        const ulong rhsMagnitude = cast(ulong)(rhs < 0 ? -rhs : rhs);
        Word lhsWord;
        Word rhsWord;
        lhsWord.limb[0] = cast(uint) lhsMagnitude;
        lhsWord.limb[1] = cast(uint)(lhsMagnitude >> 32);
        rhsWord.limb[0] = cast(uint) rhsMagnitude;
        rhsWord.limb[1] = cast(uint)(rhsMagnitude >> 32);
        return multiplyUnsigned(lhsWord, rhsWord);
    }

    const long bAx = values[2] - values[0];
    const long bAy = values[3] - values[1];
    const long cAx = values[4] - values[0];
    const long cAy = values[5] - values[1];
    const Product p = product(bAx, cAy);
    const Product q = product(bAy, cAx);
    const bool pNegative = (bAx < 0) != (cAy < 0);
    const bool qNegative = (bAy < 0) != (cAx < 0);

    if (pNegative != qNegative)
        return pNegative ? -1 : 1;

    const int comparison = compareUnsigned(p, q);
    if (comparison == 0)
        return 0;

    return pNegative ? -comparison : comparison;
}


/*
 * Exact narrow-scale path for finite values whose decoded exponents are
 * close enough to share a compact integer scale. This covers near-dyadic
 * cancellation without constructing the general 66/132-limb carriers.
 */
package(geo) bool tryOrientationNarrowExact(
    double ax, double ay, double bx, double by, double cx, double cy,
    out int sign
)
    pure nothrow @safe @nogc
{
    DoubleRep[6] representations;
    representations[0].value = ax;
    representations[1].value = ay;
    representations[2].value = bx;
    representations[3].value = by;
    representations[4].value = cx;
    representations[5].value = cy;

    uint minimumShift = uint.max;
    foreach (ref representation; representations)
    {
        if (representation.fraction == 0 && representation.exponent == 0)
            continue;
        const uint shift = representation.exponent == 0
            ? 0
            : representation.exponent - 1;
        if (shift < minimumShift)
            minimumShift = shift;
    }

    if (minimumShift == uint.max)
    {
        sign = 0;
        return true;
    }

    long[6] values;
    foreach (i, ref representation; representations)
    {
        if (representation.fraction == 0 && representation.exponent == 0)
            continue;
        const ulong mantissa = representation.exponent == 0
            ? representation.fraction
            : (1UL << 52) | representation.fraction;
        const uint shift = representation.exponent == 0
            ? 0
            : representation.exponent - 1;
        const uint relativeShift = shift - minimumShift;
        if (relativeShift > 9)
            return false;
        const ulong magnitude = mantissa << relativeShift;
        if (magnitude >= (1UL << 62))
            return false;
        values[i] = representation.sign
            ? -cast(long) magnitude
            : cast(long) magnitude;
    }

    alias Word = UIntFixed!2;
    alias Product = UIntFixed!4;
    Product product(long lhs, long rhs)
        pure nothrow @safe @nogc
    {
        if (lhs == 0 || rhs == 0)
            return Product.init;
        const ulong lhsMagnitude = cast(ulong)(lhs < 0 ? -lhs : lhs);
        const ulong rhsMagnitude = cast(ulong)(rhs < 0 ? -rhs : rhs);
        Word lhsWord;
        Word rhsWord;
        lhsWord.limb[0] = cast(uint) lhsMagnitude;
        lhsWord.limb[1] = cast(uint)(lhsMagnitude >> 32);
        rhsWord.limb[0] = cast(uint) rhsMagnitude;
        rhsWord.limb[1] = cast(uint)(rhsMagnitude >> 32);
        return multiplyUnsigned(lhsWord, rhsWord);
    }

    const long bAx = values[2] - values[0];
    const long bAy = values[3] - values[1];
    const long cAx = values[4] - values[0];
    const long cAy = values[5] - values[1];
    const Product p = product(bAx, cAy);
    const Product q = product(bAy, cAx);
    const bool pNegative = (bAx < 0) != (cAy < 0);
    const bool qNegative = (bAy < 0) != (cAx < 0);
    if (pNegative != qNegative)
    {
        sign = pNegative ? -1 : 1;
        return true;
    }
    const int comparison = compareUnsigned(p, q);
    sign = comparison == 0 ? 0 : (pNegative ? -comparison : comparison);
    return true;
}


@safe unittest
{
    int sign;
    const double large = 0x1p+500;
    const double half = 0x1p+499;

    assert(tryOrientationNarrowExact(
        0.0, 0.0,
        large, large,
        half, 0x1.0000000000001p+499,
        sign
    ));
    assert(sign > 0);

    assert(tryOrientationNarrowExact(
        0.0, 0.0,
        large, large,
        half, 0x1.fffffffffffffp+498,
        sign
    ));
    assert(sign < 0);

    assert(!tryOrientationNarrowExact(
        0.0, 0.0,
        double.max, double.max,
        0x0.0000000000001p-1022, 0.0,
        sign
    ));
}


@safe unittest
{
    /*
     * The same exact unit-triangle determinant must be obtained from
     * every currently supported scalar type.
     */
    const auto fromInt =
        orientationDeterminantDyadic(
            0, 0,
            1, 0,
            0, 1
        );

    const auto fromLong =
        orientationDeterminantDyadic(
            0L, 0L,
            1L, 0L,
            0L, 1L
        );

    const auto fromFloat =
        orientationDeterminantDyadic(
            0.0f, 0.0f,
            1.0f, 0.0f,
            0.0f, 1.0f
        );

    const auto fromDouble =
        orientationDeterminantDyadic(
            0.0, 0.0,
            1.0, 0.0,
            0.0, 1.0
        );

    assert(fromInt.sign == 1);
    assert(fromLong.sign == 1);
    assert(fromFloat.sign == 1);
    assert(fromDouble.sign == 1);

    assert(
        fromInt.magnitude.limb ==
        fromLong.magnitude.limb
    );

    assert(
        fromInt.magnitude.limb ==
        fromFloat.magnitude.limb
    );

    assert(
        fromInt.magnitude.limb ==
        fromDouble.magnitude.limb
    );


    /*
     * Prepared-coordinate construction uses the same determinant arithmetic
     * as the scalar wrapper.
     */
    {
        const auto aX = decodeDyadicCoordinate(0.0);
        const auto aY = decodeDyadicCoordinate(0.0);
        const auto bX = decodeDyadicCoordinate(1.0);
        const auto bY = decodeDyadicCoordinate(0.0);
        const auto cX = decodeDyadicCoordinate(0.0);
        const auto cY = decodeDyadicCoordinate(1.0);

        const auto decoded =
            orientationDeterminantDyadicDecoded(
                aX,
                aY,
                bX,
                bY,
                cX,
                cY
            );

        assert(decoded.sign == fromDouble.sign);
        assert(
            decoded.magnitude.limb ==
            fromDouble.magnitude.limb
        );
    }


    /*
     * Reversing two points negates the exact determinant while
     * preserving its magnitude.
     */
    const auto reversed =
        orientationDeterminantDyadic(
            0.0, 0.0,
            0.0, 1.0,
            1.0, 0.0
        );

    assert(reversed.sign == -1);

    assert(
        reversed.magnitude.limb ==
        fromDouble.magnitude.limb
    );


    /*
     * Collinearity produces canonical exact zero.
     */
    const auto collinear =
        orientationDeterminantDyadic(
            long.min, long.min,
            0L, 0L,
            long.max, long.max
        );

    assert(collinear.sign == 0);
    assert(collinear.magnitude.isZero);


    /*
     * real remains deliberately outside the current predicate backend.
     */
    static assert(
        !__traits(
            compiles,
            orientationDeterminantDyadic(
                cast(real) 0,
                cast(real) 0,
                cast(real) 1,
                cast(real) 0,
                cast(real) 0,
                cast(real) 1
            )
        )
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
            decodeBinary64Coordinate(0.0);

        const auto negativeZero =
            decodeBinary64Coordinate(-0.0);

        assert(zero.sign == 0);
        assert(negativeZero.sign == 0);

        const auto smallest =
            decodeBinary64Coordinate(
                minSubnormal
            );

        assert(smallest.sign == 1);
        assert(smallest.magnitude.limb[0] == 1);

        foreach (
            index;
            1 .. dyadicCoordinateLimbs
        )
        {
            assert(
                smallest.magnitude
                    .limb[index] == 0
            );
        }
    }
}
