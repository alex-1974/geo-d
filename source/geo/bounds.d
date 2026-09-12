/**
 * Axis-aligned two-dimensional bounds.
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
module geo.bounds;

import geo.point : Point2;
import geo.scalar : isGeoScalar;

import std.traits : isFloatingPoint;


/*
 * True when a scalar is NaN.
 *
 * Integral geo-d scalars cannot be NaN.
 */
private bool isNaNScalar(T)(T value)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    static if (isFloatingPoint!T)
        return value != value;
    else
        return false;
}


/*
 * True when either coordinate is NaN.
 */
private bool hasNaN(T)(Point2!T point)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    return isNaNScalar(point.x)
        || isNaNScalar(point.y);
}


/**
 * A closed axis-aligned bounds in a two-dimensional Euclidean space.
 *
 * Supported scalar types are `int`, `long`, `float`, `double`, and `real`.
 *
 * `Bounds2.init` is empty.
 *
 * Bounds2 has two semantic states:
 *
 * - empty: contains no point;
 * - non-empty: min <= max component-wise.
 *
 * A degenerate bounds with min == max is non-empty.
 *
 * Floating-point non-empty bounds may contain infinities but never NaN.
 */
struct Bounds2(T)
if (isGeoScalar!T)
{
private:
    /*
     * The explicit state is intentional.
     *
     * Point2.init is the origin, while Bounds2.init must be empty.
     * Empty-state representation is not inferred from coordinate
     * sentinels such as NaN or reversed extrema.
     */
    Point2!T _min;
    Point2!T _max;
    bool _hasValue;

public:
    /**
     * True when this bounds contains no point.
     */
    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return !_hasValue;
    }


    /**
     * Minimum corner.
     *
     * Precondition:
     *     This bounds is not empty.
     */
    @property Point2!T min() const
        pure nothrow @safe @nogc
    {
        assert(_hasValue,
            "Bounds2.min is undefined for an empty bounds");

        return _min;
    }


    /**
     * Maximum corner.
     *
     * Precondition:
     *     This bounds is not empty.
     */
    @property Point2!T max() const
        pure nothrow @safe @nogc
    {
        assert(_hasValue,
            "Bounds2.max is undefined for an empty bounds");

        return _max;
    }


    /**
     * True when all represented coordinates are finite.
     *
     * Empty bounds are finite vacuously.
     *
     * Infinite coordinates are valid Bounds2 coordinates, but cause
     * this property to return false.
     */
    @property bool isFinite() const
        pure nothrow @safe @nogc
    {
        if (!_hasValue)
            return true;

        return _min.isFinite && _max.isFinite;
    }


    /**
     * Constructs a degenerate non-empty bounds containing exactly p.
     *
     * Returns false when p contains NaN.
     *
     * On failure, result is Bounds2.init.
     */
    static bool tryFromPoint(
        Point2!T p,
        out Bounds2 result
    )
        pure nothrow @safe @nogc
    {
        if (hasNaN(p))
            return false;

        result._min = p;
        result._max = p;
        result._hasValue = true;

        return true;
    }


    /**
     * Constructs a non-empty bounds from minimum and maximum corners.
     *
     * Returns false when:
     *
     * - either corner contains NaN; or
     * - min is greater than max on any axis.
     *
     * Infinities are permitted when the ordering invariant holds.
     *
     * On failure, result is Bounds2.init.
     */
    static bool tryFromMinMax(
        Point2!T minimum,
        Point2!T maximum,
        out Bounds2 result
    )
        pure nothrow @safe @nogc
    {
        if (hasNaN(minimum) || hasNaN(maximum))
            return false;

        if (minimum.x > maximum.x ||
            minimum.y > maximum.y)
        {
            return false;
        }

        result._min = minimum;
        result._max = maximum;
        result._hasValue = true;

        return true;
    }


    /**
     * Extends this bounds so that it contains p.
     *
     * Returns false when p contains NaN.
     *
     * On failure, this bounds remains unchanged.
     */
    bool tryExtend(Point2!T p)
        pure nothrow @safe @nogc
    {
        if (hasNaN(p))
            return false;

        if (!_hasValue)
        {
            _min = p;
            _max = p;
            _hasValue = true;

            return true;
        }

        const T minX = p.x < _min.x ? p.x : _min.x;
        const T minY = p.y < _min.y ? p.y : _min.y;

        const T maxX = p.x > _max.x ? p.x : _max.x;
        const T maxY = p.y > _max.y ? p.y : _max.y;

        _min = Point2!T(minX, minY);
        _max = Point2!T(maxX, maxY);

        return true;
    }


    /**
     * Extends this bounds so that it contains other.
     *
     * Extending by an empty bounds has no effect.
     */
    void extend(Bounds2 other)
        pure nothrow @safe @nogc
    {
        if (!other._hasValue)
            return;

        if (!_hasValue)
        {
            _min = other._min;
            _max = other._max;
            _hasValue = true;

            return;
        }

        const T minX =
            other._min.x < _min.x ? other._min.x : _min.x;

        const T minY =
            other._min.y < _min.y ? other._min.y : _min.y;

        const T maxX =
            other._max.x > _max.x ? other._max.x : _max.x;

        const T maxY =
            other._max.y > _max.y ? other._max.y : _max.y;

        _min = Point2!T(minX, minY);
        _max = Point2!T(maxX, maxY);
    }


    /**
     * True when this closed bounds contains p.
     *
     * Empty bounds contain no point.
     * A point containing NaN is never contained.
     */
    bool contains(Point2!T p) const
        pure nothrow @safe @nogc
    {
        if (!_hasValue || hasNaN(p))
            return false;

        return p.x >= _min.x
            && p.x <= _max.x
            && p.y >= _min.y
            && p.y <= _max.y;
    }


    /**
     * True when this closed bounds intersects other.
     *
     * Empty bounds never intersect.
     *
     * Touching edges or corners count as intersection.
     */
    bool intersects(Bounds2 other) const
        pure nothrow @safe @nogc
    {
        if (!_hasValue || !other._hasValue)
            return false;

        return !(
               _max.x < other._min.x
            || other._max.x < _min.x
            || _max.y < other._min.y
            || other._max.y < _min.y
        );
    }


    /**
     * Exact bounds equality.
     *
     * All empty Bounds2 values of the same type compare equal
     * independently of their internal representation.
     */
    bool opEquals(const Bounds2 rhs) const
        pure nothrow @safe @nogc
    {
        if (_hasValue != rhs._hasValue)
            return false;

        if (!_hasValue)
            return true;

        return _min == rhs._min
            && _max == rhs._max;
    }
}


@safe unittest
{
    import std.meta : AliasSeq;

    /*
     * Bounds2.init is empty for every supported scalar.
     */
    static foreach (T; AliasSeq!(int, long, float, double, real))
    {
        static assert(Bounds2!T.init.empty);
        static assert(Bounds2!T.init.isFinite);
    }


    alias P = Point2!double;
    alias B = Bounds2!double;


    /*
     * Empty and degenerate bounds are distinct.
     */
    B pointBounds;

    assert(B.tryFromPoint(P(2.0, 3.0), pointBounds));

    assert(!pointBounds.empty);
    assert(pointBounds.min == P(2.0, 3.0));
    assert(pointBounds.max == P(2.0, 3.0));

    assert(pointBounds != B.init);


    /*
     * Ordered min/max construction.
     */
    B bounds;

    assert(B.tryFromMinMax(
        P(1.0, 2.0),
        P(4.0, 6.0),
        bounds
    ));

    assert(!bounds.empty);
    assert(bounds.min == P(1.0, 2.0));
    assert(bounds.max == P(4.0, 6.0));


    /*
     * Reversed axes are rejected.
     */
    B invalid;

    assert(!B.tryFromMinMax(
        P(5.0, 2.0),
        P(4.0, 6.0),
        invalid
    ));

    assert(invalid.empty);


    /*
     * NaN is rejected and must never become an empty-state synonym.
     */
    B nanBounds;

    assert(!B.tryFromPoint(
        P(double.nan, 0.0),
        nanBounds
    ));

    assert(nanBounds.empty);

    assert(!B.tryFromMinMax(
        P(0.0, 0.0),
        P(double.nan, 1.0),
        nanBounds
    ));

    assert(nanBounds.empty);


    /*
     * Infinity is valid when ordering remains meaningful.
     */
    B infiniteBounds;

    assert(B.tryFromMinMax(
        P(-double.infinity, 0.0),
        P(double.infinity, 10.0),
        infiniteBounds
    ));

    assert(!infiniteBounds.empty);
    assert(!infiniteBounds.isFinite);

    assert(infiniteBounds.contains(P(0.0, 5.0)));
    assert(infiniteBounds.contains(
        P(double.infinity, 5.0)
    ));


    /*
     * Incremental extension from empty.
     */
    B accumulated;

    assert(accumulated.tryExtend(P(5.0, 4.0)));

    assert(accumulated.min == P(5.0, 4.0));
    assert(accumulated.max == P(5.0, 4.0));

    assert(accumulated.tryExtend(P(1.0, 7.0)));

    assert(accumulated.min == P(1.0, 4.0));
    assert(accumulated.max == P(5.0, 7.0));


    /*
     * Failed point extension preserves the original value.
     */
    auto before = accumulated;

    assert(!accumulated.tryExtend(
        P(double.nan, 10.0)
    ));

    assert(accumulated == before);


    /*
     * Bounds extension.
     */
    B other;

    assert(B.tryFromMinMax(
        P(-2.0, 5.0),
        P(3.0, 9.0),
        other
    ));

    accumulated.extend(other);

    assert(accumulated.min == P(-2.0, 4.0));
    assert(accumulated.max == P(5.0, 9.0));

    auto unchanged = accumulated;
    unchanged.extend(B.init);

    assert(unchanged == accumulated);


    /*
     * Closed containment semantics.
     */
    assert(!B.init.contains(P(0.0, 0.0)));

    assert(bounds.contains(P(1.0, 2.0)));
    assert(bounds.contains(P(4.0, 6.0)));
    assert(bounds.contains(P(2.0, 3.0)));

    assert(!bounds.contains(P(0.0, 3.0)));
    assert(!bounds.contains(P(double.nan, 3.0)));


    /*
     * Closed intersection semantics.
     */
    B touching;
    B separate;

    assert(B.tryFromMinMax(
        P(4.0, 6.0),
        P(7.0, 8.0),
        touching
    ));

    assert(B.tryFromMinMax(
        P(4.0001, 6.0001),
        P(7.0, 8.0),
        separate
    ));

    assert(bounds.intersects(touching));
    assert(touching.intersects(bounds));

    assert(!bounds.intersects(separate));
    assert(!separate.intersects(bounds));

    assert(!bounds.intersects(B.init));
    assert(!B.init.intersects(bounds));


    /*
     * Equality.
     */
    assert(B.init == B.init);
    assert(bounds == bounds);
    assert(bounds != pointBounds);
}
