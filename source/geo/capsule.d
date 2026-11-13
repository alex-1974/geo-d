/**
 * Intrinsic capsule shape.
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
 *     November 13, 2026
 */
module geo.capsule;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import std.math : cos, sin;
import std.math.constants : PI;

/** Intrinsic 2D capsule with horizontal axis and semicircular ends. */
struct Capsule2(T) if (isGeoScalar!T)
{
private:
    Length!T _axisLength;
    Length!T _radius;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }

    static bool tryFromAxisAndRadius(Length!T axisLength,
                                     Length!T radius,
                                     out Capsule2 result)
        pure nothrow @safe @nogc
    {
        result = Capsule2.init;
        if (axisLength.value < 0 || radius.value <= 0)
            return false;
        result._axisLength = axisLength;
        result._radius = radius;
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement,
                                         size_t segmentCount = 16) const
        pure @safe
    {
        if (!_hasValue || segmentCount < 2)
            return Polygon2!(MetricScalar!T).init;
        alias R = MetricScalar!T;
        Point2!R[] points = new Point2!R[2 * segmentCount + 2];
        const R half = R(_axisLength.value) / 2;
        const R radius = R(_radius.value);
        foreach (i; 0 .. segmentCount + 1)
        {
            const R angle = R(PI) / 2 - R(PI) * R(i) / R(segmentCount);
            points[i] = placement.map(Point2!T(
                cast(T)(half + radius * cos(angle)),
                cast(T)(radius * sin(angle))));
        }
        foreach (i; 0 .. segmentCount + 1)
        {
            const R angle = -R(PI) / 2 - R(PI) * R(i) / R(segmentCount);
            points[segmentCount + 1 + i] = placement.map(Point2!T(
                cast(T)(-half + radius * cos(angle)),
                cast(T)(radius * sin(angle))));
        }
        return Polygon2!R(points[]);
    }

    Polygon2!(MetricScalar!T) toPolygon(AnchorBinding2!T binding,
                                         size_t segmentCount = 16) const
        pure @safe
    {
        Placement2!T placement;
        return tryResolve(binding, placement)
            ? toPolygon(placement, segmentCount)
            : Polygon2!(MetricScalar!T).init;
    }
}

@safe unittest
{
    import geo;
    Capsule2!double capsule;
    assert(Capsule2!double.tryFromAxisAndRadius(
        Length!double(4), Length!double(1), capsule));
    assert(capsule.toPolygon(Placement2!double.init, 8).vertexCount == 18);
}
