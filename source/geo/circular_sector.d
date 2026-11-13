module geo.circular_sector;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Angle, Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import std.math : cos, sin;
import std.math.constants : PI;

struct CircularSector2(T) if (isGeoScalar!T)
{
private:
    Length!T _radius;
    Angle!T _start;
    Angle!T _sweep;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }

    static bool tryFromRadiusAndAngle(Length!T radius, Angle!T start,
                                      Angle!T sweep,
                                      out CircularSector2 result)
        pure nothrow @safe @nogc
    {
        result = CircularSector2.init;
        if (radius.value <= 0 || sweep.radians == 0 ||
            sweep.radians > cast(T)(2 * PI) ||
            sweep.radians < -cast(T)(2 * PI)) return false;
        result._radius = radius;
        result._start = start;
        result._sweep = sweep;
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement,
                                         size_t segmentCount = 32) const
        pure @safe
    {
        if (!_hasValue || segmentCount < 1)
            return Polygon2!(MetricScalar!T).init;
        alias R = MetricScalar!T;
        Point2!R[] points = new Point2!R[segmentCount + 2];
        points[0] = placement.map(Point2!T(0, 0));
        foreach (i; 0 .. segmentCount + 1)
        {
            const R fraction = R(i) / R(segmentCount);
            const R angle = R(_start.radians) + R(_sweep.radians) * fraction;
            points[i + 1] = placement.map(Point2!T(
                cast(T)(R(_radius.value) * cos(angle)),
                cast(T)(R(_radius.value) * sin(angle))));
        }
        return Polygon2!R(points[]);
    }

    Polygon2!(MetricScalar!T) toPolygon(AnchorBinding2!T binding,
                                         size_t segmentCount = 32) const
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
    CircularSector2!double sector;
    assert(CircularSector2!double.tryFromRadiusAndAngle(
        Length!double(2), Angle!double(0),
        Angle!double.fromDegrees(90), sector));
    assert(sector.toPolygon(Placement2!double.init, 8).vertexCount == 10);
}
