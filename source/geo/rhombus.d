/**
 * Intrinsic rhombus shape.
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
module geo.rhombus;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Angle, Length;
import geo.metric : MetricScalar;
import geo.parallelogram : Parallelogram2;
import geo.placement : Placement2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import geo.shape_result : ShapeConstructionResult, ShapeConstructionStatus;

/** Intrinsic rhombus defined by side length and included angle. */
struct Rhombus2(T) if (isGeoScalar!T)
{
private:
    Length!T _side;
    Angle!T _angle;
    bool _hasValue;

public:
    static ShapeConstructionResult!(Rhombus2) fromSideAndAngle(
        Length!T side, Angle!T angle)
        pure nothrow @safe @nogc
    {
        Rhombus2 result;
        if (side.value <= 0 || angle.radians <= 0)
            return ShapeConstructionResult!(Rhombus2).failure(
                ShapeConstructionStatus.nonPositive);
        return tryFromSideAndAngle(side, angle, result)
            ? ShapeConstructionResult!(Rhombus2).success(result)
            : ShapeConstructionResult!(Rhombus2).failure(
                ShapeConstructionStatus.inconsistent);
    }
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }
    @property Length!T side() const pure nothrow @safe @nogc { assert(_hasValue); return _side; }
    @property Angle!T angle() const pure nothrow @safe @nogc { assert(_hasValue); return _angle; }

    static bool tryFromSideAndAngle(Length!T side, Angle!T angle,
                                    out Rhombus2 result)
        pure nothrow @safe @nogc
    {
        result = Rhombus2.init;
        if (side.value <= 0 || angle.radians <= 0 ||
            angle.radians >= cast(T) 3.141592653589793)
            return false;
        result._side = side;
        result._angle = angle;
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement) const
        pure @safe
    {
        Parallelogram2!T p;
        if (!_hasValue || !Parallelogram2!T.tryFromSidesAndAngle(
                _side, _side, _angle, p))
            return Polygon2!(MetricScalar!T).init;
        return p.toPolygon(placement);
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
    Rhombus2!double shape;
    assert(Rhombus2!double.tryFromSideAndAngle(
        Length!double(3), Angle!double.fromDegrees(60), shape));
    assert(shape.toPolygon(Placement2!double.init).vertexCount == 4);
}
