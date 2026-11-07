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

    /// Returns a borrowed view while this owning value remains alive.
    Polygon2View!T view() const pure nothrow @safe @nogc
    {
        return Polygon2View!T(_rings[]);
    }
}
