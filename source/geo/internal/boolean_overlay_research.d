module geo.internal.boolean_overlay_research;

import geo.internal.polygon_union_arrangement :
    ExactArrangementEdge;

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

import geo.internal.polygon_union_noding :
    polygonUnionOperandA,
    polygonUnionOperandB;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    exactOverlayPoint;

import geo.internal.polygon_union_materialization :
    MaterializedUnionBoundaryEdge,
    materializedUnionComponentsRemainValidAndDisjoint,
    tryMaterializeExactUnionBoundaryGraph,
    tryWriteMaterializedUnionRings;

import geo.internal.polygon_union_regions :
    ExactHalfEdgeSideLabel,
    initializeExactHalfEdgeSideLabels,
    selectExactUnionBoundaryHalfEdges,
    tryResolveExactHalfEdgeSideLabelsWithContainment;

import geo.internal.polygon_union_result :
    takePolygonUnionOwnedResultInternal;

import geo.linear_ring_view :
    LinearRing2View;

import geo.point :
    Point2;

import geo.polygon_view :
    Polygon2View;

import geo.segment :
    Segment2;


/*
 * INTERNAL RESEARCH MODULE.
 *
 * Executable evidence for GitHub issue #49.
 *
 * This module investigates whether regularized two-operand Boolean polygon
 * operations differ at the already-labelled arrangement boundary primarily in
 * their region-membership predicate.
 *
 * It is intentionally not imported by the public package and does not define
 * or authorize a public Boolean-overlay API.
 */


private enum ubyte researchOperandMask =
    polygonUnionOperandA |
    polygonUnionOperandB;


private enum ResearchBooleanOverlayOperation : ubyte
{
    unionSet,
    intersection,
    differenceAB,
    differenceBA,
    symmetricDifference,
}


/*
 * Evaluates one regularized two-dimensional result-region predicate from an
 * already complete exact A/B membership mask.
 */
private bool researchRegionInterior(
    ResearchBooleanOverlayOperation operation,
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
        case ResearchBooleanOverlayOperation.unionSet:
            return insideA || insideB;

        case ResearchBooleanOverlayOperation.intersection:
            return insideA && insideB;

        case ResearchBooleanOverlayOperation.differenceAB:
            return insideA && !insideB;

        case ResearchBooleanOverlayOperation.differenceBA:
            return insideB && !insideA;

        case ResearchBooleanOverlayOperation.symmetricDifference:
            return insideA != insideB;
    }
}


/*
 * Research-only generalized result-boundary selector.
 *
 * labels contain exact membership of the two-dimensional region immediately
 * left of each directed arrangement half-edge.
 *
 * For one result-region predicate R:
 *
 *     boundary iff R(left) != R(right)
 *
 * and the selected direction is exactly the one whose left side is result
 * interior.
 *
 * This deliberately mirrors the validation shape of the production union
 * selector. It does not modify or replace production code.
 */
private bool selectResearchBooleanBoundaryHalfEdges(T)(
    scope const(ExactArrangementEdge!T)[] edges,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(ExactHalfEdgeSideLabel)[] labels,
    ResearchBooleanOverlayOperation operation,
    scope bool[] selected
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
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

        const auto label =
            labels[halfEdgeIndex];

        const auto twinLabel =
            labels[
                halfEdge.twin
            ];

        if (
            label.knownMask != researchOperandMask ||
            twinLabel.knownMask != researchOperandMask
        )
        {
            return false;
        }

        const bool leftInterior =
            researchRegionInterior(
                operation,
                label.insideMask &
                    researchOperandMask
            );

        const bool rightInterior =
            researchRegionInterior(
                operation,
                twinLabel.insideMask &
                    researchOperandMask
            );

        if (leftInterior == rightInterior)
            continue;

        if (leftInterior)
            selected[halfEdgeIndex] = true;
    }

    return true;
}


/*
 * Truth-table evidence for all regularized region predicates.
 */
@safe unittest
{
    enum ubyte A = polygonUnionOperandA;
    enum ubyte B = polygonUnionOperandB;
    enum ubyte AB = A | B;

    alias O = ResearchBooleanOverlayOperation;

    assert(!researchRegionInterior(O.unionSet, 0));
    assert( researchRegionInterior(O.unionSet, A));
    assert( researchRegionInterior(O.unionSet, B));
    assert( researchRegionInterior(O.unionSet, AB));

    assert(!researchRegionInterior(O.intersection, 0));
    assert(!researchRegionInterior(O.intersection, A));
    assert(!researchRegionInterior(O.intersection, B));
    assert( researchRegionInterior(O.intersection, AB));

    assert(!researchRegionInterior(O.differenceAB, 0));
    assert( researchRegionInterior(O.differenceAB, A));
    assert(!researchRegionInterior(O.differenceAB, B));
    assert(!researchRegionInterior(O.differenceAB, AB));

    assert(!researchRegionInterior(O.differenceBA, 0));
    assert(!researchRegionInterior(O.differenceBA, A));
    assert( researchRegionInterior(O.differenceBA, B));
    assert(!researchRegionInterior(O.differenceBA, AB));

    assert(!researchRegionInterior(O.symmetricDifference, 0));
    assert( researchRegionInterior(O.symmetricDifference, A));
    assert( researchRegionInterior(O.symmetricDifference, B));
    assert(!researchRegionInterior(O.symmetricDifference, AB));
}


/*
 * Exhaustive selector evidence over all complete left/right A/B membership
 * states for one arrangement-edge twin pair.
 *
 * This verifies:
 *
 * - no result boundary when both sides have equal result membership;
 * - exactly one selected direction when memberships differ;
 * - the selected direction always has result interior on its left;
 * - research union selection is identical to the production union selector.
 */
@safe unittest
{
    alias E = ExactArrangementEdge!int;
    alias H = ExactArrangementHalfEdge;
    alias L = ExactHalfEdgeSideLabel;
    alias O = ResearchBooleanOverlayOperation;

    const E[1] edges = [
        E.init,
    ];

    const H[2] halfEdges = [
        H(0, 1, 1, 0, 0, true),
        H(1, 0, 0, 0, 1, false),
    ];

    enum ubyte A = polygonUnionOperandA;
    enum ubyte B = polygonUnionOperandB;
    enum ubyte AB = A | B;

    const ubyte[4] states = [
        0,
        A,
        B,
        AB,
    ];

    const O[5] operations = [
        O.unionSet,
        O.intersection,
        O.differenceAB,
        O.differenceBA,
        O.symmetricDifference,
    ];

    foreach (operation; operations)
    {
        foreach (leftState; states)
        {
            foreach (rightState; states)
            {
                const L[2] labels = [
                    L(AB, leftState),
                    L(AB, rightState),
                ];

                bool[2] selected = [
                    true,
                    true,
                ];

                assert(
                    selectResearchBooleanBoundaryHalfEdges(
                        edges[],
                        halfEdges[],
                        labels[],
                        operation,
                        selected[]
                    )
                );

                const bool leftInterior =
                    researchRegionInterior(
                        operation,
                        leftState
                    );

                const bool rightInterior =
                    researchRegionInterior(
                        operation,
                        rightState
                    );

                if (leftInterior == rightInterior)
                {
                    assert(!selected[0]);
                    assert(!selected[1]);
                }
                else
                {
                    assert(
                        selected[0] ==
                        leftInterior
                    );

                    assert(
                        selected[1] ==
                        rightInterior
                    );

                    assert(
                        selected[0] !=
                        selected[1]
                    );
                }

                if (
                    operation ==
                    O.unionSet
                )
                {
                    bool[2] productionSelected = [
                        true,
                        true,
                    ];

                    assert(
                        selectExactUnionBoundaryHalfEdges(
                            edges[],
                            halfEdges[],
                            labels[],
                            productionSelected[]
                        )
                    );

                    assert(
                        productionSelected ==
                        selected
                    );
                }
            }
        }
    }
}


/*
 * Incomplete side knowledge is rejected rather than treating an unknown
 * operand as outside.
 */
@safe unittest
{
    alias E = ExactArrangementEdge!int;
    alias H = ExactArrangementHalfEdge;
    alias L = ExactHalfEdgeSideLabel;

    const E[1] edges = [
        E.init,
    ];

    const H[2] halfEdges = [
        H(0, 1, 1, 0, 0, true),
        H(1, 0, 0, 0, 1, false),
    ];

    const L[2] incomplete = [
        L(
            polygonUnionOperandA,
            polygonUnionOperandA
        ),
        L(
            polygonUnionOperandA,
            0
        ),
    ];

    bool[2] selected = [
        true,
        true,
    ];

    assert(
        !selectResearchBooleanBoundaryHalfEdges(
            edges[],
            halfEdges[],
            incomplete[],
            ResearchBooleanOverlayOperation.intersection,
            selected[]
        )
    );
}


/*
 * Point-contact arrangement drives unchanged production boundary tracing.
 *
 * A is the north-east unit square and B the south-west unit square. They meet
 * only at the exact vertex (0, 0).
 *
 * The same exact arrangement and exact A/B side labels are evaluated under
 * every research Boolean predicate:
 *
 *     union                 -> two cycles
 *     intersection          -> empty
 *     A \ B                 -> A cycle only
 *     B \ A                 -> B cycle only
 *     symmetric difference  -> two cycles
 *
 * Intersection therefore also exercises regularization of a point-only
 * contact: the shared zero-dimensional point does not become polygon output.
 *
 * After selection, the production boundary tracer is used unchanged.
 */
@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;
    alias E = ExactArrangementEdge!int;
    alias O = ResearchBooleanOverlayOperation;

    enum ubyte A = polygonUnionOperandA;
    enum ubyte B = polygonUnionOperandB;
    enum ubyte AB = A | B;

    const E[8] edges = [
        E(
            0,
            1,
            A,
            S(P(0, 0), P(1, 0)),
            true,
            A
        ),
        E(
            1,
            2,
            A,
            S(P(1, 0), P(1, 1)),
            true,
            A
        ),
        E(
            2,
            3,
            A,
            S(P(1, 1), P(0, 1)),
            true,
            A
        ),
        E(
            0,
            3,
            A,
            S(P(0, 1), P(0, 0)),
            false,
            0
        ),

        E(
            0,
            4,
            B,
            S(P(0, 0), P(-1, 0)),
            true,
            B
        ),
        E(
            4,
            5,
            B,
            S(P(-1, 0), P(-1, -1)),
            true,
            B
        ),
        E(
            5,
            6,
            B,
            S(P(-1, -1), P(0, -1)),
            true,
            B
        ),
        E(
            0,
            6,
            B,
            S(P(0, -1), P(0, 0)),
            false,
            0
        ),
    ];

    P[4] aPoints = [
        P(0, 0),
        P(1, 0),
        P(1, 1),
        P(0, 1),
    ];

    P[4] bPoints = [
        P(0, 0),
        P(-1, 0),
        P(-1, -1),
        P(0, -1),
    ];

    R[1] aRings = [
        R(aPoints[]),
    ];

    R[1] bRings = [
        R(bPoints[]),
    ];

    const G polygonA =
        G(aRings[]);

    const G polygonB =
        G(bRings[]);

    ExactArrangementHalfEdge[16] halfEdges;
    size_t[16] outgoing;
    size_t[16] halfEdgePosition;
    size_t[8] vertexOffsets;
    size_t[7] vertexCursor;

    assert(
        buildExactHalfEdgeEmbedding(
            edges[],
            7,
            halfEdges[],
            outgoing[],
            halfEdgePosition[],
            vertexOffsets[],
            vertexCursor[]
        )
    );

    ExactHalfEdgeSideLabel[16] labels;

    assert(
        initializeExactHalfEdgeSideLabels(
            edges[],
            halfEdges[],
            labels[]
        )
    );

    size_t containmentSeedCount;

    assert(
        tryResolveExactHalfEdgeSideLabelsWithContainment(
            edges[],
            halfEdges[],
            polygonA,
            polygonB,
            labels[],
            containmentSeedCount
        )
    );

    foreach (label; labels)
    {
        assert(
            label.knownMask ==
            AB
        );
    }

    const bool[16] aBoundary = [
        true,  false,
        true,  false,
        true,  false,
        false, true,

        false, false,
        false, false,
        false, false,
        false, false,
    ];

    const bool[16] bBoundary = [
        false, false,
        false, false,
        false, false,
        false, false,

        true,  false,
        true,  false,
        true,  false,
        false, true,
    ];

    const O[5] operations = [
        O.unionSet,
        O.intersection,
        O.differenceAB,
        O.differenceBA,
        O.symmetricDifference,
    ];

    foreach (operation; operations)
    {
        bool expectA;
        bool expectB;
        size_t expectedCycleCount;

        final switch (operation)
        {
            case O.unionSet:
                expectA = true;
                expectB = true;
                expectedCycleCount = 2;
                break;

            case O.intersection:
                expectA = false;
                expectB = false;
                expectedCycleCount = 0;
                break;

            case O.differenceAB:
                expectA = true;
                expectB = false;
                expectedCycleCount = 1;
                break;

            case O.differenceBA:
                expectA = false;
                expectB = true;
                expectedCycleCount = 1;
                break;

            case O.symmetricDifference:
                expectA = true;
                expectB = true;
                expectedCycleCount = 2;
                break;
        }

        bool[16] selected;

        assert(
            selectResearchBooleanBoundaryHalfEdges(
                edges[],
                halfEdges[],
                labels[],
                operation,
                selected[]
            )
        );

        foreach (i; 0 .. selected.length)
        {
            const bool expected =
                (
                    expectA &&
                    aBoundary[i]
                ) ||
                (
                    expectB &&
                    bBoundary[i]
                );

            assert(
                selected[i] ==
                expected
            );
        }

        if (operation == O.unionSet)
        {
            bool[16] productionSelected;

            assert(
                selectExactUnionBoundaryHalfEdges(
                    edges[],
                    halfEdges[],
                    labels[],
                    productionSelected[]
                )
            );

            assert(
                productionSelected ==
                selected
            );
        }

        size_t[16] nextSelected;
        size_t[16] edgeCycle;
        size_t[7] vertexCycle;
        ExactUnionBoundaryCycle[16] cycles;
        size_t cycleCount;

        assert(
            tryBuildExactUnionBoundaryCycles(
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
        );

        assert(
            cycleCount ==
            expectedCycleCount
        );

        if (expectA)
        {
            assert(cycleCount >= 1);
            assert(cycles[0].startHalfEdge == 0);
            assert(cycles[0].edgeCount == 4);
        }

        if (
            expectB &&
            !expectA
        )
        {
            assert(cycleCount == 1);
            assert(cycles[0].startHalfEdge == 8);
            assert(cycles[0].edgeCount == 4);
        }

        if (
            expectA &&
            expectB
        )
        {
            assert(cycleCount == 2);

            assert(cycles[0].startHalfEdge == 0);
            assert(cycles[0].edgeCount == 4);

            assert(cycles[1].startHalfEdge == 8);
            assert(cycles[1].edgeCount == 4);

            /*
             * The shared exact vertex remains a point contact between two
             * independent result cycles.
             */
            assert(nextSelected[7] == 0);
            assert(nextSelected[15] == 8);
        }

        if (expectedCycleCount == 0)
        {
            foreach (isSelected; selected)
                assert(!isSelected);
        }
    }
}


/*
 * Containment arrangement exercises exterior/hole component grouping.
 *
 * A is one outer square. B is a smaller square strictly inside A. Their
 * boundaries are disconnected, so exact side-label completion also exercises
 * containment seeding.
 *
 * Expected regularized results:
 *
 *     union                 -> A
 *     intersection          -> B
 *     A \ B                 -> A with one B-shaped hole
 *     B \ A                 -> empty
 *     symmetric difference  -> A with one B-shaped hole
 *
 * After research-only result-boundary selection, both production stages below
 * are used unchanged:
 *
 *     tryBuildExactUnionBoundaryCycles
 *     tryBuildExactUnionComponents
 *
 * The purpose is evidence about reusable internal semantics, not authorization
 * to rename or generalize production modules.
 */
@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;
    alias E = ExactArrangementEdge!int;
    alias O = ResearchBooleanOverlayOperation;

    enum ubyte A = polygonUnionOperandA;
    enum ubyte B = polygonUnionOperandB;
    enum ubyte AB = A | B;

    /*
     * Vertex IDs follow exact lexicographic coordinate order inside each
     * disconnected square:
     *
     * outer A:
     *     0 = (0, 0)
     *     1 = (0, 10)
     *     2 = (10, 0)
     *     3 = (10, 10)
     *
     * inner B:
     *     4 = (3, 3)
     *     5 = (3, 7)
     *     6 = (7, 3)
     *     7 = (7, 7)
     */
    const E[8] edges = [
        E(
            0,
            2,
            A,
            S(P(0, 0), P(10, 0)),
            true,
            A
        ),
        E(
            2,
            3,
            A,
            S(P(10, 0), P(10, 10)),
            true,
            A
        ),
        E(
            1,
            3,
            A,
            S(P(10, 10), P(0, 10)),
            false,
            0
        ),
        E(
            0,
            1,
            A,
            S(P(0, 10), P(0, 0)),
            false,
            0
        ),

        E(
            4,
            6,
            B,
            S(P(3, 3), P(7, 3)),
            true,
            B
        ),
        E(
            6,
            7,
            B,
            S(P(7, 3), P(7, 7)),
            true,
            B
        ),
        E(
            5,
            7,
            B,
            S(P(7, 7), P(3, 7)),
            false,
            0
        ),
        E(
            4,
            5,
            B,
            S(P(3, 7), P(3, 3)),
            false,
            0
        ),
    ];

    P[4] aPoints = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(0, 10),
    ];

    P[4] bPoints = [
        P(3, 3),
        P(7, 3),
        P(7, 7),
        P(3, 7),
    ];

    R[1] aRings = [
        R(aPoints[]),
    ];

    R[1] bRings = [
        R(bPoints[]),
    ];

    const G polygonA =
        G(aRings[]);

    const G polygonB =
        G(bRings[]);

    ExactOverlayPoint[8] exactVertices = [
        exactOverlayPoint(P(0, 0)),
        exactOverlayPoint(P(0, 10)),
        exactOverlayPoint(P(10, 0)),
        exactOverlayPoint(P(10, 10)),
        exactOverlayPoint(P(3, 3)),
        exactOverlayPoint(P(3, 7)),
        exactOverlayPoint(P(7, 3)),
        exactOverlayPoint(P(7, 7)),
    ];

    ExactArrangementHalfEdge[16] halfEdges;
    size_t[16] outgoing;
    size_t[16] halfEdgePosition;
    size_t[9] vertexOffsets;
    size_t[8] vertexCursor;

    assert(
        buildExactHalfEdgeEmbedding(
            edges[],
            8,
            halfEdges[],
            outgoing[],
            halfEdgePosition[],
            vertexOffsets[],
            vertexCursor[]
        )
    );

    ExactHalfEdgeSideLabel[16] labels;

    assert(
        initializeExactHalfEdgeSideLabels(
            edges[],
            halfEdges[],
            labels[]
        )
    );

    size_t containmentSeedCount;

    assert(
        tryResolveExactHalfEdgeSideLabelsWithContainment(
            edges[],
            halfEdges[],
            polygonA,
            polygonB,
            labels[],
            containmentSeedCount
        )
    );

    /*
     * Each disconnected boundary component lacks one operand before
     * containment seeding:
     *
     * - A boundary needs B=outside;
     * - B boundary needs A=inside.
     */
    assert(containmentSeedCount == 2);

    foreach (label; labels)
    {
        assert(
            label.knownMask ==
            AB
        );
    }

    const O[5] operations = [
        O.unionSet,
        O.intersection,
        O.differenceAB,
        O.differenceBA,
        O.symmetricDifference,
    ];

    foreach (operation; operations)
    {
        size_t expectedCycleCount;
        size_t expectedComponentCount;
        size_t expectedHoleCount;

        final switch (operation)
        {
            case O.unionSet:
                expectedCycleCount = 1;
                expectedComponentCount = 1;
                expectedHoleCount = 0;
                break;

            case O.intersection:
                expectedCycleCount = 1;
                expectedComponentCount = 1;
                expectedHoleCount = 0;
                break;

            case O.differenceAB:
                expectedCycleCount = 2;
                expectedComponentCount = 1;
                expectedHoleCount = 1;
                break;

            case O.differenceBA:
                expectedCycleCount = 0;
                expectedComponentCount = 0;
                expectedHoleCount = 0;
                break;

            case O.symmetricDifference:
                expectedCycleCount = 2;
                expectedComponentCount = 1;
                expectedHoleCount = 1;
                break;
        }

        bool[16] selected;

        assert(
            selectResearchBooleanBoundaryHalfEdges(
                edges[],
                halfEdges[],
                labels[],
                operation,
                selected[]
            )
        );

        if (operation == O.unionSet)
        {
            bool[16] productionSelected;

            assert(
                selectExactUnionBoundaryHalfEdges(
                    edges[],
                    halfEdges[],
                    labels[],
                    productionSelected[]
                )
            );

            assert(
                productionSelected ==
                selected
            );
        }

        size_t[16] nextSelected;
        size_t[16] edgeCycle;
        size_t[8] vertexCycle;
        ExactUnionBoundaryCycle[16] cycles;
        size_t cycleCount;

        assert(
            tryBuildExactUnionBoundaryCycles(
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
        );

        assert(
            cycleCount ==
            expectedCycleCount
        );

        ExactUnionCycleRole[16] roles;
        size_t[16] componentOfCycle;
        ExactUnionComponent[16] components;
        size_t componentCount;

        assert(
            tryBuildExactUnionComponents(
                cycles[
                    0 ..
                    cycleCount
                ],
                halfEdges[],
                nextSelected[],
                exactVertices[],
                roles[
                    0 ..
                    cycleCount
                ],
                componentOfCycle[
                    0 ..
                    cycleCount
                ],
                components[
                    0 ..
                    cycleCount
                ],
                componentCount
            )
        );

        assert(
            componentCount ==
            expectedComponentCount
        );

        size_t exteriorCount;
        size_t holeCount;

        foreach (
            role;
            roles[
                0 ..
                cycleCount
            ]
        )
        {
            final switch (role)
            {
                case ExactUnionCycleRole.exterior:
                    ++exteriorCount;
                    break;

                case ExactUnionCycleRole.hole:
                    ++holeCount;
                    break;
            }
        }

        assert(
            exteriorCount ==
            expectedComponentCount
        );

        assert(
            holeCount ==
            expectedHoleCount
        );

        if (componentCount == 0)
        {
            assert(cycleCount == 0);
            continue;
        }

        assert(componentCount == 1);

        assert(
            components[0].holeCount ==
            expectedHoleCount
        );

        assert(
            components[0].exteriorCycle <
            cycleCount
        );

        assert(
            roles[
                components[0].exteriorCycle
            ] ==
            ExactUnionCycleRole.exterior
        );

        foreach (cycleIndex; 0 .. cycleCount)
        {
            assert(
                componentOfCycle[cycleIndex] ==
                0
            );
        }

        /*
         * Difference/XOR must reverse the inner B result boundary relative to
         * B's own CCW interior orientation. That clockwise selected cycle is
         * exactly what the unchanged component builder recognizes as a hole.
         */
        if (expectedHoleCount == 1)
        {
            size_t holeCycle =
                size_t.max;

            foreach (cycleIndex; 0 .. cycleCount)
            {
                if (
                    roles[cycleIndex] ==
                    ExactUnionCycleRole.hole
                )
                {
                    assert(holeCycle == size_t.max);

                    holeCycle =
                        cycleIndex;
                }
            }

            assert(holeCycle != size_t.max);

            assert(
                componentOfCycle[holeCycle] ==
                0
            );
        }


        /*
         * Canonicalization/materialization/ownership reuse gate.
         *
         * From this point onward the exact same production helpers used by
         * polygon union are executed unchanged.
         */
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

        assert(
            tryBuildCanonicalExactUnionLayout(
                cycles[
                    0 ..
                    cycleCount
                ],
                roles[
                    0 ..
                    cycleCount
                ],
                componentOfCycle[
                    0 ..
                    cycleCount
                ],
                components[
                    0 ..
                    componentCount
                ],
                halfEdges[],
                nextSelected[],
                exactVertices[],
                componentOrder[],
                orderedCycles[],
                componentRingOffsets[],
                cycleScratch[]
            )
        );

        assert(
            componentRingOffsets.length ==
            componentCount + 1
        );

        assert(
            componentRingOffsets[0] ==
            0
        );

        assert(
            componentRingOffsets[$ - 1] ==
            cycleCount
        );

        if (componentCount == 0)
        {
            assert(
                componentRingOffsets.length ==
                1
            );
        }
        else
        {
            assert(componentCount == 1);

            assert(
                componentRingOffsets[1] ==
                cycleCount
            );

            /*
             * Canonical polygon storage is exterior first, followed by holes.
             */
            assert(
                orderedCycles[0] ==
                components[0].exteriorCycle
            );

            if (expectedHoleCount == 1)
            {
                assert(cycleCount == 2);

                assert(
                    roles[
                        orderedCycles[1]
                    ] ==
                    ExactUnionCycleRole.hole
                );
            }
        }


        auto exactToMaterialized =
            new size_t[
                exactVertices.length
            ];

        auto compactPoints =
            new Point2!double[
                exactVertices.length
            ];

        auto materializedEdges =
            new MaterializedUnionBoundaryEdge[
                halfEdges.length
            ];

        size_t compactPointCount;
        size_t boundaryEdgeCount;

        assert(
            tryMaterializeExactUnionBoundaryGraph(
                exactVertices[],
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
        );

        const size_t expectedBoundaryEdgeCount =
            expectedCycleCount * 4;

        assert(
            boundaryEdgeCount ==
            expectedBoundaryEdgeCount
        );

        /*
         * This containment fixture has no shared result vertices between its
         * disconnected outer/inner boundary cycles.
         */
        assert(
            compactPointCount ==
            expectedBoundaryEdgeCount
        );


        auto ringPoints =
            new Point2!double[
                boundaryEdgeCount
            ];

        auto ringPointOffsets =
            new size_t[
                cycleCount + 1
            ];

        size_t ringPointCount;

        assert(
            tryWriteMaterializedUnionRings(
                exactVertices[],
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
            )
        );

        assert(
            ringPointCount ==
            boundaryEdgeCount
        );

        assert(
            ringPointOffsets.length ==
            cycleCount + 1
        );

        assert(
            ringPointOffsets[0] ==
            0
        );

        assert(
            ringPointOffsets[$ - 1] ==
            ringPointCount
        );


        assert(
            materializedUnionComponentsRemainValidAndDisjoint(
                ringPoints[
                    0 ..
                    ringPointCount
                ],
                ringPointOffsets[],
                componentRingOffsets[]
            )
        );


        /*
         * Ownership is also exercised exactly like production:
         *
         * - ringPoints becomes immutable backing;
         * - componentRingOffsets becomes immutable backing;
         * - ringPointOffsets remains build metadata.
         */
        auto owned =
            takePolygonUnionOwnedResultInternal(
                ringPoints,
                ringPointOffsets[],
                componentRingOffsets
            );

        assert(ringPoints is null);
        assert(componentRingOffsets is null);

        assert(
            owned.componentCount ==
            expectedComponentCount
        );

        assert(
            owned.ringCount ==
            expectedCycleCount
        );

        assert(
            owned.pointCount ==
            expectedBoundaryEdgeCount
        );

        if (expectedComponentCount == 0)
        {
            assert(owned.componentCount == 0);
            assert(owned.ringCount == 0);
            assert(owned.pointCount == 0);
        }
        else
        {
            const auto materialized =
                owned.component(0);

            assert(
                materialized.holeCount ==
                expectedHoleCount
            );

            assert(
                materialized.length ==
                expectedHoleCount + 1
            );
        }
    }
}
