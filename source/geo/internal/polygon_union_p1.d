module geo.internal.polygon_union_p1;

import geo.internal.polygon_union_arrangement :
    ExactArrangementEdge,
    buildExactArrangement;

import geo.internal.polygon_union_boundary :
    ExactUnionBoundaryCycle,
    tryBuildExactUnionBoundaryCycles;

import geo.internal.polygon_union_canonical :
    tryBuildCanonicalExactUnionLayout;

import geo.internal.polygon_union_components :
    ExactUnionComponent,
    ExactUnionCycleRole,
    tryBuildExactUnionComponents;

import geo.internal.polygon_union_embedding :
    ExactArrangementHalfEdge,
    buildExactHalfEdgeEmbedding;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    appendSegmentPairNodingEvents,
    seedExactEdgeEvents,
    sortUniqueExactEdgeEvents;

import geo.internal.polygon_union_input :
    ExactPolygonBoundaryEdge,
    buildExactPolygonBoundaryEdges,
    tryPolygonBoundaryEdgeCount;

import geo.internal.polygon_union_materialization :
    MaterializedUnionBoundaryEdge,
    materializedUnionComponentsRemainValidAndDisjoint,
    tryMaterializeExactUnionBoundaryGraph,
    tryWriteMaterializedUnionRings;

import geo.internal.polygon_union_noding :
    ExactAtomicEdge,
    buildExactAtomicEdgesFromNodedSource,
    polygonUnionOperandA,
    polygonUnionOperandB,
    sortMergeExactAtomicEdges;

import geo.internal.polygon_union_regions :
    ExactHalfEdgeSideLabel,
    initializeExactHalfEdgeSideLabels,
    selectExactUnionBoundaryHalfEdges,
    tryResolveExactHalfEdgeSideLabelsWithContainment;

import geo.internal.polygon_union_result :
    PolygonUnionOwnedResultInternal,
    takePolygonUnionOwnedResultInternal;

import geo.polygon_view :
    Polygon2View;

import geo.point :
    Point2;

import geo.topology_validation :
    validatePolygon;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Correctness-first P1 orchestration of the exact polygon-union machinery.
 *
 * Final public API spelling is deliberately outside this module.
 */


package(geo)
enum PolygonUnionP1InternalStatus : ubyte
{
    success,

    invalidFirstInput,

    invalidSecondInput,

    /*
     * The exact union exists, but binary64 materialization cannot preserve the
     * required result topology.
     */
    unrepresentableConstruction,

    /*
     * Workspace cardinality cannot be represented by size_t.
     *
     * This is distinct from geometric construction failure. Ordinary runtime
     * allocation exhaustion likewise remains a resource failure rather than a
     * geometry status.
     */
    resourceLimit,

    /*
     * A production invariant failed after valid inputs and correctly sized
     * workspace were established.
     *
     * This is an implementation defect signal for the internal P1 gate, not a
     * future consumer-visible geometric alternative.
     */
    internalInvariantFailure,
}


private enum bool isPolygonUnionP1Scalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


private bool checkedAdd(
    size_t lhs,
    size_t rhs,
    out size_t result
)
    pure nothrow @safe @nogc
{
    result = 0;

    if (
        lhs >
        size_t.max - rhs
    )
    {
        return false;
    }

    result =
        lhs + rhs;

    return true;
}


private bool checkedMultiply(
    size_t lhs,
    size_t rhs,
    out size_t result
)
    pure nothrow @safe @nogc
{
    result = 0;

    if (
        lhs != 0 &&
        rhs >
        size_t.max / lhs
    )
    {
        return false;
    }

    result =
        lhs * rhs;

    return true;
}


private PolygonUnionP1InternalStatus invariantFailure()
    pure nothrow @safe @nogc
{
    assert(
        false,
        "polygon-union P1 internal invariant failure"
    );

    return
        PolygonUnionP1InternalStatus
            .internalInvariantFailure;
}


/*
 * Constructs one immutable internal P1 polygon-union result.
 *
 * The function performs the complete accepted ADR-0023 pipeline but remains
 * package-internal until the ordinary public API review chooses final names,
 * result/failure spelling, documentation, and exports.
 */
package(geo)
PolygonUnionP1InternalStatus tryPolygonUnionP1Internal(T)(
    scope Polygon2View!T first,
    scope Polygon2View!T second,
    out PolygonUnionOwnedResultInternal result
)
    @safe
if (isPolygonUnionP1Scalar!T)
{
    result =
        PolygonUnionOwnedResultInternal.init;


    if (
        !validatePolygon(first).valid
    )
    {
        return
            PolygonUnionP1InternalStatus
                .invalidFirstInput;
    }

    if (
        !validatePolygon(second).valid
    )
    {
        return
            PolygonUnionP1InternalStatus
                .invalidSecondInput;
    }


    size_t firstSourceCount;
    size_t secondSourceCount;

    if (
        !tryPolygonBoundaryEdgeCount(
            first,
            firstSourceCount
        ) ||
        !tryPolygonBoundaryEdgeCount(
            second,
            secondSourceCount
        )
    )
    {
        return
            PolygonUnionP1InternalStatus
                .resourceLimit;
    }

    size_t sourceCount;

    if (
        !checkedAdd(
            firstSourceCount,
            secondSourceCount,
            sourceCount
        )
    )
    {
        return
            PolygonUnionP1InternalStatus
                .resourceLimit;
    }


    auto sources =
        new ExactPolygonBoundaryEdge!T[
            sourceCount
        ];

    size_t builtFirst;

    if (
        !buildExactPolygonBoundaryEdges(
            first,
            polygonUnionOperandA,
            sources[
                0 ..
                firstSourceCount
            ],
            builtFirst
        ) ||
        builtFirst !=
            firstSourceCount
    )
    {
        return invariantFailure();
    }

    size_t builtSecond;

    if (
        !buildExactPolygonBoundaryEdges(
            second,
            polygonUnionOperandB,
            sources[
                firstSourceCount ..
                sourceCount
            ],
            builtSecond
        ) ||
        builtSecond !=
            secondSourceCount
    )
    {
        return invariantFailure();
    }


    /*
     * Every source edge starts with two endpoint events. One interaction with
     * each of the other source edges can contribute at most two additional
     * events (positive collinear overlap). Therefore 2 * sourceCount slots per
     * source edge are a complete P1 pairwise upper bound.
     */
    size_t perEdgeEventCapacity;

    if (
        !checkedMultiply(
            sourceCount,
            2,
            perEdgeEventCapacity
        )
    )
    {
        return
            PolygonUnionP1InternalStatus
                .resourceLimit;
    }

    size_t totalEventCapacity;

    if (
        !checkedMultiply(
            sourceCount,
            perEdgeEventCapacity,
            totalEventCapacity
        )
    )
    {
        return
            PolygonUnionP1InternalStatus
                .resourceLimit;
    }


    auto eventStorage =
        new ExactOverlayPoint[
            totalEventCapacity
        ];

    auto eventCounts =
        new size_t[
            sourceCount
        ];


    foreach (sourceIndex; 0 .. sourceCount)
    {
        const size_t begin =
            sourceIndex *
            perEdgeEventCapacity;

        size_t count;

        if (
            !seedExactEdgeEvents(
                sources[
                    sourceIndex
                ].segment,
                eventStorage[
                    begin ..
                    begin +
                    perEdgeEventCapacity
                ],
                count
            )
        )
        {
            return invariantFailure();
        }

        eventCounts[sourceIndex] =
            count;
    }


    /*
     * Correctness-first P1 candidate discovery: inspect every source-edge
     * pair. This also nodes valid same-operand tangential ring contacts.
     */
    foreach (firstIndex; 0 .. sourceCount)
    {
        const size_t firstBegin =
            firstIndex *
            perEdgeEventCapacity;

        foreach (
            secondIndex;
            firstIndex + 1 ..
            sourceCount
        )
        {
            const size_t secondBegin =
                secondIndex *
                perEdgeEventCapacity;

            if (
                !appendSegmentPairNodingEvents(
                    sources[
                        firstIndex
                    ].segment,
                    sources[
                        secondIndex
                    ].segment,
                    eventStorage[
                        firstBegin ..
                        firstBegin +
                        perEdgeEventCapacity
                    ],
                    eventCounts[
                        firstIndex
                    ],
                    eventStorage[
                        secondBegin ..
                        secondBegin +
                        perEdgeEventCapacity
                    ],
                    eventCounts[
                        secondIndex
                    ]
                )
            )
            {
                return invariantFailure();
            }
        }
    }


    size_t atomicEdgeCount = 0;

    foreach (sourceIndex; 0 .. sourceCount)
    {
        const size_t begin =
            sourceIndex *
            perEdgeEventCapacity;

        const size_t uniqueCount =
            sortUniqueExactEdgeEvents(
                sources[
                    sourceIndex
                ].segment,
                eventStorage[
                    begin ..
                    begin +
                    eventCounts[
                        sourceIndex
                    ]
                ]
            );

        if (uniqueCount < 2)
            return invariantFailure();

        eventCounts[sourceIndex] =
            uniqueCount;

        size_t updatedAtomicCount;

        if (
            !checkedAdd(
                atomicEdgeCount,
                uniqueCount - 1,
                updatedAtomicCount
            )
        )
        {
            return
                PolygonUnionP1InternalStatus
                    .resourceLimit;
        }

        atomicEdgeCount =
            updatedAtomicCount;
    }


    auto atomicEdges =
        new ExactAtomicEdge!T[
            atomicEdgeCount
        ];

    size_t atomicWrite = 0;

    foreach (sourceIndex; 0 .. sourceCount)
    {
        const size_t begin =
            sourceIndex *
            perEdgeEventCapacity;

        size_t built;

        if (
            !buildExactAtomicEdgesFromNodedSource(
                sources[
                    sourceIndex
                ].segment,
                sources[
                    sourceIndex
                ].operandMask,
                sources[
                    sourceIndex
                ].interiorOnSourceLeft,
                eventStorage[
                    begin ..
                    begin +
                    eventCounts[
                        sourceIndex
                    ]
                ],
                atomicEdges[
                    atomicWrite ..
                    $
                ],
                built
            )
        )
        {
            return invariantFailure();
        }

        atomicWrite +=
            built;
    }

    if (atomicWrite != atomicEdgeCount)
        return invariantFailure();


    atomicEdgeCount =
        sortMergeExactAtomicEdges(
            atomicEdges[]
        );


    size_t arrangementVertexCapacity;

    if (
        !checkedMultiply(
            atomicEdgeCount,
            2,
            arrangementVertexCapacity
        )
    )
    {
        return
            PolygonUnionP1InternalStatus
                .resourceLimit;
    }

    auto exactVertices =
        new ExactOverlayPoint[
            arrangementVertexCapacity
        ];

    auto arrangementEdges =
        new ExactArrangementEdge!T[
            atomicEdgeCount
        ];

    size_t vertexCount;
    size_t arrangementEdgeCount;

    if (
        !buildExactArrangement(
            atomicEdges[
                0 ..
                atomicEdgeCount
            ],
            exactVertices[],
            arrangementEdges[],
            vertexCount,
            arrangementEdgeCount
        ) ||
        arrangementEdgeCount !=
            atomicEdgeCount
    )
    {
        return invariantFailure();
    }


    size_t halfEdgeCount;

    if (
        !checkedMultiply(
            arrangementEdgeCount,
            2,
            halfEdgeCount
        )
    )
    {
        return
            PolygonUnionP1InternalStatus
                .resourceLimit;
    }

    auto halfEdges =
        new ExactArrangementHalfEdge[
            halfEdgeCount
        ];

    auto outgoing =
        new size_t[
            halfEdgeCount
        ];

    auto halfEdgePosition =
        new size_t[
            halfEdgeCount
        ];

    auto vertexOffsets =
        new size_t[
            vertexCount + 1
        ];

    auto vertexCursor =
        new size_t[
            vertexCount
        ];

    if (
        !buildExactHalfEdgeEmbedding(
            arrangementEdges[
                0 ..
                arrangementEdgeCount
            ],
            vertexCount,
            halfEdges[],
            outgoing[],
            halfEdgePosition[],
            vertexOffsets[],
            vertexCursor[]
        )
    )
    {
        return invariantFailure();
    }


    auto sideLabels =
        new ExactHalfEdgeSideLabel[
            halfEdgeCount
        ];

    if (
        !initializeExactHalfEdgeSideLabels(
            arrangementEdges[
                0 ..
                arrangementEdgeCount
            ],
            halfEdges[],
            sideLabels[]
        )
    )
    {
        return invariantFailure();
    }

    size_t containmentSeedCount;

    if (
        !tryResolveExactHalfEdgeSideLabelsWithContainment(
            arrangementEdges[
                0 ..
                arrangementEdgeCount
            ],
            halfEdges[],
            first,
            second,
            sideLabels[],
            containmentSeedCount
        )
    )
    {
        return invariantFailure();
    }


    auto selected =
        new bool[
            halfEdgeCount
        ];

    if (
        !selectExactUnionBoundaryHalfEdges(
            arrangementEdges[
                0 ..
                arrangementEdgeCount
            ],
            halfEdges[],
            sideLabels[],
            selected[]
        )
    )
    {
        return invariantFailure();
    }


    auto nextSelected =
        new size_t[
            halfEdgeCount
        ];

    auto edgeCycle =
        new size_t[
            halfEdgeCount
        ];

    auto vertexCycle =
        new size_t[
            vertexCount
        ];

    auto cycles =
        new ExactUnionBoundaryCycle[
            halfEdgeCount
        ];

    size_t cycleCount;

    if (
        !tryBuildExactUnionBoundaryCycles(
            halfEdges[],
            outgoing[],
            halfEdgePosition[],
            vertexOffsets[],
            selected[],
            nextSelected[],
            edgeCycle[],
            vertexCycle[],
            cycles[],
            cycleCount
        )
    )
    {
        return invariantFailure();
    }


    auto roles =
        new ExactUnionCycleRole[
            cycleCount
        ];

    auto componentOfCycle =
        new size_t[
            cycleCount
        ];

    auto exactComponents =
        new ExactUnionComponent[
            cycleCount
        ];

    size_t componentCount;

    if (
        !tryBuildExactUnionComponents(
            cycles[
                0 ..
                cycleCount
            ],
            halfEdges[],
            nextSelected[],
            exactVertices[
                0 ..
                vertexCount
            ],
            roles[],
            componentOfCycle[],
            exactComponents[],
            componentCount
        )
    )
    {
        return invariantFailure();
    }


    auto componentOrder =
        new size_t[
            componentCount
        ];

    auto orderedCycles =
        new size_t[
            cycleCount
        ];

    auto componentRingOffsets =
        new size_t[
            componentCount + 1
        ];

    auto cycleScratch =
        new size_t[
            cycleCount
        ];

    if (
        !tryBuildCanonicalExactUnionLayout(
            cycles[
                0 ..
                cycleCount
            ],
            roles[],
            componentOfCycle[],
            exactComponents[
                0 ..
                componentCount
            ],
            halfEdges[],
            nextSelected[],
            exactVertices[
                0 ..
                vertexCount
            ],
            componentOrder[],
            orderedCycles[],
            componentRingOffsets[],
            cycleScratch[]
        )
    )
    {
        return invariantFailure();
    }


    auto exactToMaterialized =
        new size_t[
            vertexCount
        ];

    auto compactPoints =
        new Point2!double[
            vertexCount
        ];

    auto materializedEdges =
        new MaterializedUnionBoundaryEdge[
            halfEdgeCount
        ];

    size_t compactPointCount;
    size_t boundaryEdgeCount;

    if (
        !tryMaterializeExactUnionBoundaryGraph(
            exactVertices[
                0 ..
                vertexCount
            ],
            cycles[
                0 ..
                cycleCount
            ],
            orderedCycles[],
            halfEdges[],
            nextSelected[],
            exactToMaterialized[],
            compactPoints[],
            materializedEdges[],
            compactPointCount,
            boundaryEdgeCount
        )
    )
    {
        return
            PolygonUnionP1InternalStatus
                .unrepresentableConstruction;
    }


    auto ringPoints =
        new Point2!double[
            boundaryEdgeCount
        ];

    auto ringPointOffsets =
        new size_t[
            cycleCount + 1
        ];

    size_t ringPointCount;

    if (
        !tryWriteMaterializedUnionRings(
            exactVertices[
                0 ..
                vertexCount
            ],
            cycles[
                0 ..
                cycleCount
            ],
            orderedCycles[],
            halfEdges[],
            nextSelected[],
            exactToMaterialized[],
            compactPoints[
                0 ..
                compactPointCount
            ],
            ringPoints[],
            ringPointOffsets[],
            ringPointCount
        ) ||
        ringPointCount !=
            boundaryEdgeCount
    )
    {
        return
            PolygonUnionP1InternalStatus
                .unrepresentableConstruction;
    }


    if (
        !materializedUnionComponentsRemainValidAndDisjoint(
            ringPoints[
                0 ..
                ringPointCount
            ],
            ringPointOffsets[],
            componentRingOffsets[]
        )
    )
    {
        return
            PolygonUnionP1InternalStatus
                .unrepresentableConstruction;
    }


    /*
     * Exact-sized owning point storage is already ringPoints. All materialized
     * entries were written because ringPointCount == ringPoints.length.
     *
     * takePolygonUnionOwnedResultInternal consumes points and component
     * offsets into immutable backing. ringPointOffsets is build metadata.
     */
    result =
        takePolygonUnionOwnedResultInternal(
            ringPoints,
            ringPointOffsets[],
            componentRingOffsets
        );

    return
        PolygonUnionP1InternalStatus
            .success;
}


private bool sameInternalUnionResult(
    ref const PolygonUnionOwnedResultInternal lhs,
    ref const PolygonUnionOwnedResultInternal rhs
)
    pure nothrow @safe @nogc
{
    if (
        lhs.componentCount !=
        rhs.componentCount
    )
    {
        return false;
    }

    foreach (
        componentIndex;
        0 ..
        lhs.componentCount
    )
    {
        const auto first =
            lhs.component(
                componentIndex
            );

        const auto second =
            rhs.component(
                componentIndex
            );

        if (
            first.length !=
            second.length
        )
        {
            return false;
        }

        foreach (ringIndex; 0 .. first.length)
        {
            const auto firstRing =
                first[ringIndex];

            const auto secondRing =
                second[ringIndex];

            if (
                firstRing.length !=
                secondRing.length
            )
            {
                return false;
            }

            foreach (
                pointIndex;
                0 ..
                firstRing.length
            )
            {
                if (
                    firstRing[pointIndex] !=
                    secondRing[pointIndex]
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
    import geo.linear_ring_view :
        LinearRing2View;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;


    /*
     * Empty identity.
     */
    R[] emptyRings;

    const G empty =
        G(emptyRings);

    P[4] squarePoints = [
        P(0, 0),
        P(4, 0),
        P(4, 4),
        P(0, 4),
    ];

    R[1] squareRings = [
        R(squarePoints[])
    ];

    const G square =
        G(squareRings[]);

    PolygonUnionOwnedResultInternal result;

    assert(
        tryPolygonUnionP1Internal(
            empty,
            square,
            result
        ) ==
        PolygonUnionP1InternalStatus.success
    );

    assert(result.componentCount == 1);

    const auto component =
        result.component(0);

    assert(component.length == 1);
    assert(component.exterior.length == 4);

    assert(
        component.exterior[0] ==
        Point2!double(0.0, 0.0)
    );

    assert(
        component.exterior[1] ==
        Point2!double(4.0, 0.0)
    );
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;


    /*
     * Two disjoint squares produce two canonical components independent of
     * operand order.
     */
    P[4] leftPoints = [
        P(0, 0),
        P(2, 0),
        P(2, 2),
        P(0, 2),
    ];

    P[4] rightPoints = [
        P(10, 0),
        P(12, 0),
        P(12, 2),
        P(10, 2),
    ];

    R[1] leftRings = [
        R(leftPoints[])
    ];

    R[1] rightRings = [
        R(rightPoints[])
    ];

    const G left =
        G(leftRings[]);

    const G right =
        G(rightRings[]);

    PolygonUnionOwnedResultInternal first;
    PolygonUnionOwnedResultInternal second;

    assert(
        tryPolygonUnionP1Internal(
            left,
            right,
            first
        ) ==
        PolygonUnionP1InternalStatus.success
    );

    assert(
        tryPolygonUnionP1Internal(
            right,
            left,
            second
        ) ==
        PolygonUnionP1InternalStatus.success
    );

    assert(first.componentCount == 2);

    assert(
        sameInternalUnionResult(
            first,
            second
        )
    );

    assert(
        first.component(0).exterior[0] ==
        Point2!double(0.0, 0.0)
    );

    assert(
        first.component(1).exterior[0] ==
        Point2!double(10.0, 0.0)
    );
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;


    /*
     * Shared-edge adjacency removes the internal shared span and produces one
     * rectangular component.
     */
    P[4] firstPoints = [
        P(0, 0),
        P(2, 0),
        P(2, 2),
        P(0, 2),
    ];

    P[4] secondPoints = [
        P(2, 0),
        P(4, 0),
        P(4, 2),
        P(2, 2),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    PolygonUnionOwnedResultInternal result;

    assert(
        tryPolygonUnionP1Internal(
            G(firstRings[]),
            G(secondRings[]),
            result
        ) ==
        PolygonUnionP1InternalStatus.success
    );

    assert(result.componentCount == 1);

    const auto component =
        result.component(0);

    assert(component.holeCount == 0);
    assert(component.exterior.length == 6);
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;


    /*
     * Point-only contact remains two regularized components.
     */
    P[4] firstPoints = [
        P(0, 0),
        P(2, 0),
        P(2, 2),
        P(0, 2),
    ];

    P[4] secondPoints = [
        P(2, 2),
        P(4, 2),
        P(4, 4),
        P(2, 4),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    PolygonUnionOwnedResultInternal result;

    assert(
        tryPolygonUnionP1Internal(
            G(firstRings[]),
            G(secondRings[]),
            result
        ) ==
        PolygonUnionP1InternalStatus.success
    );

    assert(result.componentCount == 2);
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;


    /*
     * Containment returns only the containing boundary.
     */
    P[4] outerPoints = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(0, 10),
    ];

    P[4] innerPoints = [
        P(2, 2),
        P(4, 2),
        P(4, 4),
        P(2, 4),
    ];

    R[1] outerRings = [
        R(outerPoints[])
    ];

    R[1] innerRings = [
        R(innerPoints[])
    ];

    PolygonUnionOwnedResultInternal result;

    assert(
        tryPolygonUnionP1Internal(
            G(outerRings[]),
            G(innerRings[]),
            result
        ) ==
        PolygonUnionP1InternalStatus.success
    );

    assert(result.componentCount == 1);
    assert(result.component(0).exterior.length == 4);

    assert(
        result.component(0).exterior[0] ==
        Point2!double(0.0, 0.0)
    );
}
