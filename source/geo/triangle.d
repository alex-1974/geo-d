/**
 * Fixed-cardinality triangular shapes.
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
module geo.triangle;

import geo.bounds : Bounds2;
import geo.metric : MetricScalar;
import geo.metric : distance;
import geo.measure : Angle, Length;
import geo.point : Point2;
import geo.placement : EdgeAngle2, Placement2, VertexPlacement2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import std.math.constants : PI;
import std.math : sqrt;
import std.math.trigonometry : cos, sin;

struct TriangleSideLengths(T)
if (isGeoScalar!T)
{
    Length!T ab;
    Length!T bc;
    Length!T ca;
}

/** Fixed-cardinality three-point Euclidean shape. Degenerate triangles remain representable. */
struct Triangle2(T)
if (isGeoScalar!T)
{
private:
    Point2!T _a;
    Point2!T _b;
    Point2!T _c;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }
    @property Point2!T a() const pure nothrow @safe @nogc { assert(_hasValue); return _a; }
    @property Point2!T b() const pure nothrow @safe @nogc { assert(_hasValue); return _b; }
    @property Point2!T c() const pure nothrow @safe @nogc { assert(_hasValue); return _c; }

    @property TriangleSideLengths!T length() const
        pure nothrow @safe @nogc
    {
        assert(_hasValue);
        return TriangleSideLengths!T(
            Length!T(cast(T) distance(_a, _b)),
            Length!T(cast(T) distance(_b, _c)),
            Length!T(cast(T) distance(_c, _a))
        );
    }

    /** Construct SSS: AB, BC and CA. */
    static bool tryFrom(Length!T ab, Length!T bc, Length!T ca,
                        out Triangle2 result)
        pure nothrow @safe @nogc
    {
        result = Triangle2.init;
        alias R = MetricScalar!T;
        const R x = R(ab.value), y = R(bc.value), z = R(ca.value);
        if (x <= 0 || y <= 0 || z <= 0 ||
            x + y <= z || x + z <= y || y + z <= x)
            return false;
        const R px = (x * x + z * z - y * y) / (R(2) * x);
        const R py2 = z * z - px * px;
        if (py2 <= 0)
            return false;
        const R py = sqrt(py2);
        return tryFromPoints(
            Point2!T(cast(T) 0, cast(T) 0),
            Point2!T(ab.value, cast(T) 0),
            Point2!T(cast(T) px, cast(T) py), result);
    }

    /** Construct SAS: AB, included angle B, BC. */
    static bool tryFrom(Length!T ab, Angle!T angleB, Length!T bc,
                        out Triangle2 result)
        pure nothrow @safe @nogc
    {
        alias R = MetricScalar!T;
        const R a = R(ab.value), b = R(bc.value), angle = R(angleB.radians);
        if (a <= 0 || b <= 0 || angle <= 0 || angle >= R(PI))
        { result = Triangle2.init; return false; }
        const R c = sqrt(a * a + b * b - R(2) * a * b * cos(angle));
        return tryFrom(ab, Length!T(cast(T) c), bc, result);
    }

    /** Construct ASA: angle A, side AB, angle B. */
    static bool tryFrom(Angle!T angleA, Length!T ab, Angle!T angleB,
                        out Triangle2 result)
        pure nothrow @safe @nogc
    {
        alias R = MetricScalar!T;
        const R a = R(angleA.radians), b = R(angleB.radians);
        const R c = R(PI) - a - b;
        if (R(ab.value) <= 0 || a <= 0 || b <= 0 || c <= 0)
        { result = Triangle2.init; return false; }
        const R sideAB = R(ab.value);
        const R sideBC = sideAB * sin(b) / sin(c);
        const R sideCA = sideAB * sin(a) / sin(c);
        return tryFrom(ab, Length!T(cast(T) sideBC), Length!T(cast(T) sideCA), result);
    }

    static bool tryFromPoints(Point2!T first, Point2!T second, Point2!T third,
                              out Triangle2 result)
        pure nothrow @safe @nogc
    {
        result = Triangle2.init;
        if (!first.isFinite || !second.isFinite || !third.isFinite)
            return false;
        result._a = first;
        result._b = second;
        result._c = third;
        result._hasValue = true;
        return true;
    }

    MetricScalar!T area() const pure nothrow @safe @nogc
    {
        assert(_hasValue);
        alias R = MetricScalar!T;
        const R abx = R(_b.x) - R(_a.x);
        const R aby = R(_b.y) - R(_a.y);
        const R acx = R(_c.x) - R(_a.x);
        const R acy = R(_c.y) - R(_a.y);
        const R twice = abx * acy - aby * acx;
        return twice < 0 ? -twice / 2 : twice / 2;
    }

    MetricScalar!T perimeter() const pure nothrow @safe @nogc
    {
        assert(_hasValue);
        return distance(_a, _b) + distance(_b, _c) + distance(_c, _a);
    }

    Point2!(MetricScalar!T) centroid() const pure nothrow @safe @nogc
    {
        assert(_hasValue);
        alias R = MetricScalar!T;
        return Point2!R(
            (R(_a.x) + R(_b.x) + R(_c.x)) / 3,
            (R(_a.y) + R(_b.y) + R(_c.y)) / 3
        );
    }

    bool tryBounds(out Bounds2!T result) const pure nothrow @safe @nogc
    {
        result = Bounds2!T.init;
        if (!_hasValue) return false;
        const T minX = _a.x < _b.x
            ? (_a.x < _c.x ? _a.x : _c.x)
            : (_b.x < _c.x ? _b.x : _c.x);
        const T minY = _a.y < _b.y
            ? (_a.y < _c.y ? _a.y : _c.y)
            : (_b.y < _c.y ? _b.y : _c.y);
        const T maxX = _a.x > _b.x
            ? (_a.x > _c.x ? _a.x : _c.x)
            : (_b.x > _c.x ? _b.x : _c.x);
        const T maxY = _a.y > _b.y
            ? (_a.y > _c.y ? _a.y : _c.y)
            : (_b.y > _c.y ? _b.y : _c.y);
        return Bounds2!T.tryFromMinMax(
            Point2!T(minX, minY), Point2!T(maxX, maxY), result);
    }

    bool tryPointsInto(scope Point2!T[] destination) const
        pure nothrow @safe @nogc
    {
        if (!_hasValue || destination.length < 3) return false;
        destination[0] = _a;
        destination[1] = _b;
        destination[2] = _c;
        return true;
    }

    /** Materialize the canonical triangle in a placed coordinate frame. */
    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement) const
        pure @safe
    {
        if (!_hasValue)
            return Polygon2!(MetricScalar!T).init;
        return Polygon2!(MetricScalar!T)(
            [
                placement.map(_a),
                placement.map(_b),
                placement.map(_c)
            ]
        );
    }

    /** Derive a rigid placement from two canonical triangle vertices. */
    bool tryPlacement(VertexPlacement2!T first,
                             VertexPlacement2!T second,
                             out Placement2!T result) const
        pure nothrow @safe
    {
        if (!_hasValue || first.vertex > 2 || second.vertex > 2 ||
            first.vertex == second.vertex)
        {
            result = Placement2!T.init;
            return false;
        }
        Point2!T[3] local;
        local[] = [_a, _b, _c];
        return Placement2!T.tryFromVertices(
            local[first.vertex], first.coordinate,
            local[second.vertex], second.coordinate, result);
    }
    bool tryPlacement(VertexPlacement2!T anchor,
                      EdgeAngle2!T edge,
                      out Placement2!T result) const
        pure nothrow @safe
    {
        if (!_hasValue || anchor.vertex > 2 || edge.startVertex > 2 ||
            edge.endVertex > 2 || edge.startVertex == edge.endVertex)
        {
            result = Placement2!T.init;
            return false;
        }
        Point2!T[3] local = [_a, _b, _c];
        return Placement2!T.tryFromVertexAndEdge(
            local[anchor.vertex], anchor.coordinate,
            local[edge.startVertex], local[edge.endVertex],
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
    alias T = Triangle2!double;
    alias P = Point2!double;
    T triangle;
    assert(T.tryFromPoints(P(0, 0), P(4, 0), P(0, 3), triangle));
    assert(triangle.area == 6);
    assert(triangle.perimeter > 11.9 && triangle.perimeter < 12.1);
    assert(triangle.centroid == Point2!double(4.0 / 3.0, 1.0));
    P[3] points;
    assert(triangle.tryPointsInto(points[]));
    assert(points[1] == P(4, 0));

    T sss;
    assert(T.tryFrom(
        Length!double(4),
        Length!double(5),
        Length!double(3),
        sss
    ));
    assert(sss.length.ab == Length!double(4));
    assert(sss.length.bc == Length!double(5));
    assert(sss.length.ca == Length!double(3));

    T sas;
    assert(T.tryFrom(
        Length!double(4),
        Angle!double.fromDegrees(90),
        Length!double(3),
        sas
    ));
    assert(sas.perimeter > 11.9 && sas.perimeter < 12.1);

    T asa;
    assert(T.tryFrom(
        Angle!double.fromDegrees(45),
        Length!double(4),
        Angle!double.fromDegrees(45),
        asa
    ));
    assert(asa.length.ab == Length!double(4));
}

@safe unittest
{
    import geo;
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(int, long, float, double, real))
    {
        Triangle2!T triangle;
        assert(Triangle2!T.tryFromPoints(
            Point2!T(T(0), T(0)),
            Point2!T(T(1), T(0)),
            Point2!T(T(0), T(1)),
            triangle));
        assert(triangle.valid);
    }
}
