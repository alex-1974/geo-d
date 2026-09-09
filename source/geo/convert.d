module geo.convert;

import geo.point : Point2;
import geo.scalar : isGeoScalar;
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
    if (value > T(0))
        return floor(value + T(0.5));

    if (value < T(0))
        return ceil(value - T(0.5));

    // Preserves zero, signed zero and NaN.
    return value;
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
 * No implicit rounding is performed.
 *
 * Floating-point to integral conversion succeeds only when every
 * coordinate is finite, already integral-valued and inside the target
 * scalar range.
 *
 * On failure, result remains Point2!To.init because it is an out
 * parameter.
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
 * Conversion semantics are identical to Point2.
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
 * Returns a point whose coordinates are rounded to the nearest
 * integral-valued floating-point values.
 *
 * Halfway cases are rounded away from zero.
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
 * Halfway cases are rounded away from zero.
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

    // Quantisation functions exist only for floating-point geometry.
    static assert(!__traits(compiles, Point2!int(1, 2).rounded));
    static assert(!__traits(compiles, Vector2!long(1, 2).floored));
}
