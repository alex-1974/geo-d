module geo.internal.orientation_robust;

import geo.internal.orientation_dyadic :
    orientationDyadicExact;

import geo.internal.orientation_exact :
    tryOrientationExactExpansion;

import geo.internal.orientation_filter :
    OrientationFilterResult,
    orientationFilter;

import std.math.traits : isFinite;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Complete robust orientation pipeline for binary64:
 *
 *     certified floating filter
 *         ->
 *     exact expansion fallback
 *         ->
 *     exact full-range dyadic fallback
 *
 * Every finite binary64 input is covered.
 */


/*
 * True when all coordinates belong to the mathematical domain of the
 * robust floating orientation predicate.
 */
private bool allFinite(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy
)
    pure nothrow @safe @nogc
{
    return isFinite(ax) &&
           isFinite(ay) &&
           isFinite(bx) &&
           isFinite(by) &&
           isFinite(cx) &&
           isFinite(cy);
}


/**
 * Robust orientation sign for binary64 coordinates.
 *
 * Returns true for every finite input and establishes the mathematically
 * exact orientation sign.
 *
 * On success:
 *
 *     sign < 0  -> right
 *     sign == 0 -> collinear
 *     sign > 0  -> left
 *
 * Returns false only when at least one input coordinate is NaN or
 * infinite.
 *
 * The implementation first uses the inexpensive certified floating
 * filter. Numerically uncertain cases enter exact expansion arithmetic.
 * Inputs outside that expansion backend's conservative exponent range
 * use the exact fixed-width dyadic fallback.
 */
bool tryOrientationRobustDouble(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
    out int sign
)
    pure nothrow @safe @nogc
{
    const auto filtered =
        orientationFilter(
            ax, ay,
            bx, by,
            cx, cy
        );

    final switch (filtered)
    {
        case OrientationFilterResult.right:
            sign = -1;
            return true;

        case OrientationFilterResult.collinear:
            sign = 0;
            return true;

        case OrientationFilterResult.left:
            sign = 1;
            return true;

        case OrientationFilterResult.uncertain:
            break;
    }

    /*
     * First exact fallback: fast stack-based expansion arithmetic.
     */
    if (tryOrientationExactExpansion(
            ax, ay,
            bx, by,
            cx, cy,
            sign
        ))
    {
        return true;
    }

    /*
     * Both internal exact backends use stronger preconditions than the
     * public binary64 predicate. Check the public domain before entering
     * the final fallback, whose finite-input contract is asserted.
     */
    if (!allFinite(
            ax, ay,
            bx, by,
            cx, cy
        ))
    {
        return false;
    }

    /*
     * Final fallback:
     *
     * decode every finite binary64 coordinate exactly as a dyadic
     * integer and determine the determinant sign using fixed-width
     * integer arithmetic.
     *
     * This covers the complete finite binary64 exponent range,
     * including subnormals and coordinate differences that overflow
     * ordinary double arithmetic.
     */
    sign =
        orientationDyadicExact(
            ax, ay,
            bx, by,
            cx, cy
        );

    return true;
}


@safe unittest
{
    alias R = OrientationFilterResult;


    /*
     * Easy cases remain on the certified fast path.
     */
    {
        int sign;

        assert(
            orientationFilter(
                0.0, 0.0,
                10.0, 0.0,
                5.0, 1.0
            ) == R.left
        );

        assert(
            tryOrientationRobustDouble(
                0.0, 0.0,
                10.0, 0.0,
                5.0, 1.0,
                sign
            )
        );

        assert(sign > 0);

        assert(
            tryOrientationRobustDouble(
                0.0, 0.0,
                10.0, 0.0,
                5.0, -1.0,
                sign
            )
        );

        assert(sign < 0);
    }


    /*
     * Structurally exact horizontal collinearity is resolved directly
     * by the filter.
     */
    {
        int sign;

        assert(
            orientationFilter(
                0.0, 0.0,
                10.0, 0.0,
                5.0, 0.0
            ) == R.collinear
        );

        assert(
            tryOrientationRobustDouble(
                0.0, 0.0,
                10.0, 0.0,
                5.0, 0.0,
                sign
            )
        );

        assert(sign == 0);
    }


    /*
     * General diagonal collinearity exercises the expansion fallback.
     */
    {
        int sign;

        assert(
            orientationFilter(
                0.0, 0.0,
                10.0, 10.0,
                5.0, 5.0
            ) == R.uncertain
        );

        int exactSign;

        assert(
            tryOrientationExactExpansion(
                0.0, 0.0,
                10.0, 10.0,
                5.0, 5.0,
                exactSign
            )
        );

        assert(exactSign == 0);

        assert(
            tryOrientationRobustDouble(
                0.0, 0.0,
                10.0, 10.0,
                5.0, 5.0,
                sign
            )
        );

        assert(sign == 0);
    }


    /*
     * One ulp above the diagonal is too close for the first-stage
     * filter but is exactly resolved by the expansion backend.
     */
    {
        enum double y =
            0x1.4000000000001p+2;

        int sign;

        assert(
            orientationFilter(
                0.0, 0.0,
                10.0, 10.0,
                5.0, y
            ) == R.uncertain
        );

        assert(
            tryOrientationRobustDouble(
                0.0, 0.0,
                10.0, 10.0,
                5.0, y,
                sign
            )
        );

        assert(sign > 0);
    }


    /*
     * Full-range dyadic fallback:
     *
     * the filter sees cancelling enormous products and cannot certify
     * the sign, while the expansion backend deliberately rejects the
     * exponent range.
     */
    {
        enum double large =
            0x1p+500;

        enum double half =
            0x1p+499;

        int sign;

        assert(
            orientationFilter(
                0.0, 0.0,
                large, large,
                half, half
            ) == R.uncertain
        );

        int expansionSign;

        assert(
            !tryOrientationExactExpansion(
                0.0, 0.0,
                large, large,
                half, half,
                expansionSign
            )
        );

        assert(
            tryOrientationRobustDouble(
                0.0, 0.0,
                large, large,
                half, half,
                sign
            )
        );

        assert(sign == 0);
    }


    /*
     * A near-collinear full-range case also requires the dyadic
     * fallback.
     *
     * c.y is one ulp above 2^499.
     */
    {
        enum double large =
            0x1p+500;

        enum double half =
            0x1p+499;

        enum double halfNext =
            0x1.0000000000001p+499;

        int sign;

        assert(
            orientationFilter(
                0.0, 0.0,
                large, large,
                half, halfNext
            ) == R.uncertain
        );

        int expansionSign;

        assert(
            !tryOrientationExactExpansion(
                0.0, 0.0,
                large, large,
                half, halfNext,
                expansionSign
            )
        );

        assert(
            tryOrientationRobustDouble(
                0.0, 0.0,
                large, large,
                half, halfNext,
                sign
            )
        );

        assert(sign > 0);
    }


    /*
     * Smallest positive subnormal values are also covered.
     */
    {
        enum double minSubnormal =
            0x0.0000000000001p-1022;

        int sign;

        assert(
            tryOrientationRobustDouble(
                0.0, 0.0,
                minSubnormal, 0.0,
                0.0, minSubnormal,
                sign
            )
        );

        assert(sign > 0);
    }


    /*
     * Finite coordinate subtraction may overflow ordinary binary64,
     * but the final exact fallback still resolves orientation.
     */
    {
        int sign;

        assert(
            tryOrientationRobustDouble(
                -double.max, 0.0,
                 double.max, 0.0,
                 0.0, 1.0,
                 sign
            )
        );

        assert(sign > 0);
    }


    /*
     * Exact collinearity spanning the complete finite double range.
     */
    {
        int sign;

        assert(
            tryOrientationRobustDouble(
                -double.max,
                -double.max,

                 double.max,
                 double.max,

                 0.0,
                 0.0,

                 sign
            )
        );

        assert(sign == 0);
    }


    /*
     * Permutation identities hold through the complete pipeline.
     */
    {
        int abc;
        int bca;
        int acb;

        assert(
            tryOrientationRobustDouble(
                1.0, 2.0,
                8.0, 3.0,
                4.0, 9.0,
                abc
            )
        );

        assert(
            tryOrientationRobustDouble(
                8.0, 3.0,
                4.0, 9.0,
                1.0, 2.0,
                bca
            )
        );

        assert(
            tryOrientationRobustDouble(
                1.0, 2.0,
                4.0, 9.0,
                8.0, 3.0,
                acb
            )
        );

        assert(abc > 0);
        assert(bca == abc);
        assert(acb == -abc);
    }


    /*
     * Non-finite values are the only unsupported binary64 inputs.
     */
    {
        int sign = 123;

        assert(
            !tryOrientationRobustDouble(
                double.nan, 0.0,
                1.0, 0.0,
                0.0, 1.0,
                sign
            )
        );

        assert(sign == 0);

        assert(
            !tryOrientationRobustDouble(
                double.infinity, 0.0,
                1.0, 0.0,
                0.0, 1.0,
                sign
            )
        );

        assert(sign == 0);
    }
}
