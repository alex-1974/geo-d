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


/**
 * Constructs the positive-length collinear overlap of two closed
 * segments.
 *
 * Returns true exactly when:
 *
 *     segmentIntersectionKind(first, second)
 *         == SegmentIntersectionKind.overlap
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
