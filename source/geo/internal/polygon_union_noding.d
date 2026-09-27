module geo.internal.polygon_union_noding;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    appendSegmentPairNodingEvents,
    compareExactOverlayPoints,
    compareExactOverlayPointsAlongSegment,
    exactOverlayPoint,
    exactOverlayPointsEqual,
    seedExactEdgeEvents,
    sortUniqueExactEdgeEvents;

import geo.point :
    Point2;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact noded boundary spans for the P1 polygon-union arrangement.
 *
 * Every source edge is split at its exact event points. Consecutive exact
 * events become atomic edges. Atomic edges are stored in exact canonical
 * endpoint order so geometrically coincident spans can be deduplicated across
 * operands without using rounded construction coordinates.
 */


private enum bool isPolygonUnionNodingScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


enum ubyte polygonUnionOperandA = 1;
enum ubyte polygonUnionOperandB = 2;


/*
 * One exact atomic arrangement edge before global vertex-ID assignment.
 *
 * a/b are in exact lexicographic canonical order.
 *
 * source preserves one represented contributing source segment for later
 * exact angular embedding. canonicalFollowsSource says whether source.a ->
 * source.b points in the same direction as canonical a -> b.
 *
 * operandMask records which polygon boundaries contribute to this geometric
 * atomic span.
 */
struct ExactAtomicEdge(T)
if (isPolygonUnionNodingScalar!T)
{
    ExactOverlayPoint a;
    ExactOverlayPoint b;

    ubyte operandMask;

    Segment2!T source;
    bool canonicalFollowsSource;
}


/*
 * Exact comparison of canonical atomic edges by endpoint pair.
 */
int compareExactAtomicEdges(T)(
    ref const ExactAtomicEdge!T lhs,
    ref const ExactAtomicEdge!T rhs
)
    pure nothrow @safe @nogc
if (isPolygonUnionNodingScalar!T)
{
    const int first =
        compareExactOverlayPoints(
            lhs.a,
            rhs.a
        );

    if (first != 0)
        return first;

    return
        compareExactOverlayPoints(
            lhs.b,
            rhs.b
        );
}


/*
 * Exact equality of canonical atomic edges.
 */
bool exactAtomicEdgesEqual(T)(
    ref const ExactAtomicEdge!T lhs,
    ref const ExactAtomicEdge!T rhs
)
    pure nothrow @safe @nogc
if (isPolygonUnionNodingScalar!T)
{
    return
        exactOverlayPointsEqual(
            lhs.a,
            rhs.a
        ) &&
        exactOverlayPointsEqual(
            lhs.b,
            rhs.b
        );
}


/*
 * Builds canonical atomic edges from one already sorted/unique source-edge
 * event list.
 *
 * The event order must be source.a -> source.b. Exact endpoint
 * canonicalization is independent of source traversal direction.
 *
 * Capacity is checked before writes.
 */
bool buildExactAtomicEdgesFromNodedSource(T)(
    Segment2!T source,
    ubyte operandMask,
    scope const(ExactOverlayPoint)[] events,
    scope ExactAtomicEdge!T[] edges,
    out size_t count
)
    pure nothrow @safe @nogc
if (isPolygonUnionNodingScalar!T)
{
    count = 0;

    assert(source.a != source.b);

    assert(
        operandMask == polygonUnionOperandA ||
        operandMask == polygonUnionOperandB
    );

    if (events.length < 2)
        return false;

    const size_t required =
        events.length - 1;

    if (edges.length < required)
        return false;

    foreach (i; 0 .. required)
    {
        const auto first =
            events[i];

        const auto second =
            events[i + 1];

        assert(
            compareExactOverlayPointsAlongSegment(
                source,
                first,
                second
            ) < 0
        );

        const int canonicalComparison =
            compareExactOverlayPoints(
                first,
                second
            );

        assert(canonicalComparison != 0);

        if (canonicalComparison < 0)
        {
            edges[i] =
                ExactAtomicEdge!T(
                    first,
                    second,
                    operandMask,
                    source,
                    true
                );
        }
        else
        {
            edges[i] =
                ExactAtomicEdge!T(
                    second,
                    first,
                    operandMask,
                    source,
                    false
                );
        }
    }

    count = required;

    return true;
}


/*
 * Restores max-heap ordering by exact canonical endpoint pair.
 */
private void siftDownExactAtomicEdges(T)(
    scope ExactAtomicEdge!T[] edges,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
if (isPolygonUnionNodingScalar!T)
{
    while (true)
    {
        const size_t left =
            root * 2 + 1;

        if (left >= end)
            return;

        size_t largest = root;

        if (
            compareExactAtomicEdges(
                edges[largest],
                edges[left]
            ) < 0
        )
        {
            largest = left;
        }

        const size_t right =
            left + 1;

        if (
            right < end &&
            compareExactAtomicEdges(
                edges[largest],
                edges[right]
            ) < 0
        )
        {
            largest = right;
        }

        if (largest == root)
            return;

        const ExactAtomicEdge!T temporary =
            edges[root];

        edges[root] =
            edges[largest];

        edges[largest] =
            temporary;

        root = largest;
    }
}


/*
 * Sorts canonical atomic edges and merges geometrically identical spans.
 *
 * Merging is exact and direction-independent because endpoint pairs are
 * canonicalized before this function. Operand provenance is combined with
 * bitwise OR.
 *
 * The first exact source-direction witness is retained. Any coincident source
 * witness is collinear with the same canonical span, so its magnitude does not
 * affect later angular-order signs.
 *
 * Returns the number of unique atomic edges in edges[0 .. result].
 */
size_t sortMergeExactAtomicEdges(T)(
    scope ExactAtomicEdge!T[] edges
)
    pure nothrow @safe @nogc
if (isPolygonUnionNodingScalar!T)
{
    if (edges.length < 2)
        return edges.length;

    size_t start =
        edges.length / 2;

    while (start > 0)
    {
        --start;

        siftDownExactAtomicEdges(
            edges,
            start,
            edges.length
        );
    }

    size_t end =
        edges.length;

    while (end > 1)
    {
        --end;

        const ExactAtomicEdge!T temporary =
            edges[0];

        edges[0] =
            edges[end];

        edges[end] =
            temporary;

        siftDownExactAtomicEdges(
            edges,
            0,
            end
        );
    }

    size_t write = 1;

    foreach (read; 1 .. edges.length)
    {
        if (
            exactAtomicEdgesEqual(
                edges[write - 1],
                edges[read]
            )
        )
        {
            edges[write - 1].operandMask |=
                edges[read].operandMask;

            continue;
        }

        if (write != read)
            edges[write] = edges[read];

        ++write;
    }

    return write;
}


@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;
    alias E = ExactAtomicEdge!int;

    enum ubyte both =
        polygonUnionOperandA |
        polygonUnionOperandB;


    /*
     * Partial collinear overlap:
     *
     *     A: 0-----------4
     *     B:       2-----------6
     *
     * Exact atomic provenance becomes A / AB / B.
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

        ExactOverlayPoint[6] firstEvents;
        ExactOverlayPoint[6] secondEvents;

        size_t firstEventCount;
        size_t secondEventCount;

        assert(
            seedExactEdgeEvents(
                first,
                firstEvents[],
                firstEventCount
            )
        );

        assert(
            seedExactEdgeEvents(
                second,
                secondEvents[],
                secondEventCount
            )
        );

        assert(
            appendSegmentPairNodingEvents(
                first,
                second,
                firstEvents[],
                firstEventCount,
                secondEvents[],
                secondEventCount
            )
        );

        firstEventCount =
            sortUniqueExactEdgeEvents(
                first,
                firstEvents[0 .. firstEventCount]
            );

        secondEventCount =
            sortUniqueExactEdgeEvents(
                second,
                secondEvents[0 .. secondEventCount]
            );

        E[3] firstEdges;
        E[3] secondEdges;

        size_t firstEdgeCount;
        size_t secondEdgeCount;

        assert(
            buildExactAtomicEdgesFromNodedSource(
                first,
                polygonUnionOperandA,
                firstEvents[0 .. firstEventCount],
                firstEdges[],
                firstEdgeCount
            )
        );

        assert(
            buildExactAtomicEdgesFromNodedSource(
                second,
                polygonUnionOperandB,
                secondEvents[0 .. secondEventCount],
                secondEdges[],
                secondEdgeCount
            )
        );

        assert(firstEdgeCount == 2);
        assert(secondEdgeCount == 2);

        E[4] all;

        all[0 .. firstEdgeCount] =
            firstEdges[0 .. firstEdgeCount];

        all[
            firstEdgeCount ..
            firstEdgeCount + secondEdgeCount
        ] =
            secondEdges[0 .. secondEdgeCount];

        const size_t count =
            sortMergeExactAtomicEdges(
                all[
                    0 ..
                    firstEdgeCount +
                    secondEdgeCount
                ]
            );

        assert(count == 3);

        assert(
            all[0].operandMask ==
            polygonUnionOperandA
        );

        assert(
            all[1].operandMask ==
            both
        );

        assert(
            all[2].operandMask ==
            polygonUnionOperandB
        );

        const auto p0 =
            exactOverlayPoint(
                P(0, 0)
            );

        const auto p2 =
            exactOverlayPoint(
                P(2, 0)
            );

        const auto p4 =
            exactOverlayPoint(
                P(4, 0)
            );

        const auto p6 =
            exactOverlayPoint(
                P(6, 0)
            );

        assert(exactOverlayPointsEqual(all[0].a, p0));
        assert(exactOverlayPointsEqual(all[0].b, p2));

        assert(exactOverlayPointsEqual(all[1].a, p2));
        assert(exactOverlayPointsEqual(all[1].b, p4));

        assert(exactOverlayPointsEqual(all[2].a, p4));
        assert(exactOverlayPointsEqual(all[2].b, p6));
    }


    /*
     * Identical shared edge with opposite source traversal becomes one exact
     * AB atomic edge. The retained source witness correctly records whether
     * canonical orientation follows that source.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(4, 0)
            );

        const S second =
            S(
                P(4, 0),
                P(0, 0)
            );

        ExactOverlayPoint[4] firstEvents;
        ExactOverlayPoint[4] secondEvents;

        size_t firstEventCount;
        size_t secondEventCount;

        assert(seedExactEdgeEvents(first, firstEvents[], firstEventCount));
        assert(seedExactEdgeEvents(second, secondEvents[], secondEventCount));

        assert(
            appendSegmentPairNodingEvents(
                first,
                second,
                firstEvents[],
                firstEventCount,
                secondEvents[],
                secondEventCount
            )
        );

        firstEventCount =
            sortUniqueExactEdgeEvents(
                first,
                firstEvents[0 .. firstEventCount]
            );

        secondEventCount =
            sortUniqueExactEdgeEvents(
                second,
                secondEvents[0 .. secondEventCount]
            );

        E[2] edges;
        size_t countA;
        size_t countB;

        assert(
            buildExactAtomicEdgesFromNodedSource(
                first,
                polygonUnionOperandA,
                firstEvents[0 .. firstEventCount],
                edges[0 .. 1],
                countA
            )
        );

        assert(
            buildExactAtomicEdgesFromNodedSource(
                second,
                polygonUnionOperandB,
                secondEvents[0 .. secondEventCount],
                edges[1 .. 2],
                countB
            )
        );

        assert(countA == 1);
        assert(countB == 1);

        assert(edges[0].canonicalFollowsSource);
        assert(!edges[1].canonicalFollowsSource);

        const size_t count =
            sortMergeExactAtomicEdges(
                edges[]
            );

        assert(count == 1);
        assert(edges[0].operandMask == both);
    }


    /*
     * Proper crossing creates four atomic edges. They share one exact
     * arrangement vertex but no geometric span, so no edge merge occurs.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const S second =
            S(
                P(5, -5),
                P(5, 5)
            );

        ExactOverlayPoint[4] firstEvents;
        ExactOverlayPoint[4] secondEvents;

        size_t firstEventCount;
        size_t secondEventCount;

        assert(seedExactEdgeEvents(first, firstEvents[], firstEventCount));
        assert(seedExactEdgeEvents(second, secondEvents[], secondEventCount));

        assert(
            appendSegmentPairNodingEvents(
                first,
                second,
                firstEvents[],
                firstEventCount,
                secondEvents[],
                secondEventCount
            )
        );

        firstEventCount =
            sortUniqueExactEdgeEvents(
                first,
                firstEvents[0 .. firstEventCount]
            );

        secondEventCount =
            sortUniqueExactEdgeEvents(
                second,
                secondEvents[0 .. secondEventCount]
            );

        E[4] edges;
        size_t firstEdgeCount;
        size_t secondEdgeCount;

        assert(
            buildExactAtomicEdgesFromNodedSource(
                first,
                polygonUnionOperandA,
                firstEvents[0 .. firstEventCount],
                edges[0 .. 2],
                firstEdgeCount
            )
        );

        assert(
            buildExactAtomicEdgesFromNodedSource(
                second,
                polygonUnionOperandB,
                secondEvents[0 .. secondEventCount],
                edges[2 .. 4],
                secondEdgeCount
            )
        );

        assert(firstEdgeCount == 2);
        assert(secondEdgeCount == 2);

        const size_t count =
            sortMergeExactAtomicEdges(
                edges[]
            );

        assert(count == 4);

        size_t aCount = 0;
        size_t bCount = 0;

        foreach (edge; edges[0 .. count])
        {
            if (
                edge.operandMask ==
                polygonUnionOperandA
            )
            {
                ++aCount;
            }
            else if (
                edge.operandMask ==
                polygonUnionOperandB
            )
            {
                ++bCount;
            }
            else
            {
                assert(false);
            }
        }

        assert(aCount == 2);
        assert(bCount == 2);
    }


    /*
     * Endpoint-only contact shares one exact vertex but does not create one
     * shared AB edge.
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

        ExactOverlayPoint[4] firstEvents;
        ExactOverlayPoint[4] secondEvents;

        size_t firstEventCount;
        size_t secondEventCount;

        assert(seedExactEdgeEvents(first, firstEvents[], firstEventCount));
        assert(seedExactEdgeEvents(second, secondEvents[], secondEventCount));

        assert(
            appendSegmentPairNodingEvents(
                first,
                second,
                firstEvents[],
                firstEventCount,
                secondEvents[],
                secondEventCount
            )
        );

        firstEventCount =
            sortUniqueExactEdgeEvents(
                first,
                firstEvents[0 .. firstEventCount]
            );

        secondEventCount =
            sortUniqueExactEdgeEvents(
                second,
                secondEvents[0 .. secondEventCount]
            );

        E[2] edges;
        size_t firstEdgeCount;
        size_t secondEdgeCount;

        assert(
            buildExactAtomicEdgesFromNodedSource(
                first,
                polygonUnionOperandA,
                firstEvents[0 .. firstEventCount],
                edges[0 .. 1],
                firstEdgeCount
            )
        );

        assert(
            buildExactAtomicEdgesFromNodedSource(
                second,
                polygonUnionOperandB,
                secondEvents[0 .. secondEventCount],
                edges[1 .. 2],
                secondEdgeCount
            )
        );

        assert(firstEdgeCount == 1);
        assert(secondEdgeCount == 1);

        const size_t count =
            sortMergeExactAtomicEdges(
                edges[]
            );

        assert(count == 2);

        assert(
            edges[0].operandMask !=
            (
                polygonUnionOperandA |
                polygonUnionOperandB
            )
        );

        assert(
            edges[1].operandMask !=
            (
                polygonUnionOperandA |
                polygonUnionOperandB
            )
        );

        assert(
            exactOverlayPointsEqual(
                edges[0].b,
                edges[1].a
            )
        );
    }
}
