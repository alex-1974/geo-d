module geo.internal.polygon_union_materialize;

import geo.internal.exact_coordinate :
    roundsToFiniteBinary64;

import geo.internal.exact_coordinate_round :
    roundExactCoordinateBinary64;

import geo.internal.polygon_union_boundary :
    ExactUnionBoundaryCycle;

import geo.internal.polygon_union_components :
    ExactUnionCanonicalComponent,
    ExactUnionCanonicalRing;

import geo.internal.polygon_union_embedding :
    ExactArrangementHalfEdge;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint;

import geo.linear_ring_view :
    LinearRing2View;

import geo.point_in_polygon :
    PointPolygonLocation,
    tryClassifyPointInPolygon;

import geo.polygon_view :
    Polygon2View;

import geo.topology_validation :
    validatePolygon;

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
 * True exactly when one exact arrangement vertex participates in the selected
 * result boundary.
 */
private bool boundaryUsesVertex(
    size_t vertex,
    scope const(MaterializedBoundaryEdge)[] edges
)
    pure nothrow @safe @nogc
{
    foreach (edge; edges)
    {
        if (
            edge.firstVertex == vertex ||
            edge.secondVertex == vertex
        )
        {
            return true;
        }
    }

    return false;
}


/*
 * Correctly rounds only exact vertices required by the selected result
 * boundary.
 *
 * Non-result arrangement vertices are deliberately ignored. They may contain
 * exact events whose binary64 materialization would collapse or otherwise be
 * unrepresentable without affecting the selected regularized-union result.
 *
 * destination remains indexed by global exact arrangement vertex ID so the
 * selected boundary edges can retain their exact IDs.
 */
bool tryMaterializeExactBoundaryVertices(
    scope const(ExactOverlayPoint)[] vertices,
    scope const(MaterializedBoundaryEdge)[] edges,
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

    foreach (ref point; destination)
        point = Point2!double.init;

    foreach (edge; edges)
    {
        if (
            edge.firstVertex >= vertices.length ||
            edge.secondVertex >= vertices.length ||
            edge.firstVertex == edge.secondVertex
        )
        {
            return false;
        }
    }

    foreach (vertexIndex, ref const vertex; vertices)
    {
        if (
            !boundaryUsesVertex(
                vertexIndex,
                edges
            )
        )
        {
            continue;
        }

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

        destination[vertexIndex] =
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

        assert(
            destination[
                vertexIndex
            ].isFinite
        );
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
    /*
     * Validate edge IDs before using them to identify the required point set.
     */
    foreach (edge; edges)
    {
        if (
            edge.firstVertex >= points.length ||
            edge.secondVertex >= points.length ||
            edge.firstVertex >= edge.secondVertex
        )
        {
            return false;
        }
    }

    /*
     * Only exact result vertices are required to materialize faithfully.
     * Unselected arrangement vertices are intentionally ignored.
     */
    foreach (i; 0 .. points.length)
    {
        if (
            !boundaryUsesVertex(
                i,
                edges
            )
        )
        {
            continue;
        }

        if (!points[i].isFinite)
            return false;

        foreach (j; i + 1 .. points.length)
        {
            if (
                boundaryUsesVertex(
                    j,
                    edges
                ) &&
                points[i] == points[j]
            )
            {
                return false;
            }
        }
    }

    foreach (edge; edges)
    {
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
        !tryMaterializeExactBoundaryVertices(
            exactVertices,
            boundaryEdges[
                0 ..
                boundaryEdgeCount
            ],
            materializedVertices
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


/*
 * Verifies every materialized result component against the existing polygon
 * contract and rejects new inter-component interior overlap/containment.
 *
 * The complete selected boundary-incidence graph has already been verified by
 * materializedBoundaryIncidencePreserved().
 *
 * With that invariant in place, any new two-dimensional overlap between
 * distinct components without a new boundary crossing requires an exterior
 * vertex of one component to lie in the interior of the other. Testing both
 * directions therefore rejects newly created containment/overlap while still
 * allowing:
 *
 * - isolated point contacts on boundaries;
 * - a separate component located inside a hole of another component.
 */
bool materializedComponentsRemainDisjoint(
    scope const(Polygon2View!double)[] components
)
    pure nothrow @safe
{
    foreach (component; components)
    {
        if (
            !validatePolygon(
                component
            ).valid
        )
        {
            return false;
        }
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


/*
 * Reconstructs canonical materialized polygon views from the already rounded
 * exact result vertex table and verifies the complete public Polygon2View
 * topology contract.
 *
 * The exact canonical layout determines sequence identity BEFORE rounding:
 *
 * - component order;
 * - exterior-first ring order;
 * - hole order;
 * - exact canonical ring start;
 * - selected interior-left traversal direction.
 *
 * ringPointStorage receives one copied binary64 point for every stored result
 * ring vertex. This contiguous per-ring storage is necessary because
 * LinearRing2View is a contiguous borrowed view while arrangement vertex IDs
 * are globally deduplicated and need not be contiguous in ring order.
 *
 * ringViews and componentViews are caller-owned descriptor storage and borrow
 * from ringPointStorage / ringViews respectively. This is the internal
 * precursor to the accepted immutable owning result model.
 *
 * On success:
 *
 * - ringPointCount is the number of used entries in ringPointStorage;
 * - ringViews[0 .. canonicalRings.length] are valid ring descriptors;
 * - componentViews[0 .. canonicalComponents.length] are valid polygon views;
 * - distinct component interiors remain disjoint under materialization.
 *
 * This operation may allocate indirectly through validatePolygon() and
 * therefore intentionally does not promise @nogc.
 */
bool tryBuildMaterializedUnionComponents(
    scope const(ExactUnionBoundaryCycle)[] cycles,
    scope const(ExactUnionCanonicalRing)[] canonicalRings,
    scope const(ExactUnionCanonicalComponent)[] canonicalComponents,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(Point2!double)[] materializedVertices,
    Point2!double[] ringPointStorage,
    LinearRing2View!double[] ringViews,
    Polygon2View!double[] componentViews,
    out size_t ringPointCount
)
    pure nothrow @safe
{
    ringPointCount = 0;

    if (
        canonicalRings.length != cycles.length ||
        nextSelected.length != halfEdges.length ||
        ringViews.length < canonicalRings.length ||
        componentViews.length < canonicalComponents.length
    )
    {
        return false;
    }


    size_t requiredPoints = 0;

    foreach (ring; canonicalRings)
    {
        if (
            ring.cycle >= cycles.length ||
            ring.startHalfEdge >= halfEdges.length
        )
        {
            return false;
        }

        const size_t edgeCount =
            cycles[
                ring.cycle
            ].edgeCount;

        if (
            edgeCount < 3 ||
            requiredPoints >
                size_t.max -
                edgeCount
        )
        {
            return false;
        }

        requiredPoints +=
            edgeCount;
    }

    if (
        ringPointStorage.length <
        requiredPoints
    )
    {
        return false;
    }


    size_t write = 0;

    foreach (ringIndex, ring; canonicalRings)
    {
        const auto cycle =
            cycles[
                ring.cycle
            ];

        const size_t begin =
            write;

        size_t current =
            ring.startHalfEdge;

        foreach (_; 0 .. cycle.edgeCount)
        {
            if (current >= halfEdges.length)
            {
                ringPointCount = 0;
                return false;
            }

            const auto edge =
                halfEdges[current];

            if (
                edge.originVertex >=
                    materializedVertices.length ||
                edge.destinationVertex >=
                    materializedVertices.length ||
                edge.originVertex ==
                    edge.destinationVertex
            )
            {
                ringPointCount = 0;
                return false;
            }

            const auto point =
                materializedVertices[
                    edge.originVertex
                ];

            if (!point.isFinite)
            {
                ringPointCount = 0;
                return false;
            }

            ringPointStorage[write++] =
                point;

            const size_t next =
                nextSelected[current];

            if (
                next >= halfEdges.length ||
                halfEdges[next].originVertex !=
                    edge.destinationVertex
            )
            {
                ringPointCount = 0;
                return false;
            }

            current =
                next;
        }

        if (
            current !=
            ring.startHalfEdge
        )
        {
            ringPointCount = 0;
            return false;
        }

        ringViews[ringIndex] =
            LinearRing2View!double(
                ringPointStorage[
                    begin ..
                    write
                ]
            );
    }

    assert(write == requiredPoints);

    ringPointCount =
        write;


    size_t expectedFirstRing = 0;

    foreach (
        componentIndex,
        component;
        canonicalComponents
    )
    {
        if (
            component.ringCount == 0 ||
            component.firstRing !=
                expectedFirstRing ||
            component.firstRing >
                canonicalRings.length ||
            component.ringCount >
                canonicalRings.length -
                component.firstRing
        )
        {
            ringPointCount = 0;
            return false;
        }

        const size_t endRing =
            component.firstRing +
            component.ringCount;

        componentViews[componentIndex] =
            Polygon2View!double(
                ringViews[
                    component.firstRing ..
                    endRing
                ]
            );

        expectedFirstRing =
            endRing;
    }

    if (
        expectedFirstRing !=
        canonicalRings.length
    )
    {
        ringPointCount = 0;
        return false;
    }


    if (
        !materializedComponentsRemainDisjoint(
            componentViews[
                0 ..
                canonicalComponents.length
            ]
        )
    )
    {
        ringPointCount = 0;
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

    const MaterializedBoundaryEdge[1] selectedEdge = [
        MaterializedBoundaryEdge(
            0,
            1
        ),
    ];

    assert(
        !materializedBoundaryIncidencePreserved(
            materialized[],
            selectedEdge[]
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
    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    /*
     * Unselected arrangement vertices do not participate in representability
     * failure.
     *
     * The final two exact vertices collapse to one binary64 point, but neither
     * belongs to the selected result edge.
     */
    const ExactOverlayPoint[4] exactVertices = [
        exactOverlayPoint(
            Point2!long(0, 0)
        ),
        exactOverlayPoint(
            Point2!long(1, 0)
        ),
        exactOverlayPoint(
            Point2!long(long.max, 0)
        ),
        exactOverlayPoint(
            Point2!long(long.max - 1, 0)
        ),
    ];

    const MaterializedBoundaryEdge[1] edges = [
        MaterializedBoundaryEdge(
            0,
            1
        ),
    ];

    Point2!double[4] materialized;

    assert(
        tryMaterializeExactBoundaryVertices(
            exactVertices[],
            edges[],
            materialized[]
        )
    );

    assert(
        materializedBoundaryIncidencePreserved(
            materialized[],
            edges[]
        )
    );

    /*
     * The unused slots are non-result scratch. Their representation is
     * deliberately unspecified; only their absence from the selected
     * incidence graph matters.
     */
    Point2!double[4] fullMaterialization;

    assert(
        tryMaterializeExactOverlayVertices(
            exactVertices[],
            fullMaterialization[]
        )
    );

    assert(
        fullMaterialization[2] ==
        fullMaterialization[3]
    );
}


@safe unittest
{
    /*
     * Canonical exterior + hole layout materializes into one valid
     * Polygon2View using contiguous ring storage.
     */
    const Point2!double[8] materializedVertices = [
        Point2!double(0.0, 0.0),
        Point2!double(8.0, 0.0),
        Point2!double(8.0, 8.0),
        Point2!double(0.0, 8.0),

        Point2!double(2.0, 2.0),
        Point2!double(2.0, 4.0),
        Point2!double(4.0, 4.0),
        Point2!double(4.0, 2.0),
    ];

    ExactArrangementHalfEdge[8] halfEdges;

    foreach (i; 0 .. 4)
    {
        halfEdges[i].originVertex =
            i;

        halfEdges[i].destinationVertex =
            (i + 1) % 4;
    }

    foreach (i; 0 .. 4)
    {
        halfEdges[4 + i].originVertex =
            4 + i;

        halfEdges[4 + i].destinationVertex =
            4 + ((i + 1) % 4);
    }

    const size_t[8] nextSelected = [
        1, 2, 3, 0,
        5, 6, 7, 4,
    ];

    const ExactUnionBoundaryCycle[2] cycles = [
        ExactUnionBoundaryCycle(0, 4),
        ExactUnionBoundaryCycle(4, 4),
    ];

    const ExactUnionCanonicalRing[2] canonicalRings = [
        ExactUnionCanonicalRing(0, 0),
        ExactUnionCanonicalRing(1, 4),
    ];

    const ExactUnionCanonicalComponent[1] canonicalComponents = [
        ExactUnionCanonicalComponent(
            0,
            2
        ),
    ];

    Point2!double[8] ringPoints;
    LinearRing2View!double[2] rings;
    Polygon2View!double[1] components;

    size_t ringPointCount;

    assert(
        tryBuildMaterializedUnionComponents(
            cycles[],
            canonicalRings[],
            canonicalComponents[],
            halfEdges[],
            nextSelected[],
            materializedVertices[],
            ringPoints[],
            rings[],
            components[],
            ringPointCount
        )
    );

    assert(ringPointCount == 8);

    assert(
        validatePolygon(
            components[0]
        ).valid
    );

    assert(
        components[0].exterior[0] ==
        Point2!double(0.0, 0.0)
    );

    assert(
        components[0].hole(0)[0] ==
        Point2!double(2.0, 2.0)
    );
}


@safe unittest
{
    /*
     * A separate materialized component may lie inside a hole of another
     * component: their polygon interiors remain disjoint.
     */
    Point2!double[4] outerPoints = [
        Point2!double(0.0, 0.0),
        Point2!double(10.0, 0.0),
        Point2!double(10.0, 10.0),
        Point2!double(0.0, 10.0),
    ];

    Point2!double[4] holePoints = [
        Point2!double(3.0, 3.0),
        Point2!double(3.0, 7.0),
        Point2!double(7.0, 7.0),
        Point2!double(7.0, 3.0),
    ];

    Point2!double[4] islandPoints = [
        Point2!double(4.0, 4.0),
        Point2!double(6.0, 4.0),
        Point2!double(6.0, 6.0),
        Point2!double(4.0, 6.0),
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

    const Polygon2View!double[2] components = [
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


@safe unittest
{
    /*
     * New materialized containment in filled union interior is rejected even
     * when both individual polygons are valid.
     */
    Point2!double[4] outerPoints = [
        Point2!double(0.0, 0.0),
        Point2!double(10.0, 0.0),
        Point2!double(10.0, 10.0),
        Point2!double(0.0, 10.0),
    ];

    Point2!double[4] innerPoints = [
        Point2!double(2.0, 2.0),
        Point2!double(4.0, 2.0),
        Point2!double(4.0, 4.0),
        Point2!double(2.0, 4.0),
    ];

    LinearRing2View!double[2] rings = [
        LinearRing2View!double(
            outerPoints[]
        ),
        LinearRing2View!double(
            innerPoints[]
        ),
    ];

    const Polygon2View!double[2] components = [
        Polygon2View!double(
            rings[0 .. 1]
        ),
        Polygon2View!double(
            rings[1 .. 2]
        ),
    ];

    assert(
        validatePolygon(
            components[0]
        ).valid
    );

    assert(
        validatePolygon(
            components[1]
        ).valid
    );

    assert(
        !materializedComponentsRemainDisjoint(
            components[]
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
