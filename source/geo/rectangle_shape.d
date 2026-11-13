/**
 * Intrinsic rectangle shape.
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
module geo.rectangle_shape;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.rect : Rect2;
import geo.scalar : isGeoScalar;
import geo.shape_result : ShapeConstructionResult, ShapeConstructionStatus;

alias RectangleLengths(T) = RectLengths!T;

/** Intrinsic rectangle defined by two adjacent side lengths. */
alias Rectangle2(T) = Rect2!T;

/** Intrinsic square defined by one side length. */
struct Square2(T) if (isGeoScalar!T)
{
private:
    Length!T _side;
    bool _hasValue;

public:
    static ShapeConstructionResult!(Square2) fromSide(Length!T side)
        pure nothrow @safe @nogc
    {
        Square2 result;
        if (side.value <= 0)
            return ShapeConstructionResult!(Square2).failure(
                ShapeConstructionStatus.nonPositive);
        return tryFromSide(side, result)
            ? ShapeConstructionResult!(Square2).success(result)
            : ShapeConstructionResult!(Square2).failure(
                ShapeConstructionStatus.inconsistent);
    }

    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }
    @property Length!T side() const pure nothrow @safe @nogc
    { assert(_hasValue); return _side; }

    static bool tryFromSide(Length!T side, out Square2 result)
        pure nothrow @safe @nogc
    {
        result = Square2.init;
        if (side.value <= 0) return false;
        result._side = side;
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement) const
        pure @safe
    {
        Rect2!T rectangle;
        if (!_hasValue || !Rect2!T.tryFromLengths(_side, _side, rectangle))
            return Polygon2!(MetricScalar!T).init;
        return rectangle.toPolygon(placement);
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
    Rectangle2!double rectangle;
    assert(Rectangle2!double.tryFromLengths(
        Length!double(4), Length!double(2), rectangle));
    assert(rectangle.toPolygon(Placement2!double.init).vertexCount == 4);
    Square2!double square;
    assert(Square2!double.tryFromSide(Length!double(3), square));
    assert(square.toPolygon(Placement2!double.init).vertexCount == 4);
}
