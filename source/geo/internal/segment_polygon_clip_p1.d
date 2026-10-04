module geo.internal.segment_polygon_clip_p1;

import core.exception :
    onOutOfMemoryError;

import geo.bounding_box : tryBounds;
import geo.bounds : Bounds2;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind,
    trySegmentIntersectionOverlap,
    trySegmentTouchPoint;

import geo.internal.exact_coordinate :
    roundsToFiniteBinary64;

import geo.internal.exact_coordinate_round :
    roundExactCoordinateBinary64;

import geo.internal.intersection_exact :
    ExactProperIntersection,
    PreparedExactSegment,
    properIntersectionExactKnownCrossingPreparedFirst;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    appendSegmentPairNodingEvents,
    appendSegmentPairNodingEventsPreparedFirst,
    compareExactOverlayPointsAlongSegment,
    compareExactOverlayPointsAlongSegmentEqualPreferred,
    exactOverlayPoint,
    exactOverlayPointsEqual,
    seedExactEdgeEvents,
    sortUniqueExactEdgeEvents,
    sortUniqueExactEdgeEventsEqualPreferred,
    sortUniqueExactEdgeEventsEqualPreferredWithRawMapping;

version (DigitalMars)
import geo.internal.polygon_union_exact :
    appendSegmentPairNodingEventsKnownContact,
    appendSegmentPairNodingEventsKnownContactPreparedFirst;


import geo.internal.polygon_union_input :
    exactRingOrientationSign;

import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal,
    takeSegmentPolygonClipOwnedResultInternal;

import geo.internal.segment_polygon_clip_p1_dense_parameter_research :
    trySegmentPolygonClipP1DenseParameterResearch;

import geo.orientation :
    Orientation2,
    orientation;

import geo.point :
    Point2;

import geo.point_in_polygon :
    PointPolygonLocation,
    tryClassifyPointInPolygon;

import geo.polygon_view :
    Polygon2View;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Correctness-first exact segment/polygon clipping kernel for ADR-0024.
 *
 * The kernel:
 *
 * 1. collects every exact query/boundary event;
 * 2. sorts/deduplicates events in query traversal order;
 * 3. marks positive-length boundary-overlap intervals;
 * 4. classifies every remaining open interval from exact local polygon
 *    topology at its starting event;
 * 5. selects and merges all interior/boundary intervals;
 * 6. materializes maximal retained components only after exact topology is
 *    complete;
 * 7. rejects binary64 construction unless strict source-axis endpoint order is
 *    preserved.
 */


package(geo)
enum SegmentPolygonClipInternalStatus : ubyte
{
    success,
    unrepresentableConstruction,
}


private enum IntervalLocation : ubyte
{
    unknown,
    exterior,
    interior,
}


private enum bool isSegmentPolygonClipScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);

/*
 * Event-count research showed that the dense exact-event regime begins at
 * nine raw/unique query events. The same threshold already selects the
 * equal-denominator-preferred dense sort path.
 */
private enum size_t equalPreferredEventThreshold = 9;


/*
 * Computes total represented polygon boundary-edge count with resource-size
 * overflow mapped to the normal allocation failure path.
 */
private size_t polygonBoundaryEdgeCount(T)(
    scope Polygon2View!T polygon
)
    @safe
if (isSegmentPolygonClipScalar!T)
{
    size_t result;

    foreach (ringIndex; 0 .. polygon.length)
    {
        const size_t ringEdges =
            polygon[ringIndex].segmentCount;

        if (
            ringEdges >
            size_t.max - result
        )
        {
            onOutOfMemoryError();
        }

        result += ringEdges;
    }

    return result;
}


/*
 * Conservative candidate test using only finite represented comparisons.
 *
 * Strict separation of either closed coordinate interval proves that the
 * segments cannot meet. Equality is retained, including shared endpoints,
 * collinear overlap, subnormals and signed zero. No subtraction, rounding,
 * epsilon or exact-coordinate construction is involved. Overlapping bounds
 * do not establish contact; the existing exact writer still decides that.
 */
private bool edgeBoundsMayMeetQuery(T)(
    Bounds2!T queryBounds,
    Segment2!T edge
)
    pure nothrow @safe @nogc
if (isSegmentPolygonClipScalar!T)
{
    const lower = queryBounds.min;
    const upper = queryBounds.max;

    return !(
        (edge.a.x < lower.x && edge.b.x < lower.x) ||
        (edge.a.x > upper.x && edge.b.x > upper.x) ||
        (edge.a.y < lower.y && edge.b.y < lower.y) ||
        (edge.a.y > upper.y && edge.b.y > upper.y)
    );
}


/*
 * Conservative point/query candidate test for the vertex-topology pass.
 *
 * Every point on a closed segment lies inside that segment's closed axis-
 * aligned bounds. A represented polygon vertex outside queryBounds therefore
 * cannot contact the query and can skip the robust point/segment classifier.
 * Equality is retained; no subtraction, epsilon or rounded construction is
 * involved.
 */
private bool pointBoundsMayMeetQuery(T)(
    Bounds2!T queryBounds,
    Point2!T point
)
    pure nothrow @safe @nogc
if (isSegmentPolygonClipScalar!T)
{
    const lower = queryBounds.min;
    const upper = queryBounds.max;

    return
        point.x >= lower.x &&
        point.x <= upper.x &&
        point.y >= lower.y &&
        point.y <= upper.y;
}


/*
 * Reserves two seeds plus two raw events per possible boundary-edge contact.
 *
 * Each candidate may append at most two events (overlap), including duplicate
 * contacts at shared vertices/query endpoints. Strictly separated bounds
 * prove zero insertions. Thus the writer remains covered and the global
 * 2n + 2 bound remains valid. False-positive candidates only over-reserve.
 *
 * This adds one O(n), allocation-free comparison pass instead of repeating
 * the robust contact predicates. Event generation, ordering, labeling and
 * materialization below remain unchanged.
 */
private size_t queryBoundaryEventCapacity(T)(
    Bounds2!T queryBounds,
    scope Polygon2View!T polygon
)
    @safe
if (isSegmentPolygonClipScalar!T)
{
    assert(!queryBounds.empty);

    size_t capacity = 2;

    foreach (ringIndex; 0 .. polygon.length)
    {
        const auto ring = polygon[ringIndex];

        foreach (edgeIndex; 0 .. ring.segmentCount)
        {
            if (!edgeBoundsMayMeetQuery(queryBounds, ring.segment(edgeIndex)))
                continue;

            if (capacity > size_t.max - 2)
                onOutOfMemoryError();

            capacity += 2;
        }
    }

    return capacity;
}


/*
 * Finds one exact event in an already sorted unique query event list.
 */
private size_t findExactEventIndex(T)(
    Segment2!T query,
    scope const(ExactOverlayPoint)[] events,
    ref const ExactOverlayPoint target
)
    pure nothrow @safe @nogc
if (isSegmentPolygonClipScalar!T)
{
    size_t lower = 0;
    size_t upper = events.length;

    while (lower < upper)
    {
        const size_t middle =
            lower + (upper - lower) / 2;

        const int comparison =
            events.length >= equalPreferredEventThreshold
                ? compareExactOverlayPointsAlongSegmentEqualPreferred(
                    query,
                    events[middle],
                    target
                )
                : compareExactOverlayPointsAlongSegment(
                    query,
                    events[middle],
                    target
                );

        if (comparison < 0)
            lower = middle + 1;
        else
            upper = middle;
    }

    if (
        lower < events.length &&
        exactOverlayPointsEqual(
            events[lower],
            target
        )
    )
    {
        return lower;
    }

    return size_t.max;
}


/*
 * Records one exact non-boundary location for the query ray after an event.
 * Multiple exact witnesses for the same event must agree.
 */
private void setAfterLocation(
    ref IntervalLocation current,
    IntervalLocation value
)
    pure nothrow @safe @nogc
{
    assert(
        value == IntervalLocation.exterior ||
        value == IntervalLocation.interior
    );

    if (current == IntervalLocation.unknown)
    {
        current = value;
        return;
    }

    assert(current == value);
}


/*
 * Classifies the represented query ray leaving a strict edge-interior contact.
 */
private IntervalLocation edgeInteriorRayLocation(T)(
    Segment2!T edge,
    Point2!T target,
    bool interiorOnSourceLeft
)
    pure nothrow @safe @nogc
if (isSegmentPolygonClipScalar!T)
{
    const Orientation2 side =
        orientation(
            edge.a,
            edge.b,
            target
        );

    assert(side != Orientation2.collinear);

    const bool inside =
        interiorOnSourceLeft
            ? side == Orientation2.left
            : side == Orientation2.right;

    return
        inside
            ? IntervalLocation.interior
            : IntervalLocation.exterior;
}


/*
 * Classifies the query ray leaving one represented polygon vertex.
 *
 * unknown means the ray follows an incident polygon edge over positive
 * length. Such an interval is classified independently by the exact overlap
 * range machinery.
 */
private IntervalLocation vertexRayLocation(T)(
    Point2!T previous,
    Point2!T vertex,
    Point2!T next,
    Point2!T target,
    bool interiorOnSourceLeft
)
    pure nothrow @safe @nogc
if (isSegmentPolygonClipScalar!T)
{
    alias S = Segment2!T;

    assert(vertex != target);

    const S ray =
        S(
            vertex,
            target
        );

    if (
        segmentContactKind(
            ray,
            S(vertex, previous)
        ) == SegmentContactKind.overlap ||
        segmentContactKind(
            ray,
            S(vertex, next)
        ) == SegmentContactKind.overlap
    )
    {
        return IntervalLocation.unknown;
    }

    const Orientation2 previousSide =
        orientation(
            previous,
            vertex,
            target
        );

    const Orientation2 nextSide =
        orientation(
            vertex,
            next,
            target
        );

    const bool insidePreviousHalfPlane =
        interiorOnSourceLeft
            ? previousSide == Orientation2.left
            : previousSide == Orientation2.right;

    const bool insideNextHalfPlane =
        interiorOnSourceLeft
            ? nextSide == Orientation2.left
            : nextSide == Orientation2.right;

    const Orientation2 turn =
        orientation(
            previous,
            vertex,
            next
        );

    bool inside;

    if (turn == Orientation2.collinear)
    {
        inside =
            insidePreviousHalfPlane ||
            insideNextHalfPlane;
    }
    else
    {
        const bool convexForPolygonInterior =
            interiorOnSourceLeft
                ? turn == Orientation2.left
                : turn == Orientation2.right;

        if (convexForPolygonInterior)
        {
            inside =
                insidePreviousHalfPlane &&
                insideNextHalfPlane;
        }
        else
        {
            inside =
                insidePreviousHalfPlane ||
                insideNextHalfPlane;
        }
    }

    return
        inside
            ? IntervalLocation.interior
            : IntervalLocation.exterior;
}


/*
 * Correctly materializes one exact event into binary64.
 */
private bool tryMaterializeExactPoint(
    ref const ExactOverlayPoint exact,
    out Point2!double point
)
    pure nothrow @safe @nogc
{
    point = Point2!double.init;

    if (
        !roundsToFiniteBinary64(
            exact.xNumerator,
            exact.denominator
        ) ||
        !roundsToFiniteBinary64(
            exact.yNumerator,
            exact.denominator
        )
    )
    {
        return false;
    }

    point =
        Point2!double(
            roundExactCoordinateBinary64(
                exact.xNumerator,
                exact.denominator
            ),
            roundExactCoordinateBinary64(
                exact.yNumerator,
                exact.denominator
            )
        );

    return point.isFinite;
}


/*
 * True exactly when current lies strictly after previous in source query
 * traversal order on the source segment's authoritative monotone axis.
 */
private bool roundedPointStrictlyAfter(T)(
    Segment2!T query,
    Point2!double previous,
    Point2!double current
)
    pure nothrow @safe @nogc
if (isSegmentPolygonClipScalar!T)
{
    assert(query.a != query.b);

    if (query.a.x != query.b.x)
    {
        return
            query.a.x < query.b.x
                ? previous.x < current.x
                : previous.x > current.x;
    }

    return
        query.a.y < query.b.y
            ? previous.y < current.y
            : previous.y > current.y;
}


/*
 * Production P1 clipping kernel.
 *
 * Preconditions:
 *
 * - query is finite;
 * - polygon satisfies validatePolygon(polygon).valid.
 */
package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1Internal(T)(
    Segment2!T query,
    scope Polygon2View!T polygon,
    out SegmentPolygonClipOwnedResultInternal owned
)
    @safe
if (isSegmentPolygonClipScalar!T)
{
    alias S = Segment2!T;

    owned =
        SegmentPolygonClipOwnedResultInternal.init;

    assert(query.isFinite);

    /*
     * ADR-0024 regularizes away every zero-dimensional result.
     */
    if (query.a == query.b)
    {
        Segment2!double[] emptyComponents;

        owned =
            takeSegmentPolygonClipOwnedResultInternal(
                emptyComponents
            );

        return
            SegmentPolygonClipInternalStatus.success;
    }


    const size_t edgeCount =
        polygonBoundaryEdgeCount(
            polygon
        );

    if (edgeCount == 0)
    {
        Segment2!double[] emptyComponents;

        owned =
            takeSegmentPolygonClipOwnedResultInternal(
                emptyComponents
            );

        return
            SegmentPolygonClipInternalStatus.success;
    }


    Bounds2!T queryBounds;
    const bool bounded =
        tryBounds(query, queryBounds);

    assert(bounded && !queryBounds.empty);

    const size_t eventCapacity =
        queryBoundaryEventCapacity(
            queryBounds,
            polygon
        );

    assert(eventCapacity >= 2);
    assert((eventCapacity - 2) % 2 == 0);

    const size_t candidateEdgeCount =
        (eventCapacity - 2) / 2;

    /*
     * The capacity pass already establishes the number of edges whose closed
     * bounds can meet the query. Retained corpus evidence separates the sparse
     * regime (<= 12.5% candidates) from crossing/dense (50% candidates).
     * Apply the repeated per-edge bounds rejection only when at most one
     * quarter of boundary edges survive that first cheap pass.
     */
    const bool useEdgeBoundsPrefilter =
        candidateEdgeCount <= edgeCount / 4;

    /*
     * Dense first-pass events already contain every exact proper crossing.
     * Retain only compact slot provenance so pass 2 can reuse the final unique
     * event index without reconstructing or searching the 2120-byte carrier.
     */
    const bool prepareEventProvenance =
        !useEdgeBoundsPrefilter &&
        edgeCount >= 16;

    if (prepareEventProvenance)
    {
        const auto denseStatus =
            trySegmentPolygonClipP1DenseParameterResearch(
                query,
                polygon,
                edgeCount,
                queryBounds,
                eventCapacity,
                owned
            );

        return
            cast(SegmentPolygonClipInternalStatus)
                denseStatus;
    }

    size_t[] eventProvenanceWorkspace;
    size_t[] edgeFirstRawEventPlusOne;
    size_t[] rawEventIndices;
    size_t[] rawToUnique;

    if (prepareEventProvenance)
    {
        if (
            eventCapacity >
            (size_t.max - edgeCount) / 2
        )
        {
            onOutOfMemoryError();
        }

        const size_t workspaceLength =
            edgeCount +
            2 * eventCapacity;

        eventProvenanceWorkspace =
            new size_t[
                workspaceLength
            ];

        edgeFirstRawEventPlusOne =
            eventProvenanceWorkspace[
                0 .. edgeCount
            ];

        rawEventIndices =
            eventProvenanceWorkspace[
                edgeCount ..
                edgeCount + eventCapacity
            ];

        rawToUnique =
            eventProvenanceWorkspace[
                edgeCount + eventCapacity ..
                workspaceLength
            ];
    }

    size_t provenanceEdgeIndex;

    /*
     * DMD benefits from retaining first-pass contact kinds for sufficiently
     * large dense candidate sets. LDC deliberately does not compile this
     * workspace state into the clipping hot path.
     */
    version (DigitalMars)
    const bool reuseBoundaryContacts =
        !useEdgeBoundsPrefilter &&
        edgeCount >= 64;

    version (DigitalMars)
    SegmentContactKind[] boundaryContacts;

    version (DigitalMars)
    size_t flatEdgeIndex;

    version (DigitalMars)
    {
        if (reuseBoundaryContacts)
        {
            boundaryContacts =
                new SegmentContactKind[
                    edgeCount
                ];
        }
    }

    if (eventCapacity > size_t.max / ExactOverlayPoint.sizeof)
        onOutOfMemoryError();

    auto events =
        new ExactOverlayPoint[
            eventCapacity
        ];

    size_t eventCount;

    const bool seeded =
        seedExactEdgeEvents(
            query,
            events[],
            eventCount
        );

    assert(seeded);


    /*
     * Prepare the exact query lazily on the first strict proper crossing and
     * keep it for both boundary passes. Sparse/non-crossing calls therefore do
     * not pay scalar-to-dyadic decode cost merely for enabling this path.
     */
    PreparedExactSegment preparedExactQuery;
    bool preparedExactQueryReady;


    /*
     * First boundary pass: collect every exact query/boundary breakpoint.
     */
    version (DigitalMars)
    {
        flatEdgeIndex = 0;
    }

    provenanceEdgeIndex = 0;

    foreach (ringIndex; 0 .. polygon.length)
    {
        const auto ring =
            polygon[ringIndex];

        foreach (edgeIndex; 0 .. ring.segmentCount)
        {
            const S edge =
                ring.segment(
                    edgeIndex
                );

            version (DigitalMars)
            {
                assert(flatEdgeIndex < edgeCount);

                if (
                    useEdgeBoundsPrefilter &&
                    !edgeBoundsMayMeetQuery(
                        queryBounds,
                        edge
                    )
                )
                {
                    ++flatEdgeIndex;
                    continue;
                }
            }
            else
            {
                if (
                    useEdgeBoundsPrefilter &&
                    !edgeBoundsMayMeetQuery(
                        queryBounds,
                        edge
                    )
                )
                {
                    continue;
                }
            }

            ExactOverlayPoint[2] ignoredEdgeEvents;
            size_t ignoredCount;

            const size_t rawEventStart =
                eventCount;

            version (DigitalMars)
            bool appended;
            else
            const bool appended =
                appendSegmentPairNodingEventsPreparedFirst(
                    query,
                    edge,
                    preparedExactQuery,
                    preparedExactQueryReady,
                    events[],
                    eventCount,
                    ignoredEdgeEvents[],
                    ignoredCount
                );

            version (DigitalMars)
            {
                if (reuseBoundaryContacts)
                {
                    const SegmentContactKind contact =
                        segmentContactKind(
                            query,
                            edge
                        );

                    boundaryContacts[flatEdgeIndex] =
                        contact;

                    appended =
                        appendSegmentPairNodingEventsKnownContactPreparedFirst(
                            query,
                            edge,
                            contact,
                            preparedExactQuery,
                            preparedExactQueryReady,
                            events[],
                            eventCount,
                            ignoredEdgeEvents[],
                            ignoredCount
                        );
                }
                else
                {
                    appended =
                        appendSegmentPairNodingEventsPreparedFirst(
                            query,
                            edge,
                            preparedExactQuery,
                            preparedExactQueryReady,
                            events[],
                            eventCount,
                            ignoredEdgeEvents[],
                            ignoredCount
                        );
                }
            }

            /*
             * The conservative bounds pass covers every raw insertion,
             * including duplicates. The global 2n + 2 bound remains valid.
             */
            assert(appended);

            if (prepareEventProvenance)
            {
                assert(provenanceEdgeIndex < edgeCount);

                if (eventCount != rawEventStart)
                {
                    edgeFirstRawEventPlusOne[
                        provenanceEdgeIndex
                    ] =
                        rawEventStart + 1;
                }

                ++provenanceEdgeIndex;
            }

            version (DigitalMars)
            {
                ++flatEdgeIndex;
            }
        }
    }

    version (DigitalMars)
    {
        assert(flatEdgeIndex == edgeCount);
    }

    if (prepareEventProvenance)
        assert(provenanceEdgeIndex == edgeCount);

    const bool reuseProperCrossingEventIndex =
        prepareEventProvenance &&
        eventCount >= equalPreferredEventThreshold;


    if (eventCount >= equalPreferredEventThreshold)
    {
        if (reuseProperCrossingEventIndex)
        {
            eventCount =
                sortUniqueExactEdgeEventsEqualPreferredWithRawMapping(
                    query,
                    events[0 .. eventCount],
                    rawEventIndices[0 .. eventCount],
                    rawToUnique[0 .. eventCount]
                );
        }
        else
        {
            eventCount =
                sortUniqueExactEdgeEventsEqualPreferred(
                    query,
                    events[0 .. eventCount]
                );
        }
    }
    else
    {
        eventCount =
            sortUniqueExactEdgeEvents(
                query,
                events[0 .. eventCount]
            );
    }

    assert(eventCount >= 2);
    assert(eventCount <= eventCapacity);

    events.length =
        eventCount;


    /*
     * Per-event overlap-range counters and outgoing non-boundary locations.
     *
     * An overlap interval [i,j) increments starts[i] and ends[j]. A prefix
     * count then marks every positive-length query interval lying on polygon
     * boundary.
     */
    auto boundaryStarts =
        new size_t[eventCount];

    auto boundaryEnds =
        new size_t[eventCount];

    auto afterLocation =
        new IntervalLocation[
            eventCount
        ];


    /*
     * Second boundary pass:
     *
     * - record overlap ranges;
     * - classify proper edge crossings and strict edge-interior endpoint
     *   contacts on their outgoing query ray.
     */
    version (DigitalMars)
    {
        flatEdgeIndex = 0;
    }

    provenanceEdgeIndex = 0;

    foreach (ringIndex; 0 .. polygon.length)
    {
        const auto ring =
            polygon[ringIndex];

        const int orientationSign =
            exactRingOrientationSign(
                ring
            );

        assert(
            ring.empty ||
            orientationSign != 0
        );

        const bool counterClockwise =
            orientationSign > 0;

        const bool isHole =
            ringIndex != 0;

        const bool interiorOnSourceLeft =
            counterClockwise !=
            isHole;


        foreach (edgeIndex; 0 .. ring.segmentCount)
        {
            const S edge =
                ring.segment(
                    edgeIndex
                );

            version (DigitalMars)
            {
                assert(flatEdgeIndex < edgeCount);

                if (
                    useEdgeBoundsPrefilter &&
                    !edgeBoundsMayMeetQuery(
                        queryBounds,
                        edge
                    )
                )
                {
                    ++flatEdgeIndex;
                    continue;
                }
            }
            else
            {
                if (
                    useEdgeBoundsPrefilter &&
                    !edgeBoundsMayMeetQuery(
                        queryBounds,
                        edge
                    )
                )
                {
                    continue;
                }
            }

            version (DigitalMars)
            const SegmentContactKind contact =
                reuseBoundaryContacts
                    ? boundaryContacts[flatEdgeIndex]
                    : segmentContactKind(
                        query,
                        edge
                    );
            else
            const SegmentContactKind contact =
                segmentContactKind(
                    query,
                    edge
                );

            const size_t currentProvenanceEdgeIndex =
                provenanceEdgeIndex;

            if (prepareEventProvenance)
            {
                assert(provenanceEdgeIndex < edgeCount);
                ++provenanceEdgeIndex;
            }

            version (DigitalMars)
            {
                ++flatEdgeIndex;
            }

            final switch (contact)
            {
                case SegmentContactKind.none:
                    break;

                case SegmentContactKind.properCrossing:
                {
                    size_t index;

                    if (reuseProperCrossingEventIndex)
                    {
                        const size_t rawEventPlusOne =
                            edgeFirstRawEventPlusOne[
                                currentProvenanceEdgeIndex
                            ];

                        assert(rawEventPlusOne != 0);

                        const size_t rawEventIndex =
                            rawEventPlusOne - 1;

                        assert(rawEventIndex < rawToUnique.length);

                        index =
                            rawToUnique[
                                rawEventIndex
                            ];
                    }
                    else
                    {
                        ExactProperIntersection crossing;

                        assert(preparedExactQueryReady);

                        properIntersectionExactKnownCrossingPreparedFirst(
                            preparedExactQuery,
                            edge,
                            crossing
                        );

                        const auto event =
                            exactOverlayPoint(
                                crossing
                            );

                        index =
                            findExactEventIndex(
                                query,
                                events[],
                                event
                            );
                    }

                    assert(index != size_t.max);
                    assert(index + 1 < eventCount);

                    setAfterLocation(
                        afterLocation[index],
                        edgeInteriorRayLocation(
                            edge,
                            query.b,
                            interiorOnSourceLeft
                        )
                    );

                    break;
                }

                case SegmentContactKind.touch:
                {
                    Point2!T point;

                    const bool found =
                        trySegmentTouchPoint(
                            query,
                            edge,
                            point
                        );

                    assert(found);

                    /*
                     * Polygon-vertex events need both incident edges and are
                     * classified in the vertex pass below.
                     */
                    if (
                        point == edge.a ||
                        point == edge.b ||
                        point == query.b
                    )
                    {
                        break;
                    }

                    const auto event =
                        exactOverlayPoint(
                            point
                        );

                    const size_t index =
                        findExactEventIndex(
                            query,
                            events[],
                            event
                        );

                    assert(index != size_t.max);
                    assert(index + 1 < eventCount);

                    setAfterLocation(
                        afterLocation[index],
                        edgeInteriorRayLocation(
                            edge,
                            query.b,
                            interiorOnSourceLeft
                        )
                    );

                    break;
                }

                case SegmentContactKind.overlap:
                {
                    S overlap;

                    const bool found =
                        trySegmentIntersectionOverlap(
                            query,
                            edge,
                            overlap
                        );

                    assert(found);
                    assert(overlap.a != overlap.b);

                    const auto first =
                        exactOverlayPoint(
                            overlap.a
                        );

                    const auto second =
                        exactOverlayPoint(
                            overlap.b
                        );

                    const size_t firstIndex =
                        findExactEventIndex(
                            query,
                            events[],
                            first
                        );

                    const size_t secondIndex =
                        findExactEventIndex(
                            query,
                            events[],
                            second
                        );

                    assert(firstIndex != size_t.max);
                    assert(secondIndex != size_t.max);
                    assert(firstIndex != secondIndex);

                    const size_t lower =
                        firstIndex < secondIndex
                            ? firstIndex
                            : secondIndex;

                    const size_t upper =
                        firstIndex < secondIndex
                            ? secondIndex
                            : firstIndex;

                    if (
                        boundaryStarts[lower] ==
                        size_t.max ||
                        boundaryEnds[upper] ==
                        size_t.max
                    )
                    {
                        onOutOfMemoryError();
                    }

                    ++boundaryStarts[lower];
                    ++boundaryEnds[upper];

                    break;
                }
            }
        }


        /*
         * Third local-topology pass for this ring:
         *
         * every represented polygon vertex lying on the query determines the
         * outgoing non-boundary ray location unless that ray follows boundary.
         */
        if (ring.length != 0)
        {
            foreach (vertexIndex; 0 .. ring.length)
            {
                const Point2!T vertex =
                    ring[vertexIndex];

                if (
                    !pointBoundsMayMeetQuery(
                        queryBounds,
                        vertex
                    )
                )
                {
                    continue;
                }

                if (
                    segmentContactKind(
                        query,
                        S(vertex, vertex)
                    ) == SegmentContactKind.none
                )
                {
                    continue;
                }

                if (vertex == query.b)
                    continue;

                const size_t previousIndex =
                    vertexIndex == 0
                        ? ring.length - 1
                        : vertexIndex - 1;

                const size_t nextIndex =
                    vertexIndex + 1 == ring.length
                        ? 0
                        : vertexIndex + 1;

                const IntervalLocation location =
                    vertexRayLocation(
                        ring[previousIndex],
                        vertex,
                        ring[nextIndex],
                        query.b,
                        interiorOnSourceLeft
                    );

                if (
                    location ==
                    IntervalLocation.unknown
                )
                {
                    continue;
                }

                const auto event =
                    exactOverlayPoint(
                        vertex
                    );

                const size_t index =
                    findExactEventIndex(
                        query,
                        events[],
                        event
                    );

                assert(index != size_t.max);
                assert(index + 1 < eventCount);

                setAfterLocation(
                    afterLocation[index],
                    location
                );
            }
        }
    }


    version (DigitalMars)
    {
        assert(flatEdgeIndex == edgeCount);
    }

    if (prepareEventProvenance)
        assert(provenanceEdgeIndex == edgeCount);

    auto retained =
        new bool[
            eventCount - 1
        ];

    size_t activeBoundaryOverlaps = 0;

    foreach (intervalIndex; 0 .. retained.length)
    {
        assert(
            activeBoundaryOverlaps >=
            boundaryEnds[intervalIndex]
        );

        activeBoundaryOverlaps -=
            boundaryEnds[intervalIndex];

        if (
            boundaryStarts[intervalIndex] >
            size_t.max -
            activeBoundaryOverlaps
        )
        {
            onOutOfMemoryError();
        }

        activeBoundaryOverlaps +=
            boundaryStarts[intervalIndex];

        if (activeBoundaryOverlaps != 0)
        {
            retained[intervalIndex] = true;
            continue;
        }

        if (
            afterLocation[intervalIndex] ==
            IntervalLocation.unknown
        )
        {
            /*
             * The first non-boundary interval may begin at a query endpoint
             * that is not on polygon boundary.
             *
             * Every later event is a boundary event and must have received a
             * local outgoing classification above.
             */
            assert(intervalIndex == 0);

            PointPolygonLocation location;

            const bool classified =
                tryClassifyPointInPolygon(
                    polygon,
                    query.a,
                    location
                );

            assert(classified);

            final switch (location)
            {
                case PointPolygonLocation.outside:
                    afterLocation[0] =
                        IntervalLocation.exterior;
                    break;

                case PointPolygonLocation.inside:
                    afterLocation[0] =
                        IntervalLocation.interior;
                    break;

                case PointPolygonLocation.boundary:
                    /*
                     * A boundary start with a non-boundary outgoing interval
                     * must have been classified by the strict-edge or vertex
                     * pass.
                     */
                    assert(false);
            }
        }

        retained[intervalIndex] =
            afterLocation[intervalIndex] ==
            IntervalLocation.interior;
    }

    assert(
        activeBoundaryOverlaps >=
        boundaryEnds[eventCount - 1]
    );

    activeBoundaryOverlaps -=
        boundaryEnds[eventCount - 1];

    assert(
        boundaryStarts[eventCount - 1] == 0
    );

    assert(activeBoundaryOverlaps == 0);


    size_t componentCount = 0;
    bool inRetainedComponent = false;

    foreach (keep; retained)
    {
        if (keep)
        {
            if (!inRetainedComponent)
            {
                if (componentCount == size_t.max)
                    onOutOfMemoryError();

                ++componentCount;
                inRetainedComponent = true;
            }
        }
        else
        {
            inRetainedComponent = false;
        }
    }


    auto components =
        new Segment2!double[
            componentCount
        ];

    size_t componentIndex = 0;
    size_t runStart = 0;
    bool inRun = false;

    Point2!double previousEnd;
    bool havePreviousEnd = false;

    foreach (intervalIndex; 0 .. retained.length + 1)
    {
        const bool keep =
            intervalIndex < retained.length
                ? retained[intervalIndex]
                : false;

        if (keep && !inRun)
        {
            runStart =
                intervalIndex;

            inRun = true;
            continue;
        }

        if (keep || !inRun)
            continue;

        const size_t runEnd =
            intervalIndex;

        assert(runStart < runEnd);
        assert(runEnd < eventCount);
        assert(componentIndex < components.length);

        Point2!double start;
        Point2!double end;

        if (
            !tryMaterializeExactPoint(
                events[runStart],
                start
            ) ||
            !tryMaterializeExactPoint(
                events[runEnd],
                end
            )
        )
        {
            return
                SegmentPolygonClipInternalStatus
                    .unrepresentableConstruction;
        }

        if (
            havePreviousEnd &&
            !roundedPointStrictlyAfter(
                query,
                previousEnd,
                start
            )
        )
        {
            return
                SegmentPolygonClipInternalStatus
                    .unrepresentableConstruction;
        }

        if (
            !roundedPointStrictlyAfter(
                query,
                start,
                end
            )
        )
        {
            return
                SegmentPolygonClipInternalStatus
                    .unrepresentableConstruction;
        }

        components[componentIndex++] =
            Segment2!double(
                start,
                end
            );

        previousEnd = end;
        havePreviousEnd = true;
        inRun = false;
    }

    assert(componentIndex == componentCount);

    owned =
        takeSegmentPolygonClipOwnedResultInternal(
            components
        );

    return
        SegmentPolygonClipInternalStatus.success;
}


@safe unittest
{
    import geo.linear_ring_view : LinearRing2View;
    import std.meta : AliasSeq;

    static foreach (T; AliasSeq!(int, long, float, double))
    {{
        alias P = Point2!T;
        alias S = Segment2!T;
        P[4] points = [P(0, 0), P(10, 0), P(10, 10), P(0, 10)];
        LinearRing2View!T[1] rings = [LinearRing2View!T(points[])];
        auto polygon = Polygon2View!T(rings[]);
        S[8] queries = [
            S(P(-2, 2), P(-1, 8)), // no contacts
            S(P(1, 1), P(9, 1)),   // interior, no contacts
            S(P(-1, 5), P(11, 5)), // two proper crossings
            S(P(-2, 2), P(2, -2)), // one vertex, two raw touches
            S(P(-1, 0), P(11, 0)), // overlap plus two endpoint touches
            S(P(0, 0), P(10, 0)),  // seeded endpoints still duplicated
            S(P(0, 5), P(5, 5)),   // one seeded endpoint contact
            S(P(-2, 1), P(1, -2)), // overlapping bounds, no actual contacts
        ];
        size_t[8] expectedCapacity = [2, 2, 6, 6, 8, 8, 4, 6];
        size_t[8] expectedRawCount = [2, 2, 4, 4, 6, 6, 3, 2];

        foreach (i, original; queries)
        {
            foreach (query; [original, S(original.b, original.a)])
            {
                Bounds2!T queryBounds;
                assert(
                    tryBounds(
                        query,
                        queryBounds
                    )
                );

                const capacity =
                    queryBoundaryEventCapacity(
                        queryBounds,
                        polygon
                    );

                assert(capacity == expectedCapacity[i]);

                // Exercise the existing writer at exactly that capacity.
                auto events = new ExactOverlayPoint[capacity];
                size_t count;
                assert(seedExactEdgeEvents(query, events, count));
                foreach (edgeIndex; 0 .. rings[0].segmentCount)
                {
                    ExactOverlayPoint[2] ignored;
                    size_t ignoredCount;
                    assert(appendSegmentPairNodingEvents(query,
                        rings[0].segment(edgeIndex), events, count,
                        ignored[], ignoredCount));
                }
                assert(count == expectedRawCount[i]);
                assert(count <= capacity);
            }
        }
    }}
}
