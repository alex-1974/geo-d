/**
 * Typed intrinsic geometric measures.
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
 *     November 7, 2026
 */
module geo.measure;

import geo.scalar : isGeoScalar;
import std.math.constants : PI;

/// A scalar geometric length.
struct Length(T)
if (isGeoScalar!T)
{
    T value;
    alias value this;

    this(T value) pure nothrow @safe @nogc
    {
        this.value = value;
    }
}

/// An angle stored in radians.
struct Angle(T)
if (isGeoScalar!T)
{
    T radians;
    alias radians this;

    this(T radians) pure nothrow @safe @nogc
    {
        this.radians = radians;
    }

    static Angle fromDegrees(T degrees)
        pure nothrow @safe @nogc
    {
        return Angle(cast(T)(degrees * PI / 180));
    }
}

/// Intrinsic two-dimensional orthogonal shape dimensions.
struct Size2(T)
if (isGeoScalar!T)
{
    Length!T x;
    Length!T y;
}

/// Intrinsic three-dimensional orthogonal shape dimensions.
struct Size3(T)
if (isGeoScalar!T)
{
    Length!T x;
    Length!T y;
    Length!T z;
}

@safe unittest
{
    import geo;

    auto size = Size2!double(
        Length!double(10),
        Length!double(5)
    );
    assert(size.x == 10);
    assert(size.y == 5);

    auto angle = Angle!double.fromDegrees(180);
    assert(angle.radians > 3.14 && angle.radians < 3.15);
}
