module geo.internal.expansion;

import core.math : toPrec;
import std.math.traits : isFinite;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Error-free floating-point transformations used by robust predicates.
 *
 * This first implementation deliberately targets binary64 only.
 * `real` requires a separate precision-aware backend.
 */


/**
 * Two-component exact representation of one arithmetic result.
 *
 * Mathematically:
 *
 *     exact result = high + low
 *
 * `high` is the ordinary rounded binary64 result and `low` is the
 * exactly recovered roundoff term, subject to the documented
 * preconditions of the corresponding transformation.
 */
struct TwoComponent
{
    double high;
    double low;
}


/**
 * High/low split of one binary64 value.
 *
 * Mathematically:
 *
 *     value = high + low
 */
struct SplitComponent
{
    double high;
    double low;
}


/*
 * For IEEE binary64:
 *
 *     p = 53 significant bits
 *
 * Shewchuk / Dekker splitter:
 *
 *     2^ceil(p / 2) + 1
 *     = 2^27 + 1
 *     = 134217729
 */
private enum double splitter =
    134_217_729.0;


/*
 * Explicit binary64 rounding helpers.
 */
private double roundedAdd(double lhs, double rhs)
    pure nothrow @safe @nogc
{
    return toPrec!double(lhs + rhs);
}


private double roundedSub(double lhs, double rhs)
    pure nothrow @safe @nogc
{
    return toPrec!double(lhs - rhs);
}


private double roundedMul(double lhs, double rhs)
    pure nothrow @safe @nogc
{
    return toPrec!double(lhs * rhs);
}


/**
 * Error-free transformation of a + b.
 *
 * Returns high and low such that, mathematically:
 *
 *     high + low == a + b
 *
 * while `high` equals the ordinary correctly rounded binary64 sum.
 *
 * The current robust-predicate backend calls this only where the
 * intermediate binary64 operations remain finite.
 */
TwoComponent twoSum(double a, double b)
    pure nothrow @safe @nogc
{
    assert(isFinite(a));
    assert(isFinite(b));

    const double x =
        roundedAdd(a, b);

    assert(isFinite(x));

    const double bVirtual =
        roundedSub(x, a);

    const double aVirtual =
        roundedSub(x, bVirtual);

    const double bRoundoff =
        roundedSub(b, bVirtual);

    const double aRoundoff =
        roundedSub(a, aVirtual);

    const double y =
        roundedAdd(
            aRoundoff,
            bRoundoff
        );

    return TwoComponent(x, y);
}


/**
 * Error-free transformation of a - b.
 *
 * Returns high and low such that, mathematically:
 *
 *     high + low == a - b
 *
 * while `high` equals the ordinary correctly rounded binary64
 * difference.
 *
 * The current robust-predicate backend calls this only where the
 * intermediate binary64 operations remain finite.
 */
TwoComponent twoDiff(double a, double b)
    pure nothrow @safe @nogc
{
    assert(isFinite(a));
    assert(isFinite(b));

    const double x =
        roundedSub(a, b);

    assert(isFinite(x));

    const double bVirtual =
        roundedSub(a, x);

    const double aVirtual =
        roundedAdd(x, bVirtual);

    const double bRoundoff =
        roundedSub(bVirtual, b);

    const double aRoundoff =
        roundedSub(a, aVirtual);

    const double y =
        roundedAdd(
            aRoundoff,
            bRoundoff
        );

    return TwoComponent(x, y);
}


/**
 * Splits a binary64 value into non-overlapping high and low parts.
 *
 * The caller must ensure that multiplication by `splitter` does not
 * overflow. The later robust-predicate layer may scale coordinates
 * before entering expansion arithmetic when necessary.
 */
SplitComponent split(double value)
    pure nothrow @safe @nogc
{
    assert(isFinite(value));

    const double c =
        roundedMul(
            splitter,
            value
        );

    /*
     * This assertion makes the current numerical domain explicit.
     * It is not a general overflow-recovery mechanism.
     */
    assert(isFinite(c));

    const double aBig =
        roundedSub(c, value);

    const double high =
        roundedSub(c, aBig);

    const double low =
        roundedSub(value, high);

    return SplitComponent(high, low);
}


/**
 * Error-free transformation of a * b.
 *
 * Returns high and low such that, mathematically:
 *
 *     high + low == a * b
 *
 * while `high` equals the ordinary rounded binary64 product.
 *
 * Preconditions of this initial backend:
 *
 * - a and b are finite;
 * - a * b does not overflow;
 * - splitting either operand does not overflow.
 *
 * Exponent scaling for inputs outside this safe working range belongs
 * to the higher-level robust-predicate implementation.
 */
TwoComponent twoProduct(double a, double b)
    pure nothrow @safe @nogc
{
    assert(isFinite(a));
    assert(isFinite(b));

    const double x =
        roundedMul(a, b);

    assert(isFinite(x));

    const auto aSplit =
        split(a);

    const auto bSplit =
        split(b);

    const double highProduct =
        roundedMul(
            aSplit.high,
            bSplit.high
        );

    const double err1 =
        roundedSub(
            x,
            highProduct
        );

    const double lowHighProduct =
        roundedMul(
            aSplit.low,
            bSplit.high
        );

    const double err2 =
        roundedSub(
            err1,
            lowHighProduct
        );

    const double highLowProduct =
        roundedMul(
            aSplit.high,
            bSplit.low
        );

    const double err3 =
        roundedSub(
            err2,
            highLowProduct
        );

    const double lowProduct =
        roundedMul(
            aSplit.low,
            bSplit.low
        );

    const double y =
        roundedSub(
            lowProduct,
            err3
        );

    return TwoComponent(x, y);
}


/**
 * Fixed-capacity stack/value storage for a floating-point expansion.
 *
 * Components are stored from least significant to most significant.
 *
 * This type deliberately owns its storage inline:
 *
 * - no dynamic array allocation;
 * - no GC dependency;
 * - capacity is known at compile time.
 *
 * The type does not itself enforce expansion non-overlap or ordering.
 * Those invariants are established by the algorithms that produce an
 * expansion.
 */
struct ExpansionBuffer(size_t Capacity)
if (Capacity > 0)
{
private:
    double[Capacity] _data;
    size_t _length;

public:
    enum size_t capacity = Capacity;


    /// Number of active expansion components.
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _length;
    }


    /// True when the expansion contains no active components.
    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return _length == 0;
    }


    /**
     * Removes all active components.
     *
     * Stored bytes need not be cleared because values beyond `length`
     * are not part of the expansion.
     */
    void clear()
        pure nothrow @safe @nogc
    {
        _length = 0;
    }


    /**
     * Appends one component.
     *
     * Preconditions:
     *
     * - value is finite;
     * - spare capacity is available.
     */
    void append(double value)
        pure nothrow @safe @nogc
    {
        assert(isFinite(value));
        assert(_length < Capacity);

        _data[_length] = value;
        ++_length;
    }


    /**
     * Indexed access to active components.
     */
    double opIndex(size_t index) const
        pure nothrow @safe @nogc
    {
        assert(index < _length);
        return _data[index];
    }
}


/*
 * Absolute value for already finite binary64 inputs.
 */
private double finiteMagnitude(double value)
    pure nothrow @safe @nogc
{
    assert(isFinite(value));

    return value < 0.0
        ? -value
        : value;
}


/**
 * Error-free transformation of a + b when |a| >= |b|.
 *
 * Compared with twoSum(), FastTwoSum needs fewer operations because its
 * magnitude precondition guarantees the required rounding relation.
 *
 * Returns:
 *
 *     high + low == a + b
 *
 * mathematically, while `high` is the ordinary rounded binary64 sum.
 */
TwoComponent fastTwoSum(double a, double b)
    pure nothrow @safe @nogc
{
    assert(isFinite(a));
    assert(isFinite(b));

    assert(
        finiteMagnitude(a) >=
        finiteMagnitude(b)
    );

    const double x =
        roundedAdd(a, b);

    assert(isFinite(x));

    const double bVirtual =
        roundedSub(x, a);

    const double y =
        roundedSub(b, bVirtual);

    return TwoComponent(x, y);
}


/**
 * Floating-point estimate of an expansion's numerical value.
 *
 * Expansion components are accumulated from least significant to most
 * significant.
 *
 * This function is intentionally approximate. It must not be used as a
 * replacement for an exact expansion sign test.
 */
double estimate(size_t Capacity)(
    ref const ExpansionBuffer!Capacity expansion
)
    pure nothrow @safe @nogc
{
    double result = 0.0;

    foreach (index; 0 .. expansion.length)
    {
        result = roundedAdd(
            result,
            expansion[index]
        );
    }

    return result;
}


@safe unittest
{
    /*
     * ExpansionBuffer owns fixed inline storage and begins empty.
     */
    {
        ExpansionBuffer!4 expansion;

        assert(expansion.empty);
        assert(expansion.length == 0);
        static assert(
            ExpansionBuffer!4.capacity == 4
        );

        assert(estimate(expansion) == 0.0);

        expansion.append(0x1p-104);
        expansion.append(0x1p-52);
        expansion.append(1.0);

        assert(!expansion.empty);
        assert(expansion.length == 3);

        assert(expansion[0] == 0x1p-104);
        assert(expansion[1] == 0x1p-52);
        assert(expansion[2] == 1.0);

        expansion.clear();

        assert(expansion.empty);
        assert(expansion.length == 0);
        assert(estimate(expansion) == 0.0);
    }


    /*
     * FastTwoSum recovers an addend lost from the rounded high
     * component.
     */
    {
        enum double halfUlpAtOne =
            0x1p-53;

        const auto r =
            fastTwoSum(
                1.0,
                halfUlpAtOne
            );

        assert(r.high == 1.0);
        assert(r.low == halfUlpAtOne);
    }


    /*
     * FastTwoSum also handles exact additions naturally.
     */
    {
        const auto r =
            fastTwoSum(4.0, 2.0);

        assert(r.high == 6.0);
        assert(r.low == 0.0);
    }


    /*
     * Sign handling for FastTwoSum.
     */
    {
        const auto r =
            fastTwoSum(
                -1.0,
                -0x1p-53
            );

        assert(r.high == -1.0);
        assert(r.low == -0x1p-53);
    }


    /*
     * Cancellation remains exact when the magnitude precondition holds.
     */
    {
        const auto r =
            fastTwoSum(
                1.0,
                -1.0
            );

        assert(r.high == 0.0);
        assert(r.low == 0.0);
    }


    /*
     * estimate() is deliberately a rounded approximation.
     *
     * Components here follow expansion order: least significant first.
     */
    {
        ExpansionBuffer!4 expansion;

        expansion.append(1.0);
        expansion.append(2.0);
        expansion.append(4.0);

        assert(estimate(expansion) == 7.0);
    }


    /*
     * TwoSum: small addend lost from the rounded main result is
     * recovered exactly in the tail.
     */
    {
        const auto r =
            twoSum(
                10_000_000_000_000_000.0,
                1.0
            );

        assert(
            r.high ==
            10_000_000_000_000_000.0
        );

        assert(r.low == 1.0);
    }


    /*
     * Half an ulp at 1.0 rounds to even in the main component and is
     * retained exactly as the tail.
     */
    {
        enum double halfUlpAtOne =
            0x1p-53;

        const auto r =
            twoSum(
                1.0,
                halfUlpAtOne
            );

        assert(r.high == 1.0);
        assert(r.low == halfUlpAtOne);
    }


    /*
     * TwoDiff recovers a lost low-order unit.
     */
    {
        const auto r =
            twoDiff(
                10_000_000_000_000_000.0,
                1.0
            );

        assert(
            r.high ==
            10_000_000_000_000_000.0
        );

        assert(r.low == -1.0);
    }


    /*
     * Exact operations naturally produce a zero tail.
     */
    {
        const auto sum =
            twoSum(2.0, 4.0);

        assert(sum.high == 6.0);
        assert(sum.low == 0.0);

        const auto diff =
            twoDiff(7.0, 3.0);

        assert(diff.high == 4.0);
        assert(diff.low == 0.0);
    }


    /*
     * Split reconstructs representative binary64 values exactly after
     * ordinary binary64 addition.
     */
    {
        enum double[] values = [
            1.0,
            -1.0,
            0x1.23456789abcdep+100,
            -0x1.abcdef0123456p-100,
            0x1.0000000000001p+0
        ];

        static foreach (value; values)
        {{
            const auto parts =
                split(value);

            assert(
                roundedAdd(
                    parts.high,
                    parts.low
                ) == value
            );
        }}
    }


    /*
     * Known exact TwoProduct case.
     *
     * Let
     *
     *     a = 1 + 2^-52
     *
     * then
     *
     *     a² = 1 + 2^-51 + 2^-104
     *
     * The first two terms form the rounded binary64 high component;
     * 2^-104 remains as the exact tail.
     */
    {
        enum double a =
            0x1.0000000000001p+0;

        const auto r =
            twoProduct(a, a);

        assert(
            r.high ==
            0x1.0000000000002p+0
        );

        assert(
            r.low ==
            0x1p-104
        );
    }


    /*
     * Exact products have zero tails.
     */
    {
        const auto r =
            twoProduct(3.0, 4.0);

        assert(r.high == 12.0);
        assert(r.low == 0.0);
    }


    /*
     * Sign handling.
     */
    {
        const auto r =
            twoProduct(
                -0x1.0000000000001p+0,
                 0x1.0000000000001p+0
            );

        assert(
            r.high ==
            -0x1.0000000000002p+0
        );

        assert(
            r.low ==
            -0x1p-104
        );
    }


    /*
     * The helper types remain simple value types.
     */
    static assert(
        TwoComponent.sizeof ==
        2 * double.sizeof
    );

    static assert(
        SplitComponent.sizeof ==
        2 * double.sizeof
    );
}
