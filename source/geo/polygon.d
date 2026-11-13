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
 * Owning polygon with one exterior ring and no holes.
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
            mapped[i] = placement.map(point);
        return Polygon2(mapped[]);
    }

    Polygon2 transform(Transform2!T transform) const pure @safe
    {
        if (_points.length == 0) return Polygon2.init;
        Point2!T[] mapped = new Point2!T[_points.length];
        foreach (i, point; _points)
            mapped[i] = transform.apply(point);
        return Polygon2(mapped[]);
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
