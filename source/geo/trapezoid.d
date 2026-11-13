module geo.trapezoid;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import std.math : sqrt;

/** Convex trapezoid with AB parallel to CD. */
struct Trapezoid2(T) if (isGeoScalar!T)
{
private:
    Length!T _ab;
    Length!T _bc;
    Length!T _cd;
    Length!T _da;
    Length!T _height;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }

    static bool tryFromBasesLegsAndHeight(
        Length!T ab, Length!T bc, Length!T cd,
        Length!T da, Length!T height,
        out Trapezoid2 result)
        pure nothrow @safe @nogc
    {
        result = Trapezoid2.init;
        alias R = MetricScalar!T;
        const R h = R(height.value);
        const R legA = R(da.value);
        const R legB = R(bc.value);
        if (ab.value <= 0 || bc.value <= 0 || cd.value <= 0 ||
            da.value <= 0 || h <= 0 || legA < h || legB < h)
            return false;
        const R offsetA = sqrt(legA * legA - h * h);
        const R offsetB = sqrt(legB * legB - h * h);
        const R expectedBaseDifference = offsetA + offsetB;
        if (R(ab.value) - R(cd.value) != expectedBaseDifference &&
            R(cd.value) - R(ab.value) != expectedBaseDifference)
            return false;
        result._ab = ab;
        result._bc = bc;
        result._cd = cd;
        result._da = da;
        result._height = height;
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement) const
        pure @safe
    {
        if (!_hasValue) return Polygon2!(MetricScalar!T).init;
        alias R = MetricScalar!T;
        const R h = R(_height.value);
        const R offsetA = sqrt(R(_da.value) * R(_da.value) - h * h);
        const R xD = offsetA;
        const R xC = xD + R(_cd.value);
        Point2!T[4] local = [
            Point2!T(0, 0),
            Point2!T(_ab.value, 0),
            Point2!T(cast(T) xC, cast(T) h),
            Point2!T(cast(T) xD, cast(T) h)
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
    Trapezoid2!double shape;
    assert(Trapezoid2!double.tryFromBasesLegsAndHeight(
        Length!double(10), Length!double(5), Length!double(4),
        Length!double(5), Length!double(4), shape));
    assert(shape.toPolygon(Placement2!double.init).vertexCount == 4);
}
