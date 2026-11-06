/**
 * Analytic two-dimensional circles.
 *
 * Authors:
 *     Alexander Bernardi
 *
 * Copyright:
 *     Copyright © 2026 Alexander Bernardi
 *
 * License:
 *     MIT
 */
module geo.circle;

import geo.bounds : Bounds2;
import geo.metric : MetricScalar;
import geo.point : Point2;
import geo.scalar : isGeoScalar;

import mathTraits = std.math.traits;
import std.traits : isFloatingPoint, Unqual;


private bool isFiniteScalar(T)(T value)
    pure nothrow @safe @nogc
if (isGeoScalar!(Unqual!T))
{
    static if (isFloatingPoint!(Unqual!T))
        return mathTraits.isFinite(value);
    else
        return true;
}


/**
 * A circle represented by its centre and non-negative radius.
 *
 * `Circle2` is an analytic value type. It does not store a polygonal
 * approximation. Construction rejects NaN and non-finite values and accepts a
 * zero radius as a degenerate point circle.
 *
 * Direct metric operations use `MetricScalar!T`, matching the existing geo-d
 * metric computation policy. No tolerance is applied by containment.
 */
struct Circle2(T)
if (isGeoScalar!T)
{
private:
    Point2!T _center;
    T _radius;
    bool _hasValue;

public:
    /// True when this circle was successfully constructed.
    @property bool valid() const
        pure nothrow @safe @nogc
    {
        return _hasValue;
    }

    /**
     * Centre of the circle.
     *
     * Precondition: `valid` is true.
     */
    @property Point2!T center() const
        pure nothrow @safe @nogc
    {
        assert(_hasValue, "Circle2.center is undefined for an invalid circle");
        return _center;
    }

    /**
     * Non-negative radius of the circle.
     *
     * Precondition: `valid` is true.
     */
    @property T radius() const
        pure nothrow @safe @nogc
    {
        assert(_hasValue, "Circle2.radius is undefined for an invalid circle");
        return _radius;
    }

    /// True when the stored centre and radius are finite.
    @property bool isFinite() const
        pure nothrow @safe @nogc
    {
        return _hasValue && _center.isFinite && isFiniteScalar(_radius);
    }

    /**
     * Construct a circle from a centre and radius.
     *
     * Returns false for a non-finite centre or radius, or for a negative
     * radius. On failure `result` is reset to its invalid state.
     */
    static bool tryFromCenterRadius(
        Point2!T centre,
        T radius,
        out Circle2 result
    )
        pure nothrow @safe @nogc
    {
        result = Circle2.init;

        if (!centre.isFinite || !isFiniteScalar(radius) || radius < T(0))
            return false;

        result._center = centre;
        result._radius = radius;
        result._hasValue = true;
        return true;
    }

    /**
     * True when p lies in the closed disk bounded by this circle.
     *
     * Invalid circles and non-finite points contain no point. Boundary points
     * are included. The comparison is exact in the metric computation scalar;
     * no epsilon is used.
     */
    bool contains(Point2!T p) const
        pure nothrow @safe @nogc
    {
        if (!_hasValue || !p.isFinite)
            return false;

        alias R = MetricScalar!T;
        const R dx = R(p.x) - R(_center.x);
        const R dy = R(p.y) - R(_center.y);
        const R rr = R(_radius);
        const R distanceSquared = dx * dx + dy * dy;
        const R radiusSquared = rr * rr;

        if (!mathTraits.isFinite(distanceSquared) || !mathTraits.isFinite(radiusSquared))
            return false;

        return distanceSquared <= radiusSquared;
    }

    /**
     * Compute the closed axis-aligned bounds of this circle.
     *
     * Returns false when the derived bounds cannot be represented finitely in
     * the storage scalar. On failure `result` is empty.
     */
    bool tryBounds(out Bounds2!T result) const
        pure nothrow @safe @nogc
    {
        result = Bounds2!T.init;

        if (!_hasValue)
            return false;

        const T minX = _center.x - _radius;
        const T minY = _center.y - _radius;
        const T maxX = _center.x + _radius;
        const T maxY = _center.y + _radius;

        if (!isFiniteScalar(minX) || !isFiniteScalar(minY) ||
            !isFiniteScalar(maxX) || !isFiniteScalar(maxY))
            return false;

        return Bounds2!T.tryFromMinMax(
            Point2!T(minX, minY),
            Point2!T(maxX, maxY),
            result
        );
    }

    /// Diameter in the metric computation scalar.
    MetricScalar!T diameter() const
        pure nothrow @safe @nogc
    {
        assert(_hasValue, "Circle2.diameter is undefined for an invalid circle");
        return MetricScalar!T(_radius) * 2;
    }

    /// Area in the metric computation scalar.
    MetricScalar!T area() const
        pure nothrow @safe @nogc
    {
        import std.math.constants : PI;

        assert(_hasValue, "Circle2.area is undefined for an invalid circle");
        const auto r = MetricScalar!T(_radius);
        return MetricScalar!T(PI) * r * r;
    }

    /// Circumference in the metric computation scalar.
    MetricScalar!T circumference() const
        pure nothrow @safe @nogc
    {
        import std.math.constants : PI;

        assert(_hasValue, "Circle2.circumference is undefined for an invalid circle");
        return MetricScalar!T(PI) * diameter();
    }
}


/// Basic construction, invariant, bounds and closed-containment coverage.
@safe unittest
{
    import geo;

    alias C = Circle2!double;
    alias P = Point2!double;
    alias B = Bounds2!double;

    C circle;
    assert(C.tryFromCenterRadius(P(2.0, 3.0), 2.0, circle));
    assert(circle.valid);
    assert(circle.isFinite);
    assert(circle.center == P(2.0, 3.0));
    assert(circle.radius == 2.0);
    assert(circle.diameter == 4.0);
    assert(circle.contains(P(2.0, 3.0)));
    assert(circle.contains(P(4.0, 3.0)));
    assert(!circle.contains(P(4.1, 3.0)));

    B bounds;
    assert(circle.tryBounds(bounds));
    assert(bounds.min == P(0.0, 1.0));
    assert(bounds.max == P(4.0, 5.0));
}


/// Invalid and degenerate construction coverage.
@safe unittest
{
    import geo;

    alias C = Circle2!double;
    alias P = Point2!double;

    C circle;
    assert(!C.tryFromCenterRadius(P(0.0, 0.0), -1.0, circle));
    assert(!circle.valid);
    assert(!C.tryFromCenterRadius(P(double.nan, 0.0), 1.0, circle));
    assert(!C.tryFromCenterRadius(P(0.0, 0.0), double.infinity, circle));

    assert(C.tryFromCenterRadius(P(1.0, 2.0), 0.0, circle));
    assert(circle.contains(P(1.0, 2.0)));
    assert(!circle.contains(P(1.0, 2.1)));
}


/// Circle2 participates in the established scalar domain.
@safe unittest
{
    import geo;
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(int, long, float, double, real))
    {
        alias C = Circle2!T;
        alias P = Point2!T;

        C circle;
        assert(C.tryFromCenterRadius(P(T(0), T(0)), T(1), circle));
        assert(circle.valid);
        assert(circle.contains(P(T(0), T(0))));
        assert(circle.diameter == MetricScalar!T(2));
    }
}
