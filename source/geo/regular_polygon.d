/**
 * Analytic regular polygons with compile-time cardinality.
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
 *     November 7, 2026
 */
module geo.regular_polygon;

import geo.bounds : Bounds2;
import geo.anchor_binding : AnchorBinding2, tryResolve;
import geo.metric : MetricScalar;
import geo.measure : Angle, Length;
import geo.placement : EdgeAngle2, Placement2;
import geo.point : Point2;
import geo.polygon : Polygon2;
import geo.scalar : isGeoScalar;
import geo.shape_result : ShapeConstructionResult, ShapeConstructionStatus;

import mathTraits = std.math.traits;
import std.math.constants : PI;
import std.math.trigonometry : cos, sin;
import std.traits : isFloatingPoint;


private bool finiteValue(T)(T value)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    static if (isFloatingPoint!T)
        return mathTraits.isFinite(value);
    else
        return true;
}


/**
 * An analytic regular polygon with a compile-time number of vertices.
 *
 * `RegularPolygon2!(T, N)` is distinct from `Polygon2View`, which represents
 * an arbitrary polygon backed by caller-owned variable-size storage. This
 * type stores only centre, circumradius and rotation; vertices are generated
 * explicitly when requested.
 *
 * Vertices are emitted counter-clockwise, starting at `rotation`, and do not
 * repeat the first point at the end. `N` must be at least three.
 */
struct RegularPolygon2(T, size_t N)
if (isGeoScalar!T)
{
    static assert(N >= 3,
        "RegularPolygon2 requires at least three vertices");

private:
    Point2!T _center;
    T _radius;
    MetricScalar!T _rotation;
    bool _hasValue;

    alias R = MetricScalar!T;

    Point2!R vertex(size_t index) const
        pure nothrow @safe @nogc
    {
        const R angle = _rotation + R(2 * PI) * R(index) / R(N);
        const R radius = R(_radius);
        return Point2!R(
            R(_center.x) + radius * cos(angle),
            R(_center.y) + radius * sin(angle)
        );
    }

public:
    static ShapeConstructionResult!(RegularPolygon2) fromCircumradius(
        Length!T radius)
        pure nothrow @safe @nogc
    {
        RegularPolygon2 result;
        if (radius.value <= 0)
            return ShapeConstructionResult!(RegularPolygon2).failure(
                ShapeConstructionStatus.nonPositive);
        return tryFromCircumradius(radius, result)
            ? ShapeConstructionResult!(RegularPolygon2).success(result)
            : ShapeConstructionResult!(RegularPolygon2).failure(
                ShapeConstructionStatus.inconsistent);
    }

    /// True when construction succeeded.
    @property bool valid() const pure nothrow @safe @nogc
    {
        return _hasValue;
    }

    /// Centre of the regular polygon.
    @property Point2!T center() const pure nothrow @safe @nogc
    {
        assert(_hasValue, "RegularPolygon2.center is undefined");
        return _center;
    }

    /// Circumradius of the regular polygon.
    @property T radius() const pure nothrow @safe @nogc
    {
        assert(_hasValue, "RegularPolygon2.radius is undefined");
        return _radius;
    }

    /// Starting angle in radians, measured counter-clockwise from +x.
    @property R rotation() const pure nothrow @safe @nogc
    {
        assert(_hasValue, "RegularPolygon2.rotation is undefined");
        return _rotation;
    }

    /**
     * Constructs a regular polygon from centre, circumradius and rotation.
     *
     * The rotation is in radians. All inputs must be finite and the radius
     * must be non-negative. The output is reset on failure.
     */
    static bool tryFromCenterRadius(
        Point2!T center,
        T radius,
        R rotation,
        out RegularPolygon2 result
    ) pure nothrow @safe @nogc
    {
        result = RegularPolygon2.init;
        if (!center.isFinite || !finiteValue(radius) || radius < T(0) ||
            !finiteValue(rotation))
            return false;

        result._center = center;
        result._radius = radius;
        result._rotation = rotation;
        result._hasValue = true;
        return true;
    }

    /** Construct a local, unplaced regular polygon from its circumradius. */
    static bool tryFromCircumradius(
        Length!T radius,
        out RegularPolygon2 result
    ) pure nothrow @safe @nogc
    {
        return tryFromCenterRadius(
            Point2!T.init,
            radius.value,
            R(0),
            result
        );
    }

    /// Number of vertices, available at compile time.
    @property size_t vertexCount() const pure nothrow @safe @nogc
    {
        return N;
    }

    /// Side length in the metric computation scalar.
    R sideLength() const pure nothrow @safe @nogc
    {
        assert(_hasValue);
        return R(2) * R(_radius) * sin(R(PI) / R(N));
    }

    /// Perimeter in the metric computation scalar.
    R perimeter() const pure nothrow @safe @nogc
    {
        assert(_hasValue);
        return R(N) * sideLength();
    }

    /// Area in the metric computation scalar.
    R area() const pure nothrow @safe @nogc
    {
        assert(_hasValue);
        const R radius = R(_radius);
        return R(N) * radius * radius * sin(R(2 * PI) / R(N)) / R(2);
    }

    /**
     * Writes the N vertices into caller-owned storage.
     *
     * The first N elements are written only after capacity has been checked;
     * failure leaves the destination unchanged.
     */
    bool tryPointsInto(scope Point2!R[] destination) const
        pure nothrow @safe @nogc
    {
        if (!_hasValue || destination.length < N)
            return false;

        foreach (i; 0 .. N)
            destination[i] = vertex(i);
        return true;
    }

    EdgeAngle2!T edge(size_t startVertex, Angle!T angle) const
        pure nothrow @safe @nogc
    {
        assert(_hasValue);
        assert(startVertex >= 1 && startVertex <= N);
        const size_t endVertex = startVertex == N ? 1 : startVertex + 1;
        return EdgeAngle2!T(
            startVertex, endVertex,
            Length!T(cast(T) sideLength()), angle);
    }

    Polygon2!R toPolygon(Placement2!T placement) const
        pure @safe
    {
        if (!_hasValue)
            return Polygon2!R.init;
        Point2!R[N] points;
        if (!tryPointsInto(points[]))
            return Polygon2!R.init;
        Point2!R[N] mapped;
        foreach (i, point; points[])
            mapped[i] = placement.map(Point2!T(cast(T) point.x, cast(T) point.y));
        return Polygon2!R(mapped[]);
    }

    Polygon2!R toPolygon(AnchorBinding2!T binding) const
        pure @safe
    {
        Placement2!T placement;
        return tryResolve(binding, placement) ? toPolygon(placement)
            : Polygon2!R.init;
    }

    Polygon2!R toPolygon(AnchorBinding2!T first,
                          AnchorBinding2!T second) const
        pure @safe
    {
        Placement2!T placement;
        return tryResolve(first, second, placement) ? toPolygon(placement)
            : Polygon2!R.init;
    }

    /// Computes the finite axis-aligned bounds of the generated vertices.
    bool tryBounds(out Bounds2!R result) const
        pure nothrow @safe @nogc
    {
        result = Bounds2!R.init;
        if (!_hasValue)
            return false;

        Point2!R[N] points;
        foreach (i; 0 .. N)
            points[i] = vertex(i);

        foreach (point; points[])
        {
            if (!point.isFinite || !result.tryExtend(point))
            {
                result = Bounds2!R.init;
                return false;
            }
        }
        return true;
    }
}


/// Common regular-polygon shape aliases.
alias Pentagon2(T) = RegularPolygon2!(T, 5);
alias Hexagon2(T) = RegularPolygon2!(T, 6);
alias Heptagon2(T) = RegularPolygon2!(T, 7);
alias Octagon2(T) = RegularPolygon2!(T, 8);


@safe unittest
{
    import geo;

    alias P = Point2!double;
    alias Pentagon = RegularPolygon2!(double, 5);

    Pentagon shape;
    assert(Pentagon.tryFromCenterRadius(P(2, 3), 4, 0, shape));
    assert(shape.valid);
    assert(shape.vertexCount == 5);
    assert(shape.center == P(2, 3));
    assert(shape.radius == 4);
    assert(shape.perimeter > 23.5 && shape.perimeter < 23.6);
    assert(shape.area > 38.0 && shape.area < 38.1);

    P[5] points;
    assert(shape.tryPointsInto(points[]));
    assert(points[0] == P(6, 3));
    assert(points[1].y > 3);

    Bounds2!double bounds;
    assert(shape.tryBounds(bounds));
    assert(bounds.contains(P(6, 3)));
}


@safe unittest
{
    import geo;
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(int, long, float, double, real))
    {
        RegularPolygon2!(T, 6) shape;
        assert(RegularPolygon2!(T, 6).tryFromCenterRadius(
            Point2!T(T(0), T(0)), T(1), MetricScalar!T(0), shape));
        assert(shape.valid);
    }
}
