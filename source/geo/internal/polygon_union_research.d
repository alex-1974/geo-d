module geo.internal.polygon_union_research;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    SignedDyadicDifference,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

import geo.internal.exact_coordinate :
    SignedExactCoordinateNumerator,
    compareExactCoordinates;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind,
    trySegmentIntersectionOverlap,
    trySegmentTouchPoint;

import geo.orientation :
    Orientation2,
    orientation;

import geo.linear_ring_view :
    LinearRing2View;

import geo.point :
    Point2;

import geo.point_in_polygon :
    PointPolygonLocation,
    tryClassifyPointInPolygon;

import geo.polygon_view :
    Polygon2View;

import geo.segment :
    Segment2;

import std.exception :
    assumeUnique;

import geo.topology_validation :
    validatePolygon,
    validateRing;


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



private struct RegionLabel
{
    bool insideA;
    bool insideB;
}


private struct RegionTransition
{
    size_t firstCell;
    size_t secondCell;
    ubyte operandMask;
}


/*
 * Crossing one exact atomic arrangement edge toggles the inside parity for
 * every operand whose boundary contributes to that edge.
 */
private RegionLabel crossBoundary(
    RegionLabel source,
    ubyte operandMask
)
    pure nothrow @safe @nogc
{
    assert(
        (
            operandMask &
            ~(
                operandABoundary |
                operandBBoundary
            )
        ) == 0
    );

    if (
        (
            operandMask &
            operandABoundary
        ) != 0
    )
    {
        source.insideA =
            !source.insideA;
    }

    if (
        (
            operandMask &
            operandBBoundary
        ) != 0
    )
    {
        source.insideB =
            !source.insideB;
    }

    return source;
}


private bool unionInterior(
    RegionLabel label
)
    pure nothrow @safe @nogc
{
    return
        label.insideA ||
        label.insideB;
}


private bool unionBoundaryBetween(
    RegionLabel first,
    RegionLabel second
)
    pure nothrow @safe @nogc
{
    return
        unionInterior(first) !=
        unionInterior(second);
}


/*
 * Research-only exact parity propagation over an already constructed dual
 * arrangement graph.
 *
 * Cell zero is the unbounded exterior and is seeded as outside both operands.
 *
 * The graph itself is topological: no coordinate arithmetic participates in
 * region propagation. Boundary membership masks are exact consequences of
 * noding/source provenance.
 *
 * Repeated relaxation is intentionally simple. Production code may use a
 * queue/stack traversal once the arrangement representation is selected.
 */
private bool tryPropagateRegionLabels(
    scope const(RegionTransition)[] transitions,
    scope RegionLabel[] labels,
    scope bool[] assigned
)
    pure nothrow @safe @nogc
{
    if (
        labels.length == 0 ||
        assigned.length != labels.length
    )
    {
        return false;
    }

    foreach (i; 0 .. labels.length)
    {
        labels[i] =
            RegionLabel.init;

        assigned[i] = false;
    }

    assigned[0] = true;

    bool changed;

    do
    {
        changed = false;

        foreach (transition; transitions)
        {
            if (
                transition.firstCell >= labels.length ||
                transition.secondCell >= labels.length ||
                transition.operandMask == 0 ||
                (
                    transition.operandMask &
                    ~(
                        operandABoundary |
                        operandBBoundary
                    )
                ) != 0
            )
            {
                return false;
            }

            const bool firstAssigned =
                assigned[
                    transition.firstCell
                ];

            const bool secondAssigned =
                assigned[
                    transition.secondCell
                ];

            if (
                firstAssigned &&
                !secondAssigned
            )
            {
                labels[
                    transition.secondCell
                ] =
                    crossBoundary(
                        labels[
                            transition.firstCell
                        ],
                        transition.operandMask
                    );

                assigned[
                    transition.secondCell
                ] = true;

                changed = true;
            }
            else if (
                !firstAssigned &&
                secondAssigned
            )
            {
                labels[
                    transition.firstCell
                ] =
                    crossBoundary(
                        labels[
                            transition.secondCell
                        ],
                        transition.operandMask
                    );

                assigned[
                    transition.firstCell
                ] = true;

                changed = true;
            }
            else if (
                firstAssigned &&
                secondAssigned
            )
            {
                if (
                    crossBoundary(
                        labels[
                            transition.firstCell
                        ],
                        transition.operandMask
                    ) !=
                    labels[
                        transition.secondCell
                    ]
                )
                {
                    return false;
                }
            }
        }
    }
    while (changed);

    foreach (isAssigned; assigned)
    {
        if (!isAssigned)
            return false;
    }

    return true;
}


@safe unittest
{
    alias T = RegionTransition;

    enum ubyte both =
        operandABoundary |
        operandBBoundary;


    /*
     * Disjoint arrangement components share one unbounded exterior face.
     *
     *     cell 0 = outside both
     *     cell 1 = inside A
     *     cell 2 = inside B
     */
    {
        const T[2] transitions = [
            T(0, 1, operandABoundary),
            T(0, 2, operandBBoundary),
        ];

        RegionLabel[3] labels;
        bool[3] assigned;

        assert(
            tryPropagateRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        assert(
            labels[0] ==
            RegionLabel(false, false)
        );

        assert(
            labels[1] ==
            RegionLabel(true, false)
        );

        assert(
            labels[2] ==
            RegionLabel(false, true)
        );

        assert(
            unionBoundaryBetween(
                labels[0],
                labels[1]
            )
        );

        assert(
            unionBoundaryBetween(
                labels[0],
                labels[2]
            )
        );
    }


    /*
     * B nested strictly inside A with no boundary intersection:
     *
     *     outside --A--> A-only --B--> A+B
     *
     * The B boundary is not a union boundary because both adjacent cells are
     * inside the union.
     */
    {
        const T[2] transitions = [
            T(0, 1, operandABoundary),
            T(1, 2, operandBBoundary),
        ];

        RegionLabel[3] labels;
        bool[3] assigned;

        assert(
            tryPropagateRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        assert(
            labels[1] ==
            RegionLabel(true, false)
        );

        assert(
            labels[2] ==
            RegionLabel(true, true)
        );

        assert(
            !unionBoundaryBetween(
                labels[1],
                labels[2]
            )
        );
    }


    /*
     * Ordinary overlap has all four parity cells.
     *
     * The transition cycle must be algebraically consistent.
     */
    {
        const T[4] transitions = [
            T(0, 1, operandABoundary),
            T(0, 2, operandBBoundary),
            T(1, 3, operandBBoundary),
            T(2, 3, operandABoundary),
        ];

        RegionLabel[4] labels;
        bool[4] assigned;

        assert(
            tryPropagateRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        assert(
            labels[0] ==
            RegionLabel(false, false)
        );

        assert(
            labels[1] ==
            RegionLabel(true, false)
        );

        assert(
            labels[2] ==
            RegionLabel(false, true)
        );

        assert(
            labels[3] ==
            RegionLabel(true, true)
        );

        assert(
            !unionBoundaryBetween(
                labels[1],
                labels[3]
            )
        );

        assert(
            !unionBoundaryBetween(
                labels[2],
                labels[3]
            )
        );
    }


    /*
     * Identical boundaries toggle both operand parities together.
     */
    {
        const T[1] transitions = [
            T(0, 1, both),
        ];

        RegionLabel[2] labels;
        bool[2] assigned;

        assert(
            tryPropagateRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        assert(
            labels[1] ==
            RegionLabel(true, true)
        );

        assert(
            unionBoundaryBetween(
                labels[0],
                labels[1]
            )
        );
    }


    /*
     * Adjacent polygons sharing an edge:
     *
     *     outside --A--> A-only
     *     outside --B--> B-only
     *     A-only --AB--> B-only
     *
     * The shared AB edge separates two union-interior cells and is therefore
     * removed from the union boundary.
     */
    {
        const T[3] transitions = [
            T(0, 1, operandABoundary),
            T(0, 2, operandBBoundary),
            T(1, 2, both),
        ];

        RegionLabel[3] labels;
        bool[3] assigned;

        assert(
            tryPropagateRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        assert(
            labels[1] ==
            RegionLabel(true, false)
        );

        assert(
            labels[2] ==
            RegionLabel(false, true)
        );

        assert(
            !unionBoundaryBetween(
                labels[1],
                labels[2]
            )
        );
    }


    /*
     * An inconsistent dual graph is detected rather than silently assigning
     * contradictory topology.
     */
    {
        const T[3] transitions = [
            T(0, 1, operandABoundary),
            T(1, 2, operandBBoundary),
            T(0, 2, operandABoundary),
        ];

        RegionLabel[3] labels;
        bool[3] assigned;

        assert(
            !tryPropagateRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );
    }
}



/*
 * Research-only local continuation rule for a union boundary cycle.
 *
 * outgoingBoundaryLeft[i] describes one outgoing arrangement half-edge in
 * exact counter-clockwise angular order around a vertex. true means that
 * this half-edge is a selected union boundary oriented with union interior on
 * its left.
 *
 * twinIndex is the outgoing twin of the selected half-edge by which the trace
 * arrived at the vertex. That twin has union interior on its right and is not
 * itself the forward continuation.
 *
 * To keep the same union-interior sector on the left, select the first
 * forward union-boundary half-edge encountered clockwise from the twin.
 *
 * Returns size_t.max when no continuation exists.
 */
private size_t nextUnionBoundaryOutgoing(
    size_t twinIndex,
    scope const(bool)[] outgoingBoundaryLeft
)
    pure nothrow @safe @nogc
{
    if (
        outgoingBoundaryLeft.length == 0 ||
        twinIndex >= outgoingBoundaryLeft.length
    )
    {
        return size_t.max;
    }

    size_t index = twinIndex;

    foreach (_; 0 .. outgoingBoundaryLeft.length - 1)
    {
        index =
            index == 0
                ? outgoingBoundaryLeft.length - 1
                : index - 1;

        if (outgoingBoundaryLeft[index])
            return index;
    }

    return size_t.max;
}


@safe unittest
{
    /*
     * Indices represent exact CCW angular order:
     *
     *     0 east
     *     1 north
     *     2 west
     *     3 south
     */


    /*
     * Ordinary corner.
     *
     * Arrival along east means the outgoing twin is west (2).
     * The next boundary is north (1).
     */
    {
        const bool[4] boundary = [
            false,
            true,
            false,
            false,
        ];

        assert(
            nextUnionBoundaryOutgoing(
                2,
                boundary[]
            ) == 1
        );
    }


    /*
     * A T-junction branch inside the union is not a selected boundary.
     *
     * The tracer skips it and continues along the next actual union edge.
     */
    {
        const bool[4] boundary = [
            true,
            false,
            false,
            false,
        ];

        assert(
            nextUnionBoundaryOutgoing(
                2,
                boundary[]
            ) == 0
        );
    }


    /*
     * Two polygon interiors touch only at the vertex.
     *
     * NE component:
     *     incoming edge has outbound twin north (1)
     *     continuation is east (0)
     *
     * SW component:
     *     incoming edge has outbound twin south (3)
     *     continuation is west (2)
     *
     * The local clockwise rule therefore keeps the two boundary cycles
     * separate instead of switching components at the shared point.
     */
    {
        const bool[4] boundary = [
            true,
            false,
            true,
            false,
        ];

        assert(
            nextUnionBoundaryOutgoing(
                1,
                boundary[]
            ) == 0
        );

        assert(
            nextUnionBoundaryOutgoing(
                3,
                boundary[]
            ) == 2
        );
    }


    /*
     * Four independent interior sectors at one exact vertex pair locally by
     * angular adjacency. The rule remains deterministic.
     */
    {
        const bool[8] boundary = [
            true,
            false,
            true,
            false,
            true,
            false,
            true,
            false,
        ];

        assert(
            nextUnionBoundaryOutgoing(
                1,
                boundary[]
            ) == 0
        );

        assert(
            nextUnionBoundaryOutgoing(
                3,
                boundary[]
            ) == 2
        );

        assert(
            nextUnionBoundaryOutgoing(
                5,
                boundary[]
            ) == 4
        );

        assert(
            nextUnionBoundaryOutgoing(
                7,
                boundary[]
            ) == 6
        );
    }


    /*
     * No selected outgoing boundary is an explicit broken-cycle condition.
     */
    {
        const bool[4] boundary;

        assert(
            nextUnionBoundaryOutgoing(
                2,
                boundary[]
            ) == size_t.max
        );
    }
}



@safe unittest
{
    /*
     * Topology-safe materialization needs more than distinct rounded
     * vertices.
     *
     * This ring is valid over exact signed-long coordinates near 2^53.
     * Converting each vertex independently to binary64 keeps all four
     * vertices distinct, but introduces a non-adjacent point contact.
     *
     * Therefore exact-vertex injectivity after rounding is necessary but not
     * sufficient. The materialized result must also pass topology checks.
     */
    enum long n =
        9_007_199_254_740_992L;

    alias LP = Point2!long;
    alias LR = LinearRing2View!long;

    LP[4] exactPoints = [
        LP(n,     n - 3),
        LP(n - 2, n - 4),
        LP(n + 3, n - 1),
        LP(n + 4, n - 2),
    ];

    const exactValidation =
        validateRing(
            LR(exactPoints[])
        );

    assert(exactValidation.valid);


    alias DP = Point2!double;
    alias DR = LinearRing2View!double;

    DP[4] roundedPoints;

    foreach (i; 0 .. exactPoints.length)
    {
        roundedPoints[i] =
            DP(
                cast(double)
                    exactPoints[i].x,
                cast(double)
                    exactPoints[i].y
            );
    }

    foreach (i; 0 .. roundedPoints.length)
    {
        foreach (j; i + 1 .. roundedPoints.length)
        {
            assert(
                roundedPoints[i] !=
                roundedPoints[j]
            );
        }
    }

    const roundedValidation =
        validateRing(
            DR(roundedPoints[])
        );

    assert(!roundedValidation.valid);


    /*
     * Distinct represented integral vertices can also collapse outright
     * during construction-scalar conversion.
     */
    {
        const LP first =
            LP(
                long.max,
                0
            );

        const LP second =
            LP(
                long.max - 1,
                0
            );

        assert(first != second);

        assert(
            cast(double) first.x ==
            cast(double) second.x
        );
    }
}



/*
 * Research-only ownership prototype for variable-size polygon-union output.
 *
 * Backing arrays are immutable after construction. Copying this descriptor
 * therefore shares read-only GC-managed backing instead of deep-copying it.
 *
 * Public naming/layout are deliberately not proposed here.
 */
private struct OwnedPolygonSetResearch
{
private:
    immutable(Point2!double)[] _points;

    immutable(LinearRing2View!double)[] _rings;

    immutable(size_t)[] _componentRingOffsets;

public:
    @property size_t componentCount() const
        pure nothrow @safe @nogc
    {
        return
            _componentRingOffsets.length > 0
                ? _componentRingOffsets.length - 1
                : 0;
    }


    Polygon2View!double component(
        size_t index
    ) const
        pure nothrow @safe @nogc
    {
        assert(index < componentCount);

        const size_t begin =
            _componentRingOffsets[index];

        const size_t end =
            _componentRingOffsets[index + 1];

        return
            Polygon2View!double(
                _rings[begin .. end]
            );
    }
}


/*
 * Builds one immutable owning research result.
 *
 * points and componentRingOffsets are consumed. assumeUnique nulls the
 * mutable source slices and transfers the only mutable access path into
 * immutable backing without a second element copy.
 *
 * ringPointOffsets is caller-owned build metadata and is not retained.
 *
 * @trusted is deliberately narrow: the uniqueness proof is local because
 * the consumed arrays are required to have no mutable aliases when passed.
 * This helper is research-only and not a public contract.
 */
private OwnedPolygonSetResearch buildOwnedPolygonSetResearch(
    ref Point2!double[] points,
    scope const(size_t)[] ringPointOffsets,
    ref size_t[] componentRingOffsets
)
    @trusted
{
    assert(ringPointOffsets.length > 0);
    assert(ringPointOffsets[0] == 0);
    assert(ringPointOffsets[$ - 1] == points.length);

    foreach (i; 1 .. ringPointOffsets.length)
    {
        assert(
            ringPointOffsets[i - 1] <=
            ringPointOffsets[i]
        );
    }

    const size_t ringCount =
        ringPointOffsets.length - 1;

    assert(componentRingOffsets.length > 0);
    assert(componentRingOffsets[0] == 0);
    assert(componentRingOffsets[$ - 1] == ringCount);

    foreach (i; 1 .. componentRingOffsets.length)
    {
        assert(
            componentRingOffsets[i - 1] <=
            componentRingOffsets[i]
        );
    }

    auto frozenPoints =
        assumeUnique(points);

    assert(points is null);

    auto rings =
        new LinearRing2View!double[
            ringCount
        ];

    foreach (i; 0 .. ringCount)
    {
        rings[i] =
            LinearRing2View!double(
                frozenPoints[
                    ringPointOffsets[i] ..
                    ringPointOffsets[i + 1]
                ]
            );
    }

    auto frozenRings =
        assumeUnique(rings);

    assert(rings is null);

    auto frozenComponentRingOffsets =
        assumeUnique(
            componentRingOffsets
        );

    assert(componentRingOffsets is null);

    return
        OwnedPolygonSetResearch(
            frozenPoints,
            frozenRings,
            frozenComponentRingOffsets
        );
}


@safe unittest
{
    alias P = Point2!double;

    /*
     * Two components:
     *
     * component 0
     *     exterior + one hole
     *
     * component 1
     *     exterior only
     */
    P[] points = [
        P(0.0, 0.0),
        P(10.0, 0.0),
        P(10.0, 10.0),
        P(0.0, 10.0),

        P(2.0, 2.0),
        P(2.0, 4.0),
        P(4.0, 4.0),
        P(4.0, 2.0),

        P(20.0, 20.0),
        P(22.0, 20.0),
        P(22.0, 22.0),
        P(20.0, 22.0),
    ];

    const size_t[4] ringPointOffsets = [
        0,
        4,
        8,
        12,
    ];

    size_t[] componentRingOffsets = [
        0,
        2,
        3,
    ];

    auto result =
        buildOwnedPolygonSetResearch(
            points,
            ringPointOffsets[],
            componentRingOffsets
        );

    assert(points is null);
    assert(componentRingOffsets is null);

    assert(result.componentCount == 2);

    const auto first =
        result.component(0);

    const auto second =
        result.component(1);

    assert(first.length == 2);
    assert(first.holeCount == 1);
    assert(first.exterior.length == 4);
    assert(first.hole(0).length == 4);

    assert(second.length == 1);
    assert(second.holeCount == 0);
    assert(second.exterior.length == 4);

    assert(
        first.exterior[0] ==
        P(0.0, 0.0)
    );

    assert(
        second.exterior[2] ==
        P(22.0, 22.0)
    );


    /*
     * Ordinary descriptor copy shares immutable backing and performs no deep
     * copy.
     */
    auto copy = result;

    assert(copy._points is result._points);
    assert(copy._rings is result._rings);

    assert(
        copy._componentRingOffsets is
        result._componentRingOffsets
    );


    /*
     * A Polygon2View obtained from the result keeps references to GC-managed
     * immutable ring/point backing. Dropping the owning descriptor does not
     * create a stack-lifetime escape.
     */
    auto retainedView =
        result.component(0);

    result =
        OwnedPolygonSetResearch.init;

    assert(retainedView.length == 2);

    assert(
        retainedView.exterior[1] ==
        P(10.0, 0.0)
    );

    assert(
        retainedView.hole(0)[2] ==
        P(4.0, 4.0)
    );


    /*
     * The copied descriptor remains fully usable as well.
     */
    assert(copy.componentCount == 2);

    assert(
        copy.component(1).exterior[0] ==
        P(20.0, 20.0)
    );
}



private struct ExactOverlayPoint
{
    SignedExactCoordinateNumerator xNumerator;
    SignedExactCoordinateNumerator yNumerator;
    DyadicProductMagnitude denominator;
}


/*
 * Lifts one represented input coordinate into the common exact rational
 * construction model:
 *
 *     representedScaledInteger / 1 * 2^-1074
 */
private SignedExactCoordinateNumerator liftRepresentedCoordinate(T)(
    T value
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    const auto coordinate =
        decodeDyadicCoordinate(value);

    SignedExactCoordinateNumerator result;
    result.sign = coordinate.sign;

    foreach (i, limb; coordinate.magnitude.limb)
    {
        result.magnitude.limb[i] =
            limb;
    }

    return result;
}


private ExactOverlayPoint exactOverlayPoint(T)(
    Point2!T point
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    ExactOverlayPoint result;

    result.xNumerator =
        liftRepresentedCoordinate(
            point.x
        );

    result.yNumerator =
        liftRepresentedCoordinate(
            point.y
        );

    result.denominator.limb[0] = 1;

    return result;
}


private int compareExactOverlayPoints(
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
{
    const int xComparison =
        compareExactCoordinates(
            lhs.xNumerator,
            lhs.denominator,
            rhs.xNumerator,
            rhs.denominator
        );

    if (xComparison != 0)
        return xComparison;

    return
        compareExactCoordinates(
            lhs.yNumerator,
            lhs.denominator,
            rhs.yNumerator,
            rhs.denominator
        );
}


private size_t canonicalCycleStart(
    scope const(ExactOverlayPoint)[] cycle
)
    pure nothrow @safe @nogc
{
    assert(cycle.length > 0);

    size_t best = 0;

    foreach (i; 1 .. cycle.length)
    {
        if (
            compareExactOverlayPoints(
                cycle[i],
                cycle[best]
            ) < 0
        )
        {
            best = i;
        }
    }

    return best;
}


/*
 * Lexicographic comparison of two already interior-left oriented cycles,
 * independent of their stored starting vertex.
 */
private int compareCanonicalCycles(
    scope const(ExactOverlayPoint)[] lhs,
    scope const(ExactOverlayPoint)[] rhs
)
    pure nothrow @safe @nogc
{
    if (lhs.length == 0)
        return rhs.length == 0 ? 0 : -1;

    if (rhs.length == 0)
        return 1;

    const size_t lhsStart =
        canonicalCycleStart(lhs);

    const size_t rhsStart =
        canonicalCycleStart(rhs);

    const size_t commonLength =
        lhs.length < rhs.length
            ? lhs.length
            : rhs.length;

    foreach (offset; 0 .. commonLength)
    {
        const size_t lhsIndex =
            (
                lhsStart +
                offset
            ) %
            lhs.length;

        const size_t rhsIndex =
            (
                rhsStart +
                offset
            ) %
            rhs.length;

        const int comparison =
            compareExactOverlayPoints(
                lhs[lhsIndex],
                rhs[rhsIndex]
            );

        if (comparison != 0)
            return comparison;
    }

    if (lhs.length < rhs.length)
        return -1;

    if (lhs.length > rhs.length)
        return 1;

    return 0;
}


@safe unittest
{
    alias P = Point2!int;


    /*
     * The same represented point lifted from integral and binary64 storage
     * receives the same exact overlay identity.
     */
    {
        auto integerPoint =
            exactOverlayPoint(
                P(1, -2)
            );

        auto floatingPoint =
            exactOverlayPoint(
                Point2!double(
                    1.0,
                    -2.0
                )
            );

        assert(
            compareExactOverlayPoints(
                integerPoint,
                floatingPoint
            ) == 0
        );
    }


    /*
     * Canonical ring start is exact and independent of stored start rotation.
     */
    {
        ExactOverlayPoint[4] first = [
            exactOverlayPoint(P(0, 0)),
            exactOverlayPoint(P(4, 0)),
            exactOverlayPoint(P(4, 3)),
            exactOverlayPoint(P(0, 3)),
        ];

        ExactOverlayPoint[4] rotated = [
            exactOverlayPoint(P(4, 3)),
            exactOverlayPoint(P(0, 3)),
            exactOverlayPoint(P(0, 0)),
            exactOverlayPoint(P(4, 0)),
        ];

        assert(canonicalCycleStart(first[]) == 0);
        assert(canonicalCycleStart(rotated[]) == 2);

        assert(
            compareCanonicalCycles(
                first[],
                rotated[]
            ) == 0
        );
    }


    /*
     * When two cycles share a canonical start, the complete exact sequence is
     * a deterministic structural tie breaker.
     */
    {
        ExactOverlayPoint[3] first = [
            exactOverlayPoint(P(0, 0)),
            exactOverlayPoint(P(2, 0)),
            exactOverlayPoint(P(0, 2)),
        ];

        ExactOverlayPoint[3] second = [
            exactOverlayPoint(P(0, 0)),
            exactOverlayPoint(P(3, 0)),
            exactOverlayPoint(P(0, 1)),
        ];

        assert(
            compareCanonicalCycles(
                first[],
                second[]
            ) < 0
        );
    }


    /*
     * Reversing source storage does not change an atomic half-edge direction
     * when the half-edge itself is oriented identically.
     */
    {
        const Segment2!int forward =
            Segment2!int(
                P(-3, 2),
                P(7, 5)
            );

        const Segment2!int reversed =
            Segment2!int(
                forward.b,
                forward.a
            );

        auto firstDirection =
            sourceDirection(
                forward,
                true
            );

        auto secondDirection =
            sourceDirection(
                reversed,
                false
            );

        assert(
            compareSourceDirectionsCCW(
                firstDirection,
                secondDirection
            ) == 0
        );
    }


    /*
     * Operand-label exchange leaves union membership unchanged.
     */
    {
        assert(
            unionInterior(
                RegionLabel(true, false)
            ) ==
            unionInterior(
                RegionLabel(false, true)
            )
        );

        assert(
            unionInterior(
                RegionLabel(true, true)
            )
        );

        assert(
            !unionInterior(
                RegionLabel(false, false)
            )
        );
    }
}



private struct MaterializedBoundaryEdge
{
    size_t firstVertex;
    size_t secondVertex;
}


/*
 * Verifies that materialization preserves the exact boundary-incidence graph.
 *
 * The points slice is indexed by the already deduplicated exact arrangement
 * vertex ID. Different indices therefore denote different mathematical exact
 * points, while equal indices denote the same exact point/contact.
 *
 * The check requires:
 *
 * - every materialized point finite;
 * - exact vertex identity remains injective after rounding;
 * - every boundary edge remains nondegenerate;
 * - edge pairs with no shared exact vertex remain disjoint;
 * - edge pairs with one shared exact vertex remain one touch at exactly that
 *   materialized vertex;
 * - duplicate boundary edges are rejected.
 *
 * This rules out new/lost boundary crossings, overlaps, and point contacts.
 */
private bool materializedBoundaryIncidencePreserved(
    scope const(Point2!double)[] points,
    scope const(MaterializedBoundaryEdge)[] edges
)
    pure nothrow @safe @nogc
{
    foreach (i; 0 .. points.length)
    {
        if (!points[i].isFinite)
            return false;

        foreach (j; i + 1 .. points.length)
        {
            if (points[i] == points[j])
                return false;
        }
    }

    foreach (edge; edges)
    {
        if (
            edge.firstVertex >= points.length ||
            edge.secondVertex >= points.length ||
            edge.firstVertex == edge.secondVertex
        )
        {
            return false;
        }

        if (
            points[edge.firstVertex] ==
            points[edge.secondVertex]
        )
        {
            return false;
        }
    }

    foreach (i; 0 .. edges.length)
    {
        const auto firstEdge =
            Segment2!double(
                points[
                    edges[i].firstVertex
                ],
                points[
                    edges[i].secondVertex
                ]
            );

        foreach (j; i + 1 .. edges.length)
        {
            const auto secondEdge =
                Segment2!double(
                    points[
                        edges[j].firstVertex
                    ],
                    points[
                        edges[j].secondVertex
                    ]
                );

            size_t sharedCount = 0;
            size_t sharedVertex = size_t.max;

            if (
                edges[i].firstVertex ==
                    edges[j].firstVertex ||
                edges[i].firstVertex ==
                    edges[j].secondVertex
            )
            {
                ++sharedCount;
                sharedVertex =
                    edges[i].firstVertex;
            }

            if (
                edges[i].secondVertex ==
                    edges[j].firstVertex ||
                edges[i].secondVertex ==
                    edges[j].secondVertex
            )
            {
                ++sharedCount;
                sharedVertex =
                    edges[i].secondVertex;
            }

            if (sharedCount > 1)
                return false;

            const SegmentContactKind contact =
                segmentContactKind(
                    firstEdge,
                    secondEdge
                );

            if (sharedCount == 0)
            {
                if (
                    contact !=
                    SegmentContactKind.none
                )
                {
                    return false;
                }

                continue;
            }

            if (
                contact !=
                SegmentContactKind.touch
            )
            {
                return false;
            }

            Point2!double touch;

            if (
                !trySegmentTouchPoint(
                    firstEdge,
                    secondEdge,
                    touch
                ) ||
                touch != points[sharedVertex]
            )
            {
                return false;
            }
        }
    }

    return true;
}


/*
 * Structural post-materialization component check.
 *
 * Each component must independently satisfy the existing polygon validity
 * contract.
 *
 * For each pair, every exterior vertex of either component must not be inside
 * the other polygon. Combined with exact boundary-incidence preservation,
 * this excludes newly created interior overlap/containment while still
 * allowing:
 *
 * - isolated exact point contacts (boundary);
 * - one component located inside a hole of another (outside).
 */
private bool materializedComponentsRemainDisjoint(
    scope const(Polygon2View!double)[] components
)
    pure nothrow @safe @nogc
{
    foreach (component; components)
    {
        if (!validatePolygon(component).valid)
            return false;
    }

    foreach (i; 0 .. components.length)
    {
        foreach (j; i + 1 .. components.length)
        {
            const auto first =
                components[i];

            const auto second =
                components[j];

            if (
                first.empty ||
                second.empty
            )
            {
                continue;
            }

            PointPolygonLocation location;

            foreach (k; 0 .. first.exterior.length)
            {
                if (
                    !tryClassifyPointInPolygon(
                        second,
                        first.exterior[k],
                        location
                    ) ||
                    location ==
                        PointPolygonLocation.inside
                )
                {
                    return false;
                }
            }

            foreach (k; 0 .. second.exterior.length)
            {
                if (
                    !tryClassifyPointInPolygon(
                        first,
                        second.exterior[k],
                        location
                    ) ||
                    location ==
                        PointPolygonLocation.inside
                )
                {
                    return false;
                }
            }
        }
    }

    return true;
}


@safe unittest
{
    alias P = Point2!double;
    alias E = MaterializedBoundaryEdge;


    /*
     * One ordinary simple square preserves its exact boundary incidence.
     */
    {
        const P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 3.0),
            P(0.0, 3.0),
        ];

        const E[4] edges = [
            E(0, 1),
            E(1, 2),
            E(2, 3),
            E(3, 0),
        ];

        assert(
            materializedBoundaryIncidencePreserved(
                points[],
                edges[]
            )
        );
    }


    /*
     * Two result components may meet at one exact vertex ID.
     *
     * The materialized contact remains exactly that shared vertex and does
     * not splice the cycles into one self-touching ring.
     */
    {
        const P[7] points = [
            P(0.0, 0.0),
            P(2.0, 0.0),
            P(2.0, 2.0),
            P(0.0, 2.0),
            P(4.0, 2.0),
            P(4.0, 4.0),
            P(2.0, 4.0),
        ];

        const E[8] edges = [
            E(0, 1),
            E(1, 2),
            E(2, 3),
            E(3, 0),
            E(2, 4),
            E(4, 5),
            E(5, 6),
            E(6, 2),
        ];

        assert(
            materializedBoundaryIncidencePreserved(
                points[],
                edges[]
            )
        );

        LinearRing2View!double[2] rings = [
            LinearRing2View!double(
                points[0 .. 4]
            ),
            LinearRing2View!double.init,
        ];

        P[4] secondPoints = [
            points[2],
            points[4],
            points[5],
            points[6],
        ];

        rings[1] =
            LinearRing2View!double(
                secondPoints[]
            );

        Polygon2View!double[2] components = [
            Polygon2View!double(
                rings[0 .. 1]
            ),
            Polygon2View!double(
                rings[1 .. 2]
            ),
        ];

        assert(
            materializedComponentsRemainDisjoint(
                components[]
            )
        );
    }


    /*
     * Separate exact vertex IDs that collapse to one binary64 point fail the
     * injective materialization check before edge topology is considered.
     */
    {
        const P[2] points = [
            P(
                cast(double) long.max,
                0.0
            ),
            P(
                cast(double) (long.max - 1),
                0.0
            ),
        ];

        assert(points[0] == points[1]);

        const E[0] noEdges;

        assert(
            !materializedBoundaryIncidencePreserved(
                points[],
                noEdges[]
            )
        );
    }


    /*
     * This is the signed-long 2^53 regression used by the earlier
     * materialization test.
     *
     * All four rounded vertices remain distinct, but two non-adjacent exact
     * edges acquire a new rounded contact. Boundary-incidence verification
     * rejects the result directly, before polygon validation.
     */
    {
        enum long n =
            9_007_199_254_740_992L;

        const Point2!long[4] exactPoints = [
            Point2!long(n,     n - 3),
            Point2!long(n - 2, n - 4),
            Point2!long(n + 3, n - 1),
            Point2!long(n + 4, n - 2),
        ];

        P[4] roundedPoints;

        foreach (i; 0 .. exactPoints.length)
        {
            roundedPoints[i] =
                P(
                    cast(double)
                        exactPoints[i].x,
                    cast(double)
                        exactPoints[i].y
                );
        }

        const E[4] edges = [
            E(0, 1),
            E(1, 2),
            E(2, 3),
            E(3, 0),
        ];

        assert(
            !materializedBoundaryIncidencePreserved(
                roundedPoints[],
                edges[]
            )
        );
    }


    /*
     * Component nesting inside a hole remains disjoint polygon interior.
     */
    {
        P[4] outerPoints = [
            P(0.0, 0.0),
            P(10.0, 0.0),
            P(10.0, 10.0),
            P(0.0, 10.0),
        ];

        P[4] holePoints = [
            P(3.0, 3.0),
            P(3.0, 7.0),
            P(7.0, 7.0),
            P(7.0, 3.0),
        ];

        P[4] islandPoints = [
            P(4.0, 4.0),
            P(6.0, 4.0),
            P(6.0, 6.0),
            P(4.0, 6.0),
        ];

        LinearRing2View!double[3] rings = [
            LinearRing2View!double(
                outerPoints[]
            ),
            LinearRing2View!double(
                holePoints[]
            ),
            LinearRing2View!double(
                islandPoints[]
            ),
        ];

        Polygon2View!double[2] components = [
            Polygon2View!double(
                rings[0 .. 2]
            ),
            Polygon2View!double(
                rings[2 .. 3]
            ),
        ];

        assert(
            materializedComponentsRemainDisjoint(
                components[]
            )
        );
    }


    /*
     * Newly created component containment is rejected.
     */
    {
        P[4] outerPoints = [
            P(0.0, 0.0),
            P(10.0, 0.0),
            P(10.0, 10.0),
            P(0.0, 10.0),
        ];

        P[4] innerPoints = [
            P(2.0, 2.0),
            P(4.0, 2.0),
            P(4.0, 4.0),
            P(2.0, 4.0),
        ];

        LinearRing2View!double[2] rings = [
            LinearRing2View!double(
                outerPoints[]
            ),
            LinearRing2View!double(
                innerPoints[]
            ),
        ];

        Polygon2View!double[2] components = [
            Polygon2View!double(
                rings[0 .. 1]
            ),
            Polygon2View!double(
                rings[1 .. 2]
            ),
        ];

        assert(
            !materializedComponentsRemainDisjoint(
                components[]
            )
        );
    }
}
