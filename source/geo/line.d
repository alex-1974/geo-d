/**
 * Two-dimensional unbounded Euclidean line primitives.
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
 *     September 26, 2026
 */
module geo.line;

import geo.internal.dyadic :
    SignedDyadicDifference,
    decodeDyadicCoordinate,
    subtractDyadicCoordinates;

import geo.internal.scaled_metric :
    ScaledMetricComponent,
    scaledMetricDifference,
    scaledMetricValue;

import geo.point : Point2;
import geo.scalar : isGeoScalar;
import geo.vector : Vector2;


/*
 * Private storage discriminator.
 *
 * The caller-supplied construction form is retained because neither
 * point/point nor point/direction storage can represent the other form
 * losslessly over the complete supported scalar domain.
 */
private enum Line2StorageForm : ubyte
{
    points,
    pointDirection,
}


/*
 * Scalar domain supported by the exact dyadic line backend.
 *
 * `real` remains a valid Line2 storage scalar but is deliberately excluded
 * from robust exact topology.
 */
private enum bool isExactLineScalar(T) =
       is(T == int)
    || is(T == long)
    || is(T == float)
    || is(T == double);


/**
 * An unbounded line in two-dimensional Euclidean space.
 *
 * Supported scalar types are `int`, `long`, `float`, `double`, and `real`.
 *
 * A line can be constructed either from two points or from one point and a
 * direction vector. Both construction forms are direct and infallible; they
 * preserve the supplied scalar values without converting one representation
 * into the other.
 *
 * `Line2.init` is finite and degenerate.
 *
 * Degeneracy is exact:
 *
 * - a point/point line is degenerate when both stored points are equal;
 * - a point/direction line is degenerate when both direction components are
 *   zero.
 *
 * No epsilon or tolerance is used.
 *
 * Ordinary `==` and `!=` are deliberately unavailable. Stored representation
 * equality does not express geometric line identity; geometric coincidence is
 * classified by the line-intersection API.
 *
 * The retained point/point versus point/direction storage form is private.
 * `Line2` exposes no representation-dependent point, direction, or storage-tag
 * accessor.
 */
struct Line2(T)
if (isGeoScalar!T)
{
private:
    /*
     * The first union member deliberately makes Payload.init a second origin
     * point. Together with the default `points` tag this gives Line2.init its
     * finite, degenerate semantics.
     */
    union Payload
    {
        Point2!T secondPoint;
        Vector2!T direction;
    }

    Point2!T _point;
    Payload _payload;
    Line2StorageForm _form = Line2StorageForm.points;

public:
    /**
     * Constructs an unbounded line from two points.
     *
     * The supplied point/point representation is stored directly.
     */
    this(
        Point2!T a,
        Point2!T b
    )
        pure nothrow @safe @nogc
    {
        _point = a;
        _payload.secondPoint = b;
        _form = Line2StorageForm.points;
    }


    /**
     * Constructs an unbounded line from a point and direction vector.
     *
     * The supplied point/direction representation is stored directly.
     */
    this(
        Point2!T point,
        Vector2!T direction
    )
        pure nothrow @safe @nogc
    {
        _point = point;
        _payload.direction = direction;
        _form = Line2StorageForm.pointDirection;
    }


    /**
     * True when every scalar stored by the selected representation is finite.
     *
     * Integral lines are therefore always finite.
     */
    @property bool isFinite() const
        pure nothrow @safe @nogc
    {
        final switch (_form)
        {
        case Line2StorageForm.points:
            return
                _point.isFinite &&
                _payload.secondPoint.isFinite;

        case Line2StorageForm.pointDirection:
            return
                _point.isFinite &&
                _payload.direction.isFinite;
        }
    }


    /**
     * True when this stored representation does not define a usable
     * unbounded line.
     *
     * The test is exact and representation-aware. No point difference or
     * point-plus-direction value is materialised.
     */
    @property bool isDegenerate() const
        pure nothrow @safe @nogc
    {
        final switch (_form)
        {
        case Line2StorageForm.points:
            return
                _point.x == _payload.secondPoint.x &&
                _point.y == _payload.secondPoint.y;

        case Line2StorageForm.pointDirection:
            return
                _payload.direction.x == T(0) &&
                _payload.direction.y == T(0);
        }
    }


    /*
     * Representation equality is not geometric line equality.
     *
     * Explicitly disabling opEquals prevents D from generating struct equality
     * for the private tagged representation.
     */
    @disable bool opEquals(ref const Line2 rhs) const;
}


/*
 * Exact scalar difference used by the package-internal line bridge.
 *
 * No ordinary signed subtraction or floating-point arithmetic participates.
 */
private SignedDyadicDifference exactLineScalarDifference(T)(
    T lhs,
    T rhs
)
    pure nothrow @safe @nogc
if (isExactLineScalar!T)
{
    const auto left =
        decodeDyadicCoordinate(lhs);

    const auto right =
        decodeDyadicCoordinate(rhs);

    return subtractDyadicCoordinates(
        left,
        right
    );
}


/*
 * Package-internal reference-point access.
 *
 * This is deliberately not public API. It exposes neither the retained
 * PP/PV storage tag nor a representation-dependent public accessor.
 */
package(geo) void lineReferencePointComponents(T)(
    ref const Line2!T line,
    out T x,
    out T y
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    x = line._point.x;
    y = line._point.y;
}


/*
 * Derives the exact mathematical direction without canonicalising the stored
 * Line2 into the other source representation.
 *
 * For PP storage:
 *
 *     secondPoint - point
 *
 * For PV storage:
 *
 *     direction - zero
 *
 * The represented line must be finite because the dyadic decoder accepts
 * finite floating-point coordinates only.
 */
package(geo) void lineExactDirection(T)(
    ref const Line2!T line,
    out SignedDyadicDifference x,
    out SignedDyadicDifference y
)
    pure nothrow @safe @nogc
if (isExactLineScalar!T)
{
    assert(line.isFinite);

    final switch (line._form)
    {
    case Line2StorageForm.points:
        x =
            exactLineScalarDifference(
                line._payload.secondPoint.x,
                line._point.x
            );

        y =
            exactLineScalarDifference(
                line._payload.secondPoint.y,
                line._point.y
            );

        return;

    case Line2StorageForm.pointDirection:
        x =
            exactLineScalarDifference(
                line._payload.direction.x,
                T(0)
            );

        y =
            exactLineScalarDifference(
                line._payload.direction.y,
                T(0)
            );

        return;
    }
}



/*
 * Derives a numerically scaled direction for the extended-precision `real`
 * metric path without exposing the retained PP/PV storage representation.
 *
 * For PP storage each component is formed as an exponent-aware exact binary
 * subtraction of the two finite stored coordinates.
 *
 * For PV storage each already-stored direction component is normalized
 * directly.
 *
 * This bridge is package-internal and deliberately specialized to `real`;
 * int/long/float/double use the exact dyadic Line2 backend instead.
 */
package(geo) void lineScaledRealDirection(
    ref const Line2!real line,
    out ScaledMetricComponent!real x,
    out ScaledMetricComponent!real y
)
    pure nothrow @safe @nogc
{
    assert(line.isFinite);

    final switch (line._form)
    {
    case Line2StorageForm.points:
        x =
            scaledMetricDifference(
                line._payload.secondPoint.x,
                line._point.x
            );

        y =
            scaledMetricDifference(
                line._payload.secondPoint.y,
                line._point.y
            );

        return;

    case Line2StorageForm.pointDirection:
        x =
            scaledMetricValue(
                line._payload.direction.x
            );

        y =
            scaledMetricValue(
                line._payload.direction.y
            );

        return;
    }
}


/// Example constructing lines through the public package API.
@safe unittest
{
    import geo;

    alias P = Point2!double;
    alias V = Vector2!double;
    alias L = Line2!double;

    auto fromPoints =
        L(
            P(1.0, 2.0),
            P(4.0, 6.0)
        );

    auto fromDirection =
        L(
            P(1.0, 2.0),
            V(3.0, 4.0)
        );

    assert(fromPoints.isFinite);
    assert(!fromPoints.isDegenerate);

    assert(fromDirection.isFinite);
    assert(!fromDirection.isDegenerate);
}


@safe unittest
{
    import std.meta : AliasSeq;

    /*
     * The general geo-d scalar domain is supported.
     *
     * Default construction is deterministic, finite and degenerate.
     */
    static foreach (T; AliasSeq!(int, long, float, double, real))
    {
        static assert(Line2!T.init.isFinite);
        static assert(Line2!T.init.isDegenerate);
    }


    /*
     * Unsupported scalar types remain unavailable.
     */
    static assert(!__traits(compiles, Line2!byte));
    static assert(!__traits(compiles, Line2!short));
    static assert(!__traits(compiles, Line2!uint));
    static assert(!__traits(compiles, Line2!ulong));


    alias P = Point2!double;
    alias V = Vector2!double;
    alias L = Line2!double;


    /*
     * Both accepted constructor forms and their parameter names compile.
     */
    static assert(
        __traits(
            compiles,
            L(
                a: P(0.0, 0.0),
                b: P(1.0, 0.0)
            )
        )
    );

    static assert(
        __traits(
            compiles,
            L(
                point: P(0.0, 0.0),
                direction: V(1.0, 0.0)
            )
        )
    );


    /*
     * Exact degeneracy for point/point storage.
     */
    auto point =
        P(2.0, 3.0);

    auto ppDegenerate =
        L(
            point,
            point
        );

    auto ppValid =
        L(
            point,
            P(3.0, 3.0)
        );

    assert(ppDegenerate.isFinite);
    assert(ppDegenerate.isDegenerate);

    assert(ppValid.isFinite);
    assert(!ppValid.isDegenerate);


    /*
     * Exact degeneracy for point/direction storage.
     */
    auto pvDegenerate =
        L(
            point,
            V(0.0, 0.0)
        );

    auto pvValid =
        L(
            point,
            V(1.0, 0.0)
        );

    assert(pvDegenerate.isFinite);
    assert(pvDegenerate.isDegenerate);

    assert(pvValid.isFinite);
    assert(!pvValid.isDegenerate);


    /*
     * Representation-preservation regression.
     *
     * At 2^53, materialising anchor + (1, 0) in binary64 loses the x
     * increment. A point/direction Line2 must retain the original direction
     * and therefore remain nondegenerate.
     */
    enum double twoTo53 = 0x1p53;

    auto representabilityBoundary =
        L(
            P(twoTo53, 0.0),
            V(1.0, 0.0)
        );

    assert(representabilityBoundary.isFinite);
    assert(!representabilityBoundary.isDegenerate);


    /*
     * Full-range integral point pairs remain directly representable.
     */
    alias LP = Line2!long;
    alias PL = Point2!long;

    auto fullRangePoints =
        LP(
            PL(long.min, 0),
            PL(long.max, 0)
        );

    assert(fullRangePoints.isFinite);
    assert(!fullRangePoints.isDegenerate);


    /*
     * Non-finite stored values remain representable but observable.
     */
    auto nonFinitePP =
        L(
            P(0.0, 0.0),
            P(double.infinity, 0.0)
        );

    auto nonFinitePV =
        L(
            P(0.0, 0.0),
            V(double.nan, 1.0)
        );

    assert(!nonFinitePP.isFinite);
    assert(!nonFinitePV.isFinite);


    /*
     * Ordinary equality is deliberately not part of the Line2 API.
     */
    auto first =
        L(
            P(0.0, 0.0),
            P(1.0, 0.0)
        );

    auto second =
        L(
            P(0.0, 0.0),
            V(1.0, 0.0)
        );

    static assert(!__traits(compiles, first == second));
    static assert(!__traits(compiles, first != second));


    /*
     * The private retained representation has no public accessors.
     */
    static assert(!__traits(compiles, first.anchor));
    static assert(!__traits(compiles, first.secondPoint));
    static assert(!__traits(compiles, first.direction));
    static assert(!__traits(compiles, first.storageForm));
}
