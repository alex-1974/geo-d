module geo.internal.polygon_union_materialize;

import geo.internal.exact_coordinate :
    roundsToFiniteBinary64;

import geo.internal.exact_coordinate_round :
    roundExactCoordinateBinary64;

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
 * Correctness-first binary64 materialization checks for the P1 polygon-union
 * result.
 *
 * Exact topology is already fixed before this stage. Rounded coordinates are
 * accepted only when they preserve the exact selected boundary-incidence
 * graph.
 */


struct MaterializedBoundaryEdge
{
    size_t firstVertex;
    size_t secondVertex;
}


/*
 * Correctly rounds every exact arrangement vertex to binary64.
 *
 * destination must provide one point per exact vertex.
 *
 * Returns false when any required exact coordinate does not round to a finite
 * binary64 value. No topology judgment is made here.
 */
bool tryMaterializeExactOverlayVertices(
    scope const(ExactOverlayPoint)[] vertices,
    scope Point2!double[] destination
)
    pure nothrow @safe @nogc
{
    if (
        destination.length !=
        vertices.length
    )
    {
        return false;
    }

    foreach (i, ref const vertex; vertices)
    {
        if (
            !roundsToFiniteBinary64(
                vertex.xNumerator,
                vertex.denominator
            ) ||
            !roundsToFiniteBinary64(
                vertex.yNumerator,
                vertex.denominator
            )
        )
        {
            return false;
        }

        destination[i] =
            Point2!double(
                roundExactCoordinateBinary64(
                    vertex.xNumerator,
                    vertex.denominator
                ),
                roundExactCoordinateBinary64(
                    vertex.yNumerator,
                    vertex.denominator
                )
            );

        assert(destination[i].isFinite);
    }

    return true;
}


/*
 * Builds the selected exact union-boundary edge set over arrangement vertex
 * IDs.
 *
 * Exactly one directed half-edge of a selected boundary edge must be marked.
 * The returned edge is undirected and stores ascending vertex IDs for
 * deterministic later comparison.
 */
bool buildMaterializedBoundaryEdges(
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(bool)[] selected,
    scope MaterializedBoundaryEdge[] destination,
    out size_t count
)
    pure nothrow @safe @nogc
{
    count = 0;

    if (
        selected.length != halfEdges.length
    )
    {
        return false;
    }

    size_t required = 0;

    foreach (i, ref const halfEdge; halfEdges)
    {
        if (!selected[i])
            continue;

        if (
            halfEdge.twin >= halfEdges.length ||
            halfEdges[halfEdge.twin].twin != i ||
            selected[halfEdge.twin] ||
            halfEdge.originVertex ==
                halfEdge.destinationVertex
        )
        {
            return false;
        }

        ++required;
    }

    if (destination.length < required)
        return false;

    foreach (i, ref const halfEdge; halfEdges)
    {
        if (!selected[i])
            continue;

        const size_t first =
            halfEdge.originVertex <
                    halfEdge.destinationVertex
                ? halfEdge.originVertex
                : halfEdge.destinationVertex;

        const size_t second =
            halfEdge.originVertex <
                    halfEdge.destinationVertex
                ? halfEdge.destinationVertex
                : halfEdge.originVertex;

        destination[count++] =
            MaterializedBoundaryEdge(
                first,
                second
            );
    }

    assert(count == required);

    return true;
}


/*
 * Verifies that binary64 materialization preserves the exact selected
 * boundary-incidence graph.
 *
 * points is indexed by the deduplicated exact arrangement vertex ID.
 * Different indices therefore represent mathematically distinct exact points.
 *
 * Required invariants:
 *
 * - every materialized point is finite;
 * - distinct exact vertex IDs remain distinct after rounding;
 * - every selected edge remains nondegenerate;
 * - duplicate selected edges are rejected;
 * - edge pairs with no shared exact vertex remain disjoint;
 * - edge pairs with one shared exact vertex remain one point touch exactly at
 *   that materialized vertex.
 *
 * Consequently rounding cannot silently create or destroy a selected-boundary
 * crossing, overlap, or point contact.
 */
bool materializedBoundaryIncidencePreserved(
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
            edge.firstVertex >= edge.secondVertex ||
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
                    points[sharedVertex]
            )
            {
                return false;
            }
        }
    }

    return true;
}


/*
 * Complete P1 gate for materializing the selected exact boundary graph.
 *
 * No partial success is exposed: false means the rounded point table cannot
 * be used as a faithful representation of the exact selected boundary graph.
 */
bool tryMaterializeExactUnionBoundary(
    scope const(ExactOverlayPoint)[] exactVertices,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(bool)[] selected,
    scope Point2!double[] materializedVertices,
    scope MaterializedBoundaryEdge[] boundaryEdges,
    out size_t boundaryEdgeCount
)
    pure nothrow @safe @nogc
{
    boundaryEdgeCount = 0;

    if (
        !tryMaterializeExactOverlayVertices(
            exactVertices,
            materializedVertices
        )
    )
    {
        return false;
    }

    if (
        !buildMaterializedBoundaryEdges(
            halfEdges,
            selected,
            boundaryEdges,
            boundaryEdgeCount
        )
    )
    {
        boundaryEdgeCount = 0;
        return false;
    }

    if (
        !materializedBoundaryIncidencePreserved(
            materializedVertices,
            boundaryEdges[
                0 ..
                boundaryEdgeCount
            ]
        )
    )
    {
        boundaryEdgeCount = 0;
        return false;
    }

    return true;
}


@safe unittest
{
    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    /*
     * Ordinary exact square materializes with preserved incidence.
     */
    const ExactOverlayPoint[4] exactVertices = [
        exactOverlayPoint(Point2!int(0, 0)),
        exactOverlayPoint(Point2!int(0, 3)),
        exactOverlayPoint(Point2!int(4, 0)),
        exactOverlayPoint(Point2!int(4, 3)),
    ];

    ExactArrangementHalfEdge[8] halfEdges;

    halfEdges[0] =
        ExactArrangementHalfEdge(
            0,
            2,
            1,
            0,
            size_t.max,
            true
        );

    halfEdges[1] =
        ExactArrangementHalfEdge(
            2,
            0,
            0,
            0,
            size_t.max,
            false
        );

    halfEdges[2] =
        ExactArrangementHalfEdge(
            2,
            3,
            3,
            1,
            size_t.max,
            true
        );

    halfEdges[3] =
        ExactArrangementHalfEdge(
            3,
            2,
            2,
            1,
            size_t.max,
            false
        );

    halfEdges[4] =
        ExactArrangementHalfEdge(
            1,
            3,
            5,
            2,
            size_t.max,
            true
        );

    halfEdges[5] =
        ExactArrangementHalfEdge(
            3,
            1,
            4,
            2,
            size_t.max,
            false
        );

    halfEdges[6] =
        ExactArrangementHalfEdge(
            0,
            1,
            7,
            3,
            size_t.max,
            true
        );

    halfEdges[7] =
        ExactArrangementHalfEdge(
            1,
            0,
            6,
            3,
            size_t.max,
            false
        );

    const bool[8] selected = [
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
    ];

    Point2!double[4] materialized;
    MaterializedBoundaryEdge[4] edges;
    size_t edgeCount;

    assert(
        tryMaterializeExactUnionBoundary(
            exactVertices[],
            halfEdges[],
            selected[],
            materialized[],
            edges[],
            edgeCount
        )
    );

    assert(edgeCount == 4);

    assert(
        materialized[0] ==
        Point2!double(0.0, 0.0)
    );

    assert(
        materialized[3] ==
        Point2!double(4.0, 3.0)
    );
}


@safe unittest
{
    /*
     * Two distinct exact signed-long vertices collapse to one binary64 point.
     * The injective materialization gate rejects the result.
     */
    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    const ExactOverlayPoint[2] exactVertices = [
        exactOverlayPoint(
            Point2!long(
                long.max,
                0
            )
        ),
        exactOverlayPoint(
            Point2!long(
                long.max - 1,
                0
            )
        ),
    ];

    Point2!double[2] materialized;

    assert(
        tryMaterializeExactOverlayVertices(
            exactVertices[],
            materialized[]
        )
    );

    assert(
        materialized[0] ==
        materialized[1]
    );

    const MaterializedBoundaryEdge[0] noEdges;

    assert(
        !materializedBoundaryIncidencePreserved(
            materialized[],
            noEdges[]
        )
    );
}


@safe unittest
{
    /*
     * Exact signed-long vertices may remain pairwise distinct after rounding
     * while non-adjacent edges acquire a new binary64 contact. The incidence
     * gate rejects that topology change.
     */
    enum long n =
        9_007_199_254_740_992L;

    const Point2!long[4] exactInput = [
        Point2!long(n,     n - 3),
        Point2!long(n - 2, n - 4),
        Point2!long(n + 3, n - 1),
        Point2!long(n + 4, n - 2),
    ];

    Point2!double[4] rounded;

    foreach (i; 0 .. exactInput.length)
    {
        rounded[i] =
            Point2!double(
                cast(double)
                    exactInput[i].x,
                cast(double)
                    exactInput[i].y
            );
    }

    assert(rounded[0] != rounded[1]);
    assert(rounded[0] != rounded[2]);
    assert(rounded[0] != rounded[3]);
    assert(rounded[1] != rounded[2]);
    assert(rounded[1] != rounded[3]);
    assert(rounded[2] != rounded[3]);

    const MaterializedBoundaryEdge[4] edges = [
        MaterializedBoundaryEdge(0, 1),
        MaterializedBoundaryEdge(1, 2),
        MaterializedBoundaryEdge(2, 3),
        MaterializedBoundaryEdge(0, 3),
    ];

    assert(
        !materializedBoundaryIncidencePreserved(
            rounded[],
            edges[]
        )
    );
}


@safe unittest
{
    /*
     * Point contact between two distinct components remains allowed when it
     * is represented by one shared exact/materialized vertex ID.
     */
    const Point2!double[7] points = [
        Point2!double(0.0, 0.0),
        Point2!double(2.0, 0.0),
        Point2!double(2.0, 2.0),
        Point2!double(0.0, 2.0),
        Point2!double(4.0, 2.0),
        Point2!double(4.0, 4.0),
        Point2!double(2.0, 4.0),
    ];

    const MaterializedBoundaryEdge[8] edges = [
        MaterializedBoundaryEdge(0, 1),
        MaterializedBoundaryEdge(1, 2),
        MaterializedBoundaryEdge(2, 3),
        MaterializedBoundaryEdge(0, 3),

        MaterializedBoundaryEdge(2, 4),
        MaterializedBoundaryEdge(4, 5),
        MaterializedBoundaryEdge(5, 6),
        MaterializedBoundaryEdge(2, 6),
    ];

    assert(
        materializedBoundaryIncidencePreserved(
            points[],
            edges[]
        )
    );
}
