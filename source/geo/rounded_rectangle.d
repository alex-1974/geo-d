/**
 * Intrinsic rounded rectangle shape.
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
module geo.rounded_rectangle;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import std.math : cos, sin;
import std.math.constants : PI;

/** Intrinsic rectangle with four equal corner radii. */
struct RoundedRectangle2(T) if (isGeoScalar!T)
{
private:
    Length!T _width;
    Length!T _height;
    Length!T _radius;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }

    static bool tryFromSizeAndRadius(Length!T width, Length!T height,
                                     Length!T radius,
                                     out RoundedRectangle2 result)
        pure nothrow @safe @nogc
    {
        result = RoundedRectangle2.init;
        if (width.value <= 0 || height.value <= 0 || radius.value < 0 ||
            radius.value > width.value / 2 || radius.value > height.value / 2)
            return false;
        result._width = width;
        result._height = height;
        result._radius = radius;
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement,
                                         size_t segmentCount = 8) const
        pure @safe
    {
        if (!_hasValue || segmentCount < 1)
            return Polygon2!(MetricScalar!T).init;
        alias R = MetricScalar!T;
        Point2!R[] points = new Point2!R[4 * segmentCount + 4];
        const R w = R(_width.value), h = R(_height.value), r = R(_radius.value);
        const R[4] cx = [w - r, r, r, w - r];
        const R[4] cy = [r, r, h - r, h - r];
        const R[4] starts = [0, PI / 2, PI, 3 * PI / 2];
        size_t n;
        foreach (corner; 0 .. 4)
        {
            foreach (i; 0 .. segmentCount + 1)
            {
                const R angle = starts[corner] +
                    R(PI / 2) * R(i) / R(segmentCount);
                points[n++] = placement.map(Point2!T(
                    cast(T)(cx[corner] + r * cos(angle)),
                    cast(T)(cy[corner] + r * sin(angle))));
            }
        }
        return Polygon2!R(points[]);
    }

    Polygon2!(MetricScalar!T) toPolygon(AnchorBinding2!T binding,
                                         size_t segmentCount = 8) const
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
    RoundedRectangle2!double shape;
    assert(RoundedRectangle2!double.tryFromSizeAndRadius(
        Length!double(10), Length!double(6), Length!double(1), shape));
    assert(shape.toPolygon(Placement2!double.init, 4).vertexCount == 20);
}
