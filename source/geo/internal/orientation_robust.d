module geo.internal.orientation_robust;

import geo.internal.orientation_exact :
    tryOrientationExactExpansion;

import geo.internal.orientation_filter :
    OrientationFilterResult,
    orientationFilter;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Combines the certified binary64 fast filter with the current exact
 * expansion fallback.
 *
 * This is still not the complete public floating-point predicate:
 * the exact backend currently declines extreme exponent ranges.
 */


/**
 * Robust orientation sign for the binary64 domain currently supported
 * by the combined filter and exact expansion backend.
 *
 * Returns true when a mathematically correct sign has been established.
 *
 * On success:
 *
 *     sign < 0  -> right
 *     sign == 0 -> collinear
 *     sign > 0  -> left
 *
 * Returns false when the current exact backend cannot yet cover the
 * input, for example because an extreme exponent range requires the
 * later scaled exact implementation.
 *
 * Non-finite inputs also return false.
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
            return tryOrientationExactExpansion(
                ax, ay,
                bx, by,
                cx, cy,
                sign
            );
    }
}


@safe unittest
{
    /*
     * Easy cases are resolved by the fast filter.
     */
    {
        int sign;

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
     * Structurally exact zero handled by the filter.
     */
    {
        int sign;

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
     * General diagonal collinearity is uncertain in the first-stage
     * filter and therefore exercises the exact fallback.
     */
    {
        int sign;

        assert(
            orientationFilter(
                0.0, 0.0,
                10.0, 10.0,
                5.0, 5.0
            ) == OrientationFilterResult.uncertain
        );

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
     * One ulp above the diagonal also goes through the exact fallback.
     */
    {
        int sign;

        enum double y =
            0x1.4000000000001p+2;

        assert(
            orientationFilter(
                0.0, 0.0,
                10.0, 10.0,
                5.0, y
            ) == OrientationFilterResult.uncertain
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
     * One ulp below the diagonal.
     */
    {
        int sign;

        enum double y =
            0x1.3ffffffffffffp+2;

        assert(
            tryOrientationRobustDouble(
                0.0, 0.0,
                10.0, 10.0,
                5.0, y,
                sign
            )
        );

        assert(sign < 0);
    }


    /*
     * Permutation identities survive the complete internal pipeline.
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
     * Non-finite values remain outside the predicate domain.
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
    }


    /*
     * Extreme exponent cases remain deliberately unsupported by the
     * current exact expansion backend.
     *
     * The public double orientation overload must therefore remain
     * disabled.
     */
    {
        int sign;

        assert(
            !tryOrientationRobustDouble(
                0.0, 0.0,
                0x1p+500, 0x1p+500,
                0x1p+499,
                0x1p+499,
                sign
            )
        );
    }
}
