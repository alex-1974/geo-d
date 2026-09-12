module geo.internal.orientation_exact;

import geo.internal.expansion :
    ExpansionBuffer,
    TwoComponent,
    expansionSign,
    fastExpansionSumZeroElim,
    negateExpansion,
    scaleExpansionZeroElim,
    twoDiff;

import geo.internal.binary64_rounding : roundedSub;
import std.math.traits : isFinite;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact expansion fallback for orient2d.
 *
 * This first slice intentionally supports a conservative binary64
 * working range. It is not yet the complete finite-double backend.
 *
 * Public floating orientation must remain disabled until extreme
 * exponent ranges are handled as well.
 */


/*
 * The current Split/TwoProduct implementation has no exponent-scaling
 * layer yet.
 *
 * Keep all non-zero difference-expansion components comfortably inside
 * a range where:
 *
 * - splitter multiplication cannot overflow;
 * - pairwise products cannot overflow;
 * - even low-order product terms remain far from underflow.
 *
 * These bounds are deliberately conservative, not architectural API.
 */
private enum double minWorkingMagnitude =
    0x1p-450;

private enum double maxWorkingMagnitude =
    0x1p+450;

private double magnitude(double value)
    pure nothrow @safe @nogc
{
    return value < 0.0
        ? -value
        : value;
}


/*
 * Whether one expansion component lies inside the current proven EFT
 * working range.
 */
private bool supportedComponent(double value)
    pure nothrow @safe @nogc
{
    if (!isFinite(value))
        return false;

    if (value == 0.0)
        return true;

    const double absValue =
        magnitude(value);

    return absValue >= minWorkingMagnitude &&
           absValue <= maxWorkingMagnitude;
}


/*
 * Converts one TwoDiff result into canonical expansion order:
 *
 *     least significant -> most significant
 *
 * Exact zero becomes [0.0].
 */
private bool buildDifference(
    double lhs,
    double rhs,
    ref ExpansionBuffer!2 result
)
    pure nothrow @safe @nogc
{
    /*
     * twoDiff() asserts that the rounded subtraction is finite.
     * Check that precondition before calling it.
     */
    const double rounded =
        roundedSub(lhs, rhs);

    if (!isFinite(rounded))
        return false;

    const TwoComponent difference =
        twoDiff(lhs, rhs);

    if (!supportedComponent(difference.low) ||
        !supportedComponent(difference.high))
    {
        return false;
    }

    result.clear();

    if (difference.low != 0.0)
        result.append(difference.low);

    if (difference.high != 0.0)
        result.append(difference.high);

    if (result.empty)
        result.append(0.0);

    return true;
}


/*
 * Exact product of two at-most-two-component expansions.
 *
 * Each input represents an exact coordinate difference.
 *
 * Product construction:
 *
 *     lhs * rhs[0]
 *   + lhs * rhs[1]
 *
 * Each scale produces at most four components; their exact sum requires
 * at most eight.
 */
private void multiplyDifferenceExpansions(
    ref const ExpansionBuffer!2 lhs,
    ref const ExpansionBuffer!2 rhs,
    ref ExpansionBuffer!8 result
)
    pure nothrow @safe @nogc
{
    assert(!lhs.empty);
    assert(!rhs.empty);
    assert(rhs.length <= 2);

    ExpansionBuffer!4 first;
    ExpansionBuffer!4 second;

    scaleExpansionZeroElim(
        lhs,
        rhs[0],
        first
    );

    if (rhs.length == 2)
    {
        scaleExpansionZeroElim(
            lhs,
            rhs[1],
            second
        );
    }

    /*
     * An empty second buffer behaves as additive zero.
     */
    fastExpansionSumZeroElim(
        first,
        second,
        result
    );
}


/**
 * Exact orientation sign using floating-point expansions.
 *
 * Returns true when the current expansion backend can evaluate the
 * complete determinant exactly.
 *
 * On success:
 *
 *     sign < 0  -> right
 *     sign == 0 -> collinear
 *     sign > 0  -> left
 *
 * Returns false when:
 *
 * - an input coordinate is non-finite;
 * - a coordinate difference overflows binary64 before expansion;
 * - a required expansion component falls outside the conservative
 *   working range of the current Split/TwoProduct backend.
 *
 * `false` does NOT mean that orientation is undefined. It means that
 * the later exponent-scaled exact backend is required.
 */
bool tryOrientationExactExpansion(
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
    if (!isFinite(ax) ||
        !isFinite(ay) ||
        !isFinite(bx) ||
        !isFinite(by) ||
        !isFinite(cx) ||
        !isFinite(cy))
    {
        return false;
    }

    ExpansionBuffer!2 acx;
    ExpansionBuffer!2 acy;
    ExpansionBuffer!2 bcx;
    ExpansionBuffer!2 bcy;

    if (!buildDifference(ax, cx, acx) ||
        !buildDifference(ay, cy, acy) ||
        !buildDifference(bx, cx, bcx) ||
        !buildDifference(by, cy, bcy))
    {
        return false;
    }

    /*
     * det =
     *
     *     (ax - cx) * (by - cy)
     *   - (ay - cy) * (bx - cx)
     */
    ExpansionBuffer!8 leftProduct;
    ExpansionBuffer!8 rightProduct;

    multiplyDifferenceExpansions(
        acx,
        bcy,
        leftProduct
    );

    multiplyDifferenceExpansions(
        acy,
        bcx,
        rightProduct
    );

    ExpansionBuffer!8 negativeRight;

    negateExpansion(
        rightProduct,
        negativeRight
    );

    ExpansionBuffer!16 determinant;

    fastExpansionSumZeroElim(
        leftProduct,
        negativeRight,
        determinant
    );

    sign =
        expansionSign(determinant);

    return true;
}


@safe unittest
{
    /*
     * Basic orientation semantics.
     */
    {
        int sign;

        assert(
            tryOrientationExactExpansion(
                0.0, 0.0,
                10.0, 0.0,
                5.0, 1.0,
                sign
            )
        );

        assert(sign > 0);

        assert(
            tryOrientationExactExpansion(
                0.0, 0.0,
                10.0, 0.0,
                5.0, -1.0,
                sign
            )
        );

        assert(sign < 0);
    }


    /*
     * General diagonal collinearity is exact.
     *
     * This is one of the cases deliberately delegated by the fast
     * filter because its two non-zero products cancel exactly.
     */
    {
        int sign;

        assert(
            tryOrientationExactExpansion(
                0.0, 0.0,
                10.0, 10.0,
                5.0, 5.0,
                sign
            )
        );

        assert(sign == 0);
    }


    /*
     * One binary64 ulp above the diagonal.
     *
     * The first-stage floating filter classifies this input as
     * uncertain; the exact expansion backend must recover the positive
     * determinant sign.
     */
    {
        int sign;

        assert(
            tryOrientationExactExpansion(
                0.0, 0.0,
                10.0, 10.0,
                5.0,
                0x1.4000000000001p+2,
                sign
            )
        );

        assert(sign > 0);
    }


    /*
     * One binary64 ulp below the diagonal.
     */
    {
        int sign;

        assert(
            tryOrientationExactExpansion(
                0.0, 0.0,
                10.0, 10.0,
                5.0,
                0x1.3ffffffffffffp+2,
                sign
            )
        );

        assert(sign < 0);
    }


    /*
     * Degenerate directed line.
     */
    {
        int sign;

        assert(
            tryOrientationExactExpansion(
                7.0, -3.0,
                7.0, -3.0,
                100.0, 200.0,
                sign
            )
        );

        assert(sign == 0);
    }


    /*
     * Cyclic permutation preserves orientation.
     */
    {
        int first;
        int second;
        int third;

        assert(
            tryOrientationExactExpansion(
                1.0, 2.0,
                8.0, 3.0,
                4.0, 9.0,
                first
            )
        );

        assert(
            tryOrientationExactExpansion(
                8.0, 3.0,
                4.0, 9.0,
                1.0, 2.0,
                second
            )
        );

        assert(
            tryOrientationExactExpansion(
                4.0, 9.0,
                1.0, 2.0,
                8.0, 3.0,
                third
            )
        );

        assert(first > 0);
        assert(second == first);
        assert(third == first);
    }


    /*
     * Swapping two points reverses the sign.
     */
    {
        int forward;
        int reversed;

        assert(
            tryOrientationExactExpansion(
                1.0, 2.0,
                8.0, 3.0,
                4.0, 9.0,
                forward
            )
        );

        assert(
            tryOrientationExactExpansion(
                1.0, 2.0,
                4.0, 9.0,
                8.0, 3.0,
                reversed
            )
        );

        assert(forward == -reversed);
    }


    /*
     * Non-finite input remains outside the exact predicate domain.
     */
    {
        int sign = 123;

        assert(
            !tryOrientationExactExpansion(
                double.nan, 0.0,
                1.0, 0.0,
                0.0, 1.0,
                sign
            )
        );

        /*
         * out parameters are initialized on entry.
         */
        assert(sign == 0);
    }


    /*
     * The current slice deliberately rejects extreme exponent ranges.
     *
     * These cases require the later exponent-scaled backend rather than
     * silently weakening predicate correctness.
     */
    {
        int sign;

        assert(
            !tryOrientationExactExpansion(
                0.0, 0.0,
                0x1p+500, 0.0,
                0.0, 0x1p+500,
                sign
            )
        );

        assert(
            !tryOrientationExactExpansion(
                0.0, 0.0,
                0x1p-500, 0.0,
                0.0, 0x1p-500,
                sign
            )
        );
    }
}
