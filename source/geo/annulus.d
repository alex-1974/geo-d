module geo.annulus;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import std.math : cos, sin;
import std.math.constants : PI;

/** Intrinsic circular ring defined by outer and inner radius. */
struct Annulus2(T) if (isGeoScalar!T)
{
private:
    Length!T _outer;
    Length!T _inner;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }

    static bool tryFromRadii(Length!T outer, Length!T inner,
                             out Annulus2 result)
        pure nothrow @safe @nogc
    {
        result = Annulus2.init;
        if (outer.value <= 0 || inner.value <= 0 || inner.value >= outer.value)
            return false;
        result._outer = outer;
        result._inner = inner;
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement,
                                         size_t segmentCount = 64) const
        pure @safe
    {
        if (!_hasValue || segmentCount < 3)
            return Polygon2!(MetricScalar!T).init;
        alias R = MetricScalar!T;
        Point2!R[] exterior = new Point2!R[segmentCount];
        Point2!R[] hole = new Point2!R[segmentCount];
        foreach (i; 0 .. segmentCount)
        {
            const R angle = R(2 * PI) * R(i) / R(segmentCount);
            exterior[i] = placement.map(Point2!T(
                cast(T)(R(_outer.value) * cos(angle)),
                cast(T)(R(_outer.value) * sin(angle))));
            const size_t reverse = segmentCount - 1 - i;
            const R innerAngle = R(2 * PI) * R(reverse) / R(segmentCount);
            hole[i] = placement.map(Point2!T(
                cast(T)(R(_inner.value) * cos(innerAngle)),
                cast(T)(R(_inner.value) * sin(innerAngle))));
        }
        Point2!R[][] holes = [hole];
        return Polygon2!R(exterior[], holes);
    }

    Polygon2!(MetricScalar!T) toPolygon(AnchorBinding2!T binding,
                                         size_t segmentCount = 64) const
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
    Annulus2!double ring;
    assert(Annulus2!double.tryFromRadii(
        Length!double(4), Length!double(2), ring));
    auto polygon = ring.toPolygon(Placement2!double.init, 16);
    assert(polygon.view.holeCount == 1);
}
