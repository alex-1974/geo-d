module geo.internal.scaled_metric;

import euclid_core.internal.metric :
    metricScalbn;

import std.math.exponential :
    ilogb;

import std.math.traits :
    isFinite;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exponent-aware floating-point values used where finite source geometry can
 * require differences or products outside the directly representable range of
 * the computation scalar.
 *
 * A component represents:
 *
 *     significand * 2^exponent
 *
 * Zero is represented canonically by significand == 0.
 *
 * This is numerical construction machinery, not exact topology.
 */
struct ScaledMetricComponent(M)
{
    M significand = M(0);
    int exponent = 0;

    @property bool isZero() const
        pure nothrow @safe @nogc
    {
        return significand == M(0);
    }
}


/*
 * Two independently scaled components.
 */
struct ScaledMetricVector(M)
{
    ScaledMetricComponent!M x;
    ScaledMetricComponent!M y;

    @property bool isZero() const
        pure nothrow @safe @nogc
    {
        return x.isZero && y.isZero;
    }
}


/*
 * Converts one finite floating-point value to normalized
 * significand/exponent form.
 */
ScaledMetricComponent!M scaledMetricValue(M)(M value)
    pure nothrow @safe @nogc
{
    ScaledMetricComponent!M result;

    if (value == M(0))
        return result;

    const M magnitude =
        value < M(0)
            ? -value
            : value;

    const int exponent =
        ilogb(magnitude);

    const M significand =
        metricScalbn(
            value,
            -exponent
        );

    assert(isFinite(significand));
    assert(significand != M(0));

    result.significand = significand;
    result.exponent = exponent;

    return result;
}


/*
 * Robust finite floating-point difference lhs-rhs.
 *
 * Both operands are scaled by the same power of two before subtraction, so a
 * finite pair such as maxFinite - (-maxFinite) does not first overflow.
 */
ScaledMetricComponent!M scaledMetricDifference(M)(
    M lhs,
    M rhs
)
    pure nothrow @safe @nogc
{
    assert(isFinite(lhs));
    assert(isFinite(rhs));

    if (lhs == rhs)
        return ScaledMetricComponent!M.init;

    const M absLeft =
        lhs < M(0)
            ? -lhs
            : lhs;

    const M absRight =
        rhs < M(0)
            ? -rhs
            : rhs;

    const M scale =
        absLeft > absRight
            ? absLeft
            : absRight;

    assert(scale > M(0));
    assert(isFinite(scale));

    const int scaleExponent =
        ilogb(scale);

    const M scaledLeft =
        metricScalbn(
            lhs,
            -scaleExponent
        );

    const M scaledRight =
        metricScalbn(
            rhs,
            -scaleExponent
        );

    const M difference =
        scaledLeft -
        scaledRight;

    /*
     * Power-of-two scaling preserves the distinction between unequal finite
     * binary floating-point values. A failure here requires renewed numeric
     * research rather than silently accepting a zero component.
     */
    assert(difference != M(0));
    assert(isFinite(difference));

    auto result =
        scaledMetricValue!M(
            difference
        );

    result.exponent +=
        scaleExponent;

    return result;
}


/*
 * Product of two independently scaled components.
 */
ScaledMetricComponent!M scaledMetricProduct(M)(
    ref const ScaledMetricComponent!M first,
    ref const ScaledMetricComponent!M second
)
    pure nothrow @safe @nogc
{
    if (first.isZero || second.isZero)
        return ScaledMetricComponent!M.init;

    const M product =
        first.significand *
        second.significand;

    assert(isFinite(product));
    assert(product != M(0));

    auto result =
        scaledMetricValue!M(
            product
        );

    result.exponent +=
        first.exponent +
        second.exponent;

    return result;
}


/*
 * Sum of two independently scaled components.
 */
ScaledMetricComponent!M scaledMetricSum(M)(
    ref const ScaledMetricComponent!M first,
    ref const ScaledMetricComponent!M second
)
    pure nothrow @safe @nogc
{
    if (first.isZero)
        return second;

    if (second.isZero)
        return first;

    const int commonExponent =
        first.exponent > second.exponent
            ? first.exponent
            : second.exponent;

    const M firstScaled =
        metricScalbn(
            first.significand,
            first.exponent -
                commonExponent
        );

    const M secondScaled =
        metricScalbn(
            second.significand,
            second.exponent -
                commonExponent
        );

    const M sum =
        firstScaled +
        secondScaled;

    assert(isFinite(sum));

    if (sum == M(0))
        return ScaledMetricComponent!M.init;

    auto result =
        scaledMetricValue!M(
            sum
        );

    result.exponent +=
        commonExponent;

    return result;
}


/*
 * Exponent-aware two-dimensional dot product.
 */
ScaledMetricComponent!M scaledMetricDot(M)(
    ref const ScaledMetricVector!M first,
    ref const ScaledMetricVector!M second
)
    pure nothrow @safe @nogc
{
    const auto xProduct =
        scaledMetricProduct!M(
            first.x,
            second.x
        );

    const auto yProduct =
        scaledMetricProduct!M(
            first.y,
            second.y
        );

    return
        scaledMetricSum!M(
            xProduct,
            yProduct
        );
}


/*
 * Exponent-aware squared norm.
 */
ScaledMetricComponent!M scaledMetricSquaredNorm(M)(
    ref const ScaledMetricVector!M vector
)
    pure nothrow @safe @nogc
{
    const auto xSquare =
        scaledMetricProduct!M(
            vector.x,
            vector.x
        );

    const auto ySquare =
        scaledMetricProduct!M(
            vector.y,
            vector.y
        );

    return
        scaledMetricSum!M(
            xSquare,
            ySquare
        );
}


/*
 * One component of
 *
 *     d * dot(r,d) / dot(d,d)
 *
 * reconstructed without materializing the absolute scale of either dot
 * product or the projection parameter.
 */
M projectedMetricComponent(M)(
    ref const ScaledMetricComponent!M direction,
    ref const ScaledMetricComponent!M numerator,
    ref const ScaledMetricComponent!M denominator
)
    pure nothrow @safe @nogc
{
    if (
        direction.isZero ||
        numerator.isZero
    )
    {
        return M(0);
    }

    assert(!denominator.isZero);
    assert(denominator.significand > M(0));

    const M ratioSignificand =
        numerator.significand /
        denominator.significand;

    assert(isFinite(ratioSignificand));
    assert(ratioSignificand != M(0));

    const M productSignificand =
        direction.significand *
        ratioSignificand;

    assert(isFinite(productSignificand));
    assert(productSignificand != M(0));

    auto normalized =
        scaledMetricValue!M(
            productSignificand
        );

    normalized.exponent +=
        direction.exponent +
        numerator.exponent -
        denominator.exponent;

    return
        metricScalbn(
            normalized.significand,
            normalized.exponent
        );
}


@safe unittest
{
    enum double tiny =
        0x1p-1074;

    const auto zero =
        scaledMetricValue(0.0);

    assert(zero.isZero);

    const auto one =
        scaledMetricValue(1.0);

    assert(!one.isZero);
    assert(one.significand == 1.0);
    assert(one.exponent == 0);

    const auto hugeDifference =
        scaledMetricDifference(
            double.max,
            -double.max
        );

    assert(!hugeDifference.isZero);

    const auto tinyValue =
        scaledMetricValue(tiny);

    assert(!tinyValue.isZero);
}
