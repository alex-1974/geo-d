/**
 * Two-dimensional placement of intrinsic shapes.
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
module geo.placement;

import geo.measure : Angle;
import geo.point : Point2;
import geo.scalar : isGeoScalar;

import std.math.trigonometry : cos, sin;

/** Common placement frame for a two-dimensional intrinsic shape. */
struct Placement2(T)
if (isGeoScalar!T)
{
    Point2!T origin;
    Angle!T rotation;

    this(Point2!T origin, Angle!T rotation)
        pure nothrow @safe @nogc
    {
        this.origin = origin;
        this.rotation = rotation;
    }

    /** Maps a local point into the placed coordinate system. */
    Point2!T map(Point2!T local) const
        pure nothrow @safe @nogc
    {
        const T c = cos(rotation.radians);
        const T s = sin(rotation.radians);
        return Point2!T(
            origin.x + local.x * c - local.y * s,
            origin.y + local.x * s + local.y * c
        );
    }
}

enum TriangleAnchor : ubyte
{
    a,
    b,
    c
}

enum RectAnchor : ubyte
{
    center,
    corner0,
    corner1,
    corner2,
    corner3
}

enum CircleAnchor : ubyte
{
    center
}

@safe unittest
{
    import geo;

    alias P = Point2!double;
    auto placement = Placement2!double(
        P(10, 20),
        Angle!double.fromDegrees(90)
    );

    assert(placement.map(P(1, 0)) == P(10, 21));
}
