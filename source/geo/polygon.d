/**
 * Owning materialized polygons.
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
module geo.polygon;

import geo.anchor_binding : Anchor2, AnchorBinding2, tryResolve;
import geo.metric : MetricScalar, distance;
import geo.measure : Angle, Length;
import geo.placement : Placement2;
import geo.transform : Transform2;

import geo.linear_ring_view : LinearRing2View;
import geo.point : Point2;
import geo.polygon_view : Polygon2View;
import geo.scalar : isGeoScalar;

/**
 * Owning polygon with one exterior ring and optional interior rings.
 *
 * The point storage is owned by this value. `view` exposes the same geometry
 * through the established non-owning `Polygon2View` API and is valid only
 * while this owning value remains alive and unchanged.
 */
struct Polygon2(T)
if (isGeoScalar!T)
{
private:
    Point2!T[] _points;
    LinearRing2View!T[] _rings;

public:
    /// Materializes one exterior ring from caller-provided points.
    this(scope const(Point2!T)[] points)
    {
        _points = new Point2!T[points.length];
        _points[] = points[];
        _rings = new LinearRing2View!T[1];
        _rings[0] = LinearRing2View!T(_points[]);
    }

    /// Materializes an exterior ring and caller-provided interior rings.
    this(scope const(Point2!T)[] exterior,
         scope Point2!T[][] holes)
    {
        size_t total = exterior.length;
        foreach (hole; holes) total += hole.length;
        _points = new Point2!T[total];
        _rings = new LinearRing2View!T[holes.length + 1];
        size_t offset;
        _points[0 .. exterior.length] = exterior[];
        _rings[0] = LinearRing2View!T(_points[0 .. exterior.length]);
        offset = exterior.length;
        foreach (i, hole; holes)
        {
            _points[offset .. offset + hole.length] = hole[];
            _rings[i + 1] = LinearRing2View!T(
                _points[offset .. offset + hole.length]);
            offset += hole.length;
        }
    }

    @property bool empty() const pure nothrow @safe @nogc
    {
        return _points.length == 0;
    }

    @property size_t vertexCount() const pure nothrow @safe @nogc
    {
        return _points.length;
    }

    /** Return a polygon vertex using the public one-based index convention. */
    Point2!T vertex(size_t index) const pure nothrow @safe @nogc
    {
        assert(index >= 1 && index <= _points.length);
        return _points[index - 1];
    }

    /// Returns a borrowed view while this owning value remains alive.
    Polygon2View!T view() const pure nothrow @safe @nogc
    {
        return Polygon2View!T(_rings[]);
    }

    @property size_t holeCount() const pure nothrow @safe @nogc
    { return _rings.length > 0 ? _rings.length - 1 : 0; }

    Polygon2 attachTo(AnchorBinding2!T binding) const
        pure @safe
    {
        Placement2!T placement;
        return tryResolve(binding, placement) ? transform(placement) : Polygon2.init;
    }

    Polygon2 attachTo(AnchorBinding2!T first,
                      AnchorBinding2!T second) const
        pure @safe
    {
        Placement2!T placement;
        return tryResolve(first, second, placement) ? transform(placement) : Polygon2.init;
    }

    Polygon2 transform(Placement2!T placement) const pure @safe
    {
        if (_points.length == 0) return Polygon2.init;
        Point2!T[] mapped = new Point2!T[_points.length];
        foreach (i, point; _points)
        {
            auto p = placement.map(point);
            mapped[i] = Point2!T(cast(T) p.x, cast(T) p.y);
        }
        return withRings(mapped[]);
    }

    Polygon2 transform(Transform2!T transform) const pure @safe
    {
        if (_points.length == 0) return Polygon2.init;
        Point2!T[] mapped = new Point2!T[_points.length];
        foreach (i, point; _points)
        {
            auto p = transform.apply(point);
            mapped[i] = Point2!T(cast(T) p.x, cast(T) p.y);
        }
        return withRings(mapped[]);
    }

private:
    Polygon2 withRings(scope const(Point2!T)[] points) const
    {
        if (_rings.length <= 1) return Polygon2(points[]);
        Point2!T[] exterior = points[0 .. _rings[0].length].dup;
        Point2!T[][] holes = new Point2!T[][](_rings.length - 1);
        size_t offset = _rings[0].length;
        foreach (i; 1 .. _rings.length)
        {
            holes[i - 1] = points[offset .. offset + _rings[i].length].dup;
            offset += _rings[i].length;
        }
        return Polygon2!T(exterior[], holes);
    }
}

Anchor2!T sourceVertex(T)(Polygon2!T polygon, size_t index)
    if (isGeoScalar!T)
{
    return Anchor2!T.vertex(index, polygon.vertex(index));
}

Anchor2!T targetVertex(T)(Polygon2!T polygon, size_t index)
    if (isGeoScalar!T)
{
    return Anchor2!T.vertex(index, polygon.vertex(index));
}

private Anchor2!T polygonEdgeAnchor(T)(Polygon2!T polygon,
                                       size_t startVertex)
    if (isGeoScalar!T)
{
    assert(startVertex >= 1 && startVertex <= polygon.vertexCount);
    const size_t endVertex = startVertex == polygon.vertexCount
        ? 1 : startVertex + 1;
    const auto start = polygon.vertex(startVertex);
    const auto end = polygon.vertex(endVertex);
    alias R = MetricScalar!T;
    const R dx = R(end.x) - R(start.x);
    const R dy = R(end.y) - R(start.y);
    import std.math : atan2;
    auto result = Anchor2!T.edge(
        startVertex,
        endVertex,
        Length!T(cast(T) distance(start, end)),
        Angle!T(cast(T) atan2(dy, dx))
    );
    result.point = start;
    return result;
}

Anchor2!T sourceEdge(T)(Polygon2!T polygon, size_t startVertex)
    if (isGeoScalar!T)
{
    return polygonEdgeAnchor(polygon, startVertex);
}

Anchor2!T targetEdge(T)(Polygon2!T polygon, size_t startVertex)
    if (isGeoScalar!T)
{
    return polygonEdgeAnchor(polygon, startVertex);
}
