module geo.internal.boolean_overlay_p1_research;

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
    tryResolveExactHalfEdgeSideLabelsWithContainment;

import geo.internal.polygon_union_result :
    PolygonUnionOwnedResultInternal,
    takePolygonUnionOwnedResultInternal;

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
 * INTERNAL RESEARCH MODULE.
 *
 * Executable Issue #49 evidence for end-to-end regularized polygon Boolean
 * overlay.
 *
 * This module intentionally duplicates the accepted polygon-union P1
 * orchestration rather than refactoring production merely to make the
 * experiment convenient.
 *
 * The duplicated pre-selection machinery remains structurally aligned with
 * polygon_union_p1.d. The operation-specific research change is the exact
 * region predicate used to select the oriented result boundary.
 *
 * This module does not authorize production generalization or public API
 * expansion.
 */


package(geo)
enum BooleanOverlayP1ResearchStatus : ubyte
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
     * This is distinct from geometric construction failure. The public
     * wrapper routes this pre-detected impossible workspace size through the
     * same OutOfMemoryError resource-failure path used for impossible runtime
     * allocation sizes. Ordinary allocation exhaustion likewise remains a
     * resource failure rather than a geometry status.
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


private enum bool isBooleanOverlayP1ResearchScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


package(geo)
enum BooleanOverlayResearchOperation : ubyte
{
    unionSet,
    intersection,
    differenceAB,
    differenceBA,
    symmetricDifference,
}


private enum ubyte researchOperandMask =
    polygonUnionOperandA |
    polygonUnionOperandB;


private bool researchRegionInterior(
    BooleanOverlayResearchOperation operation,
    ubyte insideMask
)
    pure nothrow @safe @nogc
{
    assert(
        (
            insideMask &
            ~researchOperandMask
        ) == 0
    );

    const bool insideA =
        (
            insideMask &
            polygonUnionOperandA
        ) != 0;

    const bool insideB =
        (
            insideMask &
            polygonUnionOperandB
        ) != 0;

    final switch (operation)
    {
        case BooleanOverlayResearchOperation.unionSet:
            return insideA || insideB;

        case BooleanOverlayResearchOperation.intersection:
            return insideA && insideB;

        case BooleanOverlayResearchOperation.differenceAB:
            return insideA && !insideB;

        case BooleanOverlayResearchOperation.differenceBA:
            return insideB && !insideA;

        case BooleanOverlayResearchOperation.symmetricDifference:
            return insideA != insideB;
    }
}


/*
 * Research-only result-boundary selector.
 *
 * A directed half-edge is selected exactly when:
 *
 *     R(leftA, leftB) != R(rightA, rightB)
 *
 * and the selected direction is the one for which:
 *
 *     R(leftA, leftB) == true
 *
 * Therefore every selected edge has result interior on its left.
 */
private bool selectResearchBooleanBoundaryHalfEdges(T)(
    scope const(ExactArrangementEdge!T)[] edges,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(ExactHalfEdgeSideLabel)[] labels,
    BooleanOverlayResearchOperation operation,
    scope bool[] selected
)
    pure nothrow @safe @nogc
if (isBooleanOverlayP1ResearchScalar!T)
{
    if (
        labels.length != halfEdges.length ||
        selected.length != halfEdges.length
    )
    {
        return false;
    }

    foreach (ref value; selected)
        value = false;

    foreach (halfEdgeIndex, ref const halfEdge; halfEdges)
    {
        if (
            halfEdge.arrangementEdge >= edges.length ||
            halfEdge.twin >= halfEdges.length
        )
        {
            return false;
        }

        const auto leftLabel =
            labels[
                halfEdgeIndex
            ];

        const auto rightLabel =
            labels[
                halfEdge.twin
            ];

        if (
            leftLabel.knownMask != researchOperandMask ||
            rightLabel.knownMask != researchOperandMask
        )
        {
            return false;
        }

        const bool leftInterior =
            researchRegionInterior(
                operation,
                leftLabel.insideMask &
                    researchOperandMask
            );

        const bool rightInterior =
            researchRegionInterior(
                operation,
                rightLabel.insideMask &
                    researchOperandMask
            );

        if (
            leftInterior != rightInterior &&
            leftInterior
        )
        {
            selected[
                halfEdgeIndex
            ] = true;
        }
    }

    return true;
}


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
if (isBooleanOverlayP1ResearchScalar!T)
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
if (isBooleanOverlayP1ResearchScalar!T)
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


/*
 * Adds the raw noding-event demand of one exact segment contact to both
 * source-edge capacities.
 *
 * The calculation deliberately mirrors appendSegmentPairNodingEvents:
 *
 * none             -> 0 events per edge
 * touch            -> 1 event per edge
 * properCrossing   -> 1 event per edge
 * overlap          -> 2 events per edge
 *
 * Returning false means that the exact required workspace cardinality cannot
 * be represented by size_t.
 */
private bool tryAccumulateNodingEventCapacity(T)(
    Segment2!T first,
    Segment2!T second,
    ref size_t firstCapacity,
    ref size_t secondCapacity
)
    pure nothrow @safe @nogc
if (isBooleanOverlayP1ResearchScalar!T)
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


private BooleanOverlayP1ResearchStatus invariantFailure()
    pure nothrow @safe @nogc
{
    assert(
        false,
        "boolean-overlay research P1 internal invariant failure"
    );

    return
        BooleanOverlayP1ResearchStatus
            .internalInvariantFailure;
}


/*
 * Constructs one immutable research Boolean-overlay result.
 *
 * The complete production P1 input/noding/arrangement/label/downstream shape
 * is duplicated here for Issue #49. The only intended semantic experiment is
 * the operation-specific result-region selector.
 *
 * Production code is not refactored by this research module.
 */
package(geo)
BooleanOverlayP1ResearchStatus tryBooleanOverlayP1ResearchInternal(T)(
    scope Polygon2View!T first,
    scope Polygon2View!T second,
    BooleanOverlayResearchOperation operation,
    out PolygonUnionOwnedResultInternal result
)
    @safe
if (isBooleanOverlayP1ResearchScalar!T)
{
    result =
        PolygonUnionOwnedResultInternal.init;


    if (
        !validatePolygon(first).valid
    )
    {
        return
            BooleanOverlayP1ResearchStatus
                .invalidFirstInput;
    }

    if (
        !validatePolygon(second).valid
    )
    {
        return
            BooleanOverlayP1ResearchStatus
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
            BooleanOverlayP1ResearchStatus
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
            BooleanOverlayP1ResearchStatus
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
                    BooleanOverlayP1ResearchStatus
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
            BooleanOverlayP1ResearchStatus
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
                BooleanOverlayP1ResearchStatus
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
            return invariantFailure();
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
                return invariantFailure();
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
                BooleanOverlayP1ResearchStatus
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
            BooleanOverlayP1ResearchStatus
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
            BooleanOverlayP1ResearchStatus
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
        !selectResearchBooleanBoundaryHalfEdges(
            arrangementEdges[
                0 ..
                arrangementEdgeCount
            ],
            halfEdges[],
            sideLabels[],
            operation,
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
            BooleanOverlayP1ResearchStatus
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
            BooleanOverlayP1ResearchStatus
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
            BooleanOverlayP1ResearchStatus
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
        BooleanOverlayP1ResearchStatus
            .success;
}
