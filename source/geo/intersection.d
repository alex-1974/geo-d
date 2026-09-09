module geo.intersection;

import geo.orientation :
    Orientation,
    orientation;

import geo.point :
    Point2;

import geo.segment :
    Segment2;


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
    none,
    point,
    overlap
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
        ) != Orientation.collinear
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
 * True only for strict left/right opposition.
 *
 * Collinearity is deliberately not treated as opposite-side contact.
 */
private bool oppositeSides(
    Orientation lhs,
    Orientation rhs
)
    pure nothrow @safe @nogc
{
    return
        (
            lhs == Orientation.left &&
            rhs == Orientation.right
        ) ||
        (
            lhs == Orientation.right &&
            rhs == Orientation.left
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
 * For floating-point coordinates all endpoint coordinates must be
 * finite.
 *
 * The operation returns only topology. It deliberately does not
 * construct an intersection coordinate.
 *
 * Degenerate segments are valid and represent a point.
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
     * Handle point-segments first.
     *
     * This avoids imposing ordinary non-degenerate segment assumptions
     * on the orientation logic below.
     */
    if (firstDegenerate)
    {
        return pointOnSegment(
            first.a,
            second
        )
            ? SegmentIntersectionKind.point
            : SegmentIntersectionKind.none;
    }

    if (secondDegenerate)
    {
        return pointOnSegment(
            second.a,
            first
        )
            ? SegmentIntersectionKind.point
            : SegmentIntersectionKind.none;
    }


    const Orientation o1 =
        orientation(
            first.a,
            first.b,
            second.a
        );

    const Orientation o2 =
        orientation(
            first.a,
            first.b,
            second.b
        );

    const Orientation o3 =
        orientation(
            second.a,
            second.b,
            first.a
        );

    const Orientation o4 =
        orientation(
            second.a,
            second.b,
            first.b
        );


    /*
     * Complete collinearity is the only case that may yield an overlap
     * of positive length.
     */
    if (
        o1 == Orientation.collinear &&
        o2 == Orientation.collinear &&
        o3 == Orientation.collinear &&
        o4 == Orientation.collinear
    )
    {
        return classifyCollinear(
            first,
            second
        );
    }


    /*
     * Closed-segment boundary contacts.
     */
    if (
        o1 == Orientation.collinear &&
        pointInClosedCollinearInterval(
            second.a,
            first.a,
            first.b
        )
    )
    {
        return SegmentIntersectionKind.point;
    }

    if (
        o2 == Orientation.collinear &&
        pointInClosedCollinearInterval(
            second.b,
            first.a,
            first.b
        )
    )
    {
        return SegmentIntersectionKind.point;
    }

    if (
        o3 == Orientation.collinear &&
        pointInClosedCollinearInterval(
            first.a,
            second.a,
            second.b
        )
    )
    {
        return SegmentIntersectionKind.point;
    }

    if (
        o4 == Orientation.collinear &&
        pointInClosedCollinearInterval(
            first.b,
            second.a,
            second.b
        )
    )
    {
        return SegmentIntersectionKind.point;
    }


    /*
     * Proper crossing:
     *
     * each segment's endpoints lie strictly on opposite sides of the
     * other segment's supporting line.
     */
    if (
        oppositeSides(o1, o2) &&
        oppositeSides(o3, o4)
    )
    {
        return SegmentIntersectionKind.point;
    }

    return SegmentIntersectionKind.none;
}


@safe unittest
{
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
