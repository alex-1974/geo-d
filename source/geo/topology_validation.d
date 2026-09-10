module geo.topology_validation;

import geo.intersection :
    SegmentContactKind,
    SegmentIntersectionKind,
    segmentContactKind,
    segmentIntersectionKind,
    trySegmentTouchPoint;

import geo.internal.ring_point_classification :
    RingPointLocation,
    tryClassifyPointInRing;

import geo.linear_ring_view :
    LinearRingView;

import geo.polygon_view :
    PolygonView;

import geo.point :
    Point2;

import geo.segment :
    Segment2;


/**
 * Validation issue detected in a LinearRingView.
 */
enum RingValidationIssue : ubyte
{
    none,
    tooFewVertices,
    nonFiniteCoordinate,
    zeroLengthEdge,
    selfIntersection,
    selfOverlap,
}


/**
 * Result of validating one LinearRingView.
 *
 * Ring edge index i denotes the implicit segment from vertex i to vertex
 * (i + 1) % length.
 *
 * size_t.max denotes an index that does not apply to the reported issue.
 */
struct RingValidationResult
{
    RingValidationIssue issue =
        RingValidationIssue.none;

    size_t primaryIndex =
        size_t.max;

    size_t secondaryIndex =
        size_t.max;


    /**
     * True when no validation issue was detected.
     */
    @property bool valid() const
        pure nothrow @safe @nogc
    {
        return issue ==
            RingValidationIssue.none;
    }
}


/*
 * Package-internal polygon validation state.
 *
 * These types remain internal until full polygon topology validation is
 * implemented. They must not yet be exported through geo.package.
 */
package(geo) enum PolygonValidationIssue : ubyte
{
    none,
    invalidExteriorRing,
    invalidInteriorRing,
    interRingCrossing,
    interRingOverlap,
    multipleRingContacts,
    interiorRingOutsideExterior,
    nestedInteriorRings,
}


package(geo) struct PolygonValidationResult
{
    PolygonValidationIssue issue =
        PolygonValidationIssue.none;

    size_t ringIndex =
        size_t.max;

    RingValidationResult ringResult =
        RingValidationResult.init;

    size_t secondaryRingIndex =
        size_t.max;

    size_t primaryEdgeIndex =
        size_t.max;

    size_t secondaryEdgeIndex =
        size_t.max;


    @property bool valid() const
        pure nothrow @safe @nogc
    {
        return issue ==
            PolygonValidationIssue.none;
    }
}


private enum bool isValidationScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/*
 * Constructs a deterministic diagnostic result.
 */
private RingValidationResult validationIssue(
    RingValidationIssue issue,
    size_t primaryIndex = size_t.max,
    size_t secondaryIndex = size_t.max
)
    pure nothrow @safe @nogc
{
    return RingValidationResult(
        issue,
        primaryIndex,
        secondaryIndex
    );
}


/*
 * Constructs ring edge index from the implicit ring closure.
 *
 * Preconditions:
 *
 *     ring.length > 0
 *     index < ring.length
 */
private Segment2!T ringEdge(T)(
    scope LinearRingView!T ring,
    size_t index
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
    const size_t next =
        index + 1 == ring.length
            ? 0
            : index + 1;

    return Segment2!T(
        ring[index],
        ring[next]
    );
}


/*
 * True when two ring edge indices are adjacent in the cyclic edge
 * sequence.
 *
 * Preconditions:
 *
 *     edgeCount >= 3
 *     first < second
 *     second < edgeCount
 */
private bool adjacentRingEdges(
    size_t first,
    size_t second,
    size_t edgeCount
)
    pure nothrow @safe @nogc
{
    return
        second == first + 1 ||
        (
            first == 0 &&
            second + 1 == edgeCount
        );
}


/**
 * Validates one LinearRingView.
 *
 * A valid ring:
 *
 * - has at least three stored vertices;
 * - contains only finite coordinates;
 * - has no zero-length implicit edge;
 * - is a simple closed polygonal curve.
 *
 * Ring orientation does not affect validity.
 *
 * The stored point sequence is closed implicitly. An explicitly repeated
 * copy of the first vertex therefore creates a zero-length closing edge and
 * is invalid.
 *
 * The first detected issue is returned deterministically.
 *
 * Complexity:
 *
 *     time  O(n^2)
 *     space O(1)
 */
RingValidationResult validateRing(T)(
    scope LinearRingView!T ring
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
    const size_t count =
        ring.length;


    /*
     * Minimum cardinality is checked first.
     */
    if (count < 3)
    {
        return validationIssue(
            RingValidationIssue.tooFewVertices
        );
    }


    /*
     * Establish the finite-coordinate precondition required by the robust
     * segment-intersection predicates.
     */
    foreach (i; 0 .. count)
    {
        if (!ring[i].isFinite)
        {
            return validationIssue(
                RingValidationIssue.nonFiniteCoordinate,
                i
            );
        }
    }


    /*
     * Reject zero-length edges before pairwise topology testing.
     */
    foreach (i; 0 .. count)
    {
        const auto edge =
            ringEdge(
                ring,
                i
            );

        if (edge.a == edge.b)
        {
            return validationIssue(
                RingValidationIssue.zeroLengthEdge,
                i
            );
        }
    }


    /*
     * Test every unordered pair of implicit ring edges.
     *
     * Adjacent edges are expected to meet at exactly their shared stored
     * endpoint. Positive-length overlap is invalid.
     *
     * Non-adjacent edges must be completely disjoint.
     */
    foreach (i; 0 .. count)
    {
        const auto first =
            ringEdge(
                ring,
                i
            );

        foreach (j; i + 1 .. count)
        {
            const auto second =
                ringEdge(
                    ring,
                    j
                );

            const SegmentIntersectionKind kind =
                segmentIntersectionKind(
                    first,
                    second
                );

            if (
                adjacentRingEdges(
                    i,
                    j,
                    count
                )
            )
            {
                if (
                    kind ==
                    SegmentIntersectionKind.overlap
                )
                {
                    return validationIssue(
                        RingValidationIssue.selfOverlap,
                        i,
                        j
                    );
                }

                /*
                 * With finite non-degenerate adjacent edges, their common
                 * stored endpoint guarantees exactly one point
                 * intersection unless they overlap.
                 *
                 * Keep the defensive branch explicit rather than relying on
                 * an assertion for public validation semantics.
                 */
                if (
                    kind !=
                    SegmentIntersectionKind.point
                )
                {
                    return validationIssue(
                        RingValidationIssue.selfIntersection,
                        i,
                        j
                    );
                }

                continue;
            }


            if (
                kind ==
                SegmentIntersectionKind.point
            )
            {
                return validationIssue(
                    RingValidationIssue.selfIntersection,
                    i,
                    j
                );
            }

            if (
                kind ==
                SegmentIntersectionKind.overlap
            )
            {
                return validationIssue(
                    RingValidationIssue.selfOverlap,
                    i,
                    j
                );
            }
        }
    }


    return RingValidationResult.init;
}


/*
 * Validates only the constituent rings of a PolygonView.
 *
 * This is deliberately not the public polygon validator.
 *
 * It establishes:
 *
 * - empty polygon validity;
 * - exterior ring validity;
 * - interior ring validity;
 * - deterministic propagation of ring diagnostics.
 *
 * It does not yet establish:
 *
 * - exterior/interior containment;
 * - inter-ring crossings or overlaps;
 * - hole/hole relationships;
 * - connected polygon interior.
 */
package(geo) PolygonValidationResult validatePolygonRings(T)(
    scope PolygonView!T polygon
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
    if (polygon.empty)
        return PolygonValidationResult.init;


    const RingValidationResult exteriorResult =
        validateRing(
            polygon.exterior
        );

    if (!exteriorResult.valid)
    {
        return PolygonValidationResult(
            PolygonValidationIssue.invalidExteriorRing,
            0,
            exteriorResult
        );
    }


    foreach (i; 0 .. polygon.holeCount)
    {
        const RingValidationResult interiorResult =
            validateRing(
                polygon.hole(i)
            );

        if (!interiorResult.valid)
        {
            return PolygonValidationResult(
                PolygonValidationIssue.invalidInteriorRing,
                i + 1,
                interiorResult
            );
        }
    }


    return PolygonValidationResult.init;
}


/*
 * Result of screening the boundary contacts between two already validated
 * rings.
 */
private enum RingPairContactIssue : ubyte
{
    none,
    properCrossing,
    overlap,
    multipleDistinctContacts,
}


private struct RingPairContactResult
{
    RingPairContactIssue issue =
        RingPairContactIssue.none;

    size_t firstEdgeIndex =
        size_t.max;

    size_t secondEdgeIndex =
        size_t.max;
}


/*
 * Screens all segment contacts between two valid rings.
 *
 * Preconditions:
 *
 * - both rings have already passed validateRing();
 * - therefore every coordinate is finite;
 * - therefore every edge is non-degenerate.
 *
 * A single geometric touch point is retained as potentially valid.
 *
 * Multiple segment-pair touches at that same point are also potentially
 * valid because a vertex contact may involve several adjacent edges.
 *
 * A proper crossing, positive-length overlap, or a second distinct touch
 * point is rejected.
 *
 * Because both inputs are already valid simple closed rings, a remaining
 * single geometric point contact is topologically tangential. A side change
 * through that point would require another boundary contact elsewhere on the
 * closed ring.
 */
private RingPairContactResult screenRingPairContacts(T)(
    scope LinearRingView!T firstRing,
    scope LinearRingView!T secondRing
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
    bool haveTouchPoint = false;
    Point2!T firstTouchPoint;

    foreach (i; 0 .. firstRing.length)
    {
        const auto firstEdge =
            ringEdge(
                firstRing,
                i
            );

        foreach (j; 0 .. secondRing.length)
        {
            const auto secondEdge =
                ringEdge(
                    secondRing,
                    j
                );

            const SegmentContactKind contact =
                segmentContactKind(
                    firstEdge,
                    secondEdge
                );

            if (
                contact ==
                SegmentContactKind.none
            )
            {
                continue;
            }

            if (
                contact ==
                SegmentContactKind.properCrossing
            )
            {
                return RingPairContactResult(
                    RingPairContactIssue.properCrossing,
                    i,
                    j
                );
            }

            if (
                contact ==
                SegmentContactKind.overlap
            )
            {
                return RingPairContactResult(
                    RingPairContactIssue.overlap,
                    i,
                    j
                );
            }


            /*
             * Remaining contact kind is touch.
             *
             * Its exact point is an endpoint from the input scalar domain,
             * so no rounded construction is required.
             */
            Point2!T touchPoint;

            const bool havePoint =
                trySegmentTouchPoint(
                    firstEdge,
                    secondEdge,
                    touchPoint
                );

            assert(havePoint);

            if (!haveTouchPoint)
            {
                firstTouchPoint =
                    touchPoint;

                haveTouchPoint =
                    true;

                continue;
            }

            if (touchPoint != firstTouchPoint)
            {
                return RingPairContactResult(
                    RingPairContactIssue.multipleDistinctContacts,
                    i,
                    j
                );
            }
        }
    }

    return RingPairContactResult.init;
}


/*
 * Validates constituent rings and screens pairwise inter-ring contacts.
 *
 * This is still not the public polygon validator.
 *
 * A single inter-ring point contact is topologically tangential after the
 * preceding simple-ring and pair-contact checks.
 *
 * Containment and connected interior are handled by later validation stages.
 */
package(geo) PolygonValidationResult validatePolygonPairContacts(T)(
    scope PolygonView!T polygon
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
    const PolygonValidationResult ringResult =
        validatePolygonRings(
            polygon
        );

    if (!ringResult.valid)
        return ringResult;


    foreach (firstRingIndex; 0 .. polygon.length)
    {
        auto firstRing =
            polygon[firstRingIndex];

        foreach (
            secondRingIndex;
            firstRingIndex + 1 .. polygon.length
        )
        {
            auto secondRing =
                polygon[secondRingIndex];

            const RingPairContactResult contactResult =
                screenRingPairContacts(
                    firstRing,
                    secondRing
                );

            if (
                contactResult.issue ==
                RingPairContactIssue.none
            )
            {
                continue;
            }


            PolygonValidationResult result;

            result.ringIndex =
                firstRingIndex;

            result.secondaryRingIndex =
                secondRingIndex;

            result.primaryEdgeIndex =
                contactResult.firstEdgeIndex;

            result.secondaryEdgeIndex =
                contactResult.secondEdgeIndex;


            final switch (contactResult.issue)
            {
                case RingPairContactIssue.none:
                    assert(false);

                case RingPairContactIssue.properCrossing:
                    result.issue =
                        PolygonValidationIssue.interRingCrossing;
                    break;

                case RingPairContactIssue.overlap:
                    result.issue =
                        PolygonValidationIssue.interRingOverlap;
                    break;

                case RingPairContactIssue.multipleDistinctContacts:
                    result.issue =
                        PolygonValidationIssue.multipleRingContacts;
                    break;
            }

            return result;
        }
    }


    return PolygonValidationResult.init;
}


/*
 * Side of one already validated simple ring relative to another already
 * validated simple ring.
 *
 * Preconditions:
 *
 * - both rings have passed validateRing();
 * - their pair has passed screenRingPairContacts();
 *
 * Boundary vertices are skipped. With at most one geometric contact point,
 * at least one stored vertex must remain strictly inside or outside the
 * other ring.
 *
 * Because the boundaries do not cross, one such non-boundary vertex
 * determines the side of the complete ring.
 */
private enum RingRelativeLocation : ubyte
{
    outside,
    inside,
}


private RingRelativeLocation classifyRingRelativeToRing(T)(
    scope LinearRingView!T subject,
    scope LinearRingView!T reference
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
    foreach (i; 0 .. subject.length)
    {
        RingPointLocation location;

        const bool success =
            tryClassifyPointInRing(
                reference,
                subject[i],
                location
            );

        /*
         * Both rings were already validated, so all coordinates are finite.
         */
        assert(success);

        final switch (location)
        {
            case RingPointLocation.outside:
                return RingRelativeLocation.outside;

            case RingPointLocation.inside:
                return RingRelativeLocation.inside;

            case RingPointLocation.boundary:
                break;
        }
    }

    /*
     * Valid simple rings that passed pair-contact screening cannot have
     * every stored vertex on the other boundary.
     */
    assert(false);

    return RingRelativeLocation.outside;
}


/*
 * Validates ring topology, pairwise boundary contacts, and polygon ring
 * containment.
 *
 * This is still package-internal. Connected-interior validation remains to
 * be added before the public validatePolygon() API is exposed.
 *
 * Diagnostic index semantics added by this stage:
 *
 * interiorRingOutsideExterior:
 *     ringIndex          = offending interior ring
 *     secondaryRingIndex = exterior ring (0)
 *
 * nestedInteriorRings:
 *     ringIndex          = contained interior ring
 *     secondaryRingIndex = containing interior ring
 */
package(geo) PolygonValidationResult validatePolygonContainment(T)(
    scope PolygonView!T polygon
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
    const PolygonValidationResult contactResult =
        validatePolygonPairContacts(
            polygon
        );

    if (!contactResult.valid)
        return contactResult;

    if (polygon.empty)
        return PolygonValidationResult.init;


    auto exterior =
        polygon.exterior;


    /*
     * Every interior ring must lie inside the exterior.
     *
     * A single boundary touch is permitted. classifyRingRelativeToRing()
     * skips that boundary vertex and determines which side contains the
     * remainder of the ring.
     */
    foreach (holeOffset; 0 .. polygon.holeCount)
    {
        const size_t holeIndex =
            holeOffset + 1;

        auto hole =
            polygon[holeIndex];

        if (
            classifyRingRelativeToRing(
                hole,
                exterior
            ) ==
            RingRelativeLocation.outside
        )
        {
            PolygonValidationResult result;

            result.issue =
                PolygonValidationIssue.interiorRingOutsideExterior;

            result.ringIndex =
                holeIndex;

            result.secondaryRingIndex =
                0;

            return result;
        }
    }


    /*
     * Distinct interior rings may be disjoint or tangent at one point, but
     * one interior ring may not contain another.
     */
    foreach (
        firstHoleIndex;
        1 .. polygon.length
    )
    {
        auto firstHole =
            polygon[firstHoleIndex];

        foreach (
            secondHoleIndex;
            firstHoleIndex + 1 .. polygon.length
        )
        {
            auto secondHole =
                polygon[secondHoleIndex];

            if (
                classifyRingRelativeToRing(
                    firstHole,
                    secondHole
                ) ==
                RingRelativeLocation.inside
            )
            {
                PolygonValidationResult result;

                result.issue =
                    PolygonValidationIssue.nestedInteriorRings;

                result.ringIndex =
                    firstHoleIndex;

                result.secondaryRingIndex =
                    secondHoleIndex;

                return result;
            }

            if (
                classifyRingRelativeToRing(
                    secondHole,
                    firstHole
                ) ==
                RingRelativeLocation.inside
            )
            {
                PolygonValidationResult result;

                result.issue =
                    PolygonValidationIssue.nestedInteriorRings;

                result.ringIndex =
                    secondHoleIndex;

                result.secondaryRingIndex =
                    firstHoleIndex;

                return result;
            }
        }
    }


    return PolygonValidationResult.init;
}


@safe unittest
{
    import geo.point :
        Point2;

    import std.meta :
        AliasSeq;


    /*
     * Public result initialization represents a valid result with no
     * applicable diagnostic indices.
     */
    {
        const result =
            RingValidationResult.init;

        assert(result.valid);

        assert(
            result.issue ==
            RingValidationIssue.none
        );

        assert(
            result.primaryIndex ==
            size_t.max
        );

        assert(
            result.secondaryIndex ==
            size_t.max
        );
    }


    /*
     * Ordinary valid rings work across the complete robust scalar domain.
     */
    static foreach (T; AliasSeq!(int, long, float, double))
    {
        {
            alias P = Point2!T;
            alias R = LinearRingView!T;

            P[4] points = [
                P(T(0), T(0)),
                P(T(4), T(0)),
                P(T(4), T(4)),
                P(T(0), T(4))
            ];

            auto ring =
                R(points[]);

            const result =
                validateRing(ring);

            assert(result.valid);

            assert(
                result.issue ==
                RingValidationIssue.none
            );
        }
    }


    /*
     * real remains outside the robust topology domain.
     */
    static assert(
        !__traits(
            compiles,
            {
                LinearRingView!real ring;

                validateRing(ring);
            }
        )
    );


    alias P = Point2!double;
    alias R = LinearRingView!double;


    /*
     * Empty and undersized rings fail without element indices.
     */
    {
        P[] emptyPoints;

        auto emptyRing =
            R(emptyPoints);

        const emptyResult =
            validateRing(emptyRing);

        assert(!emptyResult.valid);

        assert(
            emptyResult.issue ==
            RingValidationIssue.tooFewVertices
        );

        assert(
            emptyResult.primaryIndex ==
            size_t.max
        );

        assert(
            emptyResult.secondaryIndex ==
            size_t.max
        );


        P[2] twoPoints = [
            P(0.0, 0.0),
            P(1.0, 0.0)
        ];

        auto twoRing =
            R(twoPoints[]);

        const twoResult =
            validateRing(twoRing);

        assert(
            twoResult.issue ==
            RingValidationIssue.tooFewVertices
        );
    }


    /*
     * Ring orientation does not affect validity.
     */
    {
        P[4] ccwPoints = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0)
        ];

        P[4] cwPoints = [
            P(0.0, 0.0),
            P(0.0, 4.0),
            P(4.0, 4.0),
            P(4.0, 0.0)
        ];

        auto ccw =
            R(ccwPoints[]);

        auto cw =
            R(cwPoints[]);

        assert(validateRing(ccw).valid);
        assert(validateRing(cw).valid);
    }


    /*
     * Non-finite coordinates are reported before topology predicates are
     * invoked.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(double.nan, 4.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(!result.valid);

        assert(
            result.issue ==
            RingValidationIssue.nonFiniteCoordinate
        );

        assert(
            result.primaryIndex ==
            2
        );

        assert(
            result.secondaryIndex ==
            size_t.max
        );
    }


    /*
     * Consecutive repeated vertices create a zero-length edge.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 0.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.zeroLengthEdge
        );

        assert(
            result.primaryIndex ==
            1
        );
    }


    /*
     * Explicitly repeating the first vertex is invalid because the view
     * already closes implicitly.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(0.0, 4.0),
            P(0.0, 0.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.zeroLengthEdge
        );

        assert(
            result.primaryIndex ==
            3
        );
    }


    /*
     * A bow-tie ring contains a proper non-adjacent self-intersection.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0),
            P(4.0, 0.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.selfIntersection
        );

        assert(
            result.primaryIndex ==
            0
        );

        assert(
            result.secondaryIndex ==
            2
        );
    }


    /*
     * A repeated non-adjacent vertex is a forbidden point
     * self-intersection.
     */
    {
        P[5] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 0.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.selfIntersection
        );
    }


    /*
     * Adjacent collinear edges that retrace positive length overlap and are
     * invalid.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(2.0, 0.0),
            P(2.0, 4.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.selfOverlap
        );

        assert(
            result.primaryIndex ==
            0
        );

        assert(
            result.secondaryIndex ==
            1
        );
    }


    /*
     * Collinear continuation through a redundant vertex is valid when the
     * adjacent edges share only that endpoint.
     */
    {
        P[5] points = [
            P(0.0, 0.0),
            P(2.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        assert(
            validateRing(ring).valid
        );
    }


    /*
     * Full-range long coordinates are validated using exact topology
     * without scalar overflow.
     */
    {
        alias LP = Point2!long;
        alias LR = LinearRingView!long;

        LP[3] points = [
            LP(long.min, long.min),
            LP(long.max, long.min),
            LP(0, long.max)
        ];

        auto ring =
            LR(points[]);

        assert(
            validateRing(ring).valid
        );
    }


    /*
     * Ring-only polygon validation treats an empty polygon as valid.
     */
    {
        R[] rings;

        auto polygon =
            PolygonView!double(rings);

        const result =
            validatePolygonRings(polygon);

        assert(result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.none
        );

        assert(
            result.ringIndex ==
            size_t.max
        );

        assert(result.ringResult.valid);
    }


    /*
     * Valid exterior and interior rings pass the ring-only stage.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(10.0, 0.0),
            P(10.0, 10.0),
            P(0.0, 10.0)
        ];

        P[4] holePoints = [
            P(3.0, 3.0),
            P(7.0, 3.0),
            P(7.0, 7.0),
            P(3.0, 7.0)
        ];

        R exterior =
            R(exteriorPoints[]);

        R hole =
            R(holePoints[]);

        R[2] rings = [
            exterior,
            hole
        ];

        auto polygon =
            PolygonView!double(rings[]);

        assert(
            validatePolygonRings(polygon).valid
        );
    }


    /*
     * Exterior ring diagnostics are propagated with polygon ring index zero.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0),
            P(4.0, 0.0)
        ];

        R exterior =
            R(exteriorPoints[]);

        R[1] rings = [
            exterior
        ];

        auto polygon =
            PolygonView!double(rings[]);

        const result =
            validatePolygonRings(polygon);

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.invalidExteriorRing
        );

        assert(
            result.ringIndex ==
            0
        );

        assert(
            result.ringResult.issue ==
            RingValidationIssue.selfIntersection
        );
    }


    /*
     * Interior ring diagnostics retain the actual polygon ring index.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(20.0, 0.0),
            P(20.0, 20.0),
            P(0.0, 20.0)
        ];

        P[4] firstHolePoints = [
            P(2.0, 2.0),
            P(6.0, 2.0),
            P(6.0, 6.0),
            P(2.0, 6.0)
        ];

        P[4] secondHolePoints = [
            P(10.0, 10.0),
            P(14.0, 10.0),
            P(14.0, 10.0),
            P(10.0, 14.0)
        ];

        R exterior =
            R(exteriorPoints[]);

        R firstHole =
            R(firstHolePoints[]);

        R secondHole =
            R(secondHolePoints[]);

        R[3] rings = [
            exterior,
            firstHole,
            secondHole
        ];

        auto polygon =
            PolygonView!double(rings[]);

        const result =
            validatePolygonRings(polygon);

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.invalidInteriorRing
        );

        assert(
            result.ringIndex ==
            2
        );

        assert(
            result.ringResult.issue ==
            RingValidationIssue.zeroLengthEdge
        );

        assert(
            result.ringResult.primaryIndex ==
            1
        );
    }


    /*
     * Disjoint ring boundaries pass the pair-contact screen.
     *
     * Containment is deliberately not decided by this stage.
     */
    {
        alias PP = Point2!double;
        alias PR = LinearRingView!double;
        alias PV = PolygonView!double;

        PP[4] exteriorPoints = [
            PP(0.0, 0.0),
            PP(10.0, 0.0),
            PP(10.0, 10.0),
            PP(0.0, 10.0)
        ];

        PP[4] holePoints = [
            PP(3.0, 3.0),
            PP(7.0, 3.0),
            PP(7.0, 7.0),
            PP(3.0, 7.0)
        ];

        PR exterior =
            PR(exteriorPoints[]);

        PR hole =
            PR(holePoints[]);

        PR[2] rings = [
            exterior,
            hole
        ];

        auto polygon =
            PV(rings[]);

        assert(
            validatePolygonPairContacts(polygon).valid
        );
    }


    /*
     * A proper crossing between different rings is rejected.
     */
    {
        alias PP = Point2!double;
        alias PR = LinearRingView!double;
        alias PV = PolygonView!double;

        PP[4] exteriorPoints = [
            PP(0.0, 0.0),
            PP(10.0, 0.0),
            PP(10.0, 10.0),
            PP(0.0, 10.0)
        ];

        PP[4] crossingPoints = [
            PP(8.0, -2.0),
            PP(12.0, -2.0),
            PP(12.0, 2.0),
            PP(8.0, 2.0)
        ];

        PR exterior =
            PR(exteriorPoints[]);

        PR crossing =
            PR(crossingPoints[]);

        PR[2] rings = [
            exterior,
            crossing
        ];

        auto polygon =
            PV(rings[]);

        const result =
            validatePolygonPairContacts(polygon);

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.interRingCrossing
        );

        assert(result.ringIndex == 0);
        assert(result.secondaryRingIndex == 1);

        assert(result.primaryEdgeIndex != size_t.max);
        assert(result.secondaryEdgeIndex != size_t.max);
    }


    /*
     * Positive-length overlap between different ring boundaries is
     * rejected.
     */
    {
        alias PP = Point2!double;
        alias PR = LinearRingView!double;
        alias PV = PolygonView!double;

        PP[4] exteriorPoints = [
            PP(0.0, 0.0),
            PP(10.0, 0.0),
            PP(10.0, 10.0),
            PP(0.0, 10.0)
        ];

        PP[4] overlapPoints = [
            PP(2.0, 0.0),
            PP(6.0, 0.0),
            PP(6.0, 2.0),
            PP(2.0, 2.0)
        ];

        PR exterior =
            PR(exteriorPoints[]);

        PR overlap =
            PR(overlapPoints[]);

        PR[2] rings = [
            exterior,
            overlap
        ];

        auto polygon =
            PV(rings[]);

        const result =
            validatePolygonPairContacts(polygon);

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.interRingOverlap
        );

        assert(result.ringIndex == 0);
        assert(result.secondaryRingIndex == 1);
    }


    /*
     * Several segment-pair touches at one identical geometric point still
     * represent only one ring contact.
     */
    {
        alias PP = Point2!double;
        alias PR = LinearRingView!double;
        alias PV = PolygonView!double;

        PP[4] exteriorPoints = [
            PP(0.0, 0.0),
            PP(10.0, 0.0),
            PP(10.0, 10.0),
            PP(0.0, 10.0)
        ];

        PP[3] touchingPoints = [
            PP(0.0, 5.0),
            PP(2.0, 4.0),
            PP(2.0, 6.0)
        ];

        PR exterior =
            PR(exteriorPoints[]);

        PR touching =
            PR(touchingPoints[]);

        PR[2] rings = [
            exterior,
            touching
        ];

        auto polygon =
            PV(rings[]);

        assert(
            validatePolygonPairContacts(polygon).valid
        );
    }


    /*
     * Two distinct touch points between the same pair of rings are
     * rejected even when no segment pair crosses or overlaps.
     */
    {
        alias PP = Point2!double;
        alias PR = LinearRingView!double;
        alias PV = PolygonView!double;

        PP[4] exteriorPoints = [
            PP(0.0, 0.0),
            PP(10.0, 0.0),
            PP(10.0, 10.0),
            PP(0.0, 10.0)
        ];

        PP[4] touchingPoints = [
            PP(0.0, 2.0),
            PP(2.0, 4.0),
            PP(0.0, 6.0),
            PP(1.0, 4.0)
        ];

        PR exterior =
            PR(exteriorPoints[]);

        PR touching =
            PR(touchingPoints[]);

        PR[2] rings = [
            exterior,
            touching
        ];

        auto polygon =
            PV(rings[]);

        const result =
            validatePolygonPairContacts(polygon);

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.multipleRingContacts
        );

        assert(result.ringIndex == 0);
        assert(result.secondaryRingIndex == 1);
    }



    /*
     * A conventional contained interior ring passes containment.
     */
    {
        alias CP = Point2!double;
        alias CR = LinearRingView!double;
        alias CV = PolygonView!double;

        CP[4] exteriorPoints = [
            CP(0.0, 0.0),
            CP(10.0, 0.0),
            CP(10.0, 10.0),
            CP(0.0, 10.0)
        ];

        CP[4] holePoints = [
            CP(3.0, 3.0),
            CP(7.0, 3.0),
            CP(7.0, 7.0),
            CP(3.0, 7.0)
        ];

        CR exterior =
            CR(exteriorPoints[]);

        CR hole =
            CR(holePoints[]);

        CR[2] rings = [
            exterior,
            hole
        ];

        auto polygon =
            CV(rings[]);

        assert(
            validatePolygonContainment(polygon).valid
        );
    }


    /*
     * A disjoint interior ring outside the exterior is invalid.
     */
    {
        alias CP = Point2!double;
        alias CR = LinearRingView!double;
        alias CV = PolygonView!double;

        CP[4] exteriorPoints = [
            CP(0.0, 0.0),
            CP(10.0, 0.0),
            CP(10.0, 10.0),
            CP(0.0, 10.0)
        ];

        CP[4] outsidePoints = [
            CP(20.0, 20.0),
            CP(24.0, 20.0),
            CP(24.0, 24.0),
            CP(20.0, 24.0)
        ];

        CR exterior =
            CR(exteriorPoints[]);

        CR outsideHole =
            CR(outsidePoints[]);

        CR[2] rings = [
            exterior,
            outsideHole
        ];

        auto polygon =
            CV(rings[]);

        const result =
            validatePolygonContainment(polygon);

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.interiorRingOutsideExterior
        );

        assert(result.ringIndex == 1);
        assert(result.secondaryRingIndex == 0);
    }


    /*
     * An interior ring may touch the exterior tangentially from the inside.
     */
    {
        alias CP = Point2!double;
        alias CR = LinearRingView!double;
        alias CV = PolygonView!double;

        CP[4] exteriorPoints = [
            CP(0.0, 0.0),
            CP(10.0, 0.0),
            CP(10.0, 10.0),
            CP(0.0, 10.0)
        ];

        CP[3] holePoints = [
            CP(0.0, 5.0),
            CP(2.0, 4.0),
            CP(2.0, 6.0)
        ];

        CR exterior =
            CR(exteriorPoints[]);

        CR hole =
            CR(holePoints[]);

        CR[2] rings = [
            exterior,
            hole
        ];

        auto polygon =
            CV(rings[]);

        assert(
            validatePolygonContainment(polygon).valid
        );
    }


    /*
     * Tangential contact from outside does not make an interior ring
     * contained by the exterior.
     */
    {
        alias CP = Point2!double;
        alias CR = LinearRingView!double;
        alias CV = PolygonView!double;

        CP[4] exteriorPoints = [
            CP(0.0, 0.0),
            CP(10.0, 0.0),
            CP(10.0, 10.0),
            CP(0.0, 10.0)
        ];

        CP[3] holePoints = [
            CP(0.0, 5.0),
            CP(-2.0, 4.0),
            CP(-2.0, 6.0)
        ];

        CR exterior =
            CR(exteriorPoints[]);

        CR hole =
            CR(holePoints[]);

        CR[2] rings = [
            exterior,
            hole
        ];

        auto polygon =
            CV(rings[]);

        const result =
            validatePolygonContainment(polygon);

        assert(
            result.issue ==
            PolygonValidationIssue.interiorRingOutsideExterior
        );

        assert(result.ringIndex == 1);
    }


    /*
     * Nested interior rings are invalid.
     */
    {
        alias CP = Point2!double;
        alias CR = LinearRingView!double;
        alias CV = PolygonView!double;

        CP[4] exteriorPoints = [
            CP(0.0, 0.0),
            CP(20.0, 0.0),
            CP(20.0, 20.0),
            CP(0.0, 20.0)
        ];

        CP[4] outerHolePoints = [
            CP(2.0, 2.0),
            CP(8.0, 2.0),
            CP(8.0, 8.0),
            CP(2.0, 8.0)
        ];

        CP[4] innerHolePoints = [
            CP(4.0, 4.0),
            CP(6.0, 4.0),
            CP(6.0, 6.0),
            CP(4.0, 6.0)
        ];

        CR exterior =
            CR(exteriorPoints[]);

        CR outerHole =
            CR(outerHolePoints[]);

        CR innerHole =
            CR(innerHolePoints[]);

        CR[3] rings = [
            exterior,
            outerHole,
            innerHole
        ];

        auto polygon =
            CV(rings[]);

        const result =
            validatePolygonContainment(polygon);

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.nestedInteriorRings
        );

        assert(result.ringIndex == 2);
        assert(result.secondaryRingIndex == 1);
    }


    /*
     * Two interior rings may touch tangentially at one point when neither
     * contains the other.
     */
    {
        alias CP = Point2!double;
        alias CR = LinearRingView!double;
        alias CV = PolygonView!double;

        CP[4] exteriorPoints = [
            CP(0.0, 0.0),
            CP(10.0, 0.0),
            CP(10.0, 10.0),
            CP(0.0, 10.0)
        ];

        CP[4] firstHolePoints = [
            CP(2.0, 2.0),
            CP(4.0, 2.0),
            CP(4.0, 4.0),
            CP(2.0, 4.0)
        ];

        CP[4] secondHolePoints = [
            CP(4.0, 4.0),
            CP(6.0, 4.0),
            CP(6.0, 6.0),
            CP(4.0, 6.0)
        ];

        CR exterior =
            CR(exteriorPoints[]);

        CR firstHole =
            CR(firstHolePoints[]);

        CR secondHole =
            CR(secondHolePoints[]);

        CR[3] rings = [
            exterior,
            firstHole,
            secondHole
        ];

        auto polygon =
            CV(rings[]);

        assert(
            validatePolygonContainment(polygon).valid
        );
    }


    /*
     * Tangentially nested interior rings remain invalid.
     */
    {
        alias CP = Point2!double;
        alias CR = LinearRingView!double;
        alias CV = PolygonView!double;

        CP[4] exteriorPoints = [
            CP(0.0, 0.0),
            CP(10.0, 0.0),
            CP(10.0, 10.0),
            CP(0.0, 10.0)
        ];

        CP[4] outerHolePoints = [
            CP(2.0, 2.0),
            CP(8.0, 2.0),
            CP(8.0, 8.0),
            CP(2.0, 8.0)
        ];

        CP[3] innerHolePoints = [
            CP(2.0, 5.0),
            CP(4.0, 4.0),
            CP(4.0, 6.0)
        ];

        CR exterior =
            CR(exteriorPoints[]);

        CR outerHole =
            CR(outerHolePoints[]);

        CR innerHole =
            CR(innerHolePoints[]);

        CR[3] rings = [
            exterior,
            outerHole,
            innerHole
        ];

        auto polygon =
            CV(rings[]);

        const result =
            validatePolygonContainment(polygon);

        assert(
            result.issue ==
            PolygonValidationIssue.nestedInteriorRings
        );

        assert(result.ringIndex == 2);
        assert(result.secondaryRingIndex == 1);
    }

}
