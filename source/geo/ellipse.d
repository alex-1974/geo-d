module geo.ellipse;

import geo.measure : Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import std.math.constants : PI;
import std.math.trigonometry : cos, sin;

/** Intrinsic axis-aligned ellipse defined by its two semi-axes. */
struct Ellipse2(T) if (isGeoScalar!T)
{
private:
    Length!T _a;
    Length!T _b;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }
    @property Length!T semiAxisA() const pure nothrow @safe @nogc
    { assert(_hasValue); return _a; }
    @property Length!T semiAxisB() const pure nothrow @safe @nogc
    { assert(_hasValue); return _b; }

    static bool tryFromSemiAxes(Length!T a, Length!T b,
                                out Ellipse2 result)
        pure nothrow @safe @nogc
    {
        result = Ellipse2.init;
        if (a.value <= 0 || b.value <= 0)
            return false;
        result._a = a;
        result._b = b;
        result._hasValue = true;
        return true;
    }

    MetricScalar!T area() const pure nothrow @safe @nogc
    {
        assert(_hasValue);
        return MetricScalar!T(PI) * MetricScalar!T(_a.value) *
            MetricScalar!T(_b.value);
    }

    /** Materialize an ellipse approximation with counter-clockwise vertices. */
    Polygon2!(MetricScalar!T) toPolygon(
        Placement2!T placement, size_t segmentCount = 64) const
        pure @safe
    {
        if (!_hasValue || segmentCount < 3)
            return Polygon2!(MetricScalar!T).init;
        alias R = MetricScalar!T;
        Point2!R[] points = new Point2!R[segmentCount];
        foreach (i; 0 .. segmentCount)
        {
            const R angle = R(2 * PI) * R(i) / R(segmentCount);
            const Point2!T local = Point2!T(
                cast(T)(R(_a.value) * cos(angle)),
                cast(T)(R(_b.value) * sin(angle)));
            points[i] = placement.map(local);
        }
        return Polygon2!R(points[]);
    }
}

@safe unittest
{
    import geo;
    alias E = Ellipse2!double;
    E ellipse;
    assert(E.tryFromSemiAxes(Length!double(4), Length!double(2), ellipse));
    assert(ellipse.area > 25.13 && ellipse.area < 25.14);
    assert(ellipse.toPolygon(Placement2!double.init, 16).vertexCount == 16);
}
