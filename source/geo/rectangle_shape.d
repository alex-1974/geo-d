module geo.rectangle_shape;

import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.measure : Length;
import geo.metric : MetricScalar;
import geo.placement : Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;

struct RectangleLengths(T) if (isGeoScalar!T)
{
    Length!T ab;
    Length!T bc;
}

/** Intrinsic rectangle defined by two adjacent side lengths. */
struct Rectangle2(T) if (isGeoScalar!T)
{
private:
    RectangleLengths!T _length;
    bool _hasValue;

public:
    @property bool valid() const pure nothrow @safe @nogc { return _hasValue; }
    @property RectangleLengths!T length() const pure nothrow @safe @nogc
    { assert(_hasValue); return _length; }

    static bool tryFromLengths(Length!T ab, Length!T bc,
                               out Rectangle2 result)
        pure nothrow @safe @nogc
    {
        result = Rectangle2.init;
        if (ab.value <= 0 || bc.value <= 0) return false;
        result._length = RectangleLengths!T(ab, bc);
        result._hasValue = true;
        return true;
    }

    Polygon2!(MetricScalar!T) toPolygon(Placement2!T placement) const
        pure @safe
    {
        if (!_hasValue) return Polygon2!(MetricScalar!T).init;
        Point2!T[4] local = [
            Point2!T(0, 0),
            Point2!T(_length.ab.value, 0),
            Point2!T(_length.ab.value, _length.bc.value),
            Point2!T(0, _length.bc.value)
        ];
        alias R = MetricScalar!T;
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

/** Intrinsic square defined by one side length. */
struct Square2(T) if (isGeoScalar!T)
{
private:
    Length!T _side;
    bool _hasValue;

public:
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
        Rectangle2!T rectangle;
        if (!_hasValue || !Rectangle2!T.tryFromLengths(_side, _side, rectangle))
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
