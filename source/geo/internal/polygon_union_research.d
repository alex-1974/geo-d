module geo.internal.polygon_union_research;

import geo.internal.dyadic :
    SignedDyadicDifference,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

import geo.intersection :
    trySegmentIntersectionOverlap;

import geo.orientation :
    Orientation2,
    orientation;

import geo.point :
    Point2;

import geo.segment :
    Segment2;


/*
 * INTERNAL RESEARCH MODULE.
 *
 * Executable design evidence for ADR-0023.
 *
 * This module is intentionally not imported by the public package and does not
 * define a public polygon-union API.
 */


/*
 * Exact direction inherited from one represented input segment.
 *
 * Components use the established signed dyadic-difference domain in units of
 * 2^-1074. No constructed overlay vertex is subtracted here.
 */
private struct ExactSourceDirection
{
    SignedDyadicDifference x;
    SignedDyadicDifference y;
}


/*
 * Builds the exact direction of an input segment.
 *
 * forward == true:
 *
 *     segment.a -> segment.b
 *
 * forward == false:
 *
 *     segment.b -> segment.a
 */
private ExactSourceDirection sourceDirection(T)(
    Segment2!T segment,
    bool forward = true
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    assert(segment.a != segment.b);

    const auto aX =
        decodeDyadicCoordinate(segment.a.x);

    const auto aY =
        decodeDyadicCoordinate(segment.a.y);

    const auto bX =
        decodeDyadicCoordinate(segment.b.x);

    const auto bY =
        decodeDyadicCoordinate(segment.b.y);

    ExactSourceDirection result;

    if (forward)
    {
        result.x =
            subtractDyadicCoordinates(
                bX,
                aX
            );

        result.y =
            subtractDyadicCoordinates(
                bY,
                aY
            );
    }
    else
    {
        result.x =
            subtractDyadicCoordinates(
                aX,
                bX
            );

        result.y =
            subtractDyadicCoordinates(
                aY,
                bY
            );
    }

    assert(
        result.x.sign != 0 ||
        result.y.sign != 0
    );

    return result;
}


/*
 * True for angles in [0, pi), using the positive x axis as angle zero.
 *
 * A direction on the negative x axis belongs to the lower half-plane.
 */
private bool upperAngularHalf(
    ref const ExactSourceDirection direction
)
    pure nothrow @safe @nogc
{
    return
        direction.y.sign > 0 ||
        (
            direction.y.sign == 0 &&
            direction.x.sign > 0
        );
}


/*
 * Exact counter-clockwise angular comparison.
 *
 * Returns:
 *
 *     -1 lhs appears before rhs from +x in [0, 2*pi)
 *      0 lhs and rhs are the same ray
 *      1 lhs appears after rhs
 *
 * The determinant uses only products of represented input-coordinate
 * differences. It therefore remains in the existing dyadic-product domain.
 */
private int compareSourceDirectionsCCW(
    ref const ExactSourceDirection lhs,
    ref const ExactSourceDirection rhs
)
    pure nothrow @safe @nogc
{
    const bool lhsUpper =
        upperAngularHalf(lhs);

    const bool rhsUpper =
        upperAngularHalf(rhs);

    if (lhsUpper != rhsUpper)
        return lhsUpper ? -1 : 1;

    const auto lhsXrhsY =
        multiplyDyadicDifferences(
            lhs.x,
            rhs.y
        );

    const auto lhsYrhsX =
        multiplyDyadicDifferences(
            lhs.y,
            rhs.x
        );

    const auto cross =
        subtractDyadicProducts(
            lhsXrhsY,
            lhsYrhsX
        );

    if (cross.sign > 0)
        return -1;

    if (cross.sign < 0)
        return 1;

    /*
     * Same half-plane plus zero cross product means the same ray.
     * Opposite rays cannot occupy the same angular half.
     */
    return 0;
}


@safe unittest
{
    import geo.point :
        Point2;

    alias P = Point2!int;
    alias S = Segment2!int;

    const P origin = P(0, 0);

    const S east =
        S(origin, P(1, 0));

    const S northEast =
        S(origin, P(1, 1));

    const S north =
        S(origin, P(0, 1));

    const S northWest =
        S(origin, P(-1, 1));

    const S west =
        S(origin, P(-1, 0));

    const S southWest =
        S(origin, P(-1, -1));

    const S south =
        S(origin, P(0, -1));

    const S southEast =
        S(origin, P(1, -1));

    auto directions = [
        sourceDirection(east),
        sourceDirection(northEast),
        sourceDirection(north),
        sourceDirection(northWest),
        sourceDirection(west),
        sourceDirection(southWest),
        sourceDirection(south),
        sourceDirection(southEast),
    ];

    foreach (i; 0 .. directions.length - 1)
    {
        assert(
            compareSourceDirectionsCCW(
                directions[i],
                directions[i + 1]
            ) < 0
        );
    }

    assert(
        compareSourceDirectionsCCW(
            directions[$ - 1],
            directions[0]
        ) > 0
    );


    /*
     * Opposite rays at a crossing/T-junction remain distinct and ordered.
     */
    {
        auto eastDirection =
            sourceDirection(east);

        auto westDirection =
            sourceDirection(east, false);

        auto northDirection =
            sourceDirection(north);

        assert(
            compareSourceDirectionsCCW(
                eastDirection,
                northDirection
            ) < 0
        );

        assert(
            compareSourceDirectionsCCW(
                northDirection,
                westDirection
            ) < 0
        );

        assert(
            compareSourceDirectionsCCW(
                eastDirection,
                westDirection
            ) < 0
        );
    }


    /*
     * Coincident same-ray source segments compare equal even when their
     * represented lengths differ.
     *
     * A production arrangement deduplicates these geometrically coincident
     * atomic edges before building the vertex rotation.
     */
    {
        const S shortEast =
            S(
                P(5, 7),
                P(6, 7)
            );

        const S longEast =
            S(
                P(-100, -9),
                P(300, -9)
            );

        auto shortDirection =
            sourceDirection(shortEast);

        auto longDirection =
            sourceDirection(longEast);

        assert(
            compareSourceDirectionsCCW(
                shortDirection,
                longDirection
            ) == 0
        );
    }
}


@safe unittest
{
    import geo.point :
        Point2;

    /*
     * Full-range long directions exercise signed subtraction beyond long.
     */
    {
        alias P = Point2!long;
        alias S = Segment2!long;

        const S east =
            S(
                P(long.min, 0),
                P(long.max, 0)
            );

        const S north =
            S(
                P(0, long.min),
                P(0, long.max)
            );

        auto eastDirection =
            sourceDirection(east);

        auto northDirection =
            sourceDirection(north);

        assert(
            compareSourceDirectionsCCW(
                eastDirection,
                northDirection
            ) < 0
        );

        auto westDirection =
            sourceDirection(east, false);

        assert(
            compareSourceDirectionsCCW(
                northDirection,
                westDirection
            ) < 0
        );
    }


    /*
     * Full-range finite binary64 directions remain exact without floating
     * subtraction or multiplication overflow.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;

        const S east =
            S(
                P(-double.max, 0.0),
                P(double.max, 0.0)
            );

        const S north =
            S(
                P(0.0, -double.max),
                P(0.0, double.max)
            );

        const S northEast =
            S(
                P(-double.max, -double.max),
                P(double.max, double.max)
            );

        auto eastDirection =
            sourceDirection(east);

        auto northEastDirection =
            sourceDirection(northEast);

        auto northDirection =
            sourceDirection(north);

        assert(
            compareSourceDirectionsCCW(
                eastDirection,
                northEastDirection
            ) < 0
        );

        assert(
            compareSourceDirectionsCCW(
                northEastDirection,
                northDirection
            ) < 0
        );
    }


    /*
     * One-ULP direction distinctions remain exact.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;

        const S lower =
            S(
                P(0.0, 0.0),
                P(1.0, 1.0)
            );

        const S upper =
            S(
                P(0.0, 0.0),
                P(1.0, 0x1.0000000000001p+0)
            );

        auto lowerDirection =
            sourceDirection(lower);

        auto upperDirection =
            sourceDirection(upper);

        assert(
            compareSourceDirectionsCCW(
                lowerDirection,
                upperDirection
            ) < 0
        );
    }
}



private enum ubyte operandABoundary = 1;
private enum ubyte operandBBoundary = 2;


private struct CollinearAtomicSpan(T)
{
    Segment2!T segment;
    ubyte operandMask;
}


/*
 * Exact lexicographic ordering for finite represented input points.
 *
 * Collinear overlap endpoints are input endpoints, so no constructed
 * coordinate participates in this ordering.
 */
private int compareRepresentedPoints(T)(
    Point2!T lhs,
    Point2!T rhs
)
    pure nothrow @safe @nogc
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
 * Research-only collinear noding for one segment from each operand.
 *
 * The four represented endpoints are sorted exactly, consecutive non-empty
 * intervals are tested against both source segments, and each atomic interval
 * records the operand-boundary membership mask.
 *
 * This is deliberately a semantic probe, not the production overlay noder.
 */
private size_t buildCollinearAtomicSpans(T)(
    Segment2!T first,
    Segment2!T second,
    out CollinearAtomicSpan!T[3] spans
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    assert(first.a != first.b);
    assert(second.a != second.b);

    assert(
        orientation(
            first.a,
            first.b,
            second.a
        ) == Orientation2.collinear
    );

    assert(
        orientation(
            first.a,
            first.b,
            second.b
        ) == Orientation2.collinear
    );

    Point2!T[4] endpoints = [
        first.a,
        first.b,
        second.a,
        second.b,
    ];

    foreach (i; 1 .. endpoints.length)
    {
        const Point2!T value =
            endpoints[i];

        size_t j = i;

        while (
            j > 0 &&
            compareRepresentedPoints(
                value,
                endpoints[j - 1]
            ) < 0
        )
        {
            endpoints[j] =
                endpoints[j - 1];

            --j;
        }

        endpoints[j] = value;
    }

    Point2!T[4] uniqueEndpoints;
    size_t uniqueCount = 0;

    foreach (point; endpoints)
    {
        if (
            uniqueCount == 0 ||
            compareRepresentedPoints(
                uniqueEndpoints[uniqueCount - 1],
                point
            ) != 0
        )
        {
            uniqueEndpoints[uniqueCount++] =
                point;
        }
    }

    size_t count = 0;

    foreach (i; 0 .. uniqueCount - 1)
    {
        const Segment2!T candidate =
            Segment2!T(
                uniqueEndpoints[i],
                uniqueEndpoints[i + 1]
            );

        if (candidate.a == candidate.b)
            continue;

        ubyte mask = 0;
        Segment2!T overlap;

        if (
            trySegmentIntersectionOverlap(
                candidate,
                first,
                overlap
            ) &&
            overlap == candidate
        )
        {
            mask |= operandABoundary;
        }

        if (
            trySegmentIntersectionOverlap(
                candidate,
                second,
                overlap
            ) &&
            overlap == candidate
        )
        {
            mask |= operandBBoundary;
        }

        if (mask == 0)
            continue;

        assert(count < spans.length);

        spans[count++] =
            CollinearAtomicSpan!T(
                candidate,
                mask
            );
    }

    return count;
}


@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;
    alias A = CollinearAtomicSpan!int;

    enum ubyte both =
        operandABoundary |
        operandBBoundary;


    /*
     * Identical shared edge: source direction does not affect membership.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(4, 0)
            );

        const S second =
            S(
                P(0, 0),
                P(4, 0)
            );

        A[3] spans;

        const size_t count =
            buildCollinearAtomicSpans(
                first,
                second,
                spans
            );

        assert(count == 1);
        assert(spans[0].segment == first);
        assert(spans[0].operandMask == both);


        A[3] reverseSpans;

        const size_t reverseCount =
            buildCollinearAtomicSpans(
                first,
                S(second.b, second.a),
                reverseSpans
            );

        assert(reverseCount == 1);
        assert(reverseSpans[0].segment == first);
        assert(reverseSpans[0].operandMask == both);
    }


    /*
     * Partial overlap:
     *
     *     A: 0-----------4
     *     B:       2-----------6
     *
     * Atomic membership becomes A / AB / B.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(4, 0)
            );

        const S second =
            S(
                P(2, 0),
                P(6, 0)
            );

        A[3] spans;

        const size_t count =
            buildCollinearAtomicSpans(
                first,
                second,
                spans
            );

        assert(count == 3);

        assert(
            spans[0] ==
            A(
                S(
                    P(0, 0),
                    P(2, 0)
                ),
                operandABoundary
            )
        );

        assert(
            spans[1] ==
            A(
                S(
                    P(2, 0),
                    P(4, 0)
                ),
                both
            )
        );

        assert(
            spans[2] ==
            A(
                S(
                    P(4, 0),
                    P(6, 0)
                ),
                operandBBoundary
            )
        );
    }


    /*
     * One source interval contained in the other:
     *
     * Atomic membership becomes A / AB / A.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const S second =
            S(
                P(3, 0),
                P(7, 0)
            );

        A[3] spans;

        const size_t count =
            buildCollinearAtomicSpans(
                first,
                second,
                spans
            );

        assert(count == 3);
        assert(spans[0].operandMask == operandABoundary);
        assert(spans[1].operandMask == both);
        assert(spans[2].operandMask == operandABoundary);

        assert(
            spans[1].segment ==
            S(
                P(3, 0),
                P(7, 0)
            )
        );
    }


    /*
     * Endpoint-only contact creates one shared vertex but no AB edge.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(2, 0)
            );

        const S second =
            S(
                P(2, 0),
                P(4, 0)
            );

        A[3] spans;

        const size_t count =
            buildCollinearAtomicSpans(
                first,
                second,
                spans
            );

        assert(count == 2);
        assert(spans[0].operandMask == operandABoundary);
        assert(spans[1].operandMask == operandBBoundary);
        assert(spans[0].segment.b == spans[1].segment.a);
    }


    /*
     * Vertical collinear overlap uses the same endpoint-only noding model.
     */
    {
        const S first =
            S(
                P(5, -4),
                P(5, 4)
            );

        const S second =
            S(
                P(5, 1),
                P(5, 9)
            );

        A[3] spans;

        const size_t count =
            buildCollinearAtomicSpans(
                first,
                second,
                spans
            );

        assert(count == 3);

        assert(
            spans[1] ==
            A(
                S(
                    P(5, 1),
                    P(5, 4)
                ),
                both
            )
        );
    }
}
