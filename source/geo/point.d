module geo.point;

import geo.scalar : isGeoScalar;
import geo.vector : Vector2;

import mathTraits = std.math.traits;
import std.traits : isFloatingPoint;
import std.meta : AliasSeq;

/**
 * A position in a two-dimensional Euclidean affine space.
 */
struct Point2(T)
if (isGeoScalar!T)
{
private:
    // D floating-point fields default to NaN. geo-d defines
    // Point2.init explicitly as the origin.
    T _x = 0;
    T _y = 0;

public:
    /**
     * Constructs a point from its coordinates.
     */
    this(T x, T y) pure nothrow @safe @nogc
    {
        _x = x;
        _y = y;
    }

    /// X coordinate.
    @property T x() const pure nothrow @safe @nogc
    {
        return _x;
    }

    /// Y coordinate.
    @property T y() const pure nothrow @safe @nogc
    {
        return _y;
    }

    /**
     * Returns true when both coordinates are finite.
     *
     * Integral points are always finite.
     */
    @property bool isFinite() const pure nothrow @safe @nogc
    {
        static if (isFloatingPoint!T)
            return mathTraits.isFinite(_x)
                && mathTraits.isFinite(_y);
        else
            return true;
    }

    /// Translates this point by a vector.
    Point2 opBinary(string op : "+")(Vector2!T rhs)
        const pure nothrow @safe @nogc
    {
        return Point2(
            _x + rhs.x,
            _y + rhs.y
        );
    }

    /// Supports Vector + Point.
    Point2 opBinaryRight(string op : "+")(Vector2!T lhs)
        const pure nothrow @safe @nogc
    {
        return Point2(
            lhs.x + _x,
            lhs.y + _y
        );
    }

    /// Translates this point by the inverse of a vector.
    Point2 opBinary(string op : "-")(Vector2!T rhs)
        const pure nothrow @safe @nogc
    {
        return Point2(
            _x - rhs.x,
            _y - rhs.y
        );
    }

    /// Difference between two points.
    Vector2!T opBinary(string op : "-")(Point2 rhs)
        const pure nothrow @safe @nogc
    {
        return Vector2!T(
            _x - rhs._x,
            _y - rhs._y
        );
    }

    /// Compound point translation.
    void opOpAssign(string op : "+")(Vector2!T rhs)
        pure nothrow @safe @nogc
    {
        _x += rhs.x;
        _y += rhs.y;
    }

    /// Compound inverse point translation.
    void opOpAssign(string op : "-")(Vector2!T rhs)
        pure nothrow @safe @nogc
    {
        _x -= rhs.x;
        _y -= rhs.y;
    }
}

@safe unittest
{
    static foreach (T; AliasSeq!(int, long, float, double, real))
    {
        static assert(Point2!T.init.x == T(0));
        static assert(Point2!T.init.y == T(0));
        static assert(Point2!T.init == Point2!T(T(0), T(0)));
    }

    alias P = Point2!double;
    alias V = Vector2!double;

    static assert(P.init.x == 0.0);
    static assert(P.init.y == 0.0);

    auto p = P(1.0, 2.0);
    auto q = P(4.0, 6.0);
    auto v = V(3.0, 4.0);

    assert(p.x == 1.0);
    assert(p.y == 2.0);

    assert(p + v == q);
    assert(v + p == q);
    assert(q - v == p);
    assert(q - p == v);

    auto r = p;
    r += v;
    assert(r == q);

    r -= v;
    assert(r == p);

    /*
     * Forbidden affine algebra is part of the API contract.
     */
    static assert(!__traits(compiles, p + q));
    static assert(!__traits(compiles, -p));
    static assert(!__traits(compiles, p * 2.0));
    static assert(!__traits(compiles, 2.0 * p));
    static assert(!__traits(compiles, p / 2.0));

    /*
     * Mixed geometry scalar types are deliberately unavailable.
     */
    Point2!int ip;
    Vector2!double dv;

    static assert(!__traits(compiles, ip + dv));

    assert(Point2!int.init.isFinite);
    assert(Point2!double.init.isFinite);

    auto nanPoint = P(double.nan, 0.0);
    assert(!nanPoint.isFinite);

    auto infinitePoint = P(double.infinity, 0.0);
    assert(!infinitePoint.isFinite);
}
