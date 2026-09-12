/**
 * Checked scalar conversion and explicit coordinate quantization.
  *
 * Authors:
 *     Alexander Bernardi
 *
 * Copyright:
 *     Copyright © 2026 Alexander Bernardi
 *
 * License:
 *     MIT
 *
 * Date:
 *     September 12, 2026
 */
module geo.convert;

import geo.point : Point2;
import geo.scalar : isGeoScalar;
import geo.segment : Segment2;
import geo.vector : Vector2;

import std.math.rounding : ceil, floor;
import std.math.traits : isFinite;
import std.traits : isFloatingPoint;


private enum bool isGeoIntegral(T) =
       is(T == int)
    || is(T == long);


/*
 * Rounds to the nearest integral-valued floating-point value.
 * Halfway cases are rounded away from zero.
 *
 * Implemented from floor/ceil so the result keeps T and the operation
 * remains pure, nothrow and @nogc.
 */
private T roundAwayFromZero(T)(T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    /*
     * Preserve NaN, infinities, and signed zero directly.
     */
    if (!isFinite(value) || value == T(0))
        return value;

    if (value > T(0))
    {
        const T lower = floor(value);

        return value - lower < T(0.5)
            ? lower
            : lower + T(1);
    }

    const T upper = ceil(value);

    return upper - value < T(0.5)
        ? upper
        : upper - T(1);
}


/*
 * Removes the fractional part while keeping the floating-point type.
 */
private T truncateTowardZero(T)(T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    if (value > T(0))
        return floor(value);

    if (value < T(0))
        return ceil(value);

    // Preserves zero, signed zero and NaN.
    return value;
}


/*
 * Checked scalar conversion used by the public geometry conversions.
 *
 * Precision loss within the representable target range is allowed.
 * Range overflow is not.
 *
 * Floating-point to integral conversion additionally requires:
 *   - a finite source;
 *   - an already integral-valued source;
 *   - a value inside the target range.
 */
private bool tryScalarConvert(To, From)(From value, out To result)
    pure nothrow @safe @nogc
if (isGeoScalar!To && isGeoScalar!From)
{
    static if (isGeoIntegral!From && isGeoIntegral!To)
    {
        static if (From.sizeof <= To.sizeof)
        {
            result = cast(To) value;
            return true;
        }
        else
        {
            if (value < cast(From) To.min ||
                value > cast(From) To.max)
            {
                return false;
            }

            result = cast(To) value;
            return true;
        }
    }
    else static if (isGeoIntegral!From && isFloatingPoint!To)
    {
        /*
         * int/long fit inside the exponent range of every supported
         * floating-point type. Precision loss is permitted.
         */
        result = cast(To) value;
        return true;
    }
    else static if (isFloatingPoint!From && isGeoIntegral!To)
    {
        if (!isFinite(value))
            return false;

        if (value != truncateTowardZero(value))
            return false;

        /*
         * Avoid comparing against cast(From) To.max:
         *
         * e.g. cast(double) long.max rounds to 2^63, which is already
         * outside long's positive range.
         *
         * For signed N-bit integers the valid interval is
         *
         *     [-2^(N-1), 2^(N-1))
         *
         * and powers of two are exactly representable in binary
         * floating point.
         */
        enum shift = To.sizeof * 8 - 1;
        enum ulong upperMagnitude = 1UL << shift;

        const From upperExclusive = cast(From) upperMagnitude;
        const From lowerInclusive = -upperExclusive;

        if (value < lowerInclusive || value >= upperExclusive)
            return false;

        result = cast(To) value;
        return true;
    }
    else static if (isFloatingPoint!From && isFloatingPoint!To)
    {
        const To converted = cast(To) value;

        /*
         * NaN and ±Infinity are valid Point2/Vector2 values and remain
         * representable when converting between floating-point types.
         *
         * A finite source becoming infinity, however, is range overflow.
         */
        if (isFinite(value) && !isFinite(converted))
            return false;

        result = converted;
        return true;
    }
    else
    {
        static assert(0, "unsupported geo-d scalar conversion");
    }
}


/**
 * Checked component-wise conversion of a point.
 *
 * Source and target scalar types must belong to the geo-d scalar domain.
 *
 * Conversion is explicit and checked for range, but precision loss within
 * the representable target range is permitted.
 *
 * In particular:
 *
 * - integral-to-integral narrowing fails outside the target range;
 * - integral-to-floating conversion may lose precision;
 * - floating-to-integral conversion requires every coordinate to be finite,
 *   already integral-valued, and inside the target integral range;
 * - floating-to-floating conversion permits NaN and infinity;
 * - floating-to-floating conversion fails when a finite source would become
 *   infinity in the target type.
 *
 * No implicit rounding or quantisation is performed. Use rounded, floored,
 * ceiled, or truncated explicitly before an integral conversion when those
 * semantics are required.
 *
 * Returns false when any coordinate cannot be converted according to these
 * rules.
 *
 * On failure, result is Point2!To.init.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
bool tryConvert(To, From)(
    Point2!From source,
    out Point2!To result
)
    pure nothrow @safe @nogc
if (isGeoScalar!To && isGeoScalar!From)
{
    To x;
    To y;

    if (!tryScalarConvert!To(source.x, x))
        return false;

    if (!tryScalarConvert!To(source.y, y))
        return false;

    result = Point2!To(x, y);
    return true;
}


/**
 * Checked component-wise conversion of a vector.
 *
 * Conversion follows exactly the same scalar rules as Point2 conversion:
 * range overflow is rejected, precision loss within the representable target
 * range is permitted, and no implicit rounding is performed.
 *
 * Returns false when either component cannot be converted.
 *
 * On failure, result is Vector2!To.init.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
bool tryConvert(To, From)(
    Vector2!From source,
    out Vector2!To result
)
    pure nothrow @safe @nogc
if (isGeoScalar!To && isGeoScalar!From)
{
    To x;
    To y;

    if (!tryScalarConvert!To(source.x, x))
        return false;

    if (!tryScalarConvert!To(source.y, y))
        return false;

    result = Vector2!To(x, y);
    return true;
}


/**
 * Checked component-wise conversion of a segment.
 *
 * Both endpoints are converted using the Point2 conversion rules. The
 * complete operation succeeds only when both endpoints convert successfully.
 *
 * Precision loss within the representable target range is permitted. No
 * implicit rounding or quantisation is performed.
 *
 * On failure, result is Segment2!To.init.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
bool tryConvert(To, From)(
    Segment2!From source,
    out Segment2!To result
)
    pure nothrow @safe @nogc
if (isGeoScalar!To && isGeoScalar!From)
{
    Point2!To a;
    Point2!To b;

    if (!tryConvert!To(source.a, a))
        return false;

    if (!tryConvert!To(source.b, b))
        return false;

    result = Segment2!To(a, b);
    return true;
}


/// Example of checked conversion without implicit rounding.
@safe unittest
{
    import geo;

    Point2!int result;

    assert(
        Point2!double(
            3.0,
            -2.0
        ).tryConvert(result)
    );

    assert(
        result ==
        Point2!int(
            3,
            -2
        )
    );

    assert(
        !Point2!double(
            3.5,
            -2.0
        ).tryConvert(result)
    );

    assert(
        result ==
        Point2!int.init
    );
}


/**
 * Returns a point whose coordinates are rounded to the nearest
 * integral-valued floating-point values.
 *
 * This operation is available only for floating-point geometry.
 *
 * Halfway cases are rounded away from zero. NaN and infinities remain
 * non-finite floating-point values; signed zero is preserved.
 *
 * The scalar type is unchanged. This operation does not convert the result
 * to an integral geometry type.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
@property Point2!T rounded(T)(Point2!T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    return Point2!T(
        roundAwayFromZero(value.x),
        roundAwayFromZero(value.y)
    );
}


/**
 * Returns a vector whose components are rounded to the nearest
 * integral-valued floating-point values.
 *
 * This operation is available only for floating-point geometry.
 *
 * Halfway cases are rounded away from zero. NaN and infinities remain
 * non-finite floating-point values; signed zero is preserved.
 *
 * The scalar type is unchanged. This operation does not convert the result
 * to an integral geometry type.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
@property Vector2!T rounded(T)(Vector2!T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    return Vector2!T(
        roundAwayFromZero(value.x),
        roundAwayFromZero(value.y)
    );
}


/**
 * Returns a point with each coordinate rounded toward negative infinity.
 *
 * This operation is available only for floating-point geometry and retains
 * the original scalar type. Non-finite values follow the underlying
 * floating-point floor semantics.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
@property Point2!T floored(T)(Point2!T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    return Point2!T(
        floor(value.x),
        floor(value.y)
    );
}


/**
 * Returns a vector with each component rounded toward negative infinity.
 *
 * This operation is available only for floating-point geometry and retains
 * the original scalar type. Non-finite values follow the underlying
 * floating-point floor semantics.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
@property Vector2!T floored(T)(Vector2!T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    return Vector2!T(
        floor(value.x),
        floor(value.y)
    );
}


/**
 * Returns a point with each coordinate rounded toward positive infinity.
 *
 * This operation is available only for floating-point geometry and retains
 * the original scalar type. Non-finite values follow the underlying
 * floating-point ceil semantics.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
@property Point2!T ceiled(T)(Point2!T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    return Point2!T(
        ceil(value.x),
        ceil(value.y)
    );
}


/**
 * Returns a vector with each component rounded toward positive infinity.
 *
 * This operation is available only for floating-point geometry and retains
 * the original scalar type. Non-finite values follow the underlying
 * floating-point ceil semantics.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
@property Vector2!T ceiled(T)(Vector2!T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    return Vector2!T(
        ceil(value.x),
        ceil(value.y)
    );
}


/**
 * Returns a point with each fractional coordinate part removed.
 *
 * This operation is available only for floating-point geometry. Finite
 * coordinates are rounded toward zero and the original scalar type is
 * retained. NaN and infinities remain non-finite floating-point values;
 * signed zero is preserved.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
@property Point2!T truncated(T)(Point2!T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    return Point2!T(
        truncateTowardZero(value.x),
        truncateTowardZero(value.y)
    );
}


/**
 * Returns a vector with each fractional component removed.
 *
 * This operation is available only for floating-point geometry. Finite
 * components are rounded toward zero and the original scalar type is
 * retained. NaN and infinities remain non-finite floating-point values;
 * signed zero is preserved.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
@property Vector2!T truncated(T)(Vector2!T value)
    pure nothrow @safe @nogc
if (isFloatingPoint!T)
{
    return Vector2!T(
        truncateTowardZero(value.x),
        truncateTowardZero(value.y)
    );
}


@safe unittest
{
    // Integral widening.
    Point2!long pl;
    assert(Point2!int(1, -2).tryConvert(pl));
    assert(pl == Point2!long(1, -2));

    // Integral narrowing is checked.
    Point2!int pi;
    assert(Point2!long(123, -456).tryConvert(pi));
    assert(pi == Point2!int(123, -456));

    assert(!Point2!long(long.max, 0).tryConvert(pi));
    assert(pi == Point2!int.init);

    // Integral -> floating point is explicit but always range-valid.
    Point2!double pd;
    assert(Point2!long(123, -456).tryConvert(pd));
    assert(pd == Point2!double(123.0, -456.0));

    // Floating -> integral requires already integral-valued coordinates.
    assert(Point2!double(3.0, -4.0).tryConvert(pi));
    assert(pi == Point2!int(3, -4));

    assert(!Point2!double(3.5, -4.0).tryConvert(pi));
    assert(pi == Point2!int.init);

    // Quantisation is explicit and orthogonal to conversion.
    auto p = Point2!double(1.5, -2.5);

    assert(p.rounded == Point2!double(2.0, -3.0));
    assert(p.floored == Point2!double(1.0, -3.0));
    assert(p.ceiled == Point2!double(2.0, -2.0));
    assert(p.truncated == Point2!double(1.0, -2.0));

    assert(p.rounded.tryConvert(pi));
    assert(pi == Point2!int(2, -3));

    /*
     * Values immediately below the half-way threshold must not cross it
     * merely because adding 0.5 would itself round.
     */
    const double belowPositiveHalf =
        0x1.fffffffffffffp-2;

    const double aboveNegativeHalf =
        -0x1.fffffffffffffp-2;

    assert(
        Point2!double(
            belowPositiveHalf,
            aboveNegativeHalf
        ).rounded ==
        Point2!double(
            0.0,
            0.0
        )
    );

    assert(
        Point2!double(
            0.5,
            -0.5
        ).rounded ==
        Point2!double(
            1.0,
            -1.0
        )
    );

    // Non-finite values cannot become integers.
    assert(!Point2!double(double.nan, 0.0).tryConvert(pi));
    assert(!Point2!double(double.infinity, 0.0).tryConvert(pi));

    // Floating-point non-finite values remain representable.
    Point2!float pf;

    assert(Point2!double(double.infinity, 1.0).tryConvert(pf));
    assert(pf.x == float.infinity);

    assert(Point2!double(double.nan, 1.0).tryConvert(pf));
    assert(pf.x != pf.x);

    // Finite floating narrowing must not overflow to infinity.
    assert(!Point2!double(double.max, 0.0).tryConvert(pf));

    /*
     * The upper boundary of long is intentionally tested using 2^63.
     * cast(double) long.max is also 2^63, so a naive <= long.max test
     * after conversion to double would be wrong.
     */
    Point2!long plong;

    assert(!Point2!double(
        9_223_372_036_854_775_808.0,
        0.0
    ).tryConvert(plong));

    assert(plong == Point2!long.init);


    assert(Point2!double(
        -9_223_372_036_854_775_808.0,
        0.0
    ).tryConvert(plong));

    assert(plong.x == long.min);

    // Vector conversions use the same scalar rules.
    Vector2!int vi;

    assert(Vector2!double(4.0, -7.0).tryConvert(vi));
    assert(vi == Vector2!int(4, -7));

    assert(!Vector2!double(4.25, -7.0).tryConvert(vi));

    // Segment conversion reuses the Point2 scalar rules.
    Segment2!int si;

    assert(Segment2!double(
        Point2!double(1.0, -2.0),
        Point2!double(3.0, 4.0)
    ).tryConvert(si));

    assert(si == Segment2!int(
        Point2!int(1, -2),
        Point2!int(3, 4)
    ));

    assert(!Segment2!double(
        Point2!double(1.5, -2.0),
        Point2!double(3.0, 4.0)
    ).tryConvert(si));

    assert(si == Segment2!int.init);


    // Quantisation functions exist only for floating-point geometry.
    static assert(!__traits(compiles, Point2!int(1, 2).rounded));
    static assert(!__traits(compiles, Vector2!long(1, 2).floored));
}
