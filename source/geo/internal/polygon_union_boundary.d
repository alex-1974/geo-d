module geo.internal.polygon_union_boundary;

import geo.internal.polygon_union_embedding :
    ExactArrangementHalfEdge;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Reconstruction of selected regularized-union boundary half-edges into
 * closed exact-topology cycles.
 *
 * All selected half-edges are already oriented with union interior on their
 * left. At a destination vertex, continuation is therefore the first selected
 * outgoing half-edge encountered clockwise from the outgoing twin of the edge
 * by which the trace arrived.
 *
 * This preserves the same interior sector through ordinary corners,
 * T-junctions, crossings, shared-edge transitions, and point contacts.
 */


/*
 * One exact union-boundary cycle.
 *
 * startHalfEdge is deterministic: cycle discovery scans selected half-edge
 * indices in ascending order, so it is the smallest selected index belonging
 * to this cycle.
 */
struct ExactUnionBoundaryCycle
{
    size_t startHalfEdge;
    size_t edgeCount;
}


/*
 * Builds one exact continuation for every selected union-boundary half-edge.
 *
 * outgoing contains each vertex's outgoing half-edges in exact CCW angular
 * order. vertexOffsets[v .. v + 1] identifies vertex v's outgoing range.
 * halfEdgePosition maps each half-edge index back to its position in outgoing.
 *
 * For selected h:
 *
 *     destination = h.destinationVertex
 *     twin        = h.twin
 *
 * twin is the outgoing direction from destination back toward h.origin.
 * Walk clockwise from twin and choose the first selected outgoing edge.
 *
 * Unselected entries of nextSelected are left as size_t.max.
 *
 * Returns false for an inconsistent embedding/selection or when one selected
 * boundary half-edge has no continuation.
 */
bool buildExactUnionBoundaryContinuations(
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] outgoing,
    scope const(size_t)[] halfEdgePosition,
    scope const(size_t)[] vertexOffsets,
    scope const(bool)[] selected,
    scope size_t[] nextSelected
)
    pure nothrow @safe @nogc
{
    if (
        selected.length != halfEdges.length ||
        nextSelected.length != halfEdges.length ||
        outgoing.length != halfEdges.length ||
        halfEdgePosition.length != halfEdges.length ||
        vertexOffsets.length == 0
    )
    {
        return false;
    }

    const size_t vertexCount =
        vertexOffsets.length - 1;

    foreach (ref value; nextSelected)
        value = size_t.max;

    foreach (halfEdgeIndex, ref const halfEdge; halfEdges)
    {
        if (!selected[halfEdgeIndex])
            continue;

        if (
            halfEdge.originVertex >= vertexCount ||
            halfEdge.destinationVertex >= vertexCount ||
            halfEdge.originVertex == halfEdge.destinationVertex ||
            halfEdge.twin >= halfEdges.length ||
            halfEdges[halfEdge.twin].twin != halfEdgeIndex ||
            selected[halfEdge.twin]
        )
        {
            return false;
        }

        const size_t destination =
            halfEdge.destinationVertex;

        const size_t begin =
            vertexOffsets[destination];

        const size_t end =
            vertexOffsets[destination + 1];

        if (
            begin >= end ||
            end > outgoing.length
        )
        {
            return false;
        }

        const size_t twinPosition =
            halfEdgePosition[
                halfEdge.twin
            ];

        if (
            twinPosition < begin ||
            twinPosition >= end ||
            outgoing[twinPosition] !=
                halfEdge.twin
        )
        {
            return false;
        }

        size_t position =
            twinPosition;

        size_t continuation =
            size_t.max;

        /*
         * Exclude the twin itself. Search every other outgoing ray exactly
         * once in clockwise order.
         */
        foreach (_; 0 .. end - begin - 1)
        {
            position =
                position == begin
                    ? end - 1
                    : position - 1;

            const size_t candidate =
                outgoing[position];

            if (
                candidate >= halfEdges.length ||
                halfEdges[candidate].originVertex !=
                    destination
            )
            {
                return false;
            }

            if (selected[candidate])
            {
                continuation =
                    candidate;
                break;
            }
        }

        if (continuation == size_t.max)
            return false;

        nextSelected[halfEdgeIndex] =
            continuation;
    }

    return true;
}


/*
 * Decomposes selected, interior-left union half-edges into closed boundary
 * cycles using a precomputed exact continuation relation.
 *
 * A valid result cycle:
 *
 * - closes on its own starting half-edge;
 * - contains at least three edges;
 * - preserves destination -> next-origin incidence;
 * - never revisits one exact vertex before closure.
 *
 * Different cycles MAY share one exact vertex. That represents regularized
 * point contact between distinct two-dimensional components/rings and must not
 * be spliced into one self-touching ring.
 *
 * edgeCycle.length must equal halfEdges.length.
 * vertexCycle needs one slot per arrangement vertex.
 * cycles needs capacity for at most the number of selected half-edges.
 *
 * Unselected half-edges retain edgeCycle == size_t.max.
 */
bool tryTraceExactUnionBoundaryCycles(
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(bool)[] selected,
    scope const(size_t)[] nextSelected,
    scope size_t[] edgeCycle,
    scope size_t[] vertexCycle,
    scope ExactUnionBoundaryCycle[] cycles,
    out size_t cycleCount
)
    pure nothrow @safe @nogc
{
    cycleCount = 0;

    if (
        selected.length != halfEdges.length ||
        nextSelected.length != halfEdges.length ||
        edgeCycle.length != halfEdges.length ||
        cycles.length < halfEdges.length
    )
    {
        return false;
    }

    foreach (ref value; edgeCycle)
        value = size_t.max;

    foreach (ref value; vertexCycle)
        value = size_t.max;

    foreach (start; 0 .. halfEdges.length)
    {
        if (
            !selected[start] ||
            edgeCycle[start] != size_t.max
        )
        {
            continue;
        }

        const size_t currentCycle =
            cycleCount;

        size_t current =
            start;

        size_t edgeCount = 0;

        while (true)
        {
            if (
                current >= halfEdges.length ||
                !selected[current]
            )
            {
                cycleCount = 0;
                return false;
            }

            if (
                edgeCycle[current] !=
                size_t.max
            )
            {
                if (
                    current != start ||
                    edgeCycle[current] != currentCycle ||
                    edgeCount < 3
                )
                {
                    cycleCount = 0;
                    return false;
                }

                break;
            }

            const auto halfEdge =
                halfEdges[current];

            if (
                halfEdge.originVertex >= vertexCycle.length ||
                halfEdge.destinationVertex >= vertexCycle.length ||
                halfEdge.originVertex == halfEdge.destinationVertex ||
                nextSelected[current] >= halfEdges.length
            )
            {
                cycleCount = 0;
                return false;
            }

            const size_t next =
                nextSelected[current];

            if (
                !selected[next] ||
                halfEdges[next].originVertex !=
                    halfEdge.destinationVertex
            )
            {
                cycleCount = 0;
                return false;
            }

            /*
             * Re-entering one exact vertex before returning to the starting
             * edge would encode a self-touching ring.
             *
             * A vertex marked by an earlier different cycle is allowed and
             * simply becomes associated with the current trace while that
             * trace is active.
             */
            if (
                vertexCycle[
                    halfEdge.originVertex
                ] == currentCycle
            )
            {
                cycleCount = 0;
                return false;
            }

            vertexCycle[
                halfEdge.originVertex
            ] =
                currentCycle;

            edgeCycle[current] =
                currentCycle;

            current =
                next;

            ++edgeCount;

            if (edgeCount > halfEdges.length)
            {
                cycleCount = 0;
                return false;
            }
        }

        cycles[currentCycle] =
            ExactUnionBoundaryCycle(
                start,
                edgeCount
            );

        ++cycleCount;
    }

    return true;
}


/*
 * Convenience wrapper for the complete exact union-boundary cycle stage.
 */
bool tryBuildExactUnionBoundaryCycles(
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] outgoing,
    scope const(size_t)[] halfEdgePosition,
    scope const(size_t)[] vertexOffsets,
    scope const(bool)[] selected,
    scope size_t[] nextSelected,
    scope size_t[] edgeCycle,
    scope size_t[] vertexCycle,
    scope ExactUnionBoundaryCycle[] cycles,
    out size_t cycleCount
)
    pure nothrow @safe @nogc
{
    cycleCount = 0;

    if (
        !buildExactUnionBoundaryContinuations(
            halfEdges,
            outgoing,
            halfEdgePosition,
            vertexOffsets,
            selected,
            nextSelected
        )
    )
    {
        return false;
    }

    return
        tryTraceExactUnionBoundaryCycles(
            halfEdges,
            selected,
            nextSelected,
            edgeCycle,
            vertexCycle,
            cycles,
            cycleCount
        );
}


@safe unittest
{
    import geo.internal.polygon_union_arrangement :
        ExactArrangementEdge;

    import geo.internal.polygon_union_embedding :
        buildExactHalfEdgeEmbedding;

    import geo.internal.polygon_union_noding :
        polygonUnionOperandA;

    import geo.point :
        Point2;

    import geo.segment :
        Segment2;

    alias P = Point2!int;
    alias S = Segment2!int;
    alias E = ExactArrangementEdge!int;


    /*
     * One square reconstructs exactly one four-edge union-boundary cycle.
     */
    const E[4] edges = [
        E(0, 2, polygonUnionOperandA, S(P(0, 0), P(1, 0)), true, polygonUnionOperandA),
        E(2, 3, polygonUnionOperandA, S(P(1, 0), P(1, 1)), true, polygonUnionOperandA),
        E(1, 3, polygonUnionOperandA, S(P(1, 1), P(0, 1)), false, 0),
        E(0, 1, polygonUnionOperandA, S(P(0, 1), P(0, 0)), false, 0),
    ];

    ExactArrangementHalfEdge[8] halfEdges;
    size_t[8] outgoing;
    size_t[8] position;
    size_t[5] offsets;
    size_t[4] cursor;

    assert(
        buildExactHalfEdgeEmbedding(
            edges[],
            4,
            halfEdges[],
            outgoing[],
            position[],
            offsets[],
            cursor[]
        )
    );

    bool[8] selected;

    selected[0] = true;
    selected[2] = true;
    selected[5] = true;
    selected[7] = true;

    size_t[8] nextSelected;
    size_t[8] edgeCycle;
    size_t[4] vertexCycle;
    ExactUnionBoundaryCycle[8] cycles;
    size_t cycleCount;

    assert(
        tryBuildExactUnionBoundaryCycles(
            halfEdges[],
            outgoing[],
            position[],
            offsets[],
            selected[],
            nextSelected[],
            edgeCycle[],
            vertexCycle[],
            cycles[],
            cycleCount
        )
    );

    assert(cycleCount == 1);
    assert(cycles[0].startHalfEdge == 0);
    assert(cycles[0].edgeCount == 4);

    assert(nextSelected[0] == 2);
    assert(nextSelected[2] == 5);
    assert(nextSelected[5] == 7);
    assert(nextSelected[7] == 0);

    assert(edgeCycle[0] == 0);
    assert(edgeCycle[2] == 0);
    assert(edgeCycle[5] == 0);
    assert(edgeCycle[7] == 0);
}


@safe unittest
{
    import geo.internal.polygon_union_arrangement :
        ExactArrangementEdge;

    import geo.internal.polygon_union_embedding :
        buildExactHalfEdgeEmbedding;

    import geo.internal.polygon_union_noding :
        polygonUnionOperandA,
        polygonUnionOperandB;

    import geo.point :
        Point2;

    import geo.segment :
        Segment2;

    alias P = Point2!int;
    alias S = Segment2!int;
    alias E = ExactArrangementEdge!int;


    /*
     * Two square union components meet only at exact vertex 0.
     *
     * The exact angular continuation must preserve two distinct cycles rather
     * than splice them into one self-touching ring.
     *
     * NE square selected traversal:
     *
     *     O -> E -> NE -> N -> O
     *
     * SW square selected traversal:
     *
     *     O -> W -> SW -> S -> O
     */
    const E[8] edges = [
        E(0, 1, polygonUnionOperandA, S(P(0, 0), P(1, 0)), true, polygonUnionOperandA),
        E(1, 2, polygonUnionOperandA, S(P(1, 0), P(1, 1)), true, polygonUnionOperandA),
        E(2, 3, polygonUnionOperandA, S(P(1, 1), P(0, 1)), true, polygonUnionOperandA),
        E(0, 3, polygonUnionOperandA, S(P(0, 1), P(0, 0)), false, 0),

        E(0, 4, polygonUnionOperandB, S(P(0, 0), P(-1, 0)), true, polygonUnionOperandB),
        E(4, 5, polygonUnionOperandB, S(P(-1, 0), P(-1, -1)), true, polygonUnionOperandB),
        E(5, 6, polygonUnionOperandB, S(P(-1, -1), P(0, -1)), true, polygonUnionOperandB),
        E(0, 6, polygonUnionOperandB, S(P(0, -1), P(0, 0)), false, 0),
    ];

    ExactArrangementHalfEdge[16] halfEdges;
    size_t[16] outgoing;
    size_t[16] position;
    size_t[8] offsets;
    size_t[7] cursor;

    assert(
        buildExactHalfEdgeEmbedding(
            edges[],
            7,
            halfEdges[],
            outgoing[],
            position[],
            offsets[],
            cursor[]
        )
    );

    bool[16] selected;

    selected[0] = true;
    selected[2] = true;
    selected[4] = true;
    selected[7] = true;

    selected[8] = true;
    selected[10] = true;
    selected[12] = true;
    selected[15] = true;

    size_t[16] nextSelected;
    size_t[16] edgeCycle;
    size_t[7] vertexCycle;
    ExactUnionBoundaryCycle[16] cycles;
    size_t cycleCount;

    assert(
        tryBuildExactUnionBoundaryCycles(
            halfEdges[],
            outgoing[],
            position[],
            offsets[],
            selected[],
            nextSelected[],
            edgeCycle[],
            vertexCycle[],
            cycles[],
            cycleCount
        )
    );

    assert(cycleCount == 2);

    assert(cycles[0].startHalfEdge == 0);
    assert(cycles[0].edgeCount == 4);

    assert(cycles[1].startHalfEdge == 8);
    assert(cycles[1].edgeCount == 4);

    assert(edgeCycle[0] == edgeCycle[2]);
    assert(edgeCycle[2] == edgeCycle[4]);
    assert(edgeCycle[4] == edgeCycle[7]);

    assert(edgeCycle[8] == edgeCycle[10]);
    assert(edgeCycle[10] == edgeCycle[12]);
    assert(edgeCycle[12] == edgeCycle[15]);

    assert(edgeCycle[0] != edgeCycle[8]);

    /*
     * At the shared exact vertex:
     *
     * arrival N -> O has outgoing twin O -> N and continues O -> E;
     * arrival S -> O has outgoing twin O -> S and continues O -> W.
     */
    assert(nextSelected[7] == 0);
    assert(nextSelected[15] == 8);
}


@safe unittest
{
    /*
     * A selected self-touching closed walk is rejected even when all
     * destination -> next-origin incidences are locally valid.
     */
    ExactArrangementHalfEdge[6] halfEdges;

    halfEdges[0].originVertex = 0;
    halfEdges[0].destinationVertex = 1;

    halfEdges[1].originVertex = 1;
    halfEdges[1].destinationVertex = 2;

    halfEdges[2].originVertex = 2;
    halfEdges[2].destinationVertex = 0;

    halfEdges[3].originVertex = 0;
    halfEdges[3].destinationVertex = 3;

    halfEdges[4].originVertex = 3;
    halfEdges[4].destinationVertex = 4;

    halfEdges[5].originVertex = 4;
    halfEdges[5].destinationVertex = 0;

    const bool[6] selected = [
        true,
        true,
        true,
        true,
        true,
        true,
    ];

    const size_t[6] nextSelected = [
        1,
        2,
        3,
        4,
        5,
        0,
    ];

    size_t[6] edgeCycle;
    size_t[5] vertexCycle;
    ExactUnionBoundaryCycle[6] cycles;
    size_t cycleCount;

    assert(
        !tryTraceExactUnionBoundaryCycles(
            halfEdges[],
            selected[],
            nextSelected[],
            edgeCycle[],
            vertexCycle[],
            cycles[],
            cycleCount
        )
    );

    assert(cycleCount == 0);
}


@safe unittest
{
    /*
     * A selected open/broken boundary is rejected by continuation building.
     */
    ExactArrangementHalfEdge[2] halfEdges;

    halfEdges[0] =
        ExactArrangementHalfEdge(
            0,
            1,
            1,
            0,
            size_t.max,
            true
        );

    halfEdges[1] =
        ExactArrangementHalfEdge(
            1,
            0,
            0,
            0,
            size_t.max,
            false
        );

    const size_t[2] outgoing = [
        0,
        1,
    ];

    const size_t[2] position = [
        0,
        1,
    ];

    const size_t[3] offsets = [
        0,
        1,
        2,
    ];

    const bool[2] selected = [
        true,
        false,
    ];

    size_t[2] nextSelected;

    assert(
        !buildExactUnionBoundaryContinuations(
            halfEdges[],
            outgoing[],
            position[],
            offsets[],
            selected[],
            nextSelected[]
        )
    );
}
