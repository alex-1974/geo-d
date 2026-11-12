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
import std.math : atan2, sqrt;

/** Common placement frame for a two-dimensional intrinsic shape. */
struct Placement2(T)
if (isGeoScalar!T)
{
    Point2!T origin;
    Angle!T rotation;
    T scale = 1;

    this(Point2!T origin, Angle!T rotation)
        pure nothrow @safe @nogc
    {
        this.origin = origin;
        this.rotation = rotation;
    }

    this(Point2!T origin, Angle!T rotation, T scale)
        pure nothrow @safe @nogc
    {
        this.origin = origin;
        this.rotation = rotation;
        this.scale = scale;
    }

    /** Derive a rigid placement from two local/world vertex correspondences. */
    static bool tryFromVertices(
        Point2!T localFirst, Point2!T worldFirst,
        Point2!T localSecond, Point2!T worldSecond,
        out Placement2 result)
        pure nothrow @safe
    {
        alias R = MetricScalar!T;
        const R localDx = R(localSecond.x) - R(localFirst.x);
        const R localDy = R(localSecond.y) - R(localFirst.y);
        const R worldDx = R(worldSecond.x) - R(worldFirst.x);
        const R worldDy = R(worldSecond.y) - R(worldFirst.y);
        if ((localDx == 0 && localDy == 0) ||
            (worldDx == 0 && worldDy == 0))
        {
            result = Placement2.init;
            return false;
        }
        const R rotation = atan2(worldDy, worldDx) - atan2(localDy, localDx);
        const R c = cos(rotation);
        const R s = sin(rotation);
        const R mappedX = R(localFirst.x) * c - R(localFirst.y) * s;
        const R mappedY = R(localFirst.x) * s + R(localFirst.y) * c;
        result = Placement2(
            Point2!T(cast(T)(R(worldFirst.x) - mappedX),
                     cast(T)(R(worldFirst.y) - mappedY)),
            Angle!T(cast(T) rotation)
        );
        return true;
    }

    /** Derive a placement and infer one uniform scale factor. */
    static bool tryFromVerticesScaled(
        Point2!T localFirst, Point2!T worldFirst,
        Point2!T localSecond, Point2!T worldSecond,
        out Placement2 result)
        pure nothrow @safe
    {
        alias R = MetricScalar!T;
        const R ldx = R(localSecond.x) - R(localFirst.x);
        const R ldy = R(localSecond.y) - R(localFirst.y);
        const R wdx = R(worldSecond.x) - R(worldFirst.x);
        const R wdy = R(worldSecond.y) - R(worldFirst.y);
        const R localLength = sqrt(ldx * ldx + ldy * ldy);
        const R worldLength = sqrt(wdx * wdx + wdy * wdy);
        if (localLength == 0 || worldLength == 0)
        {
            result = Placement2.init;
            return false;
        }
        const R rotation = atan2(wdy, wdx) - atan2(ldy, ldx);
        const R scale = worldLength / localLength;
        const R c = cos(rotation);
        const R s = sin(rotation);
        const R mx = R(localFirst.x) * scale * c - R(localFirst.y) * scale * s;
        const R my = R(localFirst.x) * scale * s + R(localFirst.y) * scale * c;
        result = Placement2(
            Point2!T(cast(T)(R(worldFirst.x) - mx),
                     cast(T)(R(worldFirst.y) - my)),
            Angle!T(cast(T) rotation), cast(T) scale);
        return true;
    }

    /** Derive a rigid placement from one vertex and one directed edge angle. */
    static bool tryFromVertexAndEdge(
        Point2!T localVertex, Point2!T worldVertex,
        Point2!T localEdgeStart, Point2!T localEdgeEnd,
        Angle!T worldAngle,
        out Placement2 result)
        pure nothrow @safe
    {
        alias R = MetricScalar!T;
        const R dx = R(localEdgeEnd.x) - R(localEdgeStart.x);
        const R dy = R(localEdgeEnd.y) - R(localEdgeStart.y);
        if (dx == 0 && dy == 0)
        {
            result = Placement2.init;
            return false;
        }
        const R rotation = R(worldAngle.radians) - atan2(dy, dx);
        const R c = cos(rotation);
        const R s = sin(rotation);
        const R mappedX = R(localVertex.x) * c - R(localVertex.y) * s;
        const R mappedY = R(localVertex.x) * s + R(localVertex.y) * c;
        result = Placement2(
            Point2!T(cast(T)(R(worldVertex.x) - mappedX),
                     cast(T)(R(worldVertex.y) - mappedY)),
            Angle!T(cast(T) rotation)
        );
        return true;
    }

    /** Maps a local point into the placed coordinate system. */
    Point2!(MetricScalar!T) map(Point2!T local) const
        pure nothrow @safe @nogc
    {
        alias R = MetricScalar!T;
        const R c = cos(R(rotation.radians));
        const R s = sin(R(rotation.radians));
        return Point2!R(
            R(origin.x) + R(local.x) * R(scale) * c - R(local.y) * R(scale) * s,
            R(origin.y) + R(local.x) * R(scale) * s + R(local.y) * R(scale) * c
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
    size_t startVertex;
    size_t endVertex;
    Length!T length;
    Angle!T angle;

    this(Length!T length, Angle!T angle)
        pure nothrow @safe @nogc
    {
        this.startVertex = 1;
        this.endVertex = 2;
        this.length = length;
        this.angle = angle;
    }

    this(size_t startVertex, size_t endVertex,
         Length!T length, Angle!T angle)
        pure nothrow @safe @nogc
    {
        this.startVertex = startVertex;
        this.endVertex = endVertex;
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
