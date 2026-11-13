module geo.transform;

import geo.metric : MetricScalar;
import geo.measure : Angle, Length;
import geo.point : Point2;
import geo.scalar : isGeoScalar;
import std.math.trigonometry : cos, sin;

struct Translation2(T) if (isGeoScalar!T)
{
    Length!T x;
    Length!T y;
}

struct Rotation2(T) if (isGeoScalar!T)
{
    Angle!T angle;

    static Rotation2 fromDegrees(T degrees)
        pure nothrow @safe @nogc
    {
        return Rotation2(Angle!T.fromDegrees(degrees));
    }
}

struct Scale2(T) if (isGeoScalar!T)
{
    T x = 1;
    T y = 1;

    static Scale2 uniform(T factor) pure nothrow @safe @nogc
    { return Scale2(factor, factor); }

    static Scale2 axisX(T factor) pure nothrow @safe @nogc
    { return Scale2(factor, T(1)); }

    static Scale2 axisY(T factor) pure nothrow @safe @nogc
    { return Scale2(T(1), factor); }

    static Scale2 independent(T x, T y) pure nothrow @safe @nogc
    { return Scale2(x, y); }
}

struct Transform2(T) if (isGeoScalar!T)
{
    alias R = MetricScalar!T;
    R a = 1, b = 0, c = 0, d = 1;
    R tx = 0, ty = 0;

    static Transform2 identity() pure nothrow @safe @nogc
    { return Transform2.init; }

    static Transform2 translation(Translation2!T value)
        pure nothrow @safe @nogc
    { auto r = Transform2.init; r.tx = R(value.x.value); r.ty = R(value.y.value); return r; }

    static Transform2 rotation(Rotation2!T value)
        pure nothrow @safe @nogc
    {
        const R co = cos(R(value.angle.radians));
        const R si = sin(R(value.angle.radians));
        return Transform2(co, -si, si, co, 0, 0);
    }

    static Transform2 scale(Scale2!T value)
        pure nothrow @safe @nogc
    { return Transform2(R(value.x), 0, 0, R(value.y), 0, 0); }

    static Transform2 shear(T x, T y)
        pure nothrow @safe @nogc
    { return Transform2(1, R(x), R(y), 1, 0, 0); }

    static Transform2 reflection(bool x, bool y)
        pure nothrow @safe @nogc
    { return Transform2(x ? -1 : 1, 0, 0, y ? -1 : 1, 0, 0); }

    Point2!R apply(Point2!T point) const pure nothrow @safe @nogc
    {
        return Point2!R(
            a * R(point.x) + b * R(point.y) + tx,
            c * R(point.x) + d * R(point.y) + ty
        );
    }

    Transform2 compose(Transform2 other) const
        pure nothrow @safe @nogc
    {
        return Transform2(
            a * other.a + b * other.c,
            a * other.b + b * other.d,
            c * other.a + d * other.c,
            c * other.b + d * other.d,
            a * other.tx + b * other.ty + tx,
            c * other.tx + d * other.ty + ty
        );
    }
}

@safe unittest
{
    import geo;
    alias T = double;
    auto moved = Transform2!T.translation(
        Translation2!T(Length!T(10), Length!T(20)));
    auto rotated = Transform2!T.rotation(
        Rotation2!T.fromDegrees(90));
    auto scaled = Transform2!T.scale(Scale2!T.uniform(2));
    auto result = moved.compose(rotated).compose(scaled).apply(Point2!T(1, 0));
    assert(result.x > 9.9 && result.x < 10.1);
    assert(result.y > 21.9 && result.y < 22.1);

    auto sheared = Transform2!T.shear(1, 0).apply(Point2!T(1, 1));
    assert(sheared == Point2!T(2, 1));
}

