module geo.triangle;

import geo.bounds : Bounds2;
import geo.metric : MetricScalar;
import geo.metric : distance;
import geo.point : Point2;
import geo.scalar : isGeoScalar;

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
