/**
 * Two-dimensional closed line-segment primitives.
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
 *     September 12, 2026
 */
module geo.segment;

import geo.point : Point2;
import geo.scalar : isGeoScalar;


/**
 * A line segment between two points in a two-dimensional Euclidean space.
 *
 * Supported scalar types are `int`, `long`, `float`, `double`, and `real`.
 *
 * `Segment2.init` is the degenerate segment from the origin to the origin.
 *
 * Endpoint order is part of the stored value representation, but does not
 * imply traversal direction. Reversing the endpoints therefore produces a
 * different value unless both endpoints are equal.
 *
 * Degenerate segments with equal endpoints are valid.
 *
 * Equality is exact endpoint equality according to the equality semantics
 * of `Point2!T`; no tolerance or epsilon is applied.
 *
 * Floating-point endpoints may contain non-finite coordinates. `isFinite`
 * reports whether both endpoints contain only finite coordinates.
 */
struct Segment2(T)
if (isGeoScalar!T)
{
private:
    Point2!T _a;
    Point2!T _b;

public:
    /**
     * Constructs a segment from its endpoints.
     */
    this(Point2!T a, Point2!T b)
        pure nothrow @safe @nogc
    {
        _a = a;
        _b = b;
    }


    /// First stored endpoint.
    @property Point2!T a() const
        pure nothrow @safe @nogc
    {
        return _a;
    }


    /// Second stored endpoint.
    @property Point2!T b() const
        pure nothrow @safe @nogc
    {
        return _b;
    }


    /**
     * True when both endpoints contain only finite coordinates.
     */
    @property bool isFinite() const
        pure nothrow @safe @nogc
    {
        return _a.isFinite && _b.isFinite;
    }
}


@safe unittest
{
    import std.meta : AliasSeq;

    /*
     * Segment2.init is the degenerate origin segment for every
     * supported scalar.
     */
    static foreach (T; AliasSeq!(int, long, float, double, real))
    {
        static assert(Segment2!T.init.a == Point2!T.init);
        static assert(Segment2!T.init.b == Point2!T.init);
        static assert(Segment2!T.init.isFinite);
    }


    /*
     * Unsupported scalar types must not instantiate Segment2.
     */
    static assert(!__traits(compiles, Segment2!byte));
    static assert(!__traits(compiles, Segment2!short));
    static assert(!__traits(compiles, Segment2!uint));
    static assert(!__traits(compiles, Segment2!ulong));


    alias P = Point2!double;
    alias S = Segment2!double;

    auto p = P(1.0, 2.0);
    auto q = P(4.0, 6.0);

    auto segment = S(p, q);

    assert(segment.a == p);
    assert(segment.b == q);
    assert(segment.isFinite);


    /*
     * Degenerate segments are valid values.
     */
    auto degenerate = S(p, p);

    assert(degenerate.a == p);
    assert(degenerate.b == p);
    assert(degenerate.isFinite);


    /*
     * Equality is exact stored-value equality.
     *
     * Reversing endpoints does not produce the same stored value.
     */
    assert(segment == S(p, q));
    assert(segment != S(q, p));


    /*
     * Non-finite endpoints remain representable.
     */
    auto infinite = S(
        P(double.infinity, 0.0),
        P(1.0, 2.0)
    );

    assert(!infinite.isFinite);

    auto nanSegment = S(
        P(double.nan, 0.0),
        P(1.0, 2.0)
    );

    assert(!nanSegment.isFinite);
    assert(nanSegment != nanSegment);
}
