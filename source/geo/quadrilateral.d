module geo.quadrilateral;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import std.math : sqrt;

struct QuadrilateralSideLengths(T) if (isGeoScalar!T)
{
    Length!T ab;
    Length!T bc;
    Length!T cd;
    Length!T da;
    Length!T ac;
}

/** Convex quadrilateral defined intrinsically by four sides and diagonal AC. */
struct Quadrilateral2(T) if (isGeoScalar!T)
{
private:
    QuadrilateralSideLengths!T _length;
    bool _hasValue;

    static bool validTriangle(R)(R x, R y, R z)
        pure nothrow @safe @nogc
    { return x > 0 && y > 0 && z > 0 && x + y > z && x + z > y && y + z > x; }

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }
    @property auto length() const pure nothrow @safe @nogc
    { assert(_hasValue); return _length; }

    static bool tryFromSidesAndDiagonal(
        Length!T ab, Length!T bc, Length!T cd,
        Length!T da, Length!T ac,
        out Quadrilateral2 result)
        pure nothrow @safe @nogc
    {
        result = Quadrilateral2.init;
        alias R = MetricScalar!T;
        const R d = R(ac.value);
        const R xB = (R(ab.value) * R(ab.value) + d * d -
            R(bc.value) * R(bc.value)) / (R(2) * d);
        const R yB2 = R(ab.value) * R(ab.value) - xB * xB;
        const R xD = (R(da.value) * R(da.value) + d * d -
            R(cd.value) * R(cd.value)) / (R(2) * d);
        const R yD2 = R(da.value) * R(da.value) - xD * xD;
        if (!validTriangle(R(ab.value), R(bc.value), d) ||
            !validTriangle(R(cd.value), R(da.value), d) ||
            yB2 <= 0 || yD2 <= 0)
            return false;
        result._length = QuadrilateralSideLengths!T(ab, bc, cd, da, ac);
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement) const
        pure @safe
    {
        if (!_hasValue) return Polygon2!(MetricScalar!T).init;
        alias R = MetricScalar!T;
        const R d = R(_length.ac.value);
        const R xB = (R(_length.ab.value) * R(_length.ab.value) + d * d -
            R(_length.bc.value) * R(_length.bc.value)) / (R(2) * d);
        const R yB = sqrt(R(_length.ab.value) * R(_length.ab.value) - xB * xB);
        const R xD = (R(_length.da.value) * R(_length.da.value) + d * d -
            R(_length.cd.value) * R(_length.cd.value)) / (R(2) * d);
        const R yD = -sqrt(R(_length.da.value) * R(_length.da.value) - xD * xD);
        Point2!T[4] local = [
            Point2!T(0, 0), Point2!T(cast(T) xB, cast(T) yB),
            Point2!T(cast(T) d, 0), Point2!T(cast(T) xD, cast(T) yD)
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
    alias Q = Quadrilateral2!double;
    Q q;
    assert(Q.tryFromSidesAndDiagonal(
        Length!double(3), Length!double(4),
        Length!double(3), Length!double(4),
        Length!double(5), q));
    assert(q.toPolygon(Placement2!double.init).vertexCount == 4);
}
