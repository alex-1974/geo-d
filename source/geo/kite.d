module geo.kite;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Angle, Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import std.math : cos, sin;

/** Intrinsic kite with AB=AD and BC=CD. */
struct Kite2(T) if (isGeoScalar!T)
{
private:
    Length!T _ab;
    Length!T _bc;
    Angle!T _angleA;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }
    @property Length!T sideAB() const pure nothrow @safe @nogc { assert(_hasValue); return _ab; }
    @property Length!T sideBC() const pure nothrow @safe @nogc { assert(_hasValue); return _bc; }
    @property Angle!T angleA() const pure nothrow @safe @nogc { assert(_hasValue); return _angleA; }

    static bool tryFromSidesAndAngle(Length!T ab, Length!T bc,
                                     Angle!T angleA, out Kite2 result)
        pure nothrow @safe @nogc
    {
        result = Kite2.init;
        if (ab.value <= 0 || bc.value <= 0 || angleA.radians <= 0 ||
            angleA.radians >= cast(T) 3.141592653589793)
            return false;
        result._ab = ab;
        result._bc = bc;
        result._angleA = angleA;
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement) const
        pure @safe
    {
        if (!_hasValue) return Polygon2!(MetricScalar!T).init;
        alias R = MetricScalar!T;
        const R dx = R(_ab.value) * cos(R(_angleA.radians));
        const R dy = R(_ab.value) * sin(R(_angleA.radians));
        Point2!T[4] local = [
            Point2!T(0, 0),
            Point2!T(_bc.value, 0),
            Point2!T(cast(T)(R(_bc.value) + dx), cast(T) dy),
            Point2!T(cast(T) dx, cast(T) dy)
        ];
        Point2!R[4] points;
        foreach (i, point; local) points[i] = placement.map(point);
        return Polygon2!R(points[]);
    }

    Polygon2!(MetricScalar!T) toPolygon(AnchorBinding2!T binding) const
        pure @safe
    {
        Placement2!T placement;
        return tryResolve(binding, placement) ? toPolygon(placement)
            : Polygon2!(MetricScalar!T).init;
    }
}

@safe unittest
{
    import geo;
    Kite2!double shape;
    assert(Kite2!double.tryFromSidesAndAngle(
        Length!double(3), Length!double(2),
        Angle!double.fromDegrees(90), shape));
    assert(shape.toPolygon(Placement2!double.init).vertexCount == 4);
}
