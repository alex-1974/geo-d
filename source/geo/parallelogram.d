/**
 * Intrinsic parallelogram shape.
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
 *     November 13, 2026
 */
module geo.parallelogram;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Angle, Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import geo.shape_result : ShapeConstructionResult, ShapeConstructionStatus;
import std.math : cos, sin;

struct Parallelogram2(T) if (isGeoScalar!T)
{
private:
    Length!T _ab;
    Length!T _bc;
    Angle!T _angleB;
    bool _hasValue;

public:
    static ShapeConstructionResult!(Parallelogram2) fromSidesAndAngle(
        Length!T ab, Length!T bc, Angle!T angleB)
        pure nothrow @safe @nogc
    {
        Parallelogram2 result;
        if (ab.value <= 0 || bc.value <= 0 || angleB.radians <= 0)
            return ShapeConstructionResult!(Parallelogram2).failure(
                ShapeConstructionStatus.nonPositive);
        return tryFromSidesAndAngle(ab, bc, angleB, result)
            ? ShapeConstructionResult!(Parallelogram2).success(result)
            : ShapeConstructionResult!(Parallelogram2).failure(
                ShapeConstructionStatus.inconsistent);
    }
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }
    @property Length!T sideAB() const pure nothrow @safe @nogc { assert(_hasValue); return _ab; }
    @property Length!T sideBC() const pure nothrow @safe @nogc { assert(_hasValue); return _bc; }
    @property Angle!T angleB() const pure nothrow @safe @nogc { assert(_hasValue); return _angleB; }

    static bool tryFromSidesAndAngle(Length!T ab, Length!T bc,
                                     Angle!T angleB,
                                     out Parallelogram2 result)
        pure nothrow @safe @nogc
    {
        result = Parallelogram2.init;
        if (ab.value <= 0 || bc.value <= 0 ||
            angleB.radians <= 0 || angleB.radians >= cast(T) 3.141592653589793)
            return false;
        result._ab = ab;
        result._bc = bc;
        result._angleB = angleB;
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement) const
        pure @safe
    {
        if (!_hasValue) return Polygon2!(MetricScalar!T).init;
        alias R = MetricScalar!T;
        const R dx = R(_bc.value) * cos(R(_angleB.radians));
        const R dy = R(_bc.value) * sin(R(_angleB.radians));
        Point2!T[4] local = [
            Point2!T(0, 0),
            Point2!T(_ab.value, 0),
            Point2!T(cast(T)(R(_ab.value) + dx), cast(T) dy),
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
    Parallelogram2!double shape;
    assert(Parallelogram2!double.tryFromSidesAndAngle(
        Length!double(4), Length!double(2),
        Angle!double.fromDegrees(60), shape));
    assert(shape.toPolygon(Placement2!double.init).vertexCount == 4);
}
