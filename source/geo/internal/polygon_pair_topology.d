module geo.internal.polygon_pair_topology;

import geo.internal.polygon_union_arrangement :
    ExactArrangementEdge,
    buildExactArrangement;

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

import geo.internal.polygon_union_noding :
    ExactAtomicEdge,
    buildExactAtomicEdgesFromNodedSource,
    polygonUnionOperandA,
    polygonUnionOperandB,
    sortMergeExactAtomicEdges;

import geo.internal.polygon_union_regions :
    ExactHalfEdgeSideLabel,
    initializeExactHalfEdgeSideLabels,
    tryResolveExactHalfEdgeSideLabelsWithContainment;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind;

import geo.polygon_view :
    Polygon2View;

import geo.point :
    Point2;

import geo.segment :
    Segment2;

import geo.topology_validation :
    validatePolygon;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Shared exact two-polygon topology construction.
 *
 * The builder stops after complete exact A/B half-edge side labeling.
 * Constructive consumers such as polygon union may continue from this state;
 * relationship consumers may reduce it directly without reconstructing or
 * materializing result geometry.
 */


package(geo)
enum PolygonPairTopologyStatus : ubyte
{
    success,

    invalidFirstInput,

    invalidSecondInput,

    /*
     * Required workspace cardinality cannot be represented by size_t.
     *
     * Runtime allocation exhaustion remains a normal D resource failure.
     */
    resourceLimit,

    /*
     * A production invariant failed after valid inputs and correctly sized
     * workspace were established.
     */
    internalInvariantFailure,
}


/*
 * Minimal surviving exact topology state at the shared cutpoint.
 *
 * Build-only source-edge, noding-event, atomic-edge and embedding scratch
 * storage is deliberately not retained here.
 */
package(geo)
struct ExactPolygonPairTopology(T)
{
    ExactOverlayPoint[] exactVertices;

    ExactArrangementEdge!T[] arrangementEdges;

    ExactArrangementHalfEdge[] halfEdges;

    size_t[] outgoing;

    size_t[] halfEdgePosition;

    size_t[] vertexOffsets;

    ExactHalfEdgeSideLabel[] sideLabels;

    size_t vertexCount;

    size_t arrangementEdgeCount;
}


private enum bool isPolygonPairTopologyScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


private struct SourceEdgeEnvelope(T)
{
    T minX;
    T maxX;
    T minY;
    T maxY;
}

private SourceEdgeEnvelope!T sourceEdgeEnvelope(T)(
    Segment2!T segment
)
    pure nothrow @safe @nogc
if (isPolygonPairTopologyScalar!T)
{
    return
        SourceEdgeEnvelope!T(
            segment.a.x < segment.b.x
                ? segment.a.x
                : segment.b.x,
            segment.a.x < segment.b.x
                ? segment.b.x
                : segment.a.x,
            segment.a.y < segment.b.y
                ? segment.a.y
                : segment.b.y,
            segment.a.y < segment.b.y
                ? segment.b.y
                : segment.a.y
        );
}

private bool sourceEdgeEnvelopesOverlap(T)(
    ref const SourceEdgeEnvelope!T first,
    ref const SourceEdgeEnvelope!T second
)
    pure nothrow @safe @nogc
if (isPolygonPairTopologyScalar!T)
{
    return
        first.maxX >= second.minX &&
        second.maxX >= first.minX &&
        first.maxY >= second.minY &&
        second.maxY >= first.minY;
}

private size_t requiredNodingEventCount(
    SegmentContactKind contact
)
    pure nothrow @safe @nogc
{
    final switch (contact)
    {
        case SegmentContactKind.none:
            return 0;

        case SegmentContactKind.touch:
        case SegmentContactKind.properCrossing:
            return 1;

        case SegmentContactKind.overlap:
            return 2;
    }
}

private bool tryAccumulateNodingEventCapacity(T)(
    Segment2!T first,
    Segment2!T second,
    ref size_t firstCapacity,
    ref size_t secondCapacity
)
    pure nothrow @safe @nogc
if (isPolygonPairTopologyScalar!T)
{
    const size_t required =
        requiredNodingEventCount(
            segmentContactKind(
                first,
                second
            )
        );

    if (required == 0)
        return true;

    size_t firstUpdated;
    size_t secondUpdated;

    if (
        !checkedAdd(
            firstCapacity,
            required,
            firstUpdated
        ) ||
        !checkedAdd(
            secondCapacity,
            required,
            secondUpdated
        )
    )
    {
        return false;
    }

    firstCapacity =
        firstUpdated;

    secondCapacity =
        secondUpdated;

    return true;
}

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


private PolygonPairTopologyStatus topologyInvariantFailure()
    pure nothrow @safe @nogc
{
    assert(
        false,
        "polygon-pair topology internal invariant failure"
    );

    return
        PolygonPairTopologyStatus
            .internalInvariantFailure;
}



package(geo)
PolygonPairTopologyStatus tryBuildExactPolygonPairTopology(T)(
    scope Polygon2View!T first,
    scope Polygon2View!T second,
    out ExactPolygonPairTopology!T topology
)
    @safe
if (isPolygonPairTopologyScalar!T)
{

    topology =
        ExactPolygonPairTopology!T.init;


    if (
        !validatePolygon(first).valid
    )
    {
        return
            PolygonPairTopologyStatus
                .invalidFirstInput;
    }

    if (
        !validatePolygon(second).valid
    )
    {
        return
            PolygonPairTopologyStatus
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
            PolygonPairTopologyStatus
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
            PolygonPairTopologyStatus
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
        return topologyInvariantFailure();
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
        return topologyInvariantFailure();
    }


    /*
     * Build one transient closed axis-aligned envelope per source edge.
     *
     * The envelope is only a necessary broad-phase contact condition.
     * Exact segment topology remains authoritative for every pair that
     * survives this reject.
     */
    auto sourceEnvelopes =
        new SourceEdgeEnvelope!T[
            sourceCount
        ];

    foreach (sourceIndex; 0 .. sourceCount)
    {
        sourceEnvelopes[sourceIndex] =
            sourceEdgeEnvelope(
                sources[
                    sourceIndex
                ].segment
            );
    }


    /*
     * Count the exact event capacity required by each source edge.
     *
     * Every edge starts with its two endpoints. A surviving source-edge pair
     * contributes zero, one, or two additional events according to the same
     * exact contact classification used by the established noding machinery.
     *
     * Pair traversal order remains the original deterministic nested order.
     */
    auto eventCapacities =
        new size_t[
            sourceCount
        ];

    foreach (ref capacity; eventCapacities)
    {
        capacity = 2;
    }

    foreach (firstIndex; 0 .. sourceCount)
    {
        foreach (
            secondIndex;
            firstIndex + 1 ..
            sourceCount
        )
        {
            if (
                !sourceEdgeEnvelopesOverlap(
                    sourceEnvelopes[
                        firstIndex
                    ],
                    sourceEnvelopes[
                        secondIndex
                    ]
                )
            )
            {
                continue;
            }

            if (
                !tryAccumulateNodingEventCapacity(
                    sources[
                        firstIndex
                    ].segment,
                    sources[
                        secondIndex
                    ].segment,
                    eventCapacities[
                        firstIndex
                    ],
                    eventCapacities[
                        secondIndex
                    ]
                )
            )
            {
                return
                    PolygonPairTopologyStatus
                        .resourceLimit;
            }
        }
    }


    size_t eventOffsetCount;

    if (
        !checkedAdd(
            sourceCount,
            1,
            eventOffsetCount
        )
    )
    {
        return
            PolygonPairTopologyStatus
                .resourceLimit;
    }

    auto eventOffsets =
        new size_t[
            eventOffsetCount
        ];

    foreach (sourceIndex; 0 .. sourceCount)
    {
        if (
            !checkedAdd(
                eventOffsets[
                    sourceIndex
                ],
                eventCapacities[
                    sourceIndex
                ],
                eventOffsets[
                    sourceIndex + 1
                ]
            )
        )
        {
            return
                PolygonPairTopologyStatus
                    .resourceLimit;
        }
    }

    const size_t totalEventCapacity =
        eventOffsets[
            sourceCount
        ];


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
            eventOffsets[
                sourceIndex
            ];

        const size_t capacity =
            eventOffsets[
                sourceIndex + 1
            ] -
            begin;

        size_t count;

        if (
            !seedExactEdgeEvents(
                sources[
                    sourceIndex
                ].segment,
                eventStorage[
                    begin ..
                    begin +
                    capacity
                ],
                count
            )
        )
        {
            return topologyInvariantFailure();
        }

        eventCounts[sourceIndex] =
            count;
    }


    /*
     * Run the established exact noding append path in the same deterministic
     * pair order. AABB-disjoint pairs are the only pairs skipped.
     */
    foreach (firstIndex; 0 .. sourceCount)
    {
        const size_t firstBegin =
            eventOffsets[
                firstIndex
            ];

        const size_t firstCapacity =
            eventOffsets[
                firstIndex + 1
            ] -
            firstBegin;

        foreach (
            secondIndex;
            firstIndex + 1 ..
            sourceCount
        )
        {
            if (
                !sourceEdgeEnvelopesOverlap(
                    sourceEnvelopes[
                        firstIndex
                    ],
                    sourceEnvelopes[
                        secondIndex
                    ]
                )
            )
            {
                continue;
            }

            const size_t secondBegin =
                eventOffsets[
                    secondIndex
                ];

            const size_t secondCapacity =
                eventOffsets[
                    secondIndex + 1
                ] -
                secondBegin;

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
                        firstCapacity
                    ],
                    eventCounts[
                        firstIndex
                    ],
                    eventStorage[
                        secondBegin ..
                        secondBegin +
                        secondCapacity
                    ],
                    eventCounts[
                        secondIndex
                    ]
                )
            )
            {
                return topologyInvariantFailure();
            }
        }
    }


    size_t atomicEdgeCount = 0;

    foreach (sourceIndex; 0 .. sourceCount)
    {
        const size_t begin =
            eventOffsets[
                sourceIndex
            ];

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
            return topologyInvariantFailure();

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
                PolygonPairTopologyStatus
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
            eventOffsets[
                sourceIndex
            ];

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
            return topologyInvariantFailure();
        }

        atomicWrite +=
            built;
    }

    if (atomicWrite != atomicEdgeCount)
        return topologyInvariantFailure();


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
            PolygonPairTopologyStatus
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
        return topologyInvariantFailure();
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
            PolygonPairTopologyStatus
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
        return topologyInvariantFailure();
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
        return topologyInvariantFailure();
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
        return topologyInvariantFailure();
    }


    topology.exactVertices =
        exactVertices;

    topology.arrangementEdges =
        arrangementEdges;

    topology.halfEdges =
        halfEdges;

    topology.outgoing =
        outgoing;

    topology.halfEdgePosition =
        halfEdgePosition;

    topology.vertexOffsets =
        vertexOffsets;

    topology.sideLabels =
        sideLabels;

    topology.vertexCount =
        vertexCount;

    topology.arrangementEdgeCount =
        arrangementEdgeCount;

    return
        PolygonPairTopologyStatus
            .success;
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    import geo.point :
        Point2;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;


    /*
     * Shared-edge adjacency exercises exact noding, merged A+B provenance,
     * half-edge embedding and complete side-label resolution without invoking
     * polygon-union boundary reconstruction.
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

    ExactPolygonPairTopology!int topology;

    assert(
        tryBuildExactPolygonPairTopology(
            G(firstRings[]),
            G(secondRings[]),
            topology
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(topology.vertexCount != 0);
    assert(topology.arrangementEdgeCount != 0);

    assert(
        topology.halfEdges.length ==
            topology.sideLabels.length
    );

    enum ubyte bothOperands =
        polygonUnionOperandA |
        polygonUnionOperandB;

    foreach (label; topology.sideLabels)
    {
        assert(
            (
                label.knownMask &
                bothOperands
            ) ==
                bothOperands
        );
    }
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    R[] noRings;

    const G empty =
        G(noRings);

    ExactPolygonPairTopology!int topology;

    assert(
        tryBuildExactPolygonPairTopology(
            empty,
            empty,
            topology
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(topology.vertexCount == 0);
    assert(topology.arrangementEdgeCount == 0);
    assert(topology.exactVertices.length == 0);
    assert(topology.arrangementEdges.length == 0);
    assert(topology.halfEdges.length == 0);
    assert(topology.sideLabels.length == 0);
}


/*
 * Builder regression tests moved from polygon_union_p1.d when exact
 * polygon-pair topology construction became shared infrastructure.
 */


/*
 * Workspace-cardinality arithmetic must accept the largest representable
 * size_t result and reject only the first mathematically unrepresentable
 * result. Failure resets the helper output instead of exposing a wrapped
 * cardinality.
 */
@safe unittest
{
    size_t result =
        size_t.max;

    assert(
        checkedAdd(
            size_t.max - 1,
            1,
            result
        )
    );

    assert(result == size_t.max);


    result =
        size_t.max;

    assert(
        !checkedAdd(
            size_t.max,
            1,
            result
        )
    );

    assert(result == 0);


    result =
        size_t.max;

    assert(
        checkedMultiply(
            size_t.max,
            1,
            result
        )
    );

    assert(result == size_t.max);


    result =
        size_t.max;

    assert(
        checkedMultiply(
            0,
            size_t.max,
            result
        )
    );

    assert(result == 0);


    result =
        size_t.max;

    assert(
        !checkedMultiply(
            size_t.max,
            2,
            result
        )
    );

    assert(result == 0);
}


/*
 * P3 exact event-capacity accumulation is transactional across both source
 * edges. If either edge cannot represent the exact additional raw event
 * demand, neither capacity is changed.
 */
@safe unittest
{
    alias P =
        Point2!int;

    alias S =
        Segment2!int;

    const S first =
        S(
            P(0, 0),
            P(10, 0)
        );

    const S second =
        S(
            P(2, 0),
            P(8, 0)
        );

    assert(
        segmentContactKind(
            first,
            second
        ) ==
            SegmentContactKind.overlap
    );

    size_t firstCapacity =
        size_t.max - 1;

    size_t secondCapacity =
        2;

    assert(
        !tryAccumulateNodingEventCapacity(
            first,
            second,
            firstCapacity,
            secondCapacity
        )
    );

    assert(
        firstCapacity ==
            size_t.max - 1
    );

    assert(secondCapacity == 2);


    firstCapacity =
        2;

    secondCapacity =
        size_t.max - 1;

    assert(
        !tryAccumulateNodingEventCapacity(
            first,
            second,
            firstCapacity,
            secondCapacity
        )
    );

    assert(firstCapacity == 2);

    assert(
        secondCapacity ==
            size_t.max - 1
    );
}


/*
 * Exact-sized event-capacity counting must agree exactly with the unchanged
 * noding append path before duplicate-event removal.
 *
 * This fixture deliberately combines:
 *
 * - proper crossing;
 * - positive collinear overlap;
 * - endpoint touch;
 * - disjoint segments;
 * - multiple contacts accumulated onto the same source edge.
 */
@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;

    enum size_t segmentCount = 5;

    S[segmentCount] segments = [
        S(
            P(0, 0),
            P(10, 0)
        ),
        S(
            P(5, -5),
            P(5, 5)
        ),
        S(
            P(2, 0),
            P(8, 0)
        ),
        S(
            P(10, 0),
            P(10, 5)
        ),
        S(
            P(20, 20),
            P(30, 20)
        ),
    ];

    SourceEdgeEnvelope!int[segmentCount]
        envelopes;

    size_t[segmentCount]
        capacities;

    foreach (index; 0 .. segmentCount)
    {
        envelopes[index] =
            sourceEdgeEnvelope(
                segments[index]
            );

        capacities[index] = 2;
    }


    foreach (firstIndex; 0 .. segmentCount)
    {
        foreach (
            secondIndex;
            firstIndex + 1 ..
            segmentCount
        )
        {
            if (
                !sourceEdgeEnvelopesOverlap(
                    envelopes[firstIndex],
                    envelopes[secondIndex]
                )
            )
            {
                assert(
                    segmentContactKind(
                        segments[firstIndex],
                        segments[secondIndex]
                    ) ==
                        SegmentContactKind.none
                );

                continue;
            }

            assert(
                tryAccumulateNodingEventCapacity(
                    segments[firstIndex],
                    segments[secondIndex],
                    capacities[firstIndex],
                    capacities[secondIndex]
                )
            );
        }
    }


    /*
     * Expected raw capacities before exact duplicate removal:
     *
     * edge 0: endpoints + crossing + overlap(2) + touch = 6
     * edge 1: endpoints + two crossings              = 4
     * edge 2: endpoints + overlap(2) + crossing      = 5
     * edge 3: endpoints + touch                      = 3
     * edge 4: endpoints only                         = 2
     */
    assert(
        capacities == [
            6,
            4,
            5,
            3,
            2,
        ]
    );


    size_t[segmentCount + 1]
        offsets;

    foreach (sourceIndex; 0 .. segmentCount)
    {
        assert(
            checkedAdd(
                offsets[sourceIndex],
                capacities[sourceIndex],
                offsets[sourceIndex + 1]
            )
        );
    }

    auto storage =
        new ExactOverlayPoint[
            offsets[
                segmentCount
            ]
        ];

    size_t[segmentCount]
        counts;


    foreach (sourceIndex; 0 .. segmentCount)
    {
        const size_t begin =
            offsets[sourceIndex];

        assert(
            seedExactEdgeEvents(
                segments[sourceIndex],
                storage[
                    begin ..
                    offsets[sourceIndex + 1]
                ],
                counts[sourceIndex]
            )
        );

        assert(counts[sourceIndex] == 2);
    }


    foreach (firstIndex; 0 .. segmentCount)
    {
        foreach (
            secondIndex;
            firstIndex + 1 ..
            segmentCount
        )
        {
            if (
                !sourceEdgeEnvelopesOverlap(
                    envelopes[firstIndex],
                    envelopes[secondIndex]
                )
            )
            {
                continue;
            }

            assert(
                appendSegmentPairNodingEvents(
                    segments[firstIndex],
                    segments[secondIndex],
                    storage[
                        offsets[firstIndex] ..
                        offsets[firstIndex + 1]
                    ],
                    counts[firstIndex],
                    storage[
                        offsets[secondIndex] ..
                        offsets[secondIndex + 1]
                    ],
                    counts[secondIndex]
                )
            );
        }
    }


    /*
     * Exact pre-counting must leave neither too little nor excess raw event
     * capacity for this complete pair traversal.
     */
    assert(
        counts ==
            capacities
    );
}
