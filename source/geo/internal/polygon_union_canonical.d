module geo.internal.polygon_union_canonical;

import geo.internal.polygon_union_boundary :
    ExactUnionBoundaryCycle;

import geo.internal.polygon_union_components :
    ExactUnionComponent,
    ExactUnionCycleRole;

import geo.internal.polygon_union_embedding :
    ExactArrangementHalfEdge;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    compareExactOverlayPoints;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact canonical ordering for reconstructed polygon-union cycles/components.
 *
 * Canonicalization is completed before binary64 materialization:
 *
 * - each cycle starts at its exact lexicographically smallest vertex;
 * - holes are ordered by their exact canonical cycle sequence;
 * - components are ordered by the exact canonical cycle sequence of their
 *   exterior.
 */


size_t canonicalExactUnionCycleStart(
    ref const ExactUnionBoundaryCycle cycle,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices
)
    pure nothrow @safe @nogc
{
    if (
        cycle.edgeCount < 3 ||
        cycle.startHalfEdge >= halfEdges.length ||
        nextSelected.length != halfEdges.length
    )
    {
        return size_t.max;
    }

    size_t current =
        cycle.startHalfEdge;

    size_t best =
        size_t.max;

    foreach (_; 0 .. cycle.edgeCount)
    {
        if (current >= halfEdges.length)
            return size_t.max;

        const auto edge =
            halfEdges[current];

        if (
            edge.originVertex >= vertices.length ||
            edge.destinationVertex >= vertices.length
        )
        {
            return size_t.max;
        }

        if (
            best == size_t.max ||
            compareExactOverlayPoints(
                vertices[
                    edge.originVertex
                ],
                vertices[
                    halfEdges[
                        best
                    ].originVertex
                ]
            ) < 0
        )
        {
            best =
                current;
        }

        const size_t next =
            nextSelected[current];

        if (
            next >= halfEdges.length ||
            halfEdges[next].originVertex !=
                edge.destinationVertex
        )
        {
            return size_t.max;
        }

        current =
            next;
    }

    if (
        current != cycle.startHalfEdge
    )
    {
        return size_t.max;
    }

    return best;
}


/*
 * Exact lexicographic comparison of two already interior-left oriented cycles,
 * independent of their stored start edge.
 */
int compareCanonicalExactUnionCycles(
    ref const ExactUnionBoundaryCycle lhs,
    ref const ExactUnionBoundaryCycle rhs,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices
)
    pure nothrow @safe @nogc
{
    const size_t lhsStart =
        canonicalExactUnionCycleStart(
            lhs,
            halfEdges,
            nextSelected,
            vertices
        );

    const size_t rhsStart =
        canonicalExactUnionCycleStart(
            rhs,
            halfEdges,
            nextSelected,
            vertices
        );

    assert(lhsStart != size_t.max);
    assert(rhsStart != size_t.max);

    size_t lhsCurrent =
        lhsStart;

    size_t rhsCurrent =
        rhsStart;

    const size_t commonLength =
        lhs.edgeCount <
        rhs.edgeCount
            ? lhs.edgeCount
            : rhs.edgeCount;

    foreach (_; 0 .. commonLength)
    {
        const auto lhsEdge =
            halfEdges[lhsCurrent];

        const auto rhsEdge =
            halfEdges[rhsCurrent];

        const int comparison =
            compareExactOverlayPoints(
                vertices[
                    lhsEdge.originVertex
                ],
                vertices[
                    rhsEdge.originVertex
                ]
            );

        if (comparison != 0)
            return comparison;

        lhsCurrent =
            nextSelected[lhsCurrent];

        rhsCurrent =
            nextSelected[rhsCurrent];
    }

    if (lhs.edgeCount < rhs.edgeCount)
        return -1;

    if (lhs.edgeCount > rhs.edgeCount)
        return 1;

    return 0;
}


/*
 * Exact comparator for cycle indices.
 */
private int compareCycleIndices(
    size_t lhs,
    size_t rhs,
    scope const(ExactUnionBoundaryCycle)[] cycles,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices
)
    pure nothrow @safe @nogc
{
    return
        compareCanonicalExactUnionCycles(
            cycles[lhs],
            cycles[rhs],
            halfEdges,
            nextSelected,
            vertices
        );
}


private void siftDownCycleIndices(
    scope size_t[] indices,
    size_t root,
    size_t end,
    scope const(ExactUnionBoundaryCycle)[] cycles,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices
)
    pure nothrow @safe @nogc
{
    while (true)
    {
        const size_t left =
            root * 2 + 1;

        if (left >= end)
            return;

        size_t largest =
            root;

        if (
            compareCycleIndices(
                indices[largest],
                indices[left],
                cycles,
                halfEdges,
                nextSelected,
                vertices
            ) < 0
        )
        {
            largest =
                left;
        }

        const size_t right =
            left + 1;

        if (
            right < end &&
            compareCycleIndices(
                indices[largest],
                indices[right],
                cycles,
                halfEdges,
                nextSelected,
                vertices
            ) < 0
        )
        {
            largest =
                right;
        }

        if (largest == root)
            return;

        const size_t temporary =
            indices[root];

        indices[root] =
            indices[largest];

        indices[largest] =
            temporary;

        root =
            largest;
    }
}


private void sortCycleIndices(
    scope size_t[] indices,
    scope const(ExactUnionBoundaryCycle)[] cycles,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices
)
    pure nothrow @safe @nogc
{
    if (indices.length < 2)
        return;

    size_t start =
        indices.length / 2;

    while (start > 0)
    {
        --start;

        siftDownCycleIndices(
            indices,
            start,
            indices.length,
            cycles,
            halfEdges,
            nextSelected,
            vertices
        );
    }

    size_t end =
        indices.length;

    while (end > 1)
    {
        --end;

        const size_t temporary =
            indices[0];

        indices[0] =
            indices[end];

        indices[end] =
            temporary;

        siftDownCycleIndices(
            indices,
            0,
            end,
            cycles,
            halfEdges,
            nextSelected,
            vertices
        );
    }
}


/*
 * Builds deterministic component/ring ordering without mutating exact
 * topology.
 *
 * componentOrder[0 .. componentCount] contains indices into components in
 * canonical exterior-cycle order.
 *
 * orderedCycles contains, for each ordered component:
 *
 *     exterior first
 *     then its holes in canonical exact cycle order
 *
 * componentRingOffsets indexes orderedCycles.
 *
 * cycleScratch is caller workspace of at least cycles.length entries.
 */
bool tryBuildCanonicalExactUnionLayout(
    scope const(ExactUnionBoundaryCycle)[] cycles,
    scope const(ExactUnionCycleRole)[] roles,
    scope const(size_t)[] componentOfCycle,
    scope const(ExactUnionComponent)[] components,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices,
    scope size_t[] componentOrder,
    scope size_t[] orderedCycles,
    scope size_t[] componentRingOffsets,
    scope size_t[] cycleScratch
)
    pure nothrow @safe @nogc
{
    if (
        roles.length != cycles.length ||
        componentOfCycle.length != cycles.length ||
        componentOrder.length < components.length ||
        orderedCycles.length < cycles.length ||
        componentRingOffsets.length < components.length + 1 ||
        cycleScratch.length < cycles.length
    )
    {
        return false;
    }

    foreach (componentIndex; 0 .. components.length)
    {
        const size_t exteriorCycle =
            components[
                componentIndex
            ].exteriorCycle;

        if (
            exteriorCycle >= cycles.length ||
            roles[exteriorCycle] !=
                ExactUnionCycleRole.exterior ||
            componentOfCycle[exteriorCycle] !=
                componentIndex
        )
        {
            return false;
        }

        componentOrder[componentIndex] =
            componentIndex;
    }


    /*
     * Sort components by their exterior cycles using the same cycle-index
     * heapsort. componentOrder temporarily stores component indices, so stage
     * the corresponding exterior cycle indices in cycleScratch, sort them,
     * then map back through componentOfCycle.
     */
    foreach (i; 0 .. components.length)
    {
        cycleScratch[i] =
            components[
                componentOrder[i]
            ].exteriorCycle;
    }

    sortCycleIndices(
        cycleScratch[
            0 ..
            components.length
        ],
        cycles,
        halfEdges,
        nextSelected,
        vertices
    );

    foreach (i; 0 .. components.length)
    {
        const size_t exteriorCycle =
            cycleScratch[i];

        const size_t componentIndex =
            componentOfCycle[
                exteriorCycle
            ];

        if (
            componentIndex >= components.length ||
            components[
                componentIndex
            ].exteriorCycle !=
                exteriorCycle
        )
        {
            return false;
        }

        componentOrder[i] =
            componentIndex;
    }


    size_t write = 0;

    componentRingOffsets[0] = 0;

    foreach (orderedComponent; 0 .. components.length)
    {
        const size_t componentIndex =
            componentOrder[
                orderedComponent
            ];

        const size_t exteriorCycle =
            components[
                componentIndex
            ].exteriorCycle;

        orderedCycles[write++] =
            exteriorCycle;

        size_t holeCount = 0;

        foreach (cycleIndex; 0 .. cycles.length)
        {
            if (
                roles[cycleIndex] ==
                    ExactUnionCycleRole.hole &&
                componentOfCycle[cycleIndex] ==
                    componentIndex
            )
            {
                cycleScratch[holeCount++] =
                    cycleIndex;
            }
        }

        if (
            holeCount !=
            components[
                componentIndex
            ].holeCount
        )
        {
            return false;
        }

        sortCycleIndices(
            cycleScratch[
                0 ..
                holeCount
            ],
            cycles,
            halfEdges,
            nextSelected,
            vertices
        );

        foreach (i; 0 .. holeCount)
            orderedCycles[write++] =
                cycleScratch[i];

        componentRingOffsets[
            orderedComponent + 1
        ] =
            write;
    }

    if (write != cycles.length)
        return false;

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
     * Canonical cycle start is independent of the stored starting edge.
     */
    const ExactOverlayPoint[4] vertices = [
        exactOverlayPoint(P(4, 3)),
        exactOverlayPoint(P(0, 3)),
        exactOverlayPoint(P(0, 0)),
        exactOverlayPoint(P(4, 0)),
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

    const ExactUnionBoundaryCycle cycle =
        ExactUnionBoundaryCycle(
            0,
            4
        );

    assert(
        canonicalExactUnionCycleStart(
            cycle,
            halfEdges[],
            nextSelected[],
            vertices[]
        ) == 2
    );
}


@safe unittest
{
    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    import geo.point :
        Point2;

    alias P = Point2!int;


    /*
     * Components and holes are ordered by exact canonical geometry rather than
     * incoming cycle/component index.
     *
     * cycle 0: later exterior at x=20
     * cycle 1: hole of earlier component, canonical start x=4
     * cycle 2: earlier exterior at x=0
     * cycle 3: another hole of earlier component, canonical start x=2
     */
    const ExactOverlayPoint[16] vertices = [
        exactOverlayPoint(P(20, 0)),
        exactOverlayPoint(P(24, 0)),
        exactOverlayPoint(P(24, 4)),
        exactOverlayPoint(P(20, 4)),

        exactOverlayPoint(P(4, 4)),
        exactOverlayPoint(P(4, 6)),
        exactOverlayPoint(P(6, 6)),
        exactOverlayPoint(P(6, 4)),

        exactOverlayPoint(P(0, 0)),
        exactOverlayPoint(P(10, 0)),
        exactOverlayPoint(P(10, 10)),
        exactOverlayPoint(P(0, 10)),

        exactOverlayPoint(P(2, 2)),
        exactOverlayPoint(P(2, 3)),
        exactOverlayPoint(P(3, 3)),
        exactOverlayPoint(P(3, 2)),
    ];

    ExactArrangementHalfEdge[16] halfEdges;

    foreach (cycle; 0 .. 4)
    {
        foreach (i; 0 .. 4)
        {
            const size_t edge =
                cycle * 4 + i;

            halfEdges[edge].originVertex =
                edge;

            halfEdges[edge].destinationVertex =
                cycle * 4 +
                ((i + 1) % 4);
        }
    }

    const size_t[16] nextSelected = [
        1, 2, 3, 0,
        5, 6, 7, 4,
        9, 10, 11, 8,
        13, 14, 15, 12,
    ];

    const ExactUnionBoundaryCycle[4] cycles = [
        ExactUnionBoundaryCycle(0, 4),
        ExactUnionBoundaryCycle(4, 4),
        ExactUnionBoundaryCycle(8, 4),
        ExactUnionBoundaryCycle(12, 4),
    ];

    const ExactUnionCycleRole[4] roles = [
        ExactUnionCycleRole.exterior,
        ExactUnionCycleRole.hole,
        ExactUnionCycleRole.exterior,
        ExactUnionCycleRole.hole,
    ];

    /*
     * Incoming component numbering deliberately puts x=20 before x=0.
     */
    const size_t[4] componentOfCycle = [
        0,
        1,
        1,
        1,
    ];

    const ExactUnionComponent[2] components = [
        ExactUnionComponent(0, 0),
        ExactUnionComponent(2, 2),
    ];

    size_t[2] componentOrder;
    size_t[4] orderedCycles;
    size_t[3] offsets;
    size_t[4] scratch;

    assert(
        tryBuildCanonicalExactUnionLayout(
            cycles[],
            roles[],
            componentOfCycle[],
            components[],
            halfEdges[],
            nextSelected[],
            vertices[],
            componentOrder[],
            orderedCycles[],
            offsets[],
            scratch[]
        )
    );

    assert(componentOrder == [size_t(1), size_t(0)]);

    assert(
        orderedCycles ==
        [
            size_t(2),
            size_t(3),
            size_t(1),
            size_t(0),
        ]
    );

    assert(
        offsets ==
        [
            size_t(0),
            size_t(3),
            size_t(4),
        ]
    );
}
