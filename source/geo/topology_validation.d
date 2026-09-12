/**
 * Topology validation for linear rings and polygons.
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

import std.algorithm.sorting :
    sort;


/**
 * Validation issue detected in a LinearRingView.
 */
enum RingValidationIssue : ubyte
{
    /// No validation issue was detected.
    none,

    /// The ring contains fewer than three stored vertices.
    tooFewVertices,

    /// A stored vertex contains a non-finite coordinate.
    nonFiniteCoordinate,

    /// An implicit ring edge has identical endpoints.
    zeroLengthEdge,

    /// Ring edges have an invalid point intersection.
    selfIntersection,

    /// Ring edges overlap over positive length.
    selfOverlap,
}


/**
 * Result of validating one LinearRingView.
 *
 * Ring edge index i denotes the implicit segment from vertex i to vertex
 * (i + 1) % length.
 *
 * size_t.max denotes an index that does not apply to the reported issue.
 *
 * RingValidationResult.init represents a valid ring result with issue
 * RingValidationIssue.none and both diagnostic indices set to size_t.max.
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


/**
 * Validation issue detected in a PolygonView.
 */
enum PolygonValidationIssue : ubyte
{
    /// No validation issue was detected.
    none,

    /// The exterior ring failed ring validation.
    invalidExteriorRing,

    /// An interior ring failed ring validation.
    invalidInteriorRing,

    /// Two different rings cross properly.
    interRingCrossing,

    /// Boundaries of two different rings overlap over positive length.
    interRingOverlap,

    /// One ring pair has more than one distinct geometric contact point.
    multipleRingContacts,

    /// An interior ring lies outside the exterior ring.
    interiorRingOutsideExterior,

    /// One interior ring contains another interior ring.
    nestedInteriorRings,

    /// Boundary contacts form a cycle that disconnects polygon interior.
    disconnectedInterior,
}


/**
 * Result of validating one PolygonView.
 *
 * Polygon ring index 0 denotes the exterior ring. Indices 1 and greater
 * denote interior rings in their stored PolygonView order.
 *
 * size_t.max denotes an index that does not apply to the reported issue.
 *
 * For invalidExteriorRing and invalidInteriorRing, ringResult contains the
 * corresponding detailed ring diagnostic.
 *
 * For inter-ring topology errors, primaryRingIndex and secondaryRingIndex
 * identify the involved rings. primaryEdgeIndex and secondaryEdgeIndex are
 * populated when a particular segment pair identifies the error.
 *
 * For interiorRingOutsideExterior, primaryRingIndex identifies the offending
 * interior ring and secondaryRingIndex is 0.
 *
 * For nestedInteriorRings, primaryRingIndex identifies the contained interior
 * ring and secondaryRingIndex identifies the containing interior ring.
 *
 * For disconnectedInterior, primaryRingIndex and secondaryRingIndex identify
 * the ring pair whose contact incidence closes the detected contact-graph
 * cycle.
 *
 * PolygonValidationResult.init represents a valid polygon result with issue
 * PolygonValidationIssue.none and all diagnostic indices set to size_t.max.
 */
struct PolygonValidationResult
{
    PolygonValidationIssue issue =
        PolygonValidationIssue.none;

    size_t primaryRingIndex =
        size_t.max;

    RingValidationResult ringResult =
        RingValidationResult.init;

    size_t secondaryRingIndex =
        size_t.max;

    size_t primaryEdgeIndex =
        size_t.max;

    size_t secondaryEdgeIndex =
        size_t.max;


    /**
     * True when no validation issue was detected.
     */
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
 * Supported scalar types are `int`, `long`, `float`, and `double`.
 * `real` is deliberately outside the robust topology domain.
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
 * Topological decisions are exact. No epsilon or rounded intersection
 * coordinate is used.
 *
 * The first detected issue is returned deterministically.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(n^2) time and O(1) auxiliary space for n stored vertices.
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

            result.primaryRingIndex =
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
 *     primaryRingIndex   = offending interior ring
 *     secondaryRingIndex = exterior ring (0)
 *
 * nestedInteriorRings:
 *     primaryRingIndex   = contained interior ring
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

            result.primaryRingIndex =
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

                result.primaryRingIndex =
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

                result.primaryRingIndex =
                    secondHoleIndex;

                result.secondaryRingIndex =
                    firstHoleIndex;

                return result;
            }
        }
    }


    return PolygonValidationResult.init;
}


/*
 * One exact geometric contact between two polygon rings.
 *
 * Contact points remain in the input scalar domain because inter-ring
 * proper crossings and overlaps have already been rejected.
 */
private struct RingContact(T)
{
    Point2!T point;

    size_t firstRingIndex;
    size_t secondRingIndex;
}


/*
 * Deterministic exact ordering for finite contact points.
 *
 * Ring indices break ties so sorting remains deterministic when several
 * ring pairs meet at the same geometric point.
 */
private bool ringContactLess(T)(
    ref const RingContact!T lhs,
    ref const RingContact!T rhs
)
    pure nothrow @safe @nogc
{
    if (lhs.point.x < rhs.point.x)
        return true;

    if (rhs.point.x < lhs.point.x)
        return false;

    if (lhs.point.y < rhs.point.y)
        return true;

    if (rhs.point.y < lhs.point.y)
        return false;

    if (
        lhs.firstRingIndex <
        rhs.firstRingIndex
    )
    {
        return true;
    }

    if (
        rhs.firstRingIndex <
        lhs.firstRingIndex
    )
    {
        return false;
    }

    return
        lhs.secondRingIndex <
        rhs.secondRingIndex;
}


/*
 * Returns one exact contact point for a ring pair when one exists.
 *
 * Preconditions:
 *
 * - both rings are valid;
 * - the ring pair has passed screenRingPairContacts().
 *
 * Therefore the pair is either disjoint or has exactly one geometric
 * tangential contact point.
 */
private bool tryRingPairTouchPoint(T)(
    scope LinearRingView!T firstRing,
    scope LinearRingView!T secondRing,
    out Point2!T point
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
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

            final switch (contact)
            {
                case SegmentContactKind.none:
                    break;

                case SegmentContactKind.touch:
                {
                    const bool success =
                        trySegmentTouchPoint(
                            firstEdge,
                            secondEdge,
                            point
                        );

                    assert(success);

                    return true;
                }

                case SegmentContactKind.properCrossing:
                    assert(false);
                    break;

                case SegmentContactKind.overlap:
                    assert(false);
                    break;
            }
        }
    }

    return false;
}


/*
 * Finds the root of one node in a union-find forest.
 *
 * Union by rank bounds tree depth, so path compression is not required for
 * the correctness-oriented initial implementation.
 */
private size_t contactRoot(
    scope const(size_t)[] parent,
    size_t node
)
    pure nothrow @safe @nogc
{
    while (parent[node] != node)
    {
        node =
            parent[node];
    }

    return node;
}


/*
 * Adds an undirected graph edge between two nodes.
 *
 * Returns false when both endpoints were already connected. Adding that
 * edge therefore closes a graph cycle.
 */
private bool unionContactNodes(
    scope size_t[] parent,
    scope ubyte[] rank,
    size_t first,
    size_t second
)
    pure nothrow @safe @nogc
{
    size_t firstRoot =
        contactRoot(
            parent,
            first
        );

    size_t secondRoot =
        contactRoot(
            parent,
            second
        );

    if (firstRoot == secondRoot)
        return false;


    if (
        rank[firstRoot] <
        rank[secondRoot]
    )
    {
        parent[firstRoot] =
            secondRoot;

        return true;
    }

    if (
        rank[secondRoot] <
        rank[firstRoot]
    )
    {
        parent[secondRoot] =
            firstRoot;

        return true;
    }


    parent[secondRoot] =
        firstRoot;

    ++rank[firstRoot];

    return true;
}


/*
 * Validates connected polygon interior.
 *
 * Preconditions are established by validatePolygonContainment().
 *
 * After all previous validation stages:
 *
 * - every ring is a simple closed curve;
 * - different rings do not cross or overlap;
 * - each ring pair has at most one geometric contact point;
 * - interior rings are properly contained;
 * - interior rings are not nested.
 *
 * The remaining boundary-contact topology is represented as a bipartite
 * graph:
 *
 *     ring nodes <-> geometric contact-point nodes
 *
 * Multiple rings meeting at one identical point share one contact-point
 * node.
 *
 * Polygon interior is connected exactly when this incidence graph is
 * acyclic. A cycle forms a closed boundary barrier and separates at least
 * one interior region.
 *
 * Temporary storage is proportional to the number of polygon rings and
 * touching ring pairs. This stage is deliberately not @nogc.
 */
package(geo) PolygonValidationResult
validatePolygonConnectedInterior(T)(
    scope PolygonView!T polygon
)
    pure nothrow @safe
if (isValidationScalar!T)
{
    const PolygonValidationResult containmentResult =
        validatePolygonContainment(
            polygon
        );

    if (!containmentResult.valid)
        return containmentResult;


    /*
     * Zero or one ring cannot contain an inter-ring contact cycle.
     */
    if (polygon.length <= 1)
        return PolygonValidationResult.init;


    RingContact!T[] contacts;


    /*
     * Collect exactly one contact record for every touching ring pair.
     */
    foreach (
        firstRingIndex;
        0 .. polygon.length
    )
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

            Point2!T point;

            if (
                !tryRingPairTouchPoint(
                    firstRing,
                    secondRing,
                    point
                )
            )
            {
                continue;
            }

            contacts ~=
                RingContact!T(
                    point,
                    firstRingIndex,
                    secondRingIndex
                );
        }
    }


    if (contacts.length == 0)
        return PolygonValidationResult.init;


    /*
     * Equal geometric contact points become adjacent in the sorted array.
     *
     * Finite coordinates have already been established by ring validation.
     */
    sort!(ringContactLess!T)(
        contacts
    );


    /*
     * Union-find nodes initially consist of the polygon rings.
     *
     * One additional node is appended for each distinct geometric contact
     * point.
     */
    size_t[] parent =
        new size_t[polygon.length];

    ubyte[] rank =
        new ubyte[polygon.length];

    foreach (i; 0 .. polygon.length)
    {
        parent[i] =
            i;
    }


    /*
     * Marker used to avoid adding the same ring/contact-point incidence
     * more than once when three or more rings meet at one point.
     */
    size_t[] seenAtContact =
        new size_t[polygon.length];

    foreach (i; 0 .. seenAtContact.length)
    {
        seenAtContact[i] =
            size_t.max;
    }


    size_t contactGroup = 0;
    size_t begin = 0;

    while (begin < contacts.length)
    {
        size_t end =
            begin + 1;

        const Point2!T point =
            contacts[begin].point;

        while (
            end < contacts.length &&
            contacts[end].point == point
        )
        {
            ++end;
        }


        const size_t pointNode =
            parent.length;

        parent ~=
            pointNode;

        rank ~=
            0;


        foreach (contactIndex; begin .. end)
        {
            const auto contact =
                contacts[contactIndex];

            size_t[2] touchingRings = [
                contact.firstRingIndex,
                contact.secondRingIndex
            ];

            foreach (ringIndex; touchingRings)
            {
                /*
                 * Several ring pairs at the same geometric point may
                 * mention the same ring. They represent only one incidence
                 * edge in the bipartite graph.
                 */
                if (
                    seenAtContact[ringIndex] ==
                    contactGroup
                )
                {
                    continue;
                }

                seenAtContact[ringIndex] =
                    contactGroup;


                if (
                    !unionContactNodes(
                        parent,
                        rank,
                        ringIndex,
                        pointNode
                    )
                )
                {
                    PolygonValidationResult result;

                    result.issue =
                        PolygonValidationIssue.disconnectedInterior;

                    result.primaryRingIndex =
                        contact.firstRingIndex;

                    result.secondaryRingIndex =
                        contact.secondRingIndex;

                    return result;
                }
            }
        }


        ++contactGroup;
        begin = end;
    }


    return PolygonValidationResult.init;
}


/**
 * Validates one PolygonView for polygon topology.
 *
 * Supported scalar types are `int`, `long`, `float`, and `double`.
 * `real` is deliberately outside the robust topology domain.
 *
 * A valid polygon:
 *
 * - is empty, or has a valid simple exterior ring;
 * - contains only valid simple interior rings;
 * - has no inter-ring crossing or positive-length boundary overlap;
 * - allows at most one geometric contact point between each ring pair;
 * - contains every interior ring within the exterior ring;
 * - contains no nested interior rings;
 * - has connected polygon interior.
 *
 * A single tangential contact between different rings is permitted when the
 * remaining polygon topology is valid. Several rings may meet at the same
 * geometric point when this does not disconnect the polygon interior.
 *
 * Ring orientation does not affect validity.
 *
 * Validation is exact for topology. No epsilon or rounded intersection
 * coordinate is used.
 *
 * An empty PolygonView is valid.
 *
 * The first detected issue is returned deterministically.
 *
 * This operation may allocate temporary storage while checking connected
 * polygon interior and therefore does not promise @nogc.
 *
 * Let n be the total number of stored vertices, r the number of rings, and c
 * the number of touching ring pairs. Temporary storage is O(r + c). Because
 * c may be quadratic in the number of rings, auxiliary storage is O(n^2) in
 * the worst case.
 *
 * Complexity:
 *     O(n^2 log n) time in the worst case.
 */
PolygonValidationResult validatePolygon(T)(
    scope PolygonView!T polygon
)
    pure nothrow @safe
if (isValidationScalar!T)
{
    return validatePolygonConnectedInterior(
        polygon
    );
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
            result.primaryRingIndex ==
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
            result.primaryRingIndex ==
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
            result.primaryRingIndex ==
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

        assert(result.primaryRingIndex == 0);
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

        assert(result.primaryRingIndex == 0);
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

        assert(result.primaryRingIndex == 0);
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

        assert(result.primaryRingIndex == 1);
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

        assert(result.primaryRingIndex == 1);
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

        assert(result.primaryRingIndex == 2);
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

        assert(result.primaryRingIndex == 2);
        assert(result.secondaryRingIndex == 1);
    }



    /*
     * One hole touching the exterior once does not disconnect the
     * polygon interior.
     */
    {
        alias DP = Point2!double;
        alias DR = LinearRingView!double;
        alias DV = PolygonView!double;

        DP[4] exteriorPoints = [
            DP(0.0, 0.0),
            DP(10.0, 0.0),
            DP(10.0, 10.0),
            DP(0.0, 10.0)
        ];

        DP[3] holePoints = [
            DP(0.0, 5.0),
            DP(2.0, 4.0),
            DP(2.0, 6.0)
        ];

        DR exterior =
            DR(exteriorPoints[]);

        DR hole =
            DR(holePoints[]);

        DR[2] rings = [
            exterior,
            hole
        ];

        auto polygon =
            DV(rings[]);

        assert(
            validatePolygonConnectedInterior(
                polygon
            ).valid
        );
    }


    /*
     * A chain of holes joining two distinct exterior contact points forms
     * a barrier and disconnects the polygon interior.
     */
    {
        alias DP = Point2!double;
        alias DR = LinearRingView!double;
        alias DV = PolygonView!double;

        DP[4] exteriorPoints = [
            DP(0.0, 0.0),
            DP(10.0, 0.0),
            DP(10.0, 10.0),
            DP(0.0, 10.0)
        ];

        DP[3] firstHolePoints = [
            DP(0.0, 5.0),
            DP(5.0, 5.0),
            DP(2.0, 7.0)
        ];

        DP[3] secondHolePoints = [
            DP(10.0, 5.0),
            DP(8.0, 7.0),
            DP(5.0, 5.0)
        ];

        DR exterior =
            DR(exteriorPoints[]);

        DR firstHole =
            DR(firstHolePoints[]);

        DR secondHole =
            DR(secondHolePoints[]);

        DR[3] rings = [
            exterior,
            firstHole,
            secondHole
        ];

        auto polygon =
            DV(rings[]);

        const result =
            validatePolygonConnectedInterior(
                polygon
            );

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.disconnectedInterior
        );
    }


    /*
     * A closed cycle of mutually tangent holes can disconnect interior
     * even without touching the exterior.
     */
    {
        alias DP = Point2!double;
        alias DR = LinearRingView!double;
        alias DV = PolygonView!double;

        DP[4] exteriorPoints = [
            DP(0.0, 0.0),
            DP(10.0, 0.0),
            DP(10.0, 10.0),
            DP(0.0, 10.0)
        ];

        DP[3] firstHolePoints = [
            DP(5.0, 4.0),
            DP(3.0, 7.0),
            DP(2.0, 3.0)
        ];

        DP[3] secondHolePoints = [
            DP(7.0, 7.0),
            DP(5.0, 4.0),
            DP(8.0, 3.0)
        ];

        DP[3] thirdHolePoints = [
            DP(3.0, 7.0),
            DP(7.0, 7.0),
            DP(5.0, 9.0)
        ];

        DR exterior =
            DR(exteriorPoints[]);

        DR firstHole =
            DR(firstHolePoints[]);

        DR secondHole =
            DR(secondHolePoints[]);

        DR thirdHole =
            DR(thirdHolePoints[]);

        DR[4] rings = [
            exterior,
            firstHole,
            secondHole,
            thirdHole
        ];

        auto polygon =
            DV(rings[]);

        const result =
            validatePolygonConnectedInterior(
                polygon
            );

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.disconnectedInterior
        );
    }


    /*
     * Several rings meeting at one identical geometric point form one
     * contact-point node rather than a graph cycle.
     */
    {
        alias DP = Point2!double;
        alias DR = LinearRingView!double;
        alias DV = PolygonView!double;

        DP[4] exteriorPoints = [
            DP(0.0, 0.0),
            DP(10.0, 0.0),
            DP(10.0, 10.0),
            DP(0.0, 10.0)
        ];

        DP[3] firstHolePoints = [
            DP(5.0, 5.0),
            DP(3.0, 4.0),
            DP(3.0, 6.0)
        ];

        DP[3] secondHolePoints = [
            DP(5.0, 5.0),
            DP(7.0, 6.0),
            DP(7.0, 4.0)
        ];

        DP[3] thirdHolePoints = [
            DP(5.0, 5.0),
            DP(4.0, 7.0),
            DP(6.0, 7.0)
        ];

        DR exterior =
            DR(exteriorPoints[]);

        DR firstHole =
            DR(firstHolePoints[]);

        DR secondHole =
            DR(secondHolePoints[]);

        DR thirdHole =
            DR(thirdHolePoints[]);

        DR[4] rings = [
            exterior,
            firstHole,
            secondHole,
            thirdHole
        ];

        auto polygon =
            DV(rings[]);

        assert(
            validatePolygonConnectedInterior(
                polygon
            ).valid
        );
    }



    /*
     * Public polygon validation result initialization contains no applicable
     * diagnostic indices.
     */
    {
        const result =
            PolygonValidationResult.init;

        assert(result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.none
        );

        assert(
            result.primaryRingIndex ==
            size_t.max
        );

        assert(
            result.secondaryRingIndex ==
            size_t.max
        );

        assert(
            result.primaryEdgeIndex ==
            size_t.max
        );

        assert(
            result.secondaryEdgeIndex ==
            size_t.max
        );

        assert(result.ringResult.valid);
    }


    /*
     * The public entry point propagates detailed exterior-ring diagnostics.
     */
    {
        alias AP = Point2!double;
        alias AR = LinearRingView!double;
        alias AV = PolygonView!double;

        AP[4] points = [
            AP(0.0, 0.0),
            AP(4.0, 4.0),
            AP(0.0, 4.0),
            AP(4.0, 0.0)
        ];

        AR exterior =
            AR(points[]);

        AR[1] rings = [
            exterior
        ];

        auto polygon =
            AV(rings[]);

        const result =
            validatePolygon(polygon);

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.invalidExteriorRing
        );

        assert(result.primaryRingIndex == 0);

        assert(
            result.ringResult.issue ==
            RingValidationIssue.selfIntersection
        );

        assert(result.ringResult.primaryIndex == 0);
        assert(result.ringResult.secondaryIndex == 2);
    }


    /*
     * The public entry point reaches connected-interior validation rather
     * than stopping after ring and containment checks.
     */
    {
        alias AP = Point2!double;
        alias AR = LinearRingView!double;
        alias AV = PolygonView!double;

        AP[4] exteriorPoints = [
            AP(0.0, 0.0),
            AP(10.0, 0.0),
            AP(10.0, 10.0),
            AP(0.0, 10.0)
        ];

        AP[3] firstHolePoints = [
            AP(0.0, 5.0),
            AP(5.0, 5.0),
            AP(2.0, 7.0)
        ];

        AP[3] secondHolePoints = [
            AP(10.0, 5.0),
            AP(8.0, 7.0),
            AP(5.0, 5.0)
        ];

        AR exterior =
            AR(exteriorPoints[]);

        AR firstHole =
            AR(firstHolePoints[]);

        AR secondHole =
            AR(secondHolePoints[]);

        AR[3] rings = [
            exterior,
            firstHole,
            secondHole
        ];

        auto polygon =
            AV(rings[]);

        const result =
            validatePolygon(polygon);

        assert(!result.valid);

        assert(
            result.issue ==
            PolygonValidationIssue.disconnectedInterior
        );
    }


    /*
     * Public polygon validation supports the deliberate scalar domain and
     * continues to defer real.
     */
    static assert(
        __traits(
            compiles,
            validatePolygon!int
        )
    );

    static assert(
        __traits(
            compiles,
            validatePolygon!long
        )
    );

    static assert(
        __traits(
            compiles,
            validatePolygon!float
        )
    );

    static assert(
        __traits(
            compiles,
            validatePolygon!double
        )
    );

    static assert(
        !__traits(
            compiles,
            validatePolygon!real
        )
    );

}
