module geo.internal.orientation_filter;

import geo.internal.binary64_rounding :
    roundedAdd,
    roundedMul,
    roundedSub;
import std.math.traits :
    isFinite,
    isSubnormal;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * This is not part of the public geo-d API.
 *
 * The filter may return uncertain. Public robust orientation must not
 * expose this state; uncertain inputs require the later exact/adaptive
 * fallback.
 */
enum OrientationFilterResult : byte
{
    right     = -1,
    collinear =  0,
    left      =  1,
    uncertain =  2,
}


/*
 * Shewchuk orient2d first-stage error coefficient for IEEE binary64:
 *
 *     epsilon      = 2^-53
 *     ccwerrboundA = (3 + 16 * epsilon) * epsilon
 *
 * Exact binary64 representation:
 *
 *     0x1.8000000000004p-52
 */
private enum double ccwErrboundA =
    0x1.8000000000004p-52;

/*
 * This initial certified filter deliberately refuses to reason through
 * subnormal intermediates.
 *
 * Such cases are rare and will be handled by the later adaptive/exact
 * path. Being conservative here keeps the fast-path proof simple.
 */
private bool normalOrZero(double value)
    pure nothrow @safe @nogc
{
    return value == 0.0 || (
        isFinite(value) &&
        !isSubnormal(value)
    );
}


/*
 * True when a product that rounded to zero may actually have been a
 * non-zero value lost through underflow.
 */
private bool productUnderflowed(
    double lhs,
    double rhs,
    double product
)
    pure nothrow @safe @nogc
{
    return product == 0.0 &&
           lhs != 0.0 &&
           rhs != 0.0;
}


/**
 * Certified first-stage floating-point orientation filter.
 *
 * The determinant is mathematically equivalent to
 *
 *     cross(b - a, c - a)
 *
 * but is evaluated in Shewchuk's orient2d arrangement:
 *
 *     detleft  = (ax - cx) * (by - cy)
 *     detright = (ay - cy) * (bx - cx)
 *     det      = detleft - detright
 *
 * Returns:
 *
 *     left / right
 *         only when the sign is certified;
 *
 *     collinear
 *         only in structurally exact zero-product cases;
 *
 *     uncertain
 *         when adaptive/exact arithmetic is required.
 *
 * Non-finite input and unsafe overflow/underflow intermediates are
 * conservatively classified as uncertain.
 */
OrientationFilterResult orientationFilter(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy
)
    pure nothrow @safe @nogc
{
    if (!isFinite(ax) ||
        !isFinite(ay) ||
        !isFinite(bx) ||
        !isFinite(by) ||
        !isFinite(cx) ||
        !isFinite(cy))
    {
        return OrientationFilterResult.uncertain;
    }

    const double acx = roundedSub(ax, cx);
    const double bcx = roundedSub(bx, cx);
    const double acy = roundedSub(ay, cy);
    const double bcy = roundedSub(by, cy);

    /*
     * Difference overflow or subnormal arithmetic is left to the
     * fallback.
     */
    if (!normalOrZero(acx) ||
        !normalOrZero(bcx) ||
        !normalOrZero(acy) ||
        !normalOrZero(bcy))
    {
        return OrientationFilterResult.uncertain;
    }

    const double detleft =
        roundedMul(acx, bcy);

    const double detright =
        roundedMul(acy, bcx);

    /*
     * Do not interpret multiplication underflow as an exact zero.
     */
    if (productUnderflowed(
            acx,
            bcy,
            detleft
        ) ||
        productUnderflowed(
            acy,
            bcx,
            detright
        ))
    {
        return OrientationFilterResult.uncertain;
    }

    if (!normalOrZero(detleft) ||
        !normalOrZero(detright))
    {
        return OrientationFilterResult.uncertain;
    }

    double detsum;

    /*
     * Opposite product signs determine the determinant sign directly.
     *
     * No subtraction or error bound is required.
     */
    if (detleft > 0.0)
    {
        if (detright <= 0.0)
            return OrientationFilterResult.left;

        detsum = roundedAdd(
            detleft,
            detright
        );
    }
    else if (detleft < 0.0)
    {
        if (detright >= 0.0)
            return OrientationFilterResult.right;

        detsum = roundedAdd(
            -detleft,
            -detright
        );
    }
    else
    {
        /*
         * detleft is an exact zero here: multiplication underflow has
         * already been excluded.
         */
        if (detright > 0.0)
            return OrientationFilterResult.right;

        if (detright < 0.0)
            return OrientationFilterResult.left;

        /*
         * Both products are exact zero products.
         *
         * This covers cases such as coincident points, horizontal
         * triples and vertical triples. General diagonal collinearity
         * does NOT normally reach this branch and remains uncertain
         * until the exact fallback exists.
         */
        return OrientationFilterResult.collinear;
    }

    if (!isFinite(detsum) ||
        isSubnormal(detsum))
    {
        return OrientationFilterResult.uncertain;
    }

    const double det =
        roundedSub(
            detleft,
            detright
        );

    /*
     * A same-sign subtraction cannot normally overflow, but keep the
     * filter conservative and explicit.
     */
    if (!isFinite(det) ||
        (det != 0.0 && isSubnormal(det)))
    {
        return OrientationFilterResult.uncertain;
    }

    const double errbound =
        roundedMul(
            ccwErrboundA,
            detsum
        );

    /*
     * Do not certify a result through an underflowed error bound.
     */
    if (!isFinite(errbound) ||
        errbound == 0.0 ||
        isSubnormal(errbound))
    {
        return OrientationFilterResult.uncertain;
    }

    if (det >= errbound)
        return OrientationFilterResult.left;

    if (-det >= errbound)
        return OrientationFilterResult.right;

    return OrientationFilterResult.uncertain;
}


@safe unittest
{
    alias R = OrientationFilterResult;


    /*
     * Easy opposite-sign products are certified immediately.
     */
    assert(
        orientationFilter(
            0.0, 0.0,
            10.0, 0.0,
            5.0, 1.0
        ) == R.left
    );

    assert(
        orientationFilter(
            0.0, 0.0,
            10.0, 0.0,
            5.0, -1.0
        ) == R.right
    );


    /*
     * Structurally exact horizontal and vertical collinearity can be
     * certified without an adaptive fallback.
     */
    assert(
        orientationFilter(
            0.0, 0.0,
            10.0, 0.0,
            5.0, 0.0
        ) == R.collinear
    );

    assert(
        orientationFilter(
            2.0, -5.0,
            2.0, 10.0,
            2.0, 1.0
        ) == R.collinear
    );


    /*
     * General diagonal collinearity produces cancelling non-zero
     * products and must remain uncertain until the exact fallback is
     * available.
     */
    assert(
        orientationFilter(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 5.0
        ) == R.uncertain
    );


    /*
     * One ulp above the diagonal is genuinely left of the line, but the
     * binary64 determinant is too close to zero for the first-stage
     * error bound to certify it.
     *
     * 0x1.4000000000001p+2 is nextUp(5.0).
     */
    assert(
        orientationFilter(
            0.0, 0.0,
            10.0, 10.0,
            5.0,
            0x1.4000000000001p+2
        ) == R.uncertain
    );


    /*
     * A larger displacement from the same diagonal is safely certified.
     */
    assert(
        orientationFilter(
            0.0, 0.0,
            10.0, 10.0,
            5.0,
            0x1.4000000000010p+2
        ) == R.left
    );


    /*
     * Non-finite public-coordinate values are not part of the robust
     * floating predicate domain.
     */
    assert(
        orientationFilter(
            double.infinity, 0.0,
            1.0, 0.0,
            0.0, 1.0
        ) == R.uncertain
    );

    assert(
        orientationFilter(
            double.nan, 0.0,
            1.0, 0.0,
            0.0, 1.0
        ) == R.uncertain
    );


    /*
     * Finite coordinates may still produce an overflowing subtraction.
     * The fast filter must refuse to certify such an input.
     */
    assert(
        orientationFilter(
            double.max, 0.0,
            0.0, 1.0,
            -double.max, 0.0
        ) == R.uncertain
    );


    /*
     * Subnormal differences are conservatively delegated to the
     * adaptive/exact path.
     *
     * This is the smallest positive binary64 subnormal value.
     */
    enum double minSubnormal =
        0x0.0000000000001p-1022;

    assert(
        orientationFilter(
            0.0, 0.0,
            minSubnormal, 0.0,
            0.0, minSubnormal
        ) == R.uncertain
    );


    /*
     * Filter result values deliberately mirror Orientation2 for the
     * three geometric states, while uncertain remains distinct.
     */
    static assert(
        cast(byte) R.right == -1
    );

    static assert(
        cast(byte) R.collinear == 0
    );

    static assert(
        cast(byte) R.left == 1
    );

    static assert(
        R.uncertain != R.left &&
        R.uncertain != R.right &&
        R.uncertain != R.collinear
    );
}
