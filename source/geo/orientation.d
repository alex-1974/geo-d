module geo.orientation;

import geo.point : Point2;

import geo.internal.orientation_filter :
    OrientationFilterResult,
    orientationFilter;

import geo.internal.orientation_robust :
    tryOrientationRobustDouble;

/**
 * Orientation of a point relative to the directed line a -> b.
 */
enum Orientation : byte
{
    right     = -1,
    collinear =  0,
    left      =  1,
}


/*
 * Signed difference represented without overflowing the source scalar.
 */
private struct SignedDiff32
{
    int sign;
    uint magnitude;
}


private struct SignedDiff64
{
    int sign;
    ulong magnitude;
}


/*
 * Signed product represented as sign + exact unsigned magnitude.
 */
private struct SignedProduct64
{
    int sign;
    ulong magnitude;
}


/*
 * Exact unsigned 128-bit value represented as two 64-bit limbs.
 *
 * Only multiplication and comparison are required by orientation.
 * This is intentionally not a general-purpose 128-bit integer type.
 */
private struct Unsigned128
{
    ulong hi;
    ulong lo;
}


private struct SignedProduct128
{
    int sign;
    Unsigned128 magnitude;
}


/*
 * Exact unsigned magnitude of int.
 *
 * -(value + 1) avoids overflow for int.min.
 */
private uint unsignedMagnitude(int value)
    pure nothrow @safe @nogc
{
    if (value >= 0)
        return cast(uint) value;

    return cast(uint)(-(value + 1)) + 1U;
}


/*
 * Exact unsigned magnitude of long.
 *
 * -(value + 1) avoids overflow for long.min.
 */
private ulong unsignedMagnitude(long value)
    pure nothrow @safe @nogc
{
    if (value >= 0)
        return cast(ulong) value;

    return cast(ulong)(-(value + 1)) + 1UL;
}


/*
 * Exact signed difference a - b for int coordinates.
 */
private SignedDiff32 signedDifference(int a, int b)
    pure nothrow @safe @nogc
{
    if (a == b)
        return SignedDiff32(0, 0);

    const int sign = a > b ? 1 : -1;

    uint magnitude;

    if ((a < 0) != (b < 0))
    {
        magnitude =
            unsignedMagnitude(a) +
            unsignedMagnitude(b);
    }
    else if (a > b)
    {
        magnitude = cast(uint)(a - b);
    }
    else
    {
        magnitude = cast(uint)(b - a);
    }

    return SignedDiff32(sign, magnitude);
}


/*
 * Exact signed difference a - b for long coordinates.
 */
private SignedDiff64 signedDifference(long a, long b)
    pure nothrow @safe @nogc
{
    if (a == b)
        return SignedDiff64(0, 0);

    const int sign = a > b ? 1 : -1;

    ulong magnitude;

    if ((a < 0) != (b < 0))
    {
        magnitude =
            unsignedMagnitude(a) +
            unsignedMagnitude(b);
    }
    else if (a > b)
    {
        magnitude = cast(ulong)(a - b);
    }
    else
    {
        magnitude = cast(ulong)(b - a);
    }

    return SignedDiff64(sign, magnitude);
}


/*
 * Exact unsigned 64 x 64 -> 128 bit multiplication.
 *
 * Operands are decomposed into 32-bit limbs so that every primitive
 * multiplication fits exactly in ulong.
 *
 * The result is:
 *
 *     hi * 2^64 + lo
 *
 * This is deliberately local to the predicate implementation rather
 * than a speculative general-purpose wide-integer abstraction.
 */
private Unsigned128 multiplyUnsigned64(
    ulong lhs,
    ulong rhs
)
    pure nothrow @safe @nogc
{
    enum ulong mask32 = 0xffff_ffffUL;

    const ulong lhsLo = lhs & mask32;
    const ulong lhsHi = lhs >> 32;

    const ulong rhsLo = rhs & mask32;
    const ulong rhsHi = rhs >> 32;

    /*
     * Hacker's Delight style limb multiplication.
     *
     * All partial products are 32 x 32 -> <= 64 bit.
     */
    const ulong w0 =
        lhsLo * rhsLo;

    const ulong t =
        lhsHi * rhsLo +
        (w0 >> 32);

    const ulong w1Low =
        t & mask32;

    const ulong w2 =
        t >> 32;

    const ulong w1 =
        lhsLo * rhsHi +
        w1Low;

    const ulong hi =
        lhsHi * rhsHi +
        w2 +
        (w1 >> 32);

    const ulong lo =
        ((w1 & mask32) << 32) |
        (w0 & mask32);

    return Unsigned128(hi, lo);
}


/*
 * Unsigned comparison of exact 128-bit values.
 *
 * Returns:
 *
 *     -1  lhs < rhs
 *      0  lhs == rhs
 *      1  lhs > rhs
 */
private int compareUnsigned128(
    Unsigned128 lhs,
    Unsigned128 rhs
)
    pure nothrow @safe @nogc
{
    if (lhs.hi < rhs.hi)
        return -1;

    if (lhs.hi > rhs.hi)
        return 1;

    if (lhs.lo < rhs.lo)
        return -1;

    if (lhs.lo > rhs.lo)
        return 1;

    return 0;
}


/*
 * Exact product of two signed int-coordinate differences.
 *
 * Each magnitude uses at most 32 bits, so the complete product fits in
 * ulong.
 */
private SignedProduct64 multiply(
    SignedDiff32 lhs,
    SignedDiff32 rhs
)
    pure nothrow @safe @nogc
{
    if (lhs.sign == 0 || rhs.sign == 0)
        return SignedProduct64(0, 0);

    const int sign =
        lhs.sign == rhs.sign ? 1 : -1;

    return SignedProduct64(
        sign,
        cast(ulong) lhs.magnitude *
            cast(ulong) rhs.magnitude
    );
}


/*
 * Exact product of two signed long-coordinate differences.
 *
 * Each magnitude may require all 64 bits. core.int128.mul performs an
 * exact unsigned 64 x 64 -> 128 bit multiplication.
 */
private SignedProduct128 multiply(
    SignedDiff64 lhs,
    SignedDiff64 rhs
)
    pure nothrow @safe @nogc
{
    if (lhs.sign == 0 || rhs.sign == 0)
        return SignedProduct128(
            0,
            Unsigned128.init
        );

    const int sign =
        lhs.sign == rhs.sign ? 1 : -1;

    return SignedProduct128(
        sign,
        multiplyUnsigned64(
            lhs.magnitude,
            rhs.magnitude
        )
    );
}


/*
 * Sign of p - q for exact signed 64-bit-magnitude products.
 *
 * The determinant itself does not need to be materialized.
 */
private int differenceSign(
    SignedProduct64 p,
    SignedProduct64 q
)
    pure nothrow @safe @nogc
{
    if (p.sign == 0)
        return -q.sign;

    if (q.sign == 0)
        return p.sign;

    /*
     * Opposite signs determine the result immediately.
     */
    if (p.sign != q.sign)
        return p.sign;

    if (p.magnitude == q.magnitude)
        return 0;

    if (p.sign > 0)
        return p.magnitude > q.magnitude ? 1 : -1;

    /*
     * p = -P, q = -Q
     *
     * p - q = Q - P
     */
    return p.magnitude < q.magnitude ? 1 : -1;
}


/*
 * Sign of p - q for exact signed 128-bit-magnitude products.
 *
 * Magnitudes are compared as unsigned 128-bit values.
 */
private int differenceSign(
    SignedProduct128 p,
    SignedProduct128 q
)
    pure nothrow @safe @nogc
{
    if (p.sign == 0)
        return -q.sign;

    if (q.sign == 0)
        return p.sign;

    /*
     * Opposite signs determine the determinant sign immediately.
     */
    if (p.sign != q.sign)
        return p.sign;

    const int comparison =
        compareUnsigned128(
            p.magnitude,
            q.magnitude
        );

    if (comparison == 0)
        return 0;

    /*
     * Both positive:
     *
     *     P - Q
     *
     * Both negative:
     *
     *     (-P) - (-Q) = Q - P
     */
    return p.sign > 0
        ? comparison
        : -comparison;
}


private Orientation fromDeterminantSign(int sign)
    pure nothrow @safe @nogc
{
    if (sign > 0)
        return Orientation.left;

    if (sign < 0)
        return Orientation.right;

    return Orientation.collinear;
}


/**
 * Exact orientation predicate for Point2!int.
 *
 * Returns the mathematically exact orientation over the complete int
 * coordinate domain.
 *
 * No signed subtraction or multiplication overflow is permitted in the
 * implementation.
 */
Orientation orientation(
    Point2!int a,
    Point2!int b,
    Point2!int c
)
    pure nothrow @safe @nogc
{
    const auto bax = signedDifference(b.x, a.x);
    const auto bay = signedDifference(b.y, a.y);

    const auto cax = signedDifference(c.x, a.x);
    const auto cay = signedDifference(c.y, a.y);

    const auto p = multiply(bax, cay);
    const auto q = multiply(bay, cax);

    return fromDeterminantSign(
        differenceSign(p, q)
    );
}


/**
 * Exact orientation predicate for Point2!long.
 *
 * Returns the mathematically exact orientation over the complete long
 * coordinate domain.
 *
 * Product magnitudes are evaluated with exact 128-bit arithmetic. The
 * determinant itself is not materialized; only its sign is determined.
 */
Orientation orientation(
    Point2!long a,
    Point2!long b,
    Point2!long c
)
    pure nothrow @safe @nogc
{
    const auto bax = signedDifference(b.x, a.x);
    const auto bay = signedDifference(b.y, a.y);

    const auto cax = signedDifference(c.x, a.x);
    const auto cay = signedDifference(c.y, a.y);

    const auto p = multiply(bax, cay);
    const auto q = multiply(bay, cax);

    return fromDeterminantSign(
        differenceSign(p, q)
    );
}


/**
 * Robust orientation predicate for Point2!double.
 *
 * Preconditions:
 *
 *     all coordinates are finite.
 *
 * Returns the mathematically exact orientation of c relative to the
 * directed line a -> b.
 *
 * Internally the implementation uses:
 *
 * - a certified floating-point filter;
 * - exact expansion arithmetic for uncertain ordinary cases;
 * - an exact full-range dyadic fallback for extreme finite inputs.
 */
Orientation orientation(
    Point2!double a,
    Point2!double b,
    Point2!double c
)
    pure nothrow @safe @nogc
{
    assert(a.isFinite);
    assert(b.isFinite);
    assert(c.isFinite);

    int sign;

    const bool success =
        tryOrientationRobustDouble(
            a.x, a.y,
            b.x, b.y,
            c.x, c.y,
            sign
        );

    /*
     * Finite binary64 inputs are completely covered by the robust
     * backend.
     */
    assert(success);

    return fromDeterminantSign(sign);
}


/**
 * Robust orientation predicate for Point2!float.
 *
 * Preconditions:
 *
 *     all coordinates are finite.
 *
 * Every finite IEEE binary32 value is exactly representable as binary64.
 * The coordinates are therefore promoted exactly to double and evaluated
 * by the complete robust binary64 orientation backend.
 *
 * No predicate information is lost by this promotion.
 */
Orientation orientation(
    Point2!float a,
    Point2!float b,
    Point2!float c
)
    pure nothrow @safe @nogc
{
    assert(a.isFinite);
    assert(b.isFinite);
    assert(c.isFinite);

    return orientation(
        Point2!double(
            cast(double) a.x,
            cast(double) a.y
        ),
        Point2!double(
            cast(double) b.x,
            cast(double) b.y
        ),
        Point2!double(
            cast(double) c.x,
            cast(double) c.y
        )
    );
}


@safe unittest
{
    /*
     * Public robust binary32 orientation.
     */
    {
        alias P = Point2!float;

        assert(
            orientation(
                P(0.0f, 0.0f),
                P(10.0f, 0.0f),
                P(5.0f, 1.0f)
            ) == Orientation.left
        );

        assert(
            orientation(
                P(0.0f, 0.0f),
                P(10.0f, 0.0f),
                P(5.0f, -1.0f)
            ) == Orientation.right
        );

        assert(
            orientation(
                P(0.0f, 0.0f),
                P(10.0f, 10.0f),
                P(5.0f, 5.0f)
            ) == Orientation.collinear
        );
    }


    /*
     * The next binary32 value above 1.0 is preserved exactly by the
     * promotion to binary64, so a near-degenerate determinant keeps its
     * correct sign.
     */
    {
        alias P = Point2!float;

        enum float aboveOne =
            0x1.000002p+0f;

        assert(
            orientation(
                P(0.0f, 0.0f),
                P(2.0f, 2.0f),
                P(1.0f, aboveOne)
            ) == Orientation.left
        );
    }


    /*
     * Extreme finite binary32 coordinates are still exact after
     * promotion.
     */
    {
        alias P = Point2!float;

        assert(
            orientation(
                P(-float.max, 0.0f),
                P( float.max, 0.0f),
                P(0.0f, 1.0f)
            ) == Orientation.left
        );
    }


    /*
     * The smallest positive binary32 subnormal is exactly representable
     * as binary64 as well.
     */
    {
        alias P = Point2!float;

        enum float minSubnormal =
            float.min_normal *
            float.epsilon;

        assert(minSubnormal > 0.0f);

        assert(
            orientation(
                P(0.0f, 0.0f),
                P(minSubnormal, 0.0f),
                P(0.0f, minSubnormal)
            ) == Orientation.left
        );
    }


    /*
     * real remains deliberately unsupported.
     *
     * ADR-0004 requires a platform-aware robust backend rather than
     * demotion to binary64.
     */
    static assert(
        !__traits(
            compiles,
            orientation(
                Point2!real.init,
                Point2!real.init,
                Point2!real.init
            )
        )
    );


    /*
     * Public robust binary64 orientation.
     */
    {
        alias P = Point2!double;

        assert(
            orientation(
                P(0.0, 0.0),
                P(10.0, 0.0),
                P(5.0, 1.0)
            ) == Orientation.left
        );

        assert(
            orientation(
                P(0.0, 0.0),
                P(10.0, 0.0),
                P(5.0, -1.0)
            ) == Orientation.right
        );

        assert(
            orientation(
                P(0.0, 0.0),
                P(10.0, 10.0),
                P(5.0, 5.0)
            ) == Orientation.collinear
        );
    }


    /*
     * Near-degenerate binary64 input is decided exactly.
     */
    {
        alias P = Point2!double;

        assert(
            orientation(
                P(0.0, 0.0),
                P(10.0, 10.0),
                P(
                    5.0,
                    0x1.4000000000001p+2
                )
            ) == Orientation.left
        );
    }


    /*
     * Full finite binary64 range remains supported.
     */
    {
        alias P = Point2!double;

        assert(
            orientation(
                P(-double.max, 0.0),
                P( double.max, 0.0),
                P(0.0, 1.0)
            ) == Orientation.left
        );

        enum double minSubnormal =
            0x0.0000000000001p-1022;

        assert(
            orientation(
                P(0.0, 0.0),
                P(minSubnormal, 0.0),
                P(0.0, minSubnormal)
            ) == Orientation.left
        );
    }


    /*
     * Exact 64 x 64 -> 128 multiplication.
     */
    {
        assert(
            multiplyUnsigned64(0, ulong.max) ==
            Unsigned128(0, 0)
        );

        assert(
            multiplyUnsigned64(1, ulong.max) ==
            Unsigned128(0, ulong.max)
        );

        /*
         * (2^64 - 1)^2
         *
         *   = (2^64 - 2) * 2^64 + 1
         */
        assert(
            multiplyUnsigned64(
                ulong.max,
                ulong.max
            ) == Unsigned128(
                ulong.max - 1,
                1
            )
        );

        /*
         * Highest single-bit product:
         *
         *     2^63 * 2^63 = 2^126
         */
        assert(
            multiplyUnsigned64(
                0x8000_0000_0000_0000UL,
                0x8000_0000_0000_0000UL
            ) == Unsigned128(
                0x4000_0000_0000_0000UL,
                0
            )
        );
    }


    /*
     * Public enum contract.
     */
    static assert(
        cast(byte) Orientation.right == -1
    );

    static assert(
        cast(byte) Orientation.collinear == 0
    );

    static assert(
        cast(byte) Orientation.left == 1
    );


    /*
     * Basic semantics.
     */
    {
        alias P = Point2!int;

        const a = P(0, 0);
        const b = P(10, 0);

        assert(
            orientation(a, b, P(5, 1)) ==
            Orientation.left
        );

        assert(
            orientation(a, b, P(5, -1)) ==
            Orientation.right
        );

        assert(
            orientation(a, b, P(5, 0)) ==
            Orientation.collinear
        );
    }


    /*
     * Degenerate directed line.
     */
    {
        alias P = Point2!long;

        const a = P(42, -17);

        assert(
            orientation(a, a, P(100, 200)) ==
            Orientation.collinear
        );

        assert(
            orientation(a, a, a) ==
            Orientation.collinear
        );
    }


    /*
     * Cyclic permutations preserve orientation.
     * Swapping two points reverses it.
     */
    {
        alias P = Point2!int;

        const a = P(1, 2);
        const b = P(8, 3);
        const c = P(4, 9);

        assert(
            orientation(a, b, c) ==
            Orientation.left
        );

        assert(
            orientation(b, c, a) ==
            Orientation.left
        );

        assert(
            orientation(c, a, b) ==
            Orientation.left
        );

        assert(
            orientation(a, c, b) ==
            Orientation.right
        );

        assert(
            orientation(c, b, a) ==
            Orientation.right
        );
    }


    /*
     * Complete int coordinate span.
     *
     * A naive int subtraction and multiplication implementation would
     * overflow here.
     */
    {
        alias P = Point2!int;

        const a = P(int.min, int.min);
        const b = P(int.max, int.min);
        const c = P(int.min, int.max);

        assert(
            orientation(a, b, c) ==
            Orientation.left
        );

        assert(
            orientation(a, c, b) ==
            Orientation.right
        );
    }


    /*
     * Complete long coordinate span.
     *
     * Differences require all 64 unsigned bits and their product
     * requires the full 128-bit magnitude.
     */
    {
        alias P = Point2!long;

        const a = P(long.min, long.min);
        const b = P(long.max, long.min);
        const c = P(long.min, long.max);

        assert(
            orientation(a, b, c) ==
            Orientation.left
        );

        assert(
            orientation(a, c, b) ==
            Orientation.right
        );
    }


    /*
     * Two enormous 128-bit products differing only relatively near
     * their upper end.
     *
     * This specifically exercises unsigned 128-bit product comparison,
     * not merely the zero-product cases.
     */
    {
        alias P = Point2!long;

        const a = P(long.min, long.min);

        const b = P(
            long.max,
            long.max - 1
        );

        const c = P(
            long.max - 1,
            long.max
        );

        assert(
            orientation(a, b, c) ==
            Orientation.left
        );

        assert(
            orientation(a, c, b) ==
            Orientation.right
        );
    }


    /*
     * Collinearity across almost the complete long coordinate domain.
     */
    {
        alias P = Point2!long;

        const a = P(long.min, long.min);
        const b = P(long.max, long.max);
        const c = P(0, 0);

        assert(
            orientation(a, b, c) ==
            Orientation.collinear
        );
    }


    /*
     * Vertical and horizontal extremes.
     */
    {
        alias P = Point2!long;

        assert(
            orientation(
                P(long.min, 0),
                P(long.max, 0),
                P(0, long.max)
            ) == Orientation.left
        );

        assert(
            orientation(
                P(0, long.min),
                P(0, long.max),
                P(long.max, 0)
            ) == Orientation.right
        );
    }
}
