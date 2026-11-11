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
import geo.measure : Length;
import geo.metric : MetricScalar;
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
    Point2!(MetricScalar!T) map(Point2!T local) const
        pure nothrow @safe @nogc
    {
        alias R = MetricScalar!T;
        const R c = cos(R(rotation.radians));
        const R s = sin(R(rotation.radians));
        return Point2!R(
            R(origin.x) + R(local.x) * c - R(local.y) * s,
            R(origin.y) + R(local.x) * s + R(local.y) * c
        );
    }
}

/** A vertex bound to a world-space coordinate. */
struct VertexPlacement2(T)
if (isGeoScalar!T)
{
    size_t vertex;
    Point2!T coordinate;

    this(size_t vertex, Point2!T coordinate)
        pure nothrow @safe @nogc
    {
        this.vertex = vertex;
        this.coordinate = coordinate;
    }
}

/** A local shape length and its world-space direction. */
struct EdgeAngle2(T)
if (isGeoScalar!T)
{
    Length!T length;
    Angle!T angle;

    this(Length!T length, Angle!T angle)
        pure nothrow @safe @nogc
    {
        this.length = length;
        this.angle = angle;
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

    auto vertex = VertexPlacement2!double(1, P(2, 6));
    auto edge = EdgeAngle2!double(
        Length!double(2),
        Angle!double.fromDegrees(75)
    );
    assert(vertex.vertex == 1);
    assert(vertex.coordinate == P(2, 6));
    assert(edge.length == 2);
}
