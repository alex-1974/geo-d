/**
 * Axis-aligned rectangular shapes.
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
 *     November 6, 2026
 */
module geo.rect;

import geo.bounds : Bounds2;
import geo.metric : MetricScalar;
import geo.metric : distance;
import geo.measure : Angle, Length, Size2;
import geo.point : Point2;
import geo.placement : EdgeAngle2, Placement2, VertexPlacement2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;

/** Axis-aligned rectangle with explicit rectangular semantics. */
struct Rect2(T)
if (isGeoScalar!T)
{
private:
    Point2!T _min;
    Point2!T _max;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }
    @property Point2!T min() const pure nothrow @safe @nogc
    { assert(_hasValue); return _min; }
    @property Point2!T max() const pure nothrow @safe @nogc
    { assert(_hasValue); return _max; }

    static bool tryFromMinMax(Point2!T minimum, Point2!T maximum, out Rect2 result)
        pure nothrow @safe @nogc
    {
        result = Rect2.init;
        if (!minimum.isFinite || !maximum.isFinite ||
            minimum.x > maximum.x || minimum.y > maximum.y)
            return false;
        result._min = minimum;
        result._max = maximum;
        result._hasValue = true;
        return true;
    }

    /** Construct a local, unplaced rectangle from intrinsic dimensions. */
    static bool tryFromSize(Size2!T size, out Rect2 result)
        pure nothrow @safe @nogc
    {
        return tryFromMinMax(
            Point2!T.init,
            Point2!T(size.x.value, size.y.value),
            result
        );
    }

    @property Size2!T size() const pure nothrow @safe @nogc
    {
        assert(_hasValue);
        return Size2!T(
            Length!T(_max.x - _min.x),
            Length!T(_max.y - _min.y)
        );
    }

    EdgeAngle2!T edgeAB(Angle!T angle) const
        pure nothrow @safe @nogc
    {
        return EdgeAngle2!T(1, 2, Length!T(_max.x - _min.x), angle);
    }

    EdgeAngle2!T edgeBC(Angle!T angle) const
        pure nothrow @safe @nogc
    {
        return EdgeAngle2!T(2, 3, Length!T(_max.y - _min.y), angle);
    }

    @property bool isFinite() const pure nothrow @safe @nogc
    { return _hasValue && _min.isFinite && _max.isFinite; }

    MetricScalar!T width() const pure nothrow @safe @nogc
    { assert(_hasValue); return MetricScalar!T(_max.x) - MetricScalar!T(_min.x); }

    MetricScalar!T height() const pure nothrow @safe @nogc
    { assert(_hasValue); return MetricScalar!T(_max.y) - MetricScalar!T(_min.y); }

    Point2!(MetricScalar!T) center() const pure nothrow @safe @nogc
    {
        assert(_hasValue);
        alias R = MetricScalar!T;
        return Point2!R((R(_min.x) + R(_max.x)) / 2,
                        (R(_min.y) + R(_max.y)) / 2);
    }

    MetricScalar!T area() const pure nothrow @safe @nogc
    { return width() * height(); }

    MetricScalar!T perimeter() const pure nothrow @safe @nogc
    { return (width() + height()) * 2; }

    bool contains(Point2!T point) const pure nothrow @safe @nogc
    {
        return _hasValue && point.isFinite &&
            point.x >= _min.x && point.x <= _max.x &&
            point.y >= _min.y && point.y <= _max.y;
    }

    bool tryBounds(out Bounds2!T result) const pure nothrow @safe @nogc
    {
        result = Bounds2!T.init;
        return _hasValue && Bounds2!T.tryFromMinMax(_min, _max, result);
    }

    /** Write four counter-clockwise corners into caller-owned storage. */
    bool tryCornersInto(scope Point2!T[] destination) const
        pure nothrow @safe @nogc
    {
        if (!_hasValue || destination.length < 4)
            return false;
        destination[0] = Point2!T(_min.x, _min.y);
        destination[1] = Point2!T(_max.x, _min.y);
        destination[2] = Point2!T(_max.x, _max.y);
        destination[3] = Point2!T(_min.x, _max.y);
        return true;
    }

    /** Materialize the canonical rectangle in a placed coordinate frame. */
    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement) const
        pure @safe
    {
        if (!_hasValue)
            return Polygon2!(MetricScalar!T).init;
        return Polygon2!(MetricScalar!T)(
            [
                placement.map(Point2!T(_min.x, _min.y)),
                placement.map(Point2!T(_max.x, _min.y)),
                placement.map(Point2!T(_max.x, _max.y)),
                placement.map(Point2!T(_min.x, _max.y))
            ]
        );
    }

    /** Derive a rigid placement from two canonical rectangle vertices. */
    bool tryPlacement(VertexPlacement2!T first,
                             VertexPlacement2!T second,
                             out Placement2!T result) const
        pure nothrow @safe
    {
        if (!_hasValue || first.vertex < 1 || first.vertex > 4 ||
            second.vertex < 1 || second.vertex > 4 ||
            first.vertex == second.vertex)
        {
            result = Placement2!T.init;
            return false;
        }
        Point2!T[4] local;
        if (!tryCornersInto(local[]))
        {
            result = Placement2!T.init;
            return false;
        }
        return Placement2!T.tryFromVertices(
            local[first.vertex - 1], first.coordinate,
            local[second.vertex - 1], second.coordinate, result);
    }
    bool tryPlacement(VertexPlacement2!T anchor,
                      EdgeAngle2!T edge,
                      out Placement2!T result) const
        pure nothrow @safe
    {
        if (!_hasValue || anchor.vertex < 1 || anchor.vertex > 4 ||
            edge.startVertex < 1 || edge.startVertex > 4 ||
            edge.endVertex < 1 || edge.endVertex > 4 ||
            edge.startVertex == edge.endVertex)
        {
            result = Placement2!T.init;
            return false;
        }
        Point2!T[4] local;
        if (!tryCornersInto(local[]))
        {
            result = Placement2!T.init;
            return false;
        }
        if (edge.length.value != cast(T) distance(
                local[edge.startVertex - 1], local[edge.endVertex - 1]))
        {
            result = Placement2!T.init;
            return false;
        }
        return Placement2!T.tryFromVertexAndEdge(
            local[anchor.vertex - 1], anchor.coordinate,
            local[edge.startVertex - 1], local[edge.endVertex - 1],
            edge.angle, result);
    }

    Polygon2!(MetricScalar!T) toPolygon(
        VertexPlacement2!T first,
        VertexPlacement2!T second) const
        pure @safe
    {
        Placement2!T placement;
        if (!tryPlacement(first, second, placement))
            return Polygon2!(MetricScalar!T).init;
        return toPolygon(placement);
    }

    Polygon2!(MetricScalar!T) toPolygon(
        VertexPlacement2!T anchor,
        EdgeAngle2!T edge) const
        pure @safe
    {
        Placement2!T placement;
        if (!tryPlacement(anchor, edge, placement))
            return Polygon2!(MetricScalar!T).init;
        return toPolygon(placement);
    }
}

@safe unittest
{
    import geo;
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(int, long, float, double, real))
    {
        Rect2!T rect;
        assert(Rect2!T.tryFromMinMax(
            Point2!T(T(-1), T(-2)), Point2!T(T(3), T(4)), rect));
        assert(rect.valid);
        assert(rect.contains(Point2!T(T(0), T(0))));
    }
}

@safe unittest
{
    import geo;
    alias R = Rect2!double;
    alias P = Point2!double;
    R rect;
    assert(R.tryFromMinMax(P(-1, -2), P(3, 4), rect));
    assert(rect.width == 4 && rect.height == 6);
    assert(rect.area == 24 && rect.perimeter == 20);
    assert(rect.center == Point2!double(1, 1));
    assert(rect.contains(P(0, 0)));
    P[4] corners;
    assert(rect.tryCornersInto(corners[]));
    assert(corners[0] == P(-1, -2));
    assert(corners[2] == P(3, 4));
}
