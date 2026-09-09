module geo.internal.orientation_dyadic;

import geo.internal.dyadic :
    SignedDyadicProduct,
    decodeBinary64Coordinate,
    dyadicCoordinateLimbs,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

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

private int productDifferenceSign(
    ref const SignedDyadicProduct p,
    ref const SignedDyadicProduct q
)
    pure nothrow @safe @nogc
{
    const auto difference =
        subtractDyadicProducts(
            p,
            q
        );

    return difference.sign;
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
        decodeBinary64Coordinate(ax);

    const auto aY =
        decodeBinary64Coordinate(ay);

    const auto bX =
        decodeBinary64Coordinate(bx);

    const auto bY =
        decodeBinary64Coordinate(by);

    const auto cX =
        decodeBinary64Coordinate(cx);

    const auto cY =
        decodeBinary64Coordinate(cy);

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
