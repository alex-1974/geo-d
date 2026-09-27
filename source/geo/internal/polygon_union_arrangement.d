module geo.internal.polygon_union_arrangement;

import geo.internal.dyadic :
    SignedDyadicDifference,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    compareExactOverlayPoints,
    exactOverlayPointsEqual;

import geo.internal.polygon_union_noding :
    ExactAtomicEdge;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact arrangement-vertex identity and angular embedding support for the P1
 * polygon-union overlay.
 *
 * Rounded construction coordinates do not participate in vertex identity,
 * edge incidence, or angular order.
 */


private enum bool isPolygonUnionArrangementScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/*
 * One globally noded arrangement edge after exact vertex deduplication.
 *
 * firstVertex/secondVertex follow the canonical exact endpoint order inherited
 * from ExactAtomicEdge.
 */
struct ExactArrangementEdge(T)
if (isPolygonUnionArrangementScalar!T)
{
    size_t firstVertex;
    size_t secondVertex;

    ubyte operandMask;

    Segment2!T source;
    bool canonicalFollowsSource;

    ubyte interiorLeftMask;
}


/*
 * Exact direction inherited from one represented source segment.
 *
 * Components live in the established signed dyadic-difference domain. No
 * rational overlay-vertex subtraction is needed.
 */
struct ExactSourceDirection
{
    SignedDyadicDifference x;
    SignedDyadicDifference y;
}


/*
 * Restores max-heap ordering for exact points.
 */
private void siftDownExactPoints(
    scope ExactOverlayPoint[] points,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
{
    while (true)
    {
        const size_t left =
            root * 2 + 1;

        if (left >= end)
            return;

        size_t largest = root;

        if (
            compareExactOverlayPoints(
                points[largest],
                points[left]
            ) < 0
        )
        {
            largest = left;
        }

        const size_t right =
            left + 1;

        if (
            right < end &&
            compareExactOverlayPoints(
                points[largest],
                points[right]
            ) < 0
        )
        {
            largest = right;
        }

        if (largest == root)
            return;

        const ExactOverlayPoint temporary =
            points[root];

        points[root] =
            points[largest];

        points[largest] =
            temporary;

        root = largest;
    }
}


/*
 * Sorts exact points lexicographically and removes exact duplicates in-place.
 */
private size_t sortUniqueExactPoints(
    scope ExactOverlayPoint[] points
)
    pure nothrow @safe @nogc
{
    if (points.length < 2)
        return points.length;

    size_t start =
        points.length / 2;

    while (start > 0)
    {
        --start;

        siftDownExactPoints(
            points,
            start,
            points.length
        );
    }

    size_t end =
        points.length;

    while (end > 1)
    {
        --end;

        const ExactOverlayPoint temporary =
            points[0];

        points[0] =
            points[end];

        points[end] =
            temporary;

        siftDownExactPoints(
            points,
            0,
            end
        );
    }

    size_t write = 1;

    foreach (read; 1 .. points.length)
    {
        if (
            !exactOverlayPointsEqual(
                points[write - 1],
                points[read]
            )
        )
        {
            if (write != read)
                points[write] = points[read];

            ++write;
        }
    }

    return write;
}


/*
 * Finds one exact point in an already sorted unique vertex table.
 *
 * Returns size_t.max when absent.
 */
private size_t findExactVertex(
    scope const(ExactOverlayPoint)[] vertices,
    ref const ExactOverlayPoint point
)
    pure nothrow @safe @nogc
{
    size_t lower = 0;
    size_t upper = vertices.length;

    while (lower < upper)
    {
        const size_t middle =
            lower +
            (upper - lower) / 2;

        const int comparison =
            compareExactOverlayPoints(
                vertices[middle],
                point
            );

        if (comparison < 0)
        {
            lower =
                middle + 1;
        }
        else
        {
            upper =
                middle;
        }
    }

    if (
        lower < vertices.length &&
        exactOverlayPointsEqual(
            vertices[lower],
            point
        )
    )
    {
        return lower;
    }

    return size_t.max;
}


/*
 * Builds the deterministic exact vertex table and vertex-indexed arrangement
 * edges from already merged canonical atomic edges.
 *
 * vertices needs capacity for at most 2 * atomicEdges.length points.
 * edges needs capacity for atomicEdges.length records.
 *
 * No partial counts are exposed on capacity failure.
 */
bool buildExactArrangement(T)(
    scope const(ExactAtomicEdge!T)[] atomicEdges,
    scope ExactOverlayPoint[] vertices,
    scope ExactArrangementEdge!T[] edges,
    out size_t vertexCount,
    out size_t edgeCount
)
    pure nothrow @safe @nogc
if (isPolygonUnionArrangementScalar!T)
{
    vertexCount = 0;
    edgeCount = 0;

    if (
        atomicEdges.length >
        size_t.max / 2
    )
    {
        return false;
    }

    const size_t requiredVertexCapacity =
        atomicEdges.length * 2;

    if (
        vertices.length < requiredVertexCapacity ||
        edges.length < atomicEdges.length
    )
    {
        return false;
    }

    foreach (i, ref const edge; atomicEdges)
    {
        vertices[i * 2] =
            edge.a;

        vertices[i * 2 + 1] =
            edge.b;
    }

    vertexCount =
        sortUniqueExactPoints(
            vertices[
                0 ..
                requiredVertexCapacity
            ]
        );

    foreach (i, ref const atomic; atomicEdges)
    {
        const size_t first =
            findExactVertex(
                vertices[0 .. vertexCount],
                atomic.a
            );

        const size_t second =
            findExactVertex(
                vertices[0 .. vertexCount],
                atomic.b
            );

        assert(first != size_t.max);
        assert(second != size_t.max);
        assert(first != second);
        assert(first < second);

        edges[i] =
            ExactArrangementEdge!T(
                first,
                second,
                atomic.operandMask,
                atomic.source,
                atomic.canonicalFollowsSource,
                atomic.interiorLeftMask
            );
    }

    edgeCount =
        atomicEdges.length;

    return true;
}


/*
 * Exact represented source direction.
 *
 * forward == true:
 *     source.a -> source.b
 *
 * forward == false:
 *     source.b -> source.a
 */
private ExactSourceDirection sourceDirection(T)(
    Segment2!T source,
    bool forward
)
    pure nothrow @safe @nogc
if (isPolygonUnionArrangementScalar!T)
{
    assert(source.a != source.b);

    const auto aX =
        decodeDyadicCoordinate(
            source.a.x
        );

    const auto aY =
        decodeDyadicCoordinate(
            source.a.y
        );

    const auto bX =
        decodeDyadicCoordinate(
            source.b.x
        );

    const auto bY =
        decodeDyadicCoordinate(
            source.b.y
        );

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
 * Returns the exact direction of one arrangement edge half-edge.
 *
 * forward == true means firstVertex -> secondVertex.
 * forward == false means secondVertex -> firstVertex.
 */
ExactSourceDirection exactArrangementEdgeDirection(T)(
    ref const ExactArrangementEdge!T edge,
    bool forward
)
    pure nothrow @safe @nogc
if (isPolygonUnionArrangementScalar!T)
{
    const bool sourceForward =
        forward ==
        edge.canonicalFollowsSource;

    return
        sourceDirection(
            edge.source,
            sourceForward
        );
}


/*
 * True for directions in [0, pi), using +x as angular zero.
 *
 * The negative x axis belongs to the lower half.
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
 *     -1 lhs occurs before rhs from +x in [0, 2*pi)
 *      0 lhs and rhs are the same ray
 *      1 lhs occurs after rhs
 *
 * The determinant uses only exact represented source-coordinate differences
 * and remains in the established dyadic-product domain.
 */
int compareExactSourceDirectionsCCW(
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
     * Same half plus zero determinant means the same ray. Opposite rays lie
     * in different angular halves.
     */
    return 0;
}


@safe unittest
{
    import geo.internal.polygon_union_exact :
        appendSegmentPairNodingEvents,
        seedExactEdgeEvents,
        sortUniqueExactEdgeEvents;

    import geo.internal.polygon_union_noding :
        buildExactAtomicEdgesFromNodedSource,
        polygonUnionOperandA,
        polygonUnionOperandB,
        sortMergeExactAtomicEdges;

    import geo.point :
        Point2;

    alias P = Point2!int;
    alias S = Segment2!int;
    alias A = ExactAtomicEdge!int;
    alias E = ExactArrangementEdge!int;


    /*
     * Proper crossing: four atomic edges share one exact center vertex.
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

        A[4] atomic;
        size_t firstAtomicCount;
        size_t secondAtomicCount;

        assert(
            buildExactAtomicEdgesFromNodedSource(
                first,
                polygonUnionOperandA,
                true,
                firstEvents[0 .. firstEventCount],
                atomic[0 .. 2],
                firstAtomicCount
            )
        );

        assert(
            buildExactAtomicEdgesFromNodedSource(
                second,
                polygonUnionOperandB,
                true,
                secondEvents[0 .. secondEventCount],
                atomic[2 .. 4],
                secondAtomicCount
            )
        );

        assert(firstAtomicCount == 2);
        assert(secondAtomicCount == 2);

        const size_t atomicCount =
            sortMergeExactAtomicEdges(
                atomic[]
            );

        assert(atomicCount == 4);

        ExactOverlayPoint[8] vertices;
        E[4] edges;

        size_t vertexCount;
        size_t edgeCount;

        assert(
            buildExactArrangement(
                atomic[0 .. atomicCount],
                vertices[],
                edges[],
                vertexCount,
                edgeCount
            )
        );

        assert(vertexCount == 5);
        assert(edgeCount == 4);

        size_t degreeFourVertex =
            size_t.max;

        foreach (vertex; 0 .. vertexCount)
        {
            size_t degree = 0;

            foreach (ref edge; edges[0 .. edgeCount])
            {
                if (
                    edge.firstVertex == vertex ||
                    edge.secondVertex == vertex
                )
                {
                    ++degree;
                }
            }

            if (degree == 4)
            {
                assert(degreeFourVertex == size_t.max);
                degreeFourVertex = vertex;
            }
        }

        assert(degreeFourVertex != size_t.max);
    }


    /*
     * Partial overlap retains four exact vertices and A / AB / B provenance
     * after global vertex indexing.
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

        A[4] atomic;
        size_t firstAtomicCount;
        size_t secondAtomicCount;

        assert(
            buildExactAtomicEdgesFromNodedSource(
                first,
                polygonUnionOperandA,
                true,
                firstEvents[0 .. firstEventCount],
                atomic[0 .. 2],
                firstAtomicCount
            )
        );

        assert(
            buildExactAtomicEdgesFromNodedSource(
                second,
                polygonUnionOperandB,
                true,
                secondEvents[0 .. secondEventCount],
                atomic[2 .. 4],
                secondAtomicCount
            )
        );

        const size_t atomicCount =
            sortMergeExactAtomicEdges(
                atomic[
                    0 ..
                    firstAtomicCount +
                    secondAtomicCount
                ]
            );

        assert(atomicCount == 3);

        ExactOverlayPoint[8] vertices;
        E[4] edges;

        size_t vertexCount;
        size_t edgeCount;

        assert(
            buildExactArrangement(
                atomic[0 .. atomicCount],
                vertices[],
                edges[],
                vertexCount,
                edgeCount
            )
        );

        assert(vertexCount == 4);
        assert(edgeCount == 3);

        assert(edges[0].firstVertex == 0);
        assert(edges[0].secondVertex == 1);

        assert(edges[1].firstVertex == 1);
        assert(edges[1].secondVertex == 2);

        assert(edges[2].firstVertex == 2);
        assert(edges[2].secondVertex == 3);
    }
}


@safe unittest
{
    import geo.internal.polygon_union_noding :
        polygonUnionOperandA;

    import geo.point :
        Point2;

    alias P = Point2!long;
    alias S = Segment2!long;
    alias E = ExactArrangementEdge!long;


    /*
     * Full-range signed-long source directions do not overflow subtraction.
     */
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

    const E eastEdge =
        E(
            0,
            1,
            polygonUnionOperandA,
            east,
            true,
            polygonUnionOperandA
        );

    const E northEdge =
        E(
            0,
            2,
            polygonUnionOperandA,
            north,
            true,
            polygonUnionOperandA
        );

    const auto eastDirection =
        exactArrangementEdgeDirection(
            eastEdge,
            true
        );

    const auto northDirection =
        exactArrangementEdgeDirection(
            northEdge,
            true
        );

    assert(
        compareExactSourceDirectionsCCW(
            eastDirection,
            northDirection
        ) < 0
    );

    const auto westDirection =
        exactArrangementEdgeDirection(
            eastEdge,
            false
        );

    assert(
        compareExactSourceDirectionsCCW(
            northDirection,
            westDirection
        ) < 0
    );
}


@safe unittest
{
    import geo.internal.polygon_union_noding :
        polygonUnionOperandA;

    import geo.point :
        Point2;

    alias P = Point2!double;
    alias S = Segment2!double;
    alias E = ExactArrangementEdge!double;


    /*
     * Full-range finite binary64 direction products remain exact.
     */
    const S east =
        S(
            P(-double.max, 0.0),
            P(double.max, 0.0)
        );

    const S northEast =
        S(
            P(-double.max, -double.max),
            P(double.max, double.max)
        );

    const S north =
        S(
            P(0.0, -double.max),
            P(0.0, double.max)
        );

    const E eastEdge =
        E(
            0,
            1,
            polygonUnionOperandA,
            east,
            true,
            polygonUnionOperandA
        );

    const E northEastEdge =
        E(
            0,
            2,
            polygonUnionOperandA,
            northEast,
            true,
            polygonUnionOperandA
        );

    const E northEdge =
        E(
            0,
            3,
            polygonUnionOperandA,
            north,
            true,
            polygonUnionOperandA
        );

    const auto eastDirection =
        exactArrangementEdgeDirection(
            eastEdge,
            true
        );

    const auto northEastDirection =
        exactArrangementEdgeDirection(
            northEastEdge,
            true
        );

    const auto northDirection =
        exactArrangementEdgeDirection(
            northEdge,
            true
        );

    assert(
        compareExactSourceDirectionsCCW(
            eastDirection,
            northEastDirection
        ) < 0
    );

    assert(
        compareExactSourceDirectionsCCW(
            northEastDirection,
            northDirection
        ) < 0
    );
}
