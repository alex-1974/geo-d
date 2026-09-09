module geo.vector;

import geo.scalar : isGeoScalar;

import mathTraits = std.math.traits;
import std.traits : isFloatingPoint;
import std.meta : AliasSeq;

/**
 * A displacement in a two-dimensional Euclidean vector space.
 */
struct Vector2(T)
if (isGeoScalar!T)
{
private:
    // D floating-point fields default to NaN. geo-d defines
    // Vector2.init explicitly as the zero vector.
    T _x = 0;
    T _y = 0;

public:
    /**
     * Constructs a vector from its components.
     */
    this(T x, T y) pure nothrow @safe @nogc
    {
        _x = x;
        _y = y;
    }

    /// X component.
    @property T x() const pure nothrow @safe @nogc
    {
        return _x;
    }

    /// Y component.
    @property T y() const pure nothrow @safe @nogc
    {
        return _y;
    }

    /**
     * Returns true when both components are finite.
     *
     * Integral vectors are always finite.
     */
    @property bool isFinite() const pure nothrow @safe @nogc
    {
        static if (isFloatingPoint!T)
            return mathTraits.isFinite(_x)
                && mathTraits.isFinite(_y);
        else
            return true;
    }

    /// Vector addition.
    Vector2 opBinary(string op : "+")(Vector2 rhs)
        const pure nothrow @safe @nogc
    {
        return Vector2(_x + rhs._x, _y + rhs._y);
    }

    /// Vector subtraction.
    Vector2 opBinary(string op : "-")(Vector2 rhs)
        const pure nothrow @safe @nogc
    {
        return Vector2(_x - rhs._x, _y - rhs._y);
    }

    /// Vector negation.
    Vector2 opUnary(string op : "-")()
        const pure nothrow @safe @nogc
    {
        return Vector2(-_x, -_y);
    }

    /**
     * Scales this vector.
     *
     * The arithmetic result scalar becomes the result vector scalar.
     */
    auto opBinary(string op : "*", S)(S rhs)
        const pure nothrow @safe @nogc
    if (
        isGeoScalar!S
        && isGeoScalar!(typeof(T.init * S.init))
    )
    {
        alias R = typeof(T.init * S.init);

        return Vector2!R(
            _x * rhs,
            _y * rhs
        );
    }

    /**
     * Scales this vector with the scalar on the left.
     */
    auto opBinaryRight(string op : "*", S)(S lhs)
        const pure nothrow @safe @nogc
    if (
        isGeoScalar!S
        && isGeoScalar!(typeof(S.init * T.init))
    )
    {
        alias R = typeof(S.init * T.init);

        return Vector2!R(
            lhs * _x,
            lhs * _y
        );
    }

    /**
     * Divides this vector by a scalar.
     *
     * Integer-result division is deliberately unavailable.
     */
    auto opBinary(string op : "/", S)(S rhs)
        const pure nothrow @safe @nogc
    if (
        isGeoScalar!S
        && isFloatingPoint!(typeof(T.init / S.init))
    )
    {
        alias R = typeof(T.init / S.init);

        return Vector2!R(
            _x / rhs,
            _y / rhs
        );
    }

    /// Compound vector addition.
    void opOpAssign(string op : "+")(Vector2 rhs)
        pure nothrow @safe @nogc
    {
        _x += rhs._x;
        _y += rhs._y;
    }

    /// Compound vector subtraction.
    void opOpAssign(string op : "-")(Vector2 rhs)
        pure nothrow @safe @nogc
    {
        _x -= rhs._x;
        _y -= rhs._y;
    }

    /**
     * Compound scalar multiplication.
     *
     * Available only when the result scalar remains T.
     */
    void opOpAssign(string op : "*", S)(S rhs)
        pure nothrow @safe @nogc
    if (
        isGeoScalar!S
        && is(typeof(T.init * S.init) == T)
    )
    {
        _x *= rhs;
        _y *= rhs;
    }

    /**
     * Compound scalar division.
     *
     * Available only for floating-point vectors and when the result
     * scalar remains T.
     */
    void opOpAssign(string op : "/", S)(S rhs)
        pure nothrow @safe @nogc
    if (
        isGeoScalar!S
        && isFloatingPoint!T
        && is(typeof(T.init / S.init) == T)
    )
    {
        _x /= rhs;
        _y /= rhs;
    }
}

@safe unittest
{
    static foreach (T; AliasSeq!(int, long, float, double, real))
    {
        static assert(Vector2!T.init.x == T(0));
        static assert(Vector2!T.init.y == T(0));
        static assert(Vector2!T.init == Vector2!T(T(0), T(0)));
    }

    alias V = Vector2!double;

    static assert(V.init.x == 0.0);
    static assert(V.init.y == 0.0);

    auto a = V(1.0, 2.0);
    auto b = V(3.0, 4.0);

    assert(a.x == 1.0);
    assert(a.y == 2.0);

    assert(a + b == V(4.0, 6.0));
    assert(b - a == V(2.0, 2.0));
    assert(-a == V(-1.0, -2.0));

    assert(a * 2.0 == V(2.0, 4.0));
    assert(2.0 * a == V(2.0, 4.0));
    assert(a / 2.0 == V(0.5, 1.0));

    auto c = a;
    c += b;
    assert(c == V(4.0, 6.0));

    c -= b;
    assert(c == a);

    c *= 2;
    assert(c == V(2.0, 4.0));

    c /= 2;
    assert(c == a);

    static assert(is(typeof(Vector2!int(2, 4) * 0.5) == Vector2!double));
    static assert(is(typeof(Vector2!double(2, 4) * 2) == Vector2!double));

    Vector2!int iv;

    static assert(!__traits(compiles, iv / 2));
    static assert(__traits(compiles, iv / 2.0));

    assert(Vector2!int.init.isFinite);
    assert(Vector2!double.init.isFinite);

    auto nanVector = V(double.nan, 0.0);
    assert(!nanVector.isFinite);

    auto infiniteVector = V(double.infinity, 0.0);
    assert(!infiniteVector.isFinite);
}
