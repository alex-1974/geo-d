module geo.internal.polygon_union_materialization;

import geo.internal.exact_coordinate :
    roundsToFiniteBinary64;

import geo.internal.exact_coordinate_round :
    roundExactCoordinateBinary64;

import geo.internal.polygon_union_boundary :
    ExactUnionBoundaryCycle;

import geo.internal.polygon_union_canonical :
    canonicalExactUnionCycleStart;

import geo.internal.polygon_union_embedding :
    ExactArrangementHalfEdge;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind,
    trySegmentTouchPoint;

import geo.point :
    Point2;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * All-or-nothing binary64 materialization support for the exact polygon-union
 * result boundary.
 *
 * Only exact vertices referenced by selected result cycles are materialized.
 * Internal arrangement vertices that do not belong to the result cannot cause
 * a false representability failure.
 */


struct MaterializedUnionBoundaryEdge
{
    size_t firstVertex;
    size_t secondVertex;
}


/*
 * Verifies that binary64 materialization preserves the exact selected
 * boundary-incidence graph represented by compact exact vertex IDs.
 *
 * points is indexed by materialized boundary vertex ID. Different indices
 * denote different exact result vertices; equal indices denote one shared
 * exact vertex/contact.
 */
bool materializedUnionBoundaryIncidencePreserved(
    scope const(Point2!double)[] points,
    scope const(MaterializedUnionBoundaryEdge)[] edges
)
    pure nothrow @safe @nogc
{
    foreach (i; 0 .. points.length)
    {
        if (!points[i].isFinite)
            return false;

        foreach (j; i + 1 .. points.length)
        {
            if (
                points[i] ==
                points[j]
            )
            {
                return false;
            }
        }
    }


    foreach (edge; edges)
    {
        if (
            edge.firstVertex >= points.length ||
            edge.secondVertex >= points.length ||
            edge.firstVertex == edge.secondVertex ||
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
            size_t sharedVertex =
                size_t.max;

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

            /*
             * Duplicate/reversed duplicate selected boundary edges are not a
             * valid simple-cycle boundary graph.
             */
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
                touch !=
                    points[
                        sharedVertex
                    ]
            )
            {
                return false;
            }
        }
    }

    return true;
}


/*
 * Correctly rounds one exact overlay point to binary64.
 *
 * Returns false instead of invoking roundExactCoordinateBinary64 when either
 * exact coordinate lies outside the finite binary64 rounding domain.
 */
private bool tryMaterializeExactOverlayPoint(
    ref const ExactOverlayPoint exact,
    out Point2!double point
)
    pure nothrow @safe @nogc
{
    point =
        Point2!double.init;

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
 * Materializes the complete selected boundary graph.
 *
 * orderedCycles must contain every result cycle exactly once in the already
 * established canonical component/ring order.
 *
 * exactToMaterialized must contain one entry per exact arrangement vertex and
 * is overwritten. size_t.max denotes an exact vertex not used by the selected
 * result or not yet materialized.
 *
 * materializedPoints needs worst-case capacity exactVertices.length.
 *
 * materializedEdges needs capacity for the sum of all selected cycle edges.
 *
 * The function:
 *
 * 1. walks each cycle from its exact canonical start;
 * 2. materializes each required exact vertex once;
 * 3. preserves shared exact point-contact identity through one compact vertex
 *    index;
 * 4. emits the complete selected boundary edge graph;
 * 5. verifies that rounding preserved the graph exactly.
 *
 * On any geometric representability failure pointCount and edgeCount are
 * reset to zero. Caller storage may contain scratch values but no partial
 * result length is exposed.
 */
bool tryMaterializeExactUnionBoundaryGraph(
    scope const(ExactOverlayPoint)[] exactVertices,
    scope const(ExactUnionBoundaryCycle)[] cycles,
    scope const(size_t)[] orderedCycles,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope size_t[] exactToMaterialized,
    scope Point2!double[] materializedPoints,
    scope MaterializedUnionBoundaryEdge[] materializedEdges,
    out size_t pointCount,
    out size_t edgeCount
)
    pure nothrow @safe @nogc
{
    pointCount = 0;
    edgeCount = 0;

    if (
        exactToMaterialized.length !=
            exactVertices.length ||
        materializedPoints.length <
            exactVertices.length ||
        nextSelected.length !=
            halfEdges.length
    )
    {
        return false;
    }

    foreach (ref value; exactToMaterialized)
        value = size_t.max;


    size_t requiredEdgeCount = 0;

    foreach (cycleIndex; orderedCycles)
    {
        if (cycleIndex >= cycles.length)
            return false;

        const size_t cycleEdges =
            cycles[
                cycleIndex
            ].edgeCount;

        if (
            cycleEdges < 3 ||
            requiredEdgeCount >
                size_t.max -
                cycleEdges
        )
        {
            return false;
        }

        requiredEdgeCount +=
            cycleEdges;
    }

    if (
        materializedEdges.length <
        requiredEdgeCount
    )
    {
        return false;
    }


    foreach (cycleIndex; orderedCycles)
    {
        const auto cycle =
            cycles[
                cycleIndex
            ];

        const size_t start =
            canonicalExactUnionCycleStart(
                cycle,
                halfEdges,
                nextSelected,
                exactVertices
            );

        if (start == size_t.max)
        {
            pointCount = 0;
            edgeCount = 0;
            return false;
        }

        size_t current =
            start;

        foreach (_; 0 .. cycle.edgeCount)
        {
            if (current >= halfEdges.length)
            {
                pointCount = 0;
                edgeCount = 0;
                return false;
            }

            const auto edge =
                halfEdges[current];

            if (
                edge.originVertex >=
                    exactVertices.length ||
                edge.destinationVertex >=
                    exactVertices.length ||
                edge.originVertex ==
                    edge.destinationVertex
            )
            {
                pointCount = 0;
                edgeCount = 0;
                return false;
            }


            const size_t exactIds[2] = [
                edge.originVertex,
                edge.destinationVertex,
            ];

            size_t compactIds[2];

            foreach (i; 0 .. 2)
            {
                const size_t exactId =
                    exactIds[i];

                size_t compact =
                    exactToMaterialized[
                        exactId
                    ];

                if (compact == size_t.max)
                {
                    Point2!double point;

                    if (
                        !tryMaterializeExactOverlayPoint(
                            exactVertices[
                                exactId
                            ],
                            point
                        )
                    )
                    {
                        pointCount = 0;
                        edgeCount = 0;
                        return false;
                    }

                    assert(
                        pointCount <
                        materializedPoints.length
                    );

                    compact =
                        pointCount++;

                    materializedPoints[compact] =
                        point;

                    exactToMaterialized[exactId] =
                        compact;
                }

                compactIds[i] =
                    compact;
            }


            materializedEdges[edgeCount++] =
                MaterializedUnionBoundaryEdge(
                    compactIds[0],
                    compactIds[1]
                );


            const size_t next =
                nextSelected[current];

            if (
                next >= halfEdges.length ||
                halfEdges[next].originVertex !=
                    edge.destinationVertex
            )
            {
                pointCount = 0;
                edgeCount = 0;
                return false;
            }

            current =
                next;
        }

        if (current != start)
        {
            pointCount = 0;
            edgeCount = 0;
            return false;
        }
    }


    if (
        edgeCount !=
        requiredEdgeCount ||
        !materializedUnionBoundaryIncidencePreserved(
            materializedPoints[
                0 ..
                pointCount
            ],
            materializedEdges[
                0 ..
                edgeCount
            ]
        )
    )
    {
        pointCount = 0;
        edgeCount = 0;
        return false;
    }

    return true;
}


@safe unittest
{
    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    import geo.point :
        Point2;

    alias P = Point2!int;


    /*
     * One ordinary represented square materializes without changing boundary
     * incidence.
     */
    const ExactOverlayPoint[4] exactVertices = [
        exactOverlayPoint(P(0, 0)),
        exactOverlayPoint(P(4, 0)),
        exactOverlayPoint(P(4, 3)),
        exactOverlayPoint(P(0, 3)),
    ];

    ExactArrangementHalfEdge[4] halfEdges;

    halfEdges[0].originVertex = 0;
    halfEdges[0].destinationVertex = 1;

    halfEdges[1].originVertex = 1;
    halfEdges[1].destinationVertex = 2;

    halfEdges[2].originVertex = 2;
    halfEdges[2].destinationVertex = 3;

    halfEdges[3].originVertex = 3;
    halfEdges[3].destinationVertex = 0;

    const size_t[4] nextSelected = [
        1,
        2,
        3,
        0,
    ];

    const ExactUnionBoundaryCycle[1] cycles = [
        ExactUnionBoundaryCycle(0, 4),
    ];

    const size_t[1] orderedCycles = [
        0,
    ];

    size_t[4] mapping;
    P[4] points;
    MaterializedUnionBoundaryEdge[4] edges;

    size_t pointCount;
    size_t edgeCount;

    assert(
        tryMaterializeExactUnionBoundaryGraph(
            exactVertices[],
            cycles[],
            orderedCycles[],
            halfEdges[],
            nextSelected[],
            mapping[],
            points[],
            edges[],
            pointCount,
            edgeCount
        )
    );

    assert(pointCount == 4);
    assert(edgeCount == 4);

    assert(points[0] == P(0, 0));
    assert(points[1] == P(4, 0));
    assert(points[2] == P(4, 3));
    assert(points[3] == P(0, 3));
}


@safe unittest
{
    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    import geo.point :
        Point2;

    alias LP = Point2!long;


    /*
     * Distinct required exact vertices at long.max and long.max - 1 collapse
     * to the same binary64 point. Materialization fails all-or-nothing.
     */
    const ExactOverlayPoint[3] exactVertices = [
        exactOverlayPoint(
            LP(long.max, 0)
        ),
        exactOverlayPoint(
            LP(long.max - 1, 0)
        ),
        exactOverlayPoint(
            LP(long.max - 1, 1)
        ),
    ];

    ExactArrangementHalfEdge[3] halfEdges;

    halfEdges[0].originVertex = 0;
    halfEdges[0].destinationVertex = 1;

    halfEdges[1].originVertex = 1;
    halfEdges[1].destinationVertex = 2;

    halfEdges[2].originVertex = 2;
    halfEdges[2].destinationVertex = 0;

    const size_t[3] nextSelected = [
        1,
        2,
        0,
    ];

    const ExactUnionBoundaryCycle[1] cycles = [
        ExactUnionBoundaryCycle(0, 3),
    ];

    const size_t[1] orderedCycles = [
        0,
    ];

    size_t[3] mapping;
    Point2!double[3] points;
    MaterializedUnionBoundaryEdge[3] edges;

    size_t pointCount;
    size_t edgeCount;

    assert(
        !tryMaterializeExactUnionBoundaryGraph(
            exactVertices[],
            cycles[],
            orderedCycles[],
            halfEdges[],
            nextSelected[],
            mapping[],
            points[],
            edges[],
            pointCount,
            edgeCount
        )
    );

    assert(pointCount == 0);
    assert(edgeCount == 0);
}


@safe unittest
{
    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    import geo.point :
        Point2;

    alias LP = Point2!long;


    /*
     * All rounded vertices remain distinct, but two exact non-adjacent edges
     * acquire a new binary64 contact near 2^53. The incidence verifier
     * rejects the materialized result.
     */
    enum long n =
        9_007_199_254_740_992L;

    const ExactOverlayPoint[4] exactVertices = [
        exactOverlayPoint(
            LP(n,     n - 3)
        ),
        exactOverlayPoint(
            LP(n - 2, n - 4)
        ),
        exactOverlayPoint(
            LP(n + 3, n - 1)
        ),
        exactOverlayPoint(
            LP(n + 4, n - 2)
        ),
    ];

    ExactArrangementHalfEdge[4] halfEdges;

    halfEdges[0].originVertex = 0;
    halfEdges[0].destinationVertex = 1;

    halfEdges[1].originVertex = 1;
    halfEdges[1].destinationVertex = 2;

    halfEdges[2].originVertex = 2;
    halfEdges[2].destinationVertex = 3;

    halfEdges[3].originVertex = 3;
    halfEdges[3].destinationVertex = 0;

    const size_t[4] nextSelected = [
        1,
        2,
        3,
        0,
    ];

    const ExactUnionBoundaryCycle[1] cycles = [
        ExactUnionBoundaryCycle(0, 4),
    ];

    const size_t[1] orderedCycles = [
        0,
    ];

    size_t[4] mapping;
    Point2!double[4] points;
    MaterializedUnionBoundaryEdge[4] edges;

    size_t pointCount;
    size_t edgeCount;

    assert(
        !tryMaterializeExactUnionBoundaryGraph(
            exactVertices[],
            cycles[],
            orderedCycles[],
            halfEdges[],
            nextSelected[],
            mapping[],
            points[],
            edges[],
            pointCount,
            edgeCount
        )
    );

    assert(pointCount == 0);
    assert(edgeCount == 0);
}


@safe unittest
{
    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    import geo.point :
        Point2;

    alias P = Point2!int;


    /*
     * Two components sharing one exact point materialize that contact through
     * one compact point ID while retaining two separate cycles.
     */
    const ExactOverlayPoint[7] exactVertices = [
        exactOverlayPoint(P(0, 0)),
        exactOverlayPoint(P(2, 0)),
        exactOverlayPoint(P(2, 2)),
        exactOverlayPoint(P(0, 2)),
        exactOverlayPoint(P(4, 2)),
        exactOverlayPoint(P(4, 4)),
        exactOverlayPoint(P(2, 4)),
    ];

    ExactArrangementHalfEdge[8] halfEdges;

    halfEdges[0].originVertex = 0;
    halfEdges[0].destinationVertex = 1;

    halfEdges[1].originVertex = 1;
    halfEdges[1].destinationVertex = 2;

    halfEdges[2].originVertex = 2;
    halfEdges[2].destinationVertex = 3;

    halfEdges[3].originVertex = 3;
    halfEdges[3].destinationVertex = 0;

    halfEdges[4].originVertex = 2;
    halfEdges[4].destinationVertex = 4;

    halfEdges[5].originVertex = 4;
    halfEdges[5].destinationVertex = 5;

    halfEdges[6].originVertex = 5;
    halfEdges[6].destinationVertex = 6;

    halfEdges[7].originVertex = 6;
    halfEdges[7].destinationVertex = 2;

    const size_t[8] nextSelected = [
        1, 2, 3, 0,
        5, 6, 7, 4,
    ];

    const ExactUnionBoundaryCycle[2] cycles = [
        ExactUnionBoundaryCycle(0, 4),
        ExactUnionBoundaryCycle(4, 4),
    ];

    const size_t[2] orderedCycles = [
        0,
        1,
    ];

    size_t[7] mapping;
    Point2!double[7] points;
    MaterializedUnionBoundaryEdge[8] edges;

    size_t pointCount;
    size_t edgeCount;

    assert(
        tryMaterializeExactUnionBoundaryGraph(
            exactVertices[],
            cycles[],
            orderedCycles[],
            halfEdges[],
            nextSelected[],
            mapping[],
            points[],
            edges[],
            pointCount,
            edgeCount
        )
    );

    assert(pointCount == 7);
    assert(edgeCount == 8);

    assert(
        mapping[2] !=
        size_t.max
    );
}
