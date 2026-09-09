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


version(unittest)
{
    import std.bigint : BigInt;
    import std.bitmanip : DoubleRep, FloatRep;
    import std.math.traits : isFinite;


    /*
     * Independent arbitrary-precision oracle.
     *
     * Production predicates deliberately do not depend on BigInt.
     * These helpers exist only in unittest builds.
     */


    private Orientation oracleOrientationFromDeterminant(
        ref const BigInt determinant
    )
        @safe
    {
        if (determinant > 0)
            return Orientation.left;

        if (determinant < 0)
            return Orientation.right;

        return Orientation.collinear;
    }


    private Orientation oppositeOrientation(
        Orientation value
    )
        pure nothrow @safe @nogc
    {
        final switch (value)
        {
            case Orientation.left:
                return Orientation.right;

            case Orientation.collinear:
                return Orientation.collinear;

            case Orientation.right:
                return Orientation.left;
        }
    }


    /*
     * Exact oracle for integral Point2 coordinates.
     *
     * All subtraction and multiplication happens in BigInt, so this
     * does not share geo-d's fixed-width integer orientation machinery.
     */
    private Orientation oracleIntegerOrientation(T)(
        Point2!T a,
        Point2!T b,
        Point2!T c
    )
        @safe
    if (is(T == int) || is(T == long))
    {
        const BigInt bax =
            BigInt(b.x) - BigInt(a.x);

        const BigInt bay =
            BigInt(b.y) - BigInt(a.y);

        const BigInt cax =
            BigInt(c.x) - BigInt(a.x);

        const BigInt cay =
            BigInt(c.y) - BigInt(a.y);

        const BigInt determinant =
            bax * cay -
            bay * cax;

        return oracleOrientationFromDeterminant(
            determinant
        );
    }


    /*
     * Decode one finite binary64 value exactly as an integer multiple
     * of 2^-1074.
     *
     * This shares only the IEEE-754 representation theorem with the
     * production dyadic fallback. All subsequent arithmetic is handled
     * independently by std.bigint.BigInt.
     */
    private BigInt oracleBinary64Integer(
        double value
    )
        @safe
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
             * Zero or subnormal:
             *
             *     value =
             *         fraction * 2^-1074
             */
            mantissa =
                fraction;

            shift = 0;
        }
        else
        {
            /*
             * Normal:
             *
             *     value =
             *       (2^52 + fraction)
             *       * 2^(rawExponent - 1075)
             *
             * In units of 2^-1074:
             *
             *     integer =
             *       mantissa << (rawExponent - 1)
             */
            mantissa =
                (1UL << 52) |
                fraction;

            shift =
                rawExponent - 1;
        }

        if (mantissa == 0)
            return BigInt(0);

        BigInt result =
            BigInt(mantissa);

        if (shift != 0)
            result <<= shift;

        if (representation.sign)
            result = -result;

        return result;
    }


    private Orientation oracleDoubleOrientation(
        Point2!double a,
        Point2!double b,
        Point2!double c
    )
        @safe
    {
        assert(a.isFinite);
        assert(b.isFinite);
        assert(c.isFinite);

        const BigInt ax =
            oracleBinary64Integer(a.x);

        const BigInt ay =
            oracleBinary64Integer(a.y);

        const BigInt bx =
            oracleBinary64Integer(b.x);

        const BigInt by =
            oracleBinary64Integer(b.y);

        const BigInt cx =
            oracleBinary64Integer(c.x);

        const BigInt cy =
            oracleBinary64Integer(c.y);

        const BigInt bax =
            bx - ax;

        const BigInt bay =
            by - ay;

        const BigInt cax =
            cx - ax;

        const BigInt cay =
            cy - ay;

        const BigInt determinant =
            bax * cay -
            bay * cax;

        return oracleOrientationFromDeterminant(
            determinant
        );
    }


    /*
     * binary32 -> binary64 is exact, so the binary64 BigInt oracle is
     * also an independent exact oracle for Point2!float.
     */
    private Orientation oracleFloatOrientation(
        Point2!float a,
        Point2!float b,
        Point2!float c
    )
        @safe
    {
        return oracleDoubleOrientation(
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


    /*
     * Small deterministic PRNG used only to generate reproducible test
     * vectors. It is not part of the library API and is not intended
     * for cryptographic/statistical use.
     */
    private ulong nextOracleRandom(
        ref ulong state
    )
        pure nothrow @safe @nogc
    {
        assert(state != 0);

        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;

        return state;
    }


    private int randomOracleInt(
        ref ulong state
    )
        pure nothrow @safe @nogc
    {
        const ulong bits =
            nextOracleRandom(state);

        const int magnitude =
            cast(int)(
                bits &
                0x7fff_ffffUL
            );

        return (bits & (1UL << 63))
            ? -magnitude
            : magnitude;
    }


    private long randomOracleLong(
        ref ulong state
    )
        pure nothrow @safe @nogc
    {
        const ulong bits =
            nextOracleRandom(state);

        const long magnitude =
            cast(long)(
                bits &
                0x7fff_ffff_ffff_ffffUL
            );

        return (bits & (1UL << 63))
            ? -magnitude
            : magnitude;
    }


    /*
     * Generate arbitrary finite binary64 bit patterns.
     *
     * Raw exponent 2047 would mean infinity/NaN and is remapped to the
     * largest finite exponent.
     */
    private double randomFiniteDouble(
        ref ulong state
    )
        pure nothrow @safe @nogc
    {
        const ulong bits =
            nextOracleRandom(state);

        DoubleRep representation;

        representation.value =
            0.0;

        representation.fraction =
            bits &
            ((1UL << 52) - 1);

        ushort exponent =
            cast(ushort)(
                (bits >> 52) &
                0x7ffUL
            );

        if (exponent == 0x7ff)
            exponent = 0x7fe;

        representation.exponent =
            exponent;

        representation.sign =
            (bits & (1UL << 63)) != 0;

        return representation.value;
    }


    /*
     * Same idea for arbitrary finite binary32 values.
     */
    private float randomFiniteFloat(
        ref ulong state
    )
        pure nothrow @safe @nogc
    {
        const uint bits =
            cast(uint)(
                nextOracleRandom(state)
            );

        FloatRep representation;

        representation.value =
            0.0f;

        representation.fraction =
            bits &
            ((1U << 23) - 1);

        ubyte exponent =
            cast(ubyte)(
                (bits >> 23) &
                0xffU
            );

        if (exponent == 0xff)
            exponent = 0xfe;

        representation.exponent =
            exponent;

        representation.sign =
            (bits & (1U << 31)) != 0;

        return representation.value;
    }
}


@safe unittest
{
    /*
     * BigInt oracle: full integral coordinate extremes.
     *
     * These cases force differences outside the source scalar range.
     */
    {
        alias PI = Point2!int;

        const PI a =
            PI(int.min, int.min);

        const PI b =
            PI(int.max, int.min);

        const PI c =
            PI(int.min, int.max);

        assert(
            orientation(a, b, c) ==
            oracleIntegerOrientation(a, b, c)
        );

        assert(
            orientation(a, b, c) ==
            Orientation.left
        );
    }


    {
        alias PL = Point2!long;

        const PL a =
            PL(long.min, long.min);

        const PL b =
            PL(long.max, long.min);

        const PL c =
            PL(long.min, long.max);

        assert(
            orientation(a, b, c) ==
            oracleIntegerOrientation(a, b, c)
        );

        assert(
            orientation(a, b, c) ==
            Orientation.left
        );
    }


    /*
     * Deterministic property sweep for int.
     */
    {
        alias P = Point2!int;

        ulong state =
            0x9e37_79b9_7f4a_7c15UL;

        foreach (_; 0 .. 256)
        {
            const P a =
                P(
                    randomOracleInt(state),
                    randomOracleInt(state)
                );

            const P b =
                P(
                    randomOracleInt(state),
                    randomOracleInt(state)
                );

            const P c =
                P(
                    randomOracleInt(state),
                    randomOracleInt(state)
                );

            const Orientation expected =
                oracleIntegerOrientation(
                    a,
                    b,
                    c
                );

            assert(
                orientation(a, b, c) ==
                expected
            );

            /*
             * Cyclic permutation preserves orientation.
             */
            assert(
                orientation(b, c, a) ==
                expected
            );

            /*
             * Swapping two vertices reverses orientation.
             */
            assert(
                orientation(a, c, b) ==
                oppositeOrientation(expected)
            );
        }
    }


    /*
     * Deterministic property sweep for long.
     *
     * The oracle uses arbitrary precision for both full-width
     * subtraction and multiplication.
     */
    {
        alias P = Point2!long;

        ulong state =
            0xd1b5_4a32_d192_ed03UL;

        foreach (_; 0 .. 256)
        {
            const P a =
                P(
                    randomOracleLong(state),
                    randomOracleLong(state)
                );

            const P b =
                P(
                    randomOracleLong(state),
                    randomOracleLong(state)
                );

            const P c =
                P(
                    randomOracleLong(state),
                    randomOracleLong(state)
                );

            const Orientation expected =
                oracleIntegerOrientation(
                    a,
                    b,
                    c
                );

            assert(
                orientation(a, b, c) ==
                expected
            );

            assert(
                orientation(b, c, a) ==
                expected
            );

            assert(
                orientation(a, c, b) ==
                oppositeOrientation(expected)
            );
        }
    }


    /*
     * BigInt binary64 oracle: explicitly exercise difficult exponent
     * ranges before the generated property sweep.
     */
    {
        alias P = Point2!double;

        enum double minSubnormal =
            0x0.0000000000001p-1022;

        const P a =
            P(0.0, 0.0);

        const P b =
            P(
                minSubnormal,
                0.0
            );

        const P c =
            P(
                0.0,
                minSubnormal
            );

        assert(
            orientation(a, b, c) ==
            oracleDoubleOrientation(a, b, c)
        );

        assert(
            orientation(a, b, c) ==
            Orientation.left
        );
    }


    {
        alias P = Point2!double;

        const P a =
            P(-double.max, 0.0);

        const P b =
            P( double.max, 0.0);

        const P c =
            P(0.0, 1.0);

        assert(
            orientation(a, b, c) ==
            oracleDoubleOrientation(a, b, c)
        );

        assert(
            orientation(a, b, c) ==
            Orientation.left
        );
    }


    /*
     * Exact full-range diagonal collinearity.
     */
    {
        alias P = Point2!double;

        const P a =
            P(
                -double.max,
                -double.max
            );

        const P b =
            P(
                double.max,
                double.max
            );

        const P c =
            P(0.0, 0.0);

        assert(
            oracleDoubleOrientation(
                a,
                b,
                c
            ) == Orientation.collinear
        );

        assert(
            orientation(a, b, c) ==
            Orientation.collinear
        );
    }


    /*
     * Near-degenerate binary64 case: one ulp above the diagonal.
     */
    {
        alias P = Point2!double;

        const P a =
            P(0.0, 0.0);

        const P b =
            P(10.0, 10.0);

        const P c =
            P(
                5.0,
                0x1.4000000000001p+2
            );

        assert(
            orientation(a, b, c) ==
            oracleDoubleOrientation(a, b, c)
        );

        assert(
            orientation(a, b, c) ==
            Orientation.left
        );
    }


    /*
     * Deterministic binary64 bit-pattern sweep.
     *
     * Exponents are sampled across the complete finite binary64 range,
     * including zero/subnormal exponent encodings.
     */
    {
        alias P = Point2!double;

        ulong state =
            0xa076_1d64_78bd_642fUL;

        foreach (_; 0 .. 128)
        {
            const P a =
                P(
                    randomFiniteDouble(state),
                    randomFiniteDouble(state)
                );

            const P b =
                P(
                    randomFiniteDouble(state),
                    randomFiniteDouble(state)
                );

            const P c =
                P(
                    randomFiniteDouble(state),
                    randomFiniteDouble(state)
                );

            assert(a.isFinite);
            assert(b.isFinite);
            assert(c.isFinite);

            const Orientation expected =
                oracleDoubleOrientation(
                    a,
                    b,
                    c
                );

            assert(
                orientation(a, b, c) ==
                expected
            );

            assert(
                orientation(b, c, a) ==
                expected
            );

            assert(
                orientation(a, c, b) ==
                oppositeOrientation(expected)
            );
        }
    }


    /*
     * Deterministic binary32 bit-pattern sweep.
     *
     * The independent oracle promotes each binary32 coordinate exactly
     * to binary64 before converting it to BigInt.
     */
    {
        alias P = Point2!float;

        ulong state =
            0xe703_7ed1_a0b4_28dbUL;

        foreach (_; 0 .. 128)
        {
            const P a =
                P(
                    randomFiniteFloat(state),
                    randomFiniteFloat(state)
                );

            const P b =
                P(
                    randomFiniteFloat(state),
                    randomFiniteFloat(state)
                );

            const P c =
                P(
                    randomFiniteFloat(state),
                    randomFiniteFloat(state)
                );

            assert(a.isFinite);
            assert(b.isFinite);
            assert(c.isFinite);

            const Orientation expected =
                oracleFloatOrientation(
                    a,
                    b,
                    c
                );

            assert(
                orientation(a, b, c) ==
                expected
            );

            assert(
                orientation(b, c, a) ==
                expected
            );

            assert(
                orientation(a, c, b) ==
                oppositeOrientation(expected)
            );
        }
    }


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
