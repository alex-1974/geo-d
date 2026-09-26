/**
 * Robust segment and unbounded-line intersection classification and construction.
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
module geo.intersection;

private import euclid_core.intersection :
    CoreSegmentIntersectionKind = SegmentIntersectionKind;

private import euclid_core.scalar :
    CoreIntersectionScalar = IntersectionScalar;

import geo.internal.intersection_exact :
    ExactProperIntersection,
    properIntersectionExactKnownCrossing,
    tryProperIntersectionExact;

import geo.internal.exact_coordinate_round :
    roundExactCoordinateBinary64;

import geo.internal.dyadic :
    SignedDyadicDifference,
    SignedDyadicProduct,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

import geo.line :
    Line2,
    lineExactDirection,
    lineReferencePointComponents;

import geo.orientation :
    Orientation2,
    orientation;

import geo.point :
    Point2;

import geo.segment :
    Segment2;

import geo.vector :
    Vector2;


version (D_Ddoc)
{
    /**
     * Topological classification of the intersection of two closed
     * segments.
     *
     * `point` means that the intersection contains exactly one geometric
     * point.
     *
     * `overlap` means that the intersection contains a segment of positive
     * geometric length.
     */
    enum SegmentIntersectionKind : ubyte
    {
        /// The closed segments are disjoint.
        none,

        /// The intersection contains exactly one geometric point.
        point,

        /// The intersection contains a segment of positive length.
        overlap,
    }

    static assert(
        SegmentIntersectionKind.sizeof ==
        CoreSegmentIntersectionKind.sizeof
    );

    static assert(
        cast(ubyte) SegmentIntersectionKind.none ==
        cast(ubyte) CoreSegmentIntersectionKind.none
    );

    static assert(
        cast(ubyte) SegmentIntersectionKind.point ==
        cast(ubyte) CoreSegmentIntersectionKind.point
    );

    static assert(
        cast(ubyte) SegmentIntersectionKind.overlap ==
        cast(ubyte) CoreSegmentIntersectionKind.overlap
    );
}
else
{
    alias SegmentIntersectionKind =
        CoreSegmentIntersectionKind;
}


/**
 * Topological classification of the intersection of two valid unbounded
 * lines.
 *
 * `none` means the two lines are distinct and parallel.
 *
 * `point` means the two lines contain exactly one common point.
 *
 * `coincident` means both values describe the same unbounded geometric line.
 *
 * Finite, nondegenerate inputs are required. The classification is exact and
 * does not use a tolerance or epsilon.
 */
enum LineIntersectionKind : ubyte
{
    /// The valid lines are distinct and parallel.
    none,

    /// The valid lines contain exactly one common point.
    point,

    /// Both values describe the same unbounded geometric line.
    coincident,
}


/*
 * The public intersection classifier follows the scalar domains for
 * which geo-d currently provides a robust orientation backend.
 */
private enum bool isIntersectionScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


version (D_Ddoc)
{
    /**
     * Scalar used for constructed unique segment-intersection points.
     *
     * Initial geo-d policy:
     *
     *     int     -> double
     *     long    -> double
     *     float   -> double
     *     double  -> double
     *
     * Topological classification remains exact in the input scalar domain.
     * Construction is deliberately a separate, rounded operation.
     */
    template IntersectionScalar(T)
    if (
           is(T == int)
        || is(T == long)
        || is(T == float)
        || is(T == double)
    )
    {
        alias IntersectionScalar = double;
    }

    static assert(
        is(
            IntersectionScalar!int ==
            CoreIntersectionScalar!int
        )
    );

    static assert(
        is(
            IntersectionScalar!long ==
            CoreIntersectionScalar!long
        )
    );

    static assert(
        is(
            IntersectionScalar!float ==
            CoreIntersectionScalar!float
        )
    );

    static assert(
        is(
            IntersectionScalar!double ==
            CoreIntersectionScalar!double
        )
    );

    static assert(
        !__traits(
            compiles,
            IntersectionScalar!real
        )
    );

    static assert(
        !__traits(
            compiles,
            CoreIntersectionScalar!real
        )
    );
}
else
{
    alias IntersectionScalar =
        CoreIntersectionScalar;
}


/// Example inspecting the constructed-intersection scalar policy.
@safe unittest
{
    import geo;

    static assert(is(IntersectionScalar!int == double));
    static assert(is(IntersectionScalar!long == double));
    static assert(is(IntersectionScalar!float == double));
    static assert(is(IntersectionScalar!double == double));

    static assert(
        !__traits(
            compiles,
            IntersectionScalar!real
        )
    );
}


static assert(
    is(IntersectionScalar!int == double)
);

static assert(
    is(IntersectionScalar!long == double)
);

static assert(
    is(IntersectionScalar!float == double)
);

static assert(
    is(IntersectionScalar!double == double)
);


/*
 * Exact two-component direction used by unbounded-line topology.
 */
private struct ExactLineDirection
{
    SignedDyadicDifference x;
    SignedDyadicDifference y;
}


/*
 * Exact scalar difference in the common dyadic coordinate scale.
 */
private SignedDyadicDifference exactLineCoordinateDifference(T)(
    T lhs,
    T rhs
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
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
 * Derives one exact direction through geo.line's package-internal bridge.
 */
private ExactLineDirection exactIntersectionLineDirection(T)(
    ref const Line2!T line
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    ExactLineDirection result;

    lineExactDirection(
        line,
        result.x,
        result.y
    );

    return result;
}


/*
 * Exact displacement from the first line's retained reference point to the
 * second line's retained reference point.
 */
private ExactLineDirection exactLineAnchorOffset(T)(
    ref const Line2!T first,
    ref const Line2!T second
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    T firstX;
    T firstY;
    T secondX;
    T secondY;

    lineReferencePointComponents(
        first,
        firstX,
        firstY
    );

    lineReferencePointComponents(
        second,
        secondX,
        secondY
    );

    ExactLineDirection result;

    result.x =
        exactLineCoordinateDifference(
            secondX,
            firstX
        );

    result.y =
        exactLineCoordinateDifference(
            secondY,
            firstY
        );

    return result;
}


/*
 * Exact two-dimensional determinant:
 *
 *     a.x * b.y - a.y * b.x
 */
private SignedDyadicProduct exactLineCross(
    ref const ExactLineDirection a,
    ref const ExactLineDirection b
)
    pure nothrow @safe @nogc
{
    const auto firstProduct =
        multiplyDyadicDifferences(
            a.x,
            b.y
        );

    const auto secondProduct =
        multiplyDyadicDifferences(
            a.y,
            b.x
        );

    return subtractDyadicProducts(
        firstProduct,
        secondProduct
    );
}


/**
 * Classifies the exact topological relationship of two unbounded lines.
 *
 * Preconditions:
 *
 * - `first` is finite and nondegenerate;
 * - `second` is finite and nondegenerate.
 *
 * The operation is exact over `int`, `long`, `float`, and `double`.
 * `real` is deliberately outside the robust-topology scalar domain.
 *
 * Returns:
 *     `LineIntersectionKind.none` for distinct parallel lines,
 *     `LineIntersectionKind.point` for a unique intersection, and
 *     `LineIntersectionKind.coincident` for the same unbounded line.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
LineIntersectionKind lineIntersectionKind(T)(
    Line2!T first,
    Line2!T second
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    assert(first.isFinite);
    assert(second.isFinite);
    assert(!first.isDegenerate);
    assert(!second.isDegenerate);

    const auto firstDirection =
        exactIntersectionLineDirection(first);

    const auto secondDirection =
        exactIntersectionLineDirection(second);

    const auto directionCross =
        exactLineCross(
            firstDirection,
            secondDirection
        );

    if (directionCross.sign != 0)
        return LineIntersectionKind.point;

    const auto offset =
        exactLineAnchorOffset(
            first,
            second
        );

    const auto offsetCross =
        exactLineCross(
            offset,
            firstDirection
        );

    if (offsetCross.sign == 0)
        return LineIntersectionKind.coincident;

    return LineIntersectionKind.none;
}


/// Example classifying unbounded lines through the public package API.
@safe unittest
{
    import geo;

    alias P = Point2!double;
    alias V = Vector2!double;
    alias L = Line2!double;

    auto horizontal =
        L(
            P(0.0, 0.0),
            P(10.0, 0.0)
        );

    auto vertical =
        L(
            P(5.0, -10.0),
            V(0.0, 20.0)
        );

    assert(
        lineIntersectionKind(
            horizontal,
            vertical
        ) ==
        LineIntersectionKind.point
    );

    assert(
        lineIntersectionKind(
            horizontal,
            L(
                P(0.0, 2.0),
                V(-20.0, 0.0)
            )
        ) ==
        LineIntersectionKind.none
    );

    assert(
        lineIntersectionKind(
            horizontal,
            L(
                P(3.0, 0.0),
                V(-7.0, 0.0)
            )
        ) ==
        LineIntersectionKind.coincident
    );
}


@safe unittest
{
    import std.meta : AliasSeq;

    /*
     * Public classifier scalar domain.
     */
    static foreach (T; AliasSeq!(int, long, float, double))
    {
        {
        alias P = Point2!T;
        alias V = Vector2!T;
        alias L = Line2!T;

        auto horizontalPP =
            L(
                P(T(0), T(0)),
                P(T(10), T(0))
            );

        auto horizontalPV =
            L(
                P(T(0), T(0)),
                V(T(10), T(0))
            );

        auto verticalPP =
            L(
                P(T(5), T(-10)),
                P(T(5), T(10))
            );

        auto verticalPV =
            L(
                P(T(5), T(-10)),
                V(T(0), T(20))
            );

        /*
         * All four storage-form combinations classify identically.
         */
        assert(
            lineIntersectionKind(
                horizontalPP,
                verticalPP
            ) ==
            LineIntersectionKind.point
        );

        assert(
            lineIntersectionKind(
                horizontalPP,
                verticalPV
            ) ==
            LineIntersectionKind.point
        );

        assert(
            lineIntersectionKind(
                horizontalPV,
                verticalPP
            ) ==
            LineIntersectionKind.point
        );

        assert(
            lineIntersectionKind(
                horizontalPV,
                verticalPV
            ) ==
            LineIntersectionKind.point
        );

        auto parallelPP =
            L(
                P(T(0), T(2)),
                P(T(10), T(2))
            );

        auto parallelPV =
            L(
                P(T(0), T(2)),
                V(T(-20), T(0))
            );

        assert(
            lineIntersectionKind(
                horizontalPP,
                parallelPP
            ) ==
            LineIntersectionKind.none
        );

        assert(
            lineIntersectionKind(
                horizontalPV,
                parallelPV
            ) ==
            LineIntersectionKind.none
        );

        auto coincidentPP =
            L(
                P(T(3), T(0)),
                P(T(7), T(0))
            );

        auto coincidentPV =
            L(
                P(T(3), T(0)),
                V(T(-7), T(0))
            );

        assert(
            lineIntersectionKind(
                horizontalPP,
                coincidentPP
            ) ==
            LineIntersectionKind.coincident
        );

        assert(
            lineIntersectionKind(
                horizontalPV,
                coincidentPV
            ) ==
            LineIntersectionKind.coincident
        );

        /*
         * Classification is symmetric.
         */
        assert(
            lineIntersectionKind(
                verticalPV,
                horizontalPP
            ) ==
            LineIntersectionKind.point
        );

        assert(
            lineIntersectionKind(
                coincidentPV,
                horizontalPP
            ) ==
            LineIntersectionKind.coincident
        );
        }
    }


    /*
     * real remains a representable Line2 scalar but is not part of exact
     * topology.
     */
    Line2!real realLine;

    static assert(
        !__traits(
            compiles,
            lineIntersectionKind(
                realLine,
                realLine
            )
        )
    );


    /*
     * Full-range signed-integral point differences must not overflow.
     */
    {
        alias P = Point2!long;
        alias V = Vector2!long;
        alias L = Line2!long;

        auto fullRange =
            L(
                P(long.min, 0),
                P(long.max, 0)
            );

        auto vertical =
            L(
                P(0, -1),
                V(0, 1)
            );

        assert(
            lineIntersectionKind(
                fullRange,
                vertical
            ) ==
            LineIntersectionKind.point
        );
    }


    /*
     * binary64 representability boundary.
     *
     * Converting the first line to PP storage would lose the x increment
     * because 2^53 + 1 rounds back to 2^53. The retained PV direction must
     * therefore remain authoritative.
     */
    {
        alias P = Point2!double;
        alias V = Vector2!double;
        alias L = Line2!double;

        enum double twoTo53 = 0x1p53;

        auto diagonal =
            L(
                P(twoTo53, 0.0),
                V(1.0, 1.0)
            );

        auto vertical =
            L(
                P(twoTo53, -1.0),
                P(twoTo53, 1.0)
            );

        assert(
            lineIntersectionKind(
                diagonal,
                vertical
            ) ==
            LineIntersectionKind.point
        );
    }


    /*
     * Subnormal directions remain exact.
     */
    {
        alias P = Point2!double;
        alias V = Vector2!double;
        alias L = Line2!double;

        enum double subnormal =
            0x0.0000000000001p-1022;

        auto tinyDiagonal =
            L(
                P(0.0, 0.0),
                V(subnormal, subnormal)
            );

        auto horizontal =
            L(
                P(0.0, 1.0),
                V(1.0, 0.0)
            );

        assert(
            lineIntersectionKind(
                tinyDiagonal,
                horizontal
            ) ==
            LineIntersectionKind.point
        );
    }


    /*
     * Directions separated by one binary64 ULP remain distinguishable.
     */
    {
        alias P = Point2!double;
        alias V = Vector2!double;
        alias L = Line2!double;

        auto first =
            L(
                P(0.0, 0.0),
                V(1.0, 1.0)
            );

        auto second =
            L(
                P(0.0, 1.0),
                V(
                    1.0,
                    0x1.0000000000001p0
                )
            );

        assert(
            lineIntersectionKind(
                first,
                second
            ) ==
            LineIntersectionKind.point
        );
    }
}


/*
 * Exact lexicographic point comparison.
 *
 * For a finite collinear point set this defines a consistent linear
 * order along the supporting line:
 *
 *     first x
 *     then y
 *
 * Returns:
 *
 *     -1  lhs < rhs
 *      0  lhs == rhs
 *      1  lhs > rhs
 */
private int comparePoints(T)(
    Point2!T lhs,
    Point2!T rhs
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    if (lhs.x < rhs.x)
        return -1;

    if (rhs.x < lhs.x)
        return 1;

    if (lhs.y < rhs.y)
        return -1;

    if (rhs.y < lhs.y)
        return 1;

    return 0;
}


/*
 * True when point lies inside the closed lexicographic interval
 * [lower, upper].
 *
 * All three points must already be known to be collinear when this
 * helper is used geometrically.
 */
private bool pointInClosedCollinearInterval(T)(
    Point2!T point,
    Point2!T first,
    Point2!T second
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    Point2!T lower = first;
    Point2!T upper = second;

    if (comparePoints(lower, upper) > 0)
    {
        lower = second;
        upper = first;
    }

    return
        comparePoints(point, lower) >= 0 &&
        comparePoints(point, upper) <= 0;
}


/*
 * Point-on-segment predicate.
 *
 * Degenerate segments are naturally supported.
 */
private bool pointOnSegment(T)(
    Point2!T point,
    Segment2!T segment
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    if (segment.a == segment.b)
        return point == segment.a;

    if (
        orientation(
            segment.a,
            segment.b,
            point
        ) != Orientation2.collinear
    )
    {
        return false;
    }

    return pointInClosedCollinearInterval(
        point,
        segment.a,
        segment.b
    );
}


/*
 * Converts an exact input endpoint to the construction scalar.
 *
 * For integer inputs this conversion may round when the coordinate is
 * not exactly representable as binary64. That is construction
 * semantics, not predicate semantics.
 */
private Point2!(IntersectionScalar!T)
intersectionEndpoint(T)(
    Point2!T point
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    return Point2!(IntersectionScalar!T)(
        cast(IntersectionScalar!T) point.x,
        cast(IntersectionScalar!T) point.y
    );
}


/*
 * Attempts to construct a unique intersection that is already one of
 * the input endpoints.
 *
 * `kind` must be the authoritative result of
 * segmentIntersectionKind(first, second).
 *
 * The helper returns false for:
 *
 *     none
 *     overlap
 *     proper interior/interior crossings
 *
 * It covers:
 *
 *     degenerate point-segments
 *     shared endpoints
 *     T-junctions
 *
 * For kind == point, every endpoint lying on the opposite segment must
 * denote the same unique geometric intersection, so endpoint and
 * argument order cannot change the mathematical result.
 */
private bool tryIntersectionEndpointPoint(T, R)(
    Segment2!T first,
    Segment2!T second,
    SegmentIntersectionKind kind,
    out Point2!R point
)
    pure nothrow @safe @nogc
if (
    isIntersectionScalar!T &&
    is(R == IntersectionScalar!T)
)
{
    if (kind != SegmentIntersectionKind.point)
        return false;

    if (pointOnSegment(first.a, second))
    {
        point =
            intersectionEndpoint(first.a);

        return true;
    }

    if (pointOnSegment(first.b, second))
    {
        point =
            intersectionEndpoint(first.b);

        return true;
    }

    if (pointOnSegment(second.a, first))
    {
        point =
            intersectionEndpoint(second.a);

        return true;
    }

    if (pointOnSegment(second.b, first))
    {
        point =
            intersectionEndpoint(second.b);

        return true;
    }

    /*
     * A point intersection with no endpoint on the opposite segment is
     * a proper interior/interior crossing. Its construction belongs to
     * the later exact-weight/rational-rounding path.
     */
    return false;
}


@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;

    /*
     * Shared endpoint.
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const second =
            S(
                P(10, 0),
                P(10, 10)
            );

        const kind =
            segmentIntersectionKind(
                first,
                second
            );

        Point2!double point;

        assert(
            tryIntersectionEndpointPoint(
                first,
                second,
                kind,
                point
            )
        );

        assert(
            point ==
            Point2!double(
                10.0,
                0.0
            )
        );
    }


    /*
     * T-junction.
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const second =
            S(
                P(5, 0),
                P(5, 10)
            );

        const kind =
            segmentIntersectionKind(
                first,
                second
            );

        Point2!double point;

        assert(
            tryIntersectionEndpointPoint(
                first,
                second,
                kind,
                point
            )
        );

        assert(
            point ==
            Point2!double(
                5.0,
                0.0
            )
        );
    }


    /*
     * Degenerate point-segment.
     */
    {
        const first =
            S(
                P(5, 0),
                P(5, 0)
            );

        const second =
            S(
                P(0, 0),
                P(10, 0)
            );

        const kind =
            segmentIntersectionKind(
                first,
                second
            );

        Point2!double point;

        assert(
            tryIntersectionEndpointPoint(
                first,
                second,
                kind,
                point
            )
        );

        assert(
            point ==
            Point2!double(
                5.0,
                0.0
            )
        );
    }


    /*
     * Proper crossing is deliberately not constructed by this helper.
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 10)
            );

        const second =
            S(
                P(0, 10),
                P(10, 0)
            );

        const kind =
            segmentIntersectionKind(
                first,
                second
            );

        assert(
            kind ==
            SegmentIntersectionKind.point
        );

        Point2!double point;

        assert(
            !tryIntersectionEndpointPoint(
                first,
                second,
                kind,
                point
            )
        );
    }


    /*
     * Positive-length overlap must never be reduced to one endpoint.
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const second =
            S(
                P(5, 0),
                P(15, 0)
            );

        const kind =
            segmentIntersectionKind(
                first,
                second
            );

        assert(
            kind ==
            SegmentIntersectionKind.overlap
        );

        Point2!double point;

        assert(
            !tryIntersectionEndpointPoint(
                first,
                second,
                kind,
                point
            )
        );
    }
}


/*
 * True only for strict left/right opposition.
 *
 * Collinearity is deliberately not treated as opposite-side contact.
 */
private bool oppositeSides(
    Orientation2 lhs,
    Orientation2 rhs
)
    pure nothrow @safe @nogc
{
    return
        (
            lhs == Orientation2.left &&
            rhs == Orientation2.right
        ) ||
        (
            lhs == Orientation2.right &&
            rhs == Orientation2.left
        );
}


/*
 * Exact classification of two segments already known to be collinear.
 */
private SegmentIntersectionKind classifyCollinear(T)(
    Segment2!T first,
    Segment2!T second
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    Point2!T firstLower = first.a;
    Point2!T firstUpper = first.b;

    if (comparePoints(firstLower, firstUpper) > 0)
    {
        firstLower = first.b;
        firstUpper = first.a;
    }

    Point2!T secondLower = second.a;
    Point2!T secondUpper = second.b;

    if (comparePoints(secondLower, secondUpper) > 0)
    {
        secondLower = second.b;
        secondUpper = second.a;
    }

    const Point2!T lower =
        comparePoints(firstLower, secondLower) >= 0
            ? firstLower
            : secondLower;

    const Point2!T upper =
        comparePoints(firstUpper, secondUpper) <= 0
            ? firstUpper
            : secondUpper;

    const int comparison =
        comparePoints(lower, upper);

    if (comparison > 0)
        return SegmentIntersectionKind.none;

    if (comparison == 0)
        return SegmentIntersectionKind.point;

    return SegmentIntersectionKind.overlap;
}


/*
 * Finer internal topology used by higher-level topology algorithms.
 *
 * touch means that the intersection consists of exactly one point and is
 * not a proper interior/interior crossing.
 *
 * This distinction is intentionally internal. The public
 * SegmentIntersectionKind API continues to expose both touch and
 * properCrossing as point.
 */
package(geo) enum SegmentContactKind : ubyte
{
    none,
    touch,
    properCrossing,
    overlap,
}


/*
 * Exact internal contact classification of two closed segments.
 *
 * Floating-point endpoints must be finite.
 *
 * No intersection coordinate is constructed.
 */
package(geo) SegmentContactKind segmentContactKind(T)(
    Segment2!T first,
    Segment2!T second
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    static if (
        is(T == float) ||
        is(T == double)
    )
    {
        assert(first.isFinite);
        assert(second.isFinite);
    }

    const bool firstDegenerate =
        first.a == first.b;

    const bool secondDegenerate =
        second.a == second.b;


    /*
     * Degenerate segments represent points.
     *
     * Any non-empty intersection involving a point-segment is therefore a
     * touch rather than a proper crossing or positive-length overlap.
     */
    if (firstDegenerate)
    {
        return pointOnSegment(
            first.a,
            second
        )
            ? SegmentContactKind.touch
            : SegmentContactKind.none;
    }

    if (secondDegenerate)
    {
        return pointOnSegment(
            second.a,
            first
        )
            ? SegmentContactKind.touch
            : SegmentContactKind.none;
    }


    const Orientation2 o1 =
        orientation(
            first.a,
            first.b,
            second.a
        );

    const Orientation2 o2 =
        orientation(
            first.a,
            first.b,
            second.b
        );

    const Orientation2 o3 =
        orientation(
            second.a,
            second.b,
            first.a
        );

    const Orientation2 o4 =
        orientation(
            second.a,
            second.b,
            first.b
        );


    /*
     * Complete collinearity is the only case that can yield a
     * positive-length overlap.
     */
    if (
        o1 == Orientation2.collinear &&
        o2 == Orientation2.collinear &&
        o3 == Orientation2.collinear &&
        o4 == Orientation2.collinear
    )
    {
        const SegmentIntersectionKind kind =
            classifyCollinear(
                first,
                second
            );

        if (
            kind ==
            SegmentIntersectionKind.none
        )
        {
            return SegmentContactKind.none;
        }

        if (
            kind ==
            SegmentIntersectionKind.overlap
        )
        {
            return SegmentContactKind.overlap;
        }

        return SegmentContactKind.touch;
    }


    /*
     * Closed-segment boundary contacts:
     *
     * shared endpoints and T-junctions are touches.
     */
    if (
        o1 == Orientation2.collinear &&
        pointInClosedCollinearInterval(
            second.a,
            first.a,
            first.b
        )
    )
    {
        return SegmentContactKind.touch;
    }

    if (
        o2 == Orientation2.collinear &&
        pointInClosedCollinearInterval(
            second.b,
            first.a,
            first.b
        )
    )
    {
        return SegmentContactKind.touch;
    }

    if (
        o3 == Orientation2.collinear &&
        pointInClosedCollinearInterval(
            first.a,
            second.a,
            second.b
        )
    )
    {
        return SegmentContactKind.touch;
    }

    if (
        o4 == Orientation2.collinear &&
        pointInClosedCollinearInterval(
            first.b,
            second.a,
            second.b
        )
    )
    {
        return SegmentContactKind.touch;
    }


    /*
     * Proper interior/interior crossing.
     */
    if (
        oppositeSides(o1, o2) &&
        oppositeSides(o3, o4)
    )
    {
        return SegmentContactKind.properCrossing;
    }

    return SegmentContactKind.none;
}


/*
 * Returns the exact contact point when two segments have SegmentContactKind.touch.
 *
 * A segment touch always occurs at at least one input endpoint:
 *
 * - shared endpoint;
 * - T-junction;
 * - collinear endpoint contact;
 * - degenerate point-segment contact.
 *
 * The returned point therefore remains in the input scalar domain and no
 * rounded construction is required.
 */
package(geo) bool trySegmentTouchPoint(T)(
    Segment2!T first,
    Segment2!T second,
    out Point2!T point
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    static if (
        is(T == float) ||
        is(T == double)
    )
    {
        assert(first.isFinite);
        assert(second.isFinite);
    }

    if (
        segmentContactKind(
            first,
            second
        ) != SegmentContactKind.touch
    )
    {
        return false;
    }

    if (pointOnSegment(first.a, second))
    {
        point = first.a;
        return true;
    }

    if (pointOnSegment(first.b, second))
    {
        point = first.b;
        return true;
    }

    if (pointOnSegment(second.a, first))
    {
        point = second.a;
        return true;
    }

    if (pointOnSegment(second.b, first))
    {
        point = second.b;
        return true;
    }

    /*
     * Every touch classified by segmentContactKind is endpoint-based.
     */
    assert(false);
}


/**
 * Classifies the exact topological intersection of two closed segments.
 *
 * Supported scalar types:
 *
 *     int
 *     long
 *     float
 *     double
 *
 * For floating-point coordinates all endpoint coordinates must be finite.
 *
 * The operation returns only topology. It deliberately does not construct
 * an intersection coordinate.
 *
 * Degenerate segments are valid and represent a point.
 *
 * No allocation is performed.
 *
 * Complexity:
 *
 *     time  O(1)
 *     space O(1)
 */
SegmentIntersectionKind segmentIntersectionKind(T)(
    Segment2!T first,
    Segment2!T second
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    const SegmentContactKind contact =
        segmentContactKind(
            first,
            second
        );

    if (
        contact ==
        SegmentContactKind.none
    )
    {
        return SegmentIntersectionKind.none;
    }

    if (
        contact ==
        SegmentContactKind.overlap
    )
    {
        return SegmentIntersectionKind.overlap;
    }

    /*
     * Both touch and properCrossing remain one-point intersections in the
     * public topology API.
     */
    return SegmentIntersectionKind.point;
}


/// Example classifying closed-segment intersections without construction.
@safe unittest
{
    import geo;

    alias P = Point2!int;
    alias S = Segment2!int;
    alias K = SegmentIntersectionKind;

    assert(
        segmentIntersectionKind(
            S(P(0, 0), P(4, 0)),
            S(P(0, 2), P(4, 2))
        ) ==
        K.none
    );

    assert(
        segmentIntersectionKind(
            S(P(0, 0), P(4, 4)),
            S(P(0, 4), P(4, 0))
        ) ==
        K.point
    );

    assert(
        segmentIntersectionKind(
            S(P(0, 0), P(6, 0)),
            S(P(2, 0), P(8, 0))
        ) ==
        K.overlap
    );
}


@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;


    /*
     * Disjoint segments.
     */
    assert(
        segmentContactKind(
            S(P(0, 0), P(4, 0)),
            S(P(0, 2), P(4, 2))
        ) ==
        SegmentContactKind.none
    );


    /*
     * Shared endpoint.
     */
    assert(
        segmentContactKind(
            S(P(0, 0), P(4, 0)),
            S(P(4, 0), P(4, 4))
        ) ==
        SegmentContactKind.touch
    );


    /*
     * T-junction.
     */
    assert(
        segmentContactKind(
            S(P(0, 0), P(4, 0)),
            S(P(2, 0), P(2, 4))
        ) ==
        SegmentContactKind.touch
    );


    /*
     * Proper interior/interior crossing.
     */
    assert(
        segmentContactKind(
            S(P(0, 0), P(4, 4)),
            S(P(0, 4), P(4, 0))
        ) ==
        SegmentContactKind.properCrossing
    );


    /*
     * Positive-length collinear overlap.
     */
    assert(
        segmentContactKind(
            S(P(0, 0), P(4, 0)),
            S(P(2, 0), P(6, 0))
        ) ==
        SegmentContactKind.overlap
    );


    /*
     * Degenerate point-segment contact remains a touch.
     */
    assert(
        segmentContactKind(
            S(P(2, 0), P(2, 0)),
            S(P(0, 0), P(4, 0))
        ) ==
        SegmentContactKind.touch
    );


    /*
     * Touch-point construction remains exact in the input scalar domain.
     */
    {
        P point;

        assert(
            trySegmentTouchPoint(
                S(P(0, 0), P(4, 0)),
                S(P(4, 0), P(4, 4)),
                point
            )
        );

        assert(point == P(4, 0));
    }


    /*
     * T-junction contact is an exact endpoint of one input segment.
     */
    {
        P point;

        assert(
            trySegmentTouchPoint(
                S(P(0, 0), P(4, 0)),
                S(P(2, 0), P(2, 4)),
                point
            )
        );

        assert(point == P(2, 0));
    }


    /*
     * Collinear endpoint contact remains exact.
     */
    {
        P point;

        assert(
            trySegmentTouchPoint(
                S(P(0, 0), P(4, 0)),
                S(P(4, 0), P(8, 0)),
                point
            )
        );

        assert(point == P(4, 0));
    }


    /*
     * Argument order does not change the geometric touch point.
     */
    {
        P firstPoint;
        P secondPoint;

        assert(
            trySegmentTouchPoint(
                S(P(0, 0), P(4, 0)),
                S(P(2, 0), P(2, 4)),
                firstPoint
            )
        );

        assert(
            trySegmentTouchPoint(
                S(P(2, 0), P(2, 4)),
                S(P(0, 0), P(4, 0)),
                secondPoint
            )
        );

        assert(firstPoint == secondPoint);
    }


    /*
     * Proper crossings deliberately have no input-domain touch point.
     */
    {
        P point;

        assert(
            !trySegmentTouchPoint(
                S(P(0, 0), P(4, 4)),
                S(P(0, 4), P(4, 0)),
                point
            )
        );
    }


    /*
     * Positive-length overlaps are not single-point touches.
     */
    {
        P point;

        assert(
            !trySegmentTouchPoint(
                S(P(0, 0), P(4, 0)),
                S(P(2, 0), P(6, 0)),
                point
            )
        );
    }


    /*
     * The finer internal distinction must collapse exactly to the existing
     * public topology.
     */
    assert(
        segmentIntersectionKind(
            S(P(0, 0), P(4, 0)),
            S(P(4, 0), P(4, 4))
        ) ==
        SegmentIntersectionKind.point
    );

    assert(
        segmentIntersectionKind(
            S(P(0, 0), P(4, 4)),
            S(P(0, 4), P(4, 0))
        ) ==
        SegmentIntersectionKind.point
    );

    assert(
        segmentIntersectionKind(
            S(P(0, 0), P(4, 0)),
            S(P(2, 0), P(6, 0))
        ) ==
        SegmentIntersectionKind.overlap
    );
}


/**
 * Constructs the unique intersection point of two closed segments.
 *
 * Returns true exactly when:
 *
 *     segmentIntersectionKind(first, second)
 *         == SegmentIntersectionKind.point
 *
 * Supported input scalar types:
 *
 *     int
 *     long
 *     float
 *     double
 *
 * The constructed point uses IntersectionScalar!T, which is currently
 * double for every supported input scalar.
 *
 * Topology and construction deliberately remain separate:
 *
 * - segmentIntersectionKind() determines the exact topology;
 * - endpoint contacts reuse the known input endpoint;
 * - proper interior/interior crossings are constructed from exact
 *   dyadic determinant weights and correctly rounded to binary64.
 *
 * For floating-point coordinates all endpoints must be finite.
 *
 * Returns false for:
 *
 * - disjoint segments;
 * - positive-length overlaps.
 *
 * Because `point` is an `out` parameter, false leaves it at
 * Point2!R.init.
 *
 * The returned rounded point is construction data. It must not be fed
 * back into exact predicates as evidence of the already established
 * topology.
 *
 * No allocation is performed.
 *
 * Complexity:
 *
 *     time  O(1)
 *     space O(1)
 */
bool trySegmentIntersectionPoint(T, R)(
    Segment2!T first,
    Segment2!T second,
    out Point2!R point
)
    pure nothrow @safe @nogc
if (
    isIntersectionScalar!T &&
    is(R == IntersectionScalar!T)
)
{
    static if (
        is(T == float) ||
        is(T == double)
    )
    {
        assert(first.isFinite);
        assert(second.isFinite);
    }

    const SegmentIntersectionKind kind =
        segmentIntersectionKind(
            first,
            second
        );

    if (kind != SegmentIntersectionKind.point)
        return false;


    /*
     * Degenerate contacts, shared endpoints and T-junctions already
     * have an exact input endpoint representing the unique
     * intersection.
     */
    if (
        tryIntersectionEndpointPoint(
            first,
            second,
            kind,
            point
        )
    )
    {
        return true;
    }


    /*
     * A unique intersection with no endpoint on the opposite segment
     * is necessarily a strict interior/interior crossing.
     */
    ExactProperIntersection exact;

    properIntersectionExactKnownCrossing(
        first,
        second,
        exact
    );

    point =
        Point2!R(
            roundExactCoordinateBinary64(
                exact.xNumerator,
                exact.denominator
            ),
            roundExactCoordinateBinary64(
                exact.yNumerator,
                exact.denominator
            )
        );

    return true;
}


/// Example using the public package API.
@safe unittest
{
    import geo;

    alias P = Point2!int;
    alias S = Segment2!int;

    const first =
        S(
            P(0, 0),
            P(10, 10)
        );

    const second =
        S(
            P(0, 10),
            P(10, 0)
        );

    assert(
        segmentIntersectionKind(
            first,
            second
        ) == SegmentIntersectionKind.point
    );

    Point2!double point;

    assert(
        trySegmentIntersectionPoint(
            first,
            second,
            point
        )
    );

    assert(
        point ==
        Point2!double(
            5.0,
            5.0
        )
    );
}


@safe unittest
{
    /*
     * Ordinary proper crossing.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S first =
            S(
                P(0, 0),
                P(10, 10)
            );

        const S second =
            S(
                P(0, 10),
                P(10, 0)
            );

        Point2!double point;

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                point
            )
        );

        assert(
            point ==
            Point2!double(
                5.0,
                5.0
            )
        );
    }


    /*
     * Shared endpoint construction.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        Point2!double point;

        assert(
            trySegmentIntersectionPoint(
                S(
                    P(0, 0),
                    P(10, 0)
                ),
                S(
                    P(10, 0),
                    P(10, 10)
                ),
                point
            )
        );

        assert(
            point ==
            Point2!double(
                10.0,
                0.0
            )
        );
    }


    /*
     * T-junction construction.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        Point2!double point;

        assert(
            trySegmentIntersectionPoint(
                S(
                    P(0, 0),
                    P(10, 0)
                ),
                S(
                    P(5, 0),
                    P(5, 10)
                ),
                point
            )
        );

        assert(
            point ==
            Point2!double(
                5.0,
                0.0
            )
        );
    }


    /*
     * Degenerate point-segment construction.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        Point2!double point;

        assert(
            trySegmentIntersectionPoint(
                S(
                    P(3, 3),
                    P(3, 3)
                ),
                S(
                    P(0, 0),
                    P(10, 10)
                ),
                point
            )
        );

        assert(
            point ==
            Point2!double(
                3.0,
                3.0
            )
        );
    }


    /*
     * Disjoint geometry returns false and the out parameter is reset.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        Point2!double point =
            Point2!double(
                99.0,
                100.0
            );

        assert(
            !trySegmentIntersectionPoint(
                S(
                    P(0, 0),
                    P(2, 0)
                ),
                S(
                    P(0, 2),
                    P(2, 2)
                ),
                point
            )
        );

        assert(
            point ==
            Point2!double.init
        );
    }


    /*
     * Positive-length overlap is not a unique point.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        Point2!double point;

        assert(
            !trySegmentIntersectionPoint(
                S(
                    P(0, 0),
                    P(10, 0)
                ),
                S(
                    P(5, 0),
                    P(15, 0)
                ),
                point
            )
        );

        assert(
            point ==
            Point2!double.init
        );
    }


    /*
     * Full-range signed integer geometry.
     *
     * The exact crossing is the origin even though ordinary signed
     * arithmetic cannot represent the endpoint differences.
     */
    {
        alias P = Point2!long;
        alias S = Segment2!long;

        const S horizontal =
            S(
                P(long.min, 0),
                P(long.max, 0)
            );

        const S vertical =
            S(
                P(0, long.min),
                P(0, long.max)
            );

        Point2!double point;

        assert(
            trySegmentIntersectionPoint(
                horizontal,
                vertical,
                point
            )
        );

        assert(point.x == 0.0);
        assert(point.y == 0.0);
    }


    /*
     * Full-range finite binary64 geometry.
     *
     * Naive determinant construction would overflow, while the exact
     * dyadic path constructs the origin.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;

        const S horizontal =
            S(
                P(-double.max, 0.0),
                P( double.max, 0.0)
            );

        const S vertical =
            S(
                P(0.0, -double.max),
                P(0.0,  double.max)
            );

        Point2!double point;

        assert(
            trySegmentIntersectionPoint(
                horizontal,
                vertical,
                point
            )
        );

        assert(point.x == 0.0);
        assert(point.y == 0.0);
    }


    /*
     * Subnormal proper crossing.
     *
     * The exact coordinate is half of the smallest positive binary64
     * subnormal in both dimensions. Round-to-nearest, ties-to-even
     * therefore produces +0.0.
     */
    {
        enum double tiny =
            0x0.0000000000001p-1022;

        alias P = Point2!double;
        alias S = Segment2!double;

        const S first =
            S(
                P(0.0, 0.0),
                P(tiny, tiny)
            );

        const S second =
            S(
                P(0.0, tiny),
                P(tiny, 0.0)
            );

        Point2!double point;

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                point
            )
        );

        assert(point.x == 0.0);
        assert(point.y == 0.0);
    }


    /*
     * Proper-crossing construction must be invariant under argument
     * order and endpoint reversal.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S first =
            S(
                P(-7, 2),
                P(11, 13)
            );

        const S second =
            S(
                P(-3, 15),
                P(9, -5)
            );

        const S reverseFirst =
            S(
                first.b,
                first.a
            );

        const S reverseSecond =
            S(
                second.b,
                second.a
            );

        Point2!double a;
        Point2!double b;
        Point2!double c;
        Point2!double d;

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                a
            )
        );

        assert(
            trySegmentIntersectionPoint(
                second,
                first,
                b
            )
        );

        assert(
            trySegmentIntersectionPoint(
                reverseFirst,
                second,
                c
            )
        );

        assert(
            trySegmentIntersectionPoint(
                reverseFirst,
                reverseSecond,
                d
            )
        );

        assert(a == b);
        assert(a == c);
        assert(a == d);
    }


    /*
     * Endpoint construction follows the same invariance contract.
     */
    {
        alias P = Point2!long;
        alias S = Segment2!long;

        const S first =
            S(
                P(long.max, 7),
                P(0, 0)
            );

        const S second =
            S(
                P(long.max, 7),
                P(long.max, -20)
            );

        const S reverseFirst =
            S(
                first.b,
                first.a
            );

        const S reverseSecond =
            S(
                second.b,
                second.a
            );

        Point2!double a;
        Point2!double b;
        Point2!double c;

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                a
            )
        );

        assert(
            trySegmentIntersectionPoint(
                second,
                first,
                b
            )
        );

        assert(
            trySegmentIntersectionPoint(
                reverseFirst,
                reverseSecond,
                c
            )
        );

        assert(a == b);
        assert(a == c);

        /*
         * long.max is not exactly representable in binary64. Endpoint
         * construction deliberately returns its rounded double value.
         */
        assert(
            a.x ==
            cast(double) long.max
        );

        assert(a.y == 7.0);
    }


    /*
     * Runtime coverage of float input.
     */
    {
        alias P = Point2!float;
        alias S = Segment2!float;

        Point2!double point;

        assert(
            trySegmentIntersectionPoint(
                S(
                    P(0.0f, 0.0f),
                    P(4.0f, 4.0f)
                ),
                S(
                    P(0.0f, 4.0f),
                    P(4.0f, 0.0f)
                ),
                point
            )
        );

        assert(
            point ==
            Point2!double(
                2.0,
                2.0
            )
        );
    }


    /*
     * Public scalar/result contract.
     *
     * The separately deduced R parameter avoids D template deduction
     * through the transformed IntersectionScalar!T alias.
     */
    static assert(
        __traits(
            compiles,
            {
                Point2!double result;

                trySegmentIntersectionPoint(
                    Segment2!int.init,
                    Segment2!int.init,
                    result
                );
            }
        )
    );

    static assert(
        __traits(
            compiles,
            {
                Point2!double result;

                trySegmentIntersectionPoint(
                    Segment2!long.init,
                    Segment2!long.init,
                    result
                );
            }
        )
    );

    static assert(
        __traits(
            compiles,
            {
                Point2!double result;

                trySegmentIntersectionPoint(
                    Segment2!float.init,
                    Segment2!float.init,
                    result
                );
            }
        )
    );

    static assert(
        __traits(
            compiles,
            {
                Point2!double result;

                trySegmentIntersectionPoint(
                    Segment2!double.init,
                    Segment2!double.init,
                    result
                );
            }
        )
    );

    static assert(
        !__traits(
            compiles,
            {
                Point2!float result;

                trySegmentIntersectionPoint(
                    Segment2!int.init,
                    Segment2!int.init,
                    result
                );
            }
        )
    );

    static assert(
        !__traits(
            compiles,
            {
                Point2!double result;

                trySegmentIntersectionPoint(
                    Segment2!real.init,
                    Segment2!real.init,
                    result
                );
            }
        )
    );
}


@safe unittest
{
    import std.bitmanip :
        DoubleRep;


    /*
     * Exact binary64 comparison, including the sign of zero.
     *
     * Construction symmetry is stronger than ordinary floating-point
     * equality: equivalent segment representations should produce the
     * same binary64 result bits.
     */
    bool sameDoubleBits(
        double lhs,
        double rhs
    )
    {
        DoubleRep left;
        DoubleRep right;

        left.value = lhs;
        right.value = rhs;

        return
            left.sign == right.sign &&
            left.exponent == right.exponent &&
            left.fraction == right.fraction;
    }


    bool samePointBits(
        Point2!double lhs,
        Point2!double rhs
    )
    {
        return
            sameDoubleBits(
                lhs.x,
                rhs.x
            ) &&
            sameDoubleBits(
                lhs.y,
                rhs.y
            );
    }


    /*
     * Deterministic broad verification over small integer geometry.
     *
     * The classifier remains authoritative:
     *
     *     kind == point
     *
     * iff
     *
     *     unique-point construction succeeds.
     *
     * For every successful construction, argument order and endpoint
     * reversal must produce bit-identical Point2!double results.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;
        alias K = SegmentIntersectionKind;

        int coordinate(
            size_t index,
            uint salt
        )
            pure nothrow @safe @nogc
        {
            const ulong value =
                cast(ulong)(index + 1) *
                    (37UL + 17UL * salt) +
                cast(ulong)(index * index + 3) *
                    (11UL + 5UL * salt) +
                53UL * salt;

            return
                cast(int)(
                    value % 97UL
                ) -
                48;
        }

        foreach (index; 0 .. 256)
        {
            const S first =
                S(
                    P(
                        coordinate(index, 1),
                        coordinate(index, 2)
                    ),
                    P(
                        coordinate(index, 3),
                        coordinate(index, 4)
                    )
                );

            const S second =
                S(
                    P(
                        coordinate(index, 5),
                        coordinate(index, 6)
                    ),
                    P(
                        coordinate(index, 7),
                        coordinate(index, 8)
                    )
                );

            const S reverseFirst =
                S(
                    first.b,
                    first.a
                );

            const S reverseSecond =
                S(
                    second.b,
                    second.a
                );

            const K kind =
                segmentIntersectionKind(
                    first,
                    second
                );

            Point2!double normal =
                Point2!double(
                    123.0,
                    456.0
                );

            const bool success =
                trySegmentIntersectionPoint(
                    first,
                    second,
                    normal
                );

            assert(
                success ==
                (
                    kind ==
                    K.point
                )
            );

            if (!success)
            {
                /*
                 * `out` semantics reset the result even when
                 * construction fails.
                 */
                assert(
                    normal ==
                    Point2!double.init
                );

                continue;
            }

            Point2!double swapped;
            Point2!double reversedFirst;
            Point2!double reversedSecond;
            Point2!double reversedBoth;

            assert(
                trySegmentIntersectionPoint(
                    second,
                    first,
                    swapped
                )
            );

            assert(
                trySegmentIntersectionPoint(
                    reverseFirst,
                    second,
                    reversedFirst
                )
            );

            assert(
                trySegmentIntersectionPoint(
                    first,
                    reverseSecond,
                    reversedSecond
                )
            );

            assert(
                trySegmentIntersectionPoint(
                    reverseFirst,
                    reverseSecond,
                    reversedBoth
                )
            );

            assert(
                samePointBits(
                    normal,
                    swapped
                )
            );

            assert(
                samePointBits(
                    normal,
                    reversedFirst
                )
            );

            assert(
                samePointBits(
                    normal,
                    reversedSecond
                )
            );

            assert(
                samePointBits(
                    normal,
                    reversedBoth
                )
            );
        }
    }


    /*
     * Non-dyadic rational proper crossing.
     *
     * AB:
     *
     *     (0,0) -> (1,0)
     *
     * CD:
     *
     *     (0,1) -> (1,-2)
     *
     * intersects at exactly:
     *
     *     x = 1/3
     *     y = 0
     *
     * The expected binary64 value is written directly as its correctly
     * rounded hexadecimal representation.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S first =
            S(
                P(0, 0),
                P(1, 0)
            );

        const S second =
            S(
                P(0, 1),
                P(1, -2)
            );

        Point2!double point;

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                point
            )
        );

        assert(
            sameDoubleBits(
                point.x,
                0x1.5555555555555p-2
            )
        );

        assert(
            sameDoubleBits(
                point.y,
                0.0
            )
        );
    }


    /*
     * A case that specifically defeats construction through a rounded
     * binary64 segment parameter.
     *
     * The proper crossing lies at:
     *
     *     (2^-977, 2^-977)
     *
     * on the segment:
     *
     *     (0,0) -> (2^1023, 2^1023)
     *
     * Its segment parameter is:
     *
     *     t = 2^-2000
     *
     * which underflows to zero in binary64 even though:
     *
     *     t * 2^1023 = 2^-977
     *
     * is a normal, exactly representable binary64 value.
     *
     * This is the motivating failure mode for carrying the exact
     * barycentric ratio through multiplication before rounding.
     */
    {
        enum double huge =
            0x1p+1023;

        enum double expected =
            0x1p-977;

        /*
         * Demonstrate why a conventional binary64 segment parameter
         * is insufficient.
         *
         * Constant expressions may otherwise retain excess precision,
         * so force the intermediate result to binary64 explicitly.
         */
        import core.math : toPrec;

        const double roundedParameter =
            toPrec!double(
                expected / huge
            );

        assert(
            roundedParameter ==
            0.0
        );

        alias P = Point2!double;
        alias S = Segment2!double;

        const S first =
            S(
                P(0.0, 0.0),
                P(huge, huge)
            );

        const S second =
            S(
                P(expected, -1.0),
                P(expected,  1.0)
            );

        const S reverseFirst =
            S(
                first.b,
                first.a
            );

        const S reverseSecond =
            S(
                second.b,
                second.a
            );

        Point2!double normal;
        Point2!double swapped;
        Point2!double reversed;

        assert(
            segmentIntersectionKind(
                first,
                second
            ) ==
            SegmentIntersectionKind.point
        );

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                normal
            )
        );

        assert(
            trySegmentIntersectionPoint(
                second,
                first,
                swapped
            )
        );

        assert(
            trySegmentIntersectionPoint(
                reverseFirst,
                reverseSecond,
                reversed
            )
        );

        assert(
            sameDoubleBits(
                normal.x,
                expected
            )
        );

        assert(
            sameDoubleBits(
                normal.y,
                expected
            )
        );

        assert(
            samePointBits(
                normal,
                swapped
            )
        );

        assert(
            samePointBits(
                normal,
                reversed
            )
        );
    }


    /*
     * Two identical degenerate segments have exactly their common
     * endpoint as the unique intersection.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;

        const S first =
            S(
                P(3.5, -7.25),
                P(3.5, -7.25)
            );

        const S second =
            S(
                P(3.5, -7.25),
                P(3.5, -7.25)
            );

        Point2!double point;

        assert(
            segmentIntersectionKind(
                first,
                second
            ) ==
            SegmentIntersectionKind.point
        );

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                point
            )
        );

        assert(
            sameDoubleBits(
                point.x,
                3.5
            )
        );

        assert(
            sameDoubleBits(
                point.y,
                -7.25
            )
        );
    }


    /*
     * Near-parallel binary64 proper crossing.
     *
     * First supporting line:
     *
     *     y = x
     *
     * Second supporting line:
     *
     *     y = (1 - 2^-52) x + 2^-53
     *
     * Their exact intersection is:
     *
     *     (1/2, 1/2)
     *
     * The slopes differ by only one binary64 ulp at 1.0.
     */
    {
        enum double halfUlp =
            0x1p-53;

        enum double oneMinusHalfUlp =
            0x1.fffffffffffffp-1;

        alias P = Point2!double;
        alias S = Segment2!double;

        const S first =
            S(
                P(0.0, 0.0),
                P(1.0, 1.0)
            );

        const S second =
            S(
                P(0.0, halfUlp),
                P(1.0, oneMinusHalfUlp)
            );

        const S reverseFirst =
            S(
                first.b,
                first.a
            );

        const S reverseSecond =
            S(
                second.b,
                second.a
            );

        Point2!double normal;
        Point2!double swapped;
        Point2!double reversed;

        assert(
            segmentIntersectionKind(
                first,
                second
            ) ==
            SegmentIntersectionKind.point
        );

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                normal
            )
        );

        assert(
            trySegmentIntersectionPoint(
                second,
                first,
                swapped
            )
        );

        assert(
            trySegmentIntersectionPoint(
                reverseFirst,
                reverseSecond,
                reversed
            )
        );

        assert(
            sameDoubleBits(
                normal.x,
                0.5
            )
        );

        assert(
            sameDoubleBits(
                normal.y,
                0.5
            )
        );

        assert(
            samePointBits(
                normal,
                swapped
            )
        );

        assert(
            samePointBits(
                normal,
                reversed
            )
        );
    }


    /*
     * Full-range long construction remains invariant under every basic
     * representation symmetry.
     */
    {
        alias P = Point2!long;
        alias S = Segment2!long;

        const S first =
            S(
                P(long.min, 0),
                P(long.max, 0)
            );

        const S second =
            S(
                P(0, long.min),
                P(0, long.max)
            );

        const S reverseFirst =
            S(
                first.b,
                first.a
            );

        const S reverseSecond =
            S(
                second.b,
                second.a
            );

        Point2!double a;
        Point2!double b;
        Point2!double c;
        Point2!double d;

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                a
            )
        );

        assert(
            trySegmentIntersectionPoint(
                second,
                first,
                b
            )
        );

        assert(
            trySegmentIntersectionPoint(
                reverseFirst,
                second,
                c
            )
        );

        assert(
            trySegmentIntersectionPoint(
                reverseFirst,
                reverseSecond,
                d
            )
        );

        assert(samePointBits(a, b));
        assert(samePointBits(a, c));
        assert(samePointBits(a, d));

        assert(
            sameDoubleBits(
                a.x,
                0.0
            )
        );

        assert(
            sameDoubleBits(
                a.y,
                0.0
            )
        );
    }


    /*
     * Full-range binary64 construction receives the same symmetry
     * verification.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;

        const S first =
            S(
                P(-double.max, 0.0),
                P( double.max, 0.0)
            );

        const S second =
            S(
                P(0.0, -double.max),
                P(0.0,  double.max)
            );

        const S reverseFirst =
            S(
                first.b,
                first.a
            );

        const S reverseSecond =
            S(
                second.b,
                second.a
            );

        Point2!double a;
        Point2!double b;
        Point2!double c;
        Point2!double d;

        assert(
            trySegmentIntersectionPoint(
                first,
                second,
                a
            )
        );

        assert(
            trySegmentIntersectionPoint(
                second,
                first,
                b
            )
        );

        assert(
            trySegmentIntersectionPoint(
                reverseFirst,
                second,
                c
            )
        );

        assert(
            trySegmentIntersectionPoint(
                reverseFirst,
                reverseSecond,
                d
            )
        );

        assert(samePointBits(a, b));
        assert(samePointBits(a, c));
        assert(samePointBits(a, d));
    }
}


/**
 * Constructs the positive-length collinear overlap of two closed
 * segments.
 *
 * Returns true exactly when:
 *
 *     segmentIntersectionKind(first, second)
 *         == SegmentIntersectionKind.overlap
 *
 * Supported scalar types:
 *
 *     int
 *     long
 *     float
 *     double
 *
 * On success, `overlap` contains the exact common segment in the
 * original scalar type. Its endpoints are selected from the input
 * endpoints and returned in canonical lexicographic order.
 *
 * Returns false for:
 *
 * - disjoint segments;
 * - unique-point intersections.
 *
 * No numerical intersection coordinate is constructed.
 *
 * For floating-point coordinates all endpoints must be finite.
 *
 * On failure, overlap is Segment2!T.init.
 *
 * No allocation is performed.
 *
 * Complexity:
 *
 *     time  O(1)
 *     space O(1)
 */
bool trySegmentIntersectionOverlap(T)(
    Segment2!T first,
    Segment2!T second,
    out Segment2!T overlap
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T)
{
    static if (
        is(T == float) ||
        is(T == double)
    )
    {
        assert(first.isFinite);
        assert(second.isFinite);
    }

    if (
        segmentIntersectionKind(
            first,
            second
        ) != SegmentIntersectionKind.overlap
    )
    {
        return false;
    }

    Point2!T firstLower =
        first.a;

    Point2!T firstUpper =
        first.b;

    if (
        comparePoints(
            firstLower,
            firstUpper
        ) > 0
    )
    {
        firstLower =
            first.b;

        firstUpper =
            first.a;
    }

    Point2!T secondLower =
        second.a;

    Point2!T secondUpper =
        second.b;

    if (
        comparePoints(
            secondLower,
            secondUpper
        ) > 0
    )
    {
        secondLower =
            second.b;

        secondUpper =
            second.a;
    }

    const Point2!T lower =
        comparePoints(
            firstLower,
            secondLower
        ) >= 0
            ? firstLower
            : secondLower;

    const Point2!T upper =
        comparePoints(
            firstUpper,
            secondUpper
        ) <= 0
            ? firstUpper
            : secondUpper;

    /*
     * The classifier established positive-length overlap.
     */
    assert(
        comparePoints(
            lower,
            upper
        ) < 0
    );

    overlap =
        Segment2!T(
            lower,
            upper
        );

    return true;
}


/// Example constructing the exact canonical overlap in the input scalar type.
@safe unittest
{
    import geo;

    alias P = Point2!int;
    alias S = Segment2!int;

    const first =
        S(
            P(10, 0),
            P(0, 0)
        );

    const second =
        S(
            P(3, 0),
            P(12, 0)
        );

    S overlap;

    assert(
        trySegmentIntersectionOverlap(
            first,
            second,
            overlap
        )
    );

    static assert(
        is(typeof(overlap) == S)
    );

    assert(
        overlap ==
        S(
            P(3, 0),
            P(10, 0)
        )
    );
}


version(unittest)
{
    /*
     * Independent one-dimensional oracle for closed intervals.
     *
     * The segment classifier uses lexicographic ordering of geometric
     * endpoints. This oracle instead works on the independent line
     * parameter used to construct the test geometry.
     */
    private SegmentIntersectionKind intervalIntersectionOracle(
        int firstA,
        int firstB,
        int secondA,
        int secondB
    )
        pure nothrow @safe @nogc
    {
        int firstLower = firstA;
        int firstUpper = firstB;

        if (firstUpper < firstLower)
        {
            firstLower = firstB;
            firstUpper = firstA;
        }

        int secondLower = secondA;
        int secondUpper = secondB;

        if (secondUpper < secondLower)
        {
            secondLower = secondB;
            secondUpper = secondA;
        }

        const int lower =
            firstLower > secondLower
                ? firstLower
                : secondLower;

        const int upper =
            firstUpper < secondUpper
                ? firstUpper
                : secondUpper;

        if (upper < lower)
            return SegmentIntersectionKind.none;

        if (upper == lower)
            return SegmentIntersectionKind.point;

        return SegmentIntersectionKind.overlap;
    }


    /*
     * Four independent embeddings of the same integer line parameter.
     *
     * These exercise horizontal, vertical, positive-slope and
     * negative-slope collinear geometry.
     */
    private Point2!int collinearOraclePoint(
        size_t family,
        int parameter
    )
        pure nothrow @safe @nogc
    {
        final switch (family)
        {
            case 0:
                return Point2!int(
                    parameter,
                    7
                );

            case 1:
                return Point2!int(
                    -3,
                    parameter
                );

            case 2:
                return Point2!int(
                    parameter,
                    2 * parameter + 1
                );

            case 3:
                return Point2!int(
                    parameter,
                    -3 * parameter + 5
                );
        }
    }


    /*
     * Small deterministic PRNG for reproducible invariant sweeps.
     */
    private ulong nextIntersectionRandom(
        ref ulong state
    )
        pure nothrow @safe @nogc
    {
        assert(state != 0);

        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;

        return state;
    }


    private int randomIntersectionCoordinate(
        ref ulong state
    )
        pure nothrow @safe @nogc
    {
        return
            cast(int)(
                nextIntersectionRandom(state) %
                2001UL
            ) -
            1000;
    }
}


@safe unittest
{
    /*
     * Exact horizontal partial overlap.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S first =
            S(
                P(0, 2),
                P(8, 2)
            );

        const S second =
            S(
                P(5, 2),
                P(12, 2)
            );

        S overlap;

        assert(
            trySegmentIntersectionOverlap(
                first,
                second,
                overlap
            )
        );

        assert(
            overlap ==
            S(
                P(5, 2),
                P(8, 2)
            )
        );
    }


    /*
     * Vertical overlap uses canonical y ordering when x is equal.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S first =
            S(
                P(4, 10),
                P(4, -10)
            );

        const S second =
            S(
                P(4, 20),
                P(4, 5)
            );

        S overlap;

        assert(
            trySegmentIntersectionOverlap(
                first,
                second,
                overlap
            )
        );

        assert(
            overlap ==
            S(
                P(4, 5),
                P(4, 10)
            )
        );
    }


    /*
     * Positive-slope containment.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S outer =
            S(
                P(0, 0),
                P(10, 10)
            );

        const S inner =
            S(
                P(3, 3),
                P(7, 7)
            );

        S overlap;

        assert(
            trySegmentIntersectionOverlap(
                outer,
                inner,
                overlap
            )
        );

        assert(overlap == inner);
    }


    /*
     * Negative-slope overlap is still canonicalized lexicographically.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S first =
            S(
                P(10, 0),
                P(0, 10)
            );

        const S second =
            S(
                P(3, 7),
                P(20, -10)
            );

        S overlap;

        assert(
            trySegmentIntersectionOverlap(
                first,
                second,
                overlap
            )
        );

        assert(
            overlap ==
            S(
                P(3, 7),
                P(10, 0)
            )
        );
    }


    /*
     * Identical and reversed-identical segments return the same
     * canonical result.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S canonical =
            S(
                P(-4, -1),
                P(9, 12)
            );

        const S reversed =
            S(
                canonical.b,
                canonical.a
            );

        S firstResult;
        S secondResult;

        assert(
            trySegmentIntersectionOverlap(
                canonical,
                canonical,
                firstResult
            )
        );

        assert(
            trySegmentIntersectionOverlap(
                reversed,
                canonical,
                secondResult
            )
        );

        assert(
            firstResult ==
            canonical
        );

        assert(
            secondResult ==
            canonical
        );
    }


    /*
     * Argument order and both endpoint orders produce an exactly
     * identical canonical overlap segment.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S first =
            S(
                P(-10, -10),
                P(10, 10)
            );

        const S second =
            S(
                P(-3, -3),
                P(20, 20)
            );

        const S reverseFirst =
            S(
                first.b,
                first.a
            );

        const S reverseSecond =
            S(
                second.b,
                second.a
            );

        const S expected =
            S(
                P(-3, -3),
                P(10, 10)
            );

        S a;
        S b;
        S c;
        S d;

        assert(
            trySegmentIntersectionOverlap(
                first,
                second,
                a
            )
        );

        assert(
            trySegmentIntersectionOverlap(
                second,
                first,
                b
            )
        );

        assert(
            trySegmentIntersectionOverlap(
                reverseFirst,
                second,
                c
            )
        );

        assert(
            trySegmentIntersectionOverlap(
                reverseFirst,
                reverseSecond,
                d
            )
        );

        assert(a == expected);
        assert(b == expected);
        assert(c == expected);
        assert(d == expected);
    }


    /*
     * A unique-point intersection does not produce overlap geometry.
     *
     * Because the result parameter is `out`, false leaves it at
     * Segment2.init.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S first =
            S(
                P(0, 0),
                P(10, 10)
            );

        const S second =
            S(
                P(0, 10),
                P(10, 0)
            );

        S overlap =
            S(
                P(99, 99),
                P(100, 100)
            );

        assert(
            !trySegmentIntersectionOverlap(
                first,
                second,
                overlap
            )
        );

        assert(
            overlap ==
            S.init
        );
    }


    /*
     * Collinear one-point contact is still not positive-length overlap.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S first =
            S(
                P(0, 0),
                P(5, 0)
            );

        const S second =
            S(
                P(5, 0),
                P(10, 0)
            );

        S overlap;

        assert(
            !trySegmentIntersectionOverlap(
                first,
                second,
                overlap
            )
        );
    }


    /*
     * Disjoint segments return false.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        S overlap;

        assert(
            !trySegmentIntersectionOverlap(
                S(
                    P(0, 0),
                    P(4, 0)
                ),
                S(
                    P(5, 0),
                    P(10, 0)
                ),
                overlap
            )
        );
    }


    /*
     * Degenerate segments can never produce positive-length overlap.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const S point =
            S(
                P(5, 5),
                P(5, 5)
            );

        const S line =
            S(
                P(0, 0),
                P(10, 10)
            );

        S overlap;

        assert(
            !trySegmentIntersectionOverlap(
                point,
                line,
                overlap
            )
        );

        assert(
            !trySegmentIntersectionOverlap(
                point,
                point,
                overlap
            )
        );
    }


    /*
     * Full-range long coordinates are preserved exactly because overlap
     * endpoints are selected directly from the inputs.
     */
    {
        alias P = Point2!long;
        alias S = Segment2!long;

        const S first =
            S(
                P(long.min, 0),
                P(long.max, 0)
            );

        const S second =
            S(
                P(-1, 0),
                P(long.max, 0)
            );

        S overlap;

        assert(
            trySegmentIntersectionOverlap(
                first,
                second,
                overlap
            )
        );

        assert(
            overlap ==
            S(
                P(-1, 0),
                P(long.max, 0)
            )
        );
    }


    /*
     * Floating endpoint bit patterns are preserved exactly.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;

        enum double lower =
            0x1.0000000000001p+0;

        enum double upper =
            0x1.0000000000003p+0;

        enum double beyond =
            0x1.0000000000004p+0;

        const S first =
            S(
                P(1.0, 0.0),
                P(upper, 0.0)
            );

        const S second =
            S(
                P(lower, 0.0),
                P(beyond, 0.0)
            );

        S overlap;

        assert(
            trySegmentIntersectionOverlap(
                first,
                second,
                overlap
            )
        );

        assert(
            overlap.a.x ==
            lower
        );

        assert(
            overlap.b.x ==
            upper
        );

        assert(
            overlap.a.y == 0.0
        );

        assert(
            overlap.b.y == 0.0
        );
    }


    /*
     * Smallest subnormal binary64 endpoints are preserved.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;

        enum double one =
            0x0.0000000000001p-1022;

        enum double two =
            0x0.0000000000002p-1022;

        enum double four =
            0x0.0000000000004p-1022;

        enum double six =
            0x0.0000000000006p-1022;

        const S first =
            S(
                P(0.0, 0.0),
                P(four, four)
            );

        const S second =
            S(
                P(two, two),
                P(six, six)
            );

        S overlap;

        assert(
            trySegmentIntersectionOverlap(
                first,
                second,
                overlap
            )
        );

        assert(
            overlap ==
            S(
                P(two, two),
                P(four, four)
            )
        );

        assert(one > 0.0);
    }


    /*
     * Scalar-domain compile contract follows segment classification.
     */
    static assert(
        __traits(
            compiles,
            {
                Segment2!int result;

                trySegmentIntersectionOverlap(
                    Segment2!int.init,
                    Segment2!int.init,
                    result
                );
            }
        )
    );

    static assert(
        __traits(
            compiles,
            {
                Segment2!long result;

                trySegmentIntersectionOverlap(
                    Segment2!long.init,
                    Segment2!long.init,
                    result
                );
            }
        )
    );

    static assert(
        __traits(
            compiles,
            {
                Segment2!float result;

                trySegmentIntersectionOverlap(
                    Segment2!float.init,
                    Segment2!float.init,
                    result
                );
            }
        )
    );

    static assert(
        __traits(
            compiles,
            {
                Segment2!double result;

                trySegmentIntersectionOverlap(
                    Segment2!double.init,
                    Segment2!double.init,
                    result
                );
            }
        )
    );

    static assert(
        !__traits(
            compiles,
            {
                Segment2!real result;

                trySegmentIntersectionOverlap(
                    Segment2!real.init,
                    Segment2!real.init,
                    result
                );
            }
        )
    );


    /*
     * Independent exhaustive collinear oracle.
     *
     * The expected result is computed solely from one-dimensional
     * parameter intervals. Geometry is then embedded into four
     * differently oriented supporting lines.
     *
     * The parameter range includes degenerate segments, disjoint
     * intervals, endpoint contact, containment and positive-length
     * overlap.
     */
    {
        enum int[] parameters = [
            -4, -3, -2, -1, 0,
             1,  2,  3,  4
        ];

        foreach (family; 0 .. 4)
        {
            foreach (firstA; parameters)
            foreach (firstB; parameters)
            foreach (secondA; parameters)
            foreach (secondB; parameters)
            {
                const auto expected =
                    intervalIntersectionOracle(
                        firstA,
                        firstB,
                        secondA,
                        secondB
                    );

                const Segment2!int first =
                    Segment2!int(
                        collinearOraclePoint(
                            family,
                            firstA
                        ),
                        collinearOraclePoint(
                            family,
                            firstB
                        )
                    );

                const Segment2!int second =
                    Segment2!int(
                        collinearOraclePoint(
                            family,
                            secondA
                        ),
                        collinearOraclePoint(
                            family,
                            secondB
                        )
                    );

                assert(
                    segmentIntersectionKind(
                        first,
                        second
                    ) == expected
                );
            }
        }
    }


    /*
     * Deterministic general-geometry invariant sweep.
     *
     * This does not assume an expected classification. Instead it tests
     * semantic invariants that must hold for every pair of segments:
     *
     * - argument symmetry;
     * - endpoint-order invariance;
     * - self-intersection semantics.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;
        alias K = SegmentIntersectionKind;

        ulong state =
            0x8f3f_73b5_cf1c_9adeUL;

        foreach (_; 0 .. 512)
        {
            const S first =
                S(
                    P(
                        randomIntersectionCoordinate(
                            state
                        ),
                        randomIntersectionCoordinate(
                            state
                        )
                    ),
                    P(
                        randomIntersectionCoordinate(
                            state
                        ),
                        randomIntersectionCoordinate(
                            state
                        )
                    )
                );

            const S second =
                S(
                    P(
                        randomIntersectionCoordinate(
                            state
                        ),
                        randomIntersectionCoordinate(
                            state
                        )
                    ),
                    P(
                        randomIntersectionCoordinate(
                            state
                        ),
                        randomIntersectionCoordinate(
                            state
                        )
                    )
                );

            const S reverseFirst =
                S(
                    first.b,
                    first.a
                );

            const S reverseSecond =
                S(
                    second.b,
                    second.a
                );

            const K expected =
                segmentIntersectionKind(
                    first,
                    second
                );

            assert(
                segmentIntersectionKind(
                    second,
                    first
                ) == expected
            );

            assert(
                segmentIntersectionKind(
                    reverseFirst,
                    second
                ) == expected
            );

            assert(
                segmentIntersectionKind(
                    first,
                    reverseSecond
                ) == expected
            );

            assert(
                segmentIntersectionKind(
                    reverseFirst,
                    reverseSecond
                ) == expected
            );

            assert(
                segmentIntersectionKind(
                    second,
                    reverseFirst
                ) == expected
            );

            const K selfExpected =
                first.a == first.b
                    ? K.point
                    : K.overlap;

            assert(
                segmentIntersectionKind(
                    first,
                    first
                ) == selfExpected
            );

            assert(
                segmentIntersectionKind(
                    first,
                    reverseFirst
                ) == selfExpected
            );
        }
    }


    /*
     * Near-collinear binary64 proper crossing.
     *
     * The two endpoints of the vertical segment lie one binary64 step
     * on opposite sides of the diagonal at x = 5.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;
        alias K = SegmentIntersectionKind;

        enum double below =
            0x1.3ffffffffffffp+2;

        enum double above =
            0x1.4000000000001p+2;

        const S diagonal =
            S(
                P(0.0, 0.0),
                P(10.0, 10.0)
            );

        const S needle =
            S(
                P(5.0, below),
                P(5.0, above)
            );

        assert(
            segmentIntersectionKind(
                diagonal,
                needle
            ) == K.point
        );

        assert(
            segmentIntersectionKind(
                needle,
                diagonal
            ) == K.point
        );
    }


    /*
     * Near-collinear binary32 proper crossing.
     *
     * Promotion to the binary64 predicate backend must preserve the
     * two binary32 values exactly.
     */
    {
        alias P = Point2!float;
        alias S = Segment2!float;
        alias K = SegmentIntersectionKind;

        enum float below =
            0x1.fffffep-1f;

        enum float above =
            0x1.000002p+0f;

        const S diagonal =
            S(
                P(0.0f, 0.0f),
                P(2.0f, 2.0f)
            );

        const S needle =
            S(
                P(1.0f, below),
                P(1.0f, above)
            );

        assert(
            segmentIntersectionKind(
                diagonal,
                needle
            ) == K.point
        );
    }


    /*
     * Full-range binary64 near-collinear crossing.
     *
     * This configuration lies well outside the conservative expansion
     * backend working range and therefore exercises the complete robust
     * orientation pipeline, including the full-range exact fallback.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;
        alias K = SegmentIntersectionKind;

        enum double large =
            0x1p+500;

        enum double half =
            0x1p+499;

        enum double below =
            0x1.fffffffffffffp+498;

        enum double above =
            0x1.0000000000001p+499;

        const S diagonal =
            S(
                P(0.0, 0.0),
                P(large, large)
            );

        const S needle =
            S(
                P(half, below),
                P(half, above)
            );

        assert(
            segmentIntersectionKind(
                diagonal,
                needle
            ) == K.point
        );

        const S reverseDiagonal =
            S(
                diagonal.b,
                diagonal.a
            );

        const S reverseNeedle =
            S(
                needle.b,
                needle.a
            );

        assert(
            segmentIntersectionKind(
                reverseDiagonal,
                reverseNeedle
            ) == K.point
        );
    }


    /*
     * Subnormal collinear overlap.
     *
     * All coordinates are exact binary64 subnormals. The mathematical
     * orientation determinants underflow ordinary binary64 arithmetic,
     * but topological classification must remain exact.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;
        alias K = SegmentIntersectionKind;

        enum double one =
            0x0.0000000000001p-1022;

        enum double two =
            0x0.0000000000002p-1022;

        enum double four =
            0x0.0000000000004p-1022;

        enum double six =
            0x0.0000000000006p-1022;

        const S first =
            S(
                P(0.0, 0.0),
                P(four, four)
            );

        const S second =
            S(
                P(two, two),
                P(six, six)
            );

        assert(one > 0.0);

        assert(
            segmentIntersectionKind(
                first,
                second
            ) == K.overlap
        );
    }


    /*
     * Extreme finite binary64 collinear containment.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;
        alias K = SegmentIntersectionKind;

        const S outer =
            S(
                P(
                    -double.max,
                    -double.max
                ),
                P(
                    double.max,
                    double.max
                )
            );

        const S inner =
            S(
                P(-1.0, -1.0),
                P( 1.0,  1.0)
            );

        assert(
            segmentIntersectionKind(
                outer,
                inner
            ) == K.overlap
        );

        assert(
            segmentIntersectionKind(
                inner,
                outer
            ) == K.overlap
        );
    }


    alias P = Point2!int;
    alias S = Segment2!int;
    alias K = SegmentIntersectionKind;


    /*
     * Proper crossing.
     */
    {
        const S a =
            S(
                P(0, 0),
                P(10, 10)
            );

        const S b =
            S(
                P(0, 10),
                P(10, 0)
            );

        assert(
            segmentIntersectionKind(a, b) ==
            K.point
        );
    }


    /*
     * Parallel non-collinear segments.
     */
    {
        const S a =
            S(
                P(0, 0),
                P(10, 0)
            );

        const S b =
            S(
                P(0, 1),
                P(10, 1)
            );

        assert(
            segmentIntersectionKind(a, b) ==
            K.none
        );
    }


    /*
     * Shared endpoint.
     */
    {
        const S a =
            S(
                P(0, 0),
                P(5, 0)
            );

        const S b =
            S(
                P(5, 0),
                P(8, 4)
            );

        assert(
            segmentIntersectionKind(a, b) ==
            K.point
        );
    }


    /*
     * Endpoint touches the interior of the other segment.
     */
    {
        const S horizontal =
            S(
                P(0, 0),
                P(10, 0)
            );

        const S vertical =
            S(
                P(5, 0),
                P(5, 5)
            );

        assert(
            segmentIntersectionKind(
                horizontal,
                vertical
            ) == K.point
        );
    }


    /*
     * Collinear disjoint.
     */
    {
        const S a =
            S(
                P(0, 0),
                P(4, 0)
            );

        const S b =
            S(
                P(5, 0),
                P(10, 0)
            );

        assert(
            segmentIntersectionKind(a, b) ==
            K.none
        );
    }


    /*
     * Collinear single-point contact.
     */
    {
        const S a =
            S(
                P(0, 0),
                P(5, 0)
            );

        const S b =
            S(
                P(5, 0),
                P(10, 0)
            );

        assert(
            segmentIntersectionKind(a, b) ==
            K.point
        );
    }


    /*
     * Partial collinear overlap.
     */
    {
        const S a =
            S(
                P(0, 0),
                P(8, 0)
            );

        const S b =
            S(
                P(5, 0),
                P(10, 0)
            );

        assert(
            segmentIntersectionKind(a, b) ==
            K.overlap
        );
    }


    /*
     * Complete containment.
     */
    {
        const S outer =
            S(
                P(0, 0),
                P(10, 10)
            );

        const S inner =
            S(
                P(3, 3),
                P(7, 7)
            );

        assert(
            segmentIntersectionKind(
                outer,
                inner
            ) == K.overlap
        );
    }


    /*
     * Identical and reversed-identical non-degenerate segments.
     */
    {
        const S a =
            S(
                P(-3, 2),
                P(7, 12)
            );

        const S same =
            S(
                P(-3, 2),
                P(7, 12)
            );

        const S reversed =
            S(
                P(7, 12),
                P(-3, 2)
            );

        assert(
            segmentIntersectionKind(
                a,
                same
            ) == K.overlap
        );

        assert(
            segmentIntersectionKind(
                a,
                reversed
            ) == K.overlap
        );
    }


    /*
     * Degenerate point segment on a non-degenerate segment.
     */
    {
        const S pointSegment =
            S(
                P(5, 5),
                P(5, 5)
            );

        const S lineSegment =
            S(
                P(0, 0),
                P(10, 10)
            );

        assert(
            segmentIntersectionKind(
                pointSegment,
                lineSegment
            ) == K.point
        );
    }


    /*
     * Degenerate point segment outside the other segment.
     */
    {
        const S pointSegment =
            S(
                P(20, 20),
                P(20, 20)
            );

        const S lineSegment =
            S(
                P(0, 0),
                P(10, 10)
            );

        assert(
            segmentIntersectionKind(
                pointSegment,
                lineSegment
            ) == K.none
        );
    }


    /*
     * Equal and unequal point segments.
     */
    {
        const S a =
            S(
                P(3, 4),
                P(3, 4)
            );

        const S equal =
            S(
                P(3, 4),
                P(3, 4)
            );

        const S different =
            S(
                P(3, 5),
                P(3, 5)
            );

        assert(
            segmentIntersectionKind(
                a,
                equal
            ) == K.point
        );

        assert(
            segmentIntersectionKind(
                a,
                different
            ) == K.none
        );
    }


    /*
     * Vertical collinear overlap exercises the y fallback of
     * lexicographic ordering.
     */
    {
        const S a =
            S(
                P(4, -10),
                P(4, 10)
            );

        const S b =
            S(
                P(4, 5),
                P(4, 20)
            );

        assert(
            segmentIntersectionKind(a, b) ==
            K.overlap
        );
    }


    /*
     * Negative-slope collinear overlap.
     */
    {
        const S a =
            S(
                P(0, 10),
                P(10, 0)
            );

        const S b =
            S(
                P(3, 7),
                P(20, -10)
            );

        assert(
            segmentIntersectionKind(a, b) ==
            K.overlap
        );
    }


    /*
     * Symmetry and endpoint-order invariance.
     */
    {
        const S a =
            S(
                P(-5, -5),
                P(10, 10)
            );

        const S b =
            S(
                P(-5, 10),
                P(10, -5)
            );

        const S reverseA =
            S(a.b, a.a);

        const S reverseB =
            S(b.b, b.a);

        const K expected =
            segmentIntersectionKind(
                a,
                b
            );

        assert(expected == K.point);

        assert(
            segmentIntersectionKind(
                b,
                a
            ) == expected
        );

        assert(
            segmentIntersectionKind(
                reverseA,
                b
            ) == expected
        );

        assert(
            segmentIntersectionKind(
                a,
                reverseB
            ) == expected
        );

        assert(
            segmentIntersectionKind(
                reverseA,
                reverseB
            ) == expected
        );
    }


    /*
     * Scalar-domain compile contract.
     */
    static assert(
        __traits(
            compiles,
            segmentIntersectionKind(
                Segment2!int.init,
                Segment2!int.init
            )
        )
    );

    static assert(
        __traits(
            compiles,
            segmentIntersectionKind(
                Segment2!long.init,
                Segment2!long.init
            )
        )
    );

    static assert(
        __traits(
            compiles,
            segmentIntersectionKind(
                Segment2!float.init,
                Segment2!float.init
            )
        )
    );

    static assert(
        __traits(
            compiles,
            segmentIntersectionKind(
                Segment2!double.init,
                Segment2!double.init
            )
        )
    );

    static assert(
        !__traits(
            compiles,
            segmentIntersectionKind(
                Segment2!real.init,
                Segment2!real.init
            )
        )
    );


    /*
     * Basic runtime coverage of every supported scalar backend.
     */
    assert(
        segmentIntersectionKind(
            Segment2!long(
                Point2!long(0, 0),
                Point2!long(4, 4)
            ),
            Segment2!long(
                Point2!long(0, 4),
                Point2!long(4, 0)
            )
        ) == K.point
    );

    assert(
        segmentIntersectionKind(
            Segment2!float(
                Point2!float(0.0f, 0.0f),
                Point2!float(4.0f, 4.0f)
            ),
            Segment2!float(
                Point2!float(0.0f, 4.0f),
                Point2!float(4.0f, 0.0f)
            )
        ) == K.point
    );

    assert(
        segmentIntersectionKind(
            Segment2!double(
                Point2!double(0.0, 0.0),
                Point2!double(4.0, 4.0)
            ),
            Segment2!double(
                Point2!double(0.0, 4.0),
                Point2!double(4.0, 0.0)
            )
        ) == K.point
    );


    /*
     * Full-range integer coordinates exercise the robust orientation
     * backend rather than widened ordinary arithmetic.
     */
    {
        alias L = long;
        alias LP = Point2!L;
        alias LS = Segment2!L;

        const LS horizontal =
            LS(
                LP(L.min, 0),
                LP(L.max, 0)
            );

        const LS vertical =
            LS(
                LP(0, L.min),
                LP(0, L.max)
            );

        assert(
            segmentIntersectionKind(
                horizontal,
                vertical
            ) == K.point
        );
    }


    /*
     * Full-range finite binary64 crossing.
     */
    {
        alias DP = Point2!double;
        alias DS = Segment2!double;

        const DS horizontal =
            DS(
                DP(-double.max, 0.0),
                DP( double.max, 0.0)
            );

        const DS vertical =
            DS(
                DP(0.0, -double.max),
                DP(0.0,  double.max)
            );

        assert(
            segmentIntersectionKind(
                horizontal,
                vertical
            ) == K.point
        );
    }


    /*
     * Subnormal binary64 coordinates remain valid predicate inputs.
     */
    {
        enum double tiny =
            0x0.0000000000001p-1022;

        alias DP = Point2!double;
        alias DS = Segment2!double;

        assert(
            segmentIntersectionKind(
                DS(
                    DP(0.0, 0.0),
                    DP(tiny, tiny)
                ),
                DS(
                    DP(0.0, tiny),
                    DP(tiny, 0.0)
                )
            ) == K.point
        );
    }
}
