module geo.internal.polygon_union_faces;

import geo.internal.polygon_union_embedding :
    ExactArrangementHalfEdge;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Topological face-boundary-cycle decomposition for the P1 polygon-union
 * arrangement.
 *
 * Important distinction:
 *
 * A nextLeftFace cycle is one connected boundary component of a
 * two-dimensional arrangement face. It is NOT automatically a unique face.
 *
 * One face may own multiple boundary cycles:
 *
 * - the unbounded exterior of disconnected arrangement components;
 * - bounded faces containing holes/islands;
 * - nested disconnected components before region-cell consolidation.
 *
 * This module deliberately records only the cycle decomposition. Later region
 * construction must explicitly consolidate boundary cycles into actual
 * two-dimensional cells.
 */


/*
 * One boundary-cycle descriptor.
 *
 * startHalfEdge is a deterministic representative: the smallest half-edge
 * index encountered in the cycle.
 */
struct ExactFaceBoundaryCycle
{
    size_t startHalfEdge;
    size_t edgeCount;
}


/*
 * Decomposes the complete directed half-edge set into nextLeftFace cycles.
 *
 * Preconditions encoded as checked failure:
 * - every nextLeftFace index must be in range;
 * - every traversal must close on its own first edge;
 * - a traversal must not enter a cycle already assigned to another start;
 * - every half-edge must belong to exactly one cycle;
 * - no zero-length cycle exists.
 *
 * cycleOfHalfEdge.length must equal halfEdges.length.
 * cycles needs capacity for at most halfEdges.length cycles.
 *
 * Returns false without exposing a trusted cycleCount if the embedding is
 * inconsistent.
 */
bool tryBuildExactFaceBoundaryCycles(
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope size_t[] cycleOfHalfEdge,
    scope ExactFaceBoundaryCycle[] cycles,
    out size_t cycleCount
)
    pure nothrow @safe @nogc
{
    cycleCount = 0;

    if (
        cycleOfHalfEdge.length != halfEdges.length ||
        cycles.length < halfEdges.length
    )
    {
        return false;
    }

    foreach (ref value; cycleOfHalfEdge)
        value = size_t.max;

    foreach (start; 0 .. halfEdges.length)
    {
        if (
            cycleOfHalfEdge[start] !=
            size_t.max
        )
        {
            continue;
        }

        const size_t thisCycle =
            cycleCount;

        size_t current =
            start;

        size_t count = 0;
        size_t minimum =
            start;

        while (true)
        {
            if (current >= halfEdges.length)
            {
                cycleCount = 0;
                return false;
            }

            if (
                cycleOfHalfEdge[current] !=
                size_t.max
            )
            {
                if (
                    current != start ||
                    cycleOfHalfEdge[current] !=
                    thisCycle
                )
                {
                    cycleCount = 0;
                    return false;
                }

                break;
            }

            cycleOfHalfEdge[current] =
                thisCycle;

            ++count;

            if (current < minimum)
                minimum = current;

            if (count > halfEdges.length)
            {
                cycleCount = 0;
                return false;
            }

            const size_t next =
                halfEdges[
                    current
                ].nextLeftFace;

            if (next >= halfEdges.length)
            {
                cycleCount = 0;
                return false;
            }

            current =
                next;
        }

        if (count == 0)
        {
            cycleCount = 0;
            return false;
        }

        cycles[thisCycle] =
            ExactFaceBoundaryCycle(
                minimum,
                count
            );

        ++cycleCount;
    }

    foreach (cycle; cycleOfHalfEdge)
    {
        if (
            cycle == size_t.max ||
            cycle >= cycleCount
        )
        {
            cycleCount = 0;
            return false;
        }
    }

    return true;
}


@safe unittest
{
    /*
     * One square embedding has two boundary cycles:
     * - one bounded interior face boundary;
     * - one unbounded exterior face boundary.
     *
     * The concrete half-edge indices match the square embedding fixture in
     * polygon_union_embedding.d.
     */
    ExactArrangementHalfEdge[8] halfEdges;

    halfEdges[0].nextLeftFace = 2;
    halfEdges[2].nextLeftFace = 5;
    halfEdges[5].nextLeftFace = 7;
    halfEdges[7].nextLeftFace = 0;

    halfEdges[1].nextLeftFace = 6;
    halfEdges[6].nextLeftFace = 4;
    halfEdges[4].nextLeftFace = 3;
    halfEdges[3].nextLeftFace = 1;

    size_t[8] cycleOf;
    ExactFaceBoundaryCycle[8] cycles;
    size_t cycleCount;

    assert(
        tryBuildExactFaceBoundaryCycles(
            halfEdges[],
            cycleOf[],
            cycles[],
            cycleCount
        )
    );

    assert(cycleCount == 2);

    assert(cycles[0].edgeCount == 4);
    assert(cycles[1].edgeCount == 4);

    assert(cycleOf[0] == cycleOf[2]);
    assert(cycleOf[2] == cycleOf[5]);
    assert(cycleOf[5] == cycleOf[7]);

    assert(cycleOf[1] == cycleOf[6]);
    assert(cycleOf[6] == cycleOf[4]);
    assert(cycleOf[4] == cycleOf[3]);

    assert(cycleOf[0] != cycleOf[1]);
}


@safe unittest
{
    /*
     * Two disconnected squares produce four half-edge boundary cycles, not
     * three geometric faces.
     *
     * Both exterior-oriented cycles belong to the same unbounded 2D face,
     * but this module deliberately does not merge them yet.
     */
    ExactArrangementHalfEdge[16] halfEdges;

    foreach (base; [size_t(0), size_t(8)])
    {
        halfEdges[base + 0].nextLeftFace =
            base + 2;

        halfEdges[base + 2].nextLeftFace =
            base + 5;

        halfEdges[base + 5].nextLeftFace =
            base + 7;

        halfEdges[base + 7].nextLeftFace =
            base + 0;

        halfEdges[base + 1].nextLeftFace =
            base + 6;

        halfEdges[base + 6].nextLeftFace =
            base + 4;

        halfEdges[base + 4].nextLeftFace =
            base + 3;

        halfEdges[base + 3].nextLeftFace =
            base + 1;
    }

    size_t[16] cycleOf;
    ExactFaceBoundaryCycle[16] cycles;
    size_t cycleCount;

    assert(
        tryBuildExactFaceBoundaryCycles(
            halfEdges[],
            cycleOf[],
            cycles[],
            cycleCount
        )
    );

    assert(cycleCount == 4);
}


@safe unittest
{
    /*
     * A chain that enters an already assigned different cycle is rejected.
     */
    ExactArrangementHalfEdge[4] halfEdges;

    halfEdges[0].nextLeftFace = 1;
    halfEdges[1].nextLeftFace = 0;

    halfEdges[2].nextLeftFace = 0;
    halfEdges[3].nextLeftFace = 3;

    size_t[4] cycleOf;
    ExactFaceBoundaryCycle[4] cycles;
    size_t cycleCount;

    assert(
        !tryBuildExactFaceBoundaryCycles(
            halfEdges[],
            cycleOf[],
            cycles[],
            cycleCount
        )
    );

    assert(cycleCount == 0);
}


@safe unittest
{
    /*
     * Out-of-range continuation is rejected.
     */
    ExactArrangementHalfEdge[1] halfEdges;
    halfEdges[0].nextLeftFace = 1;

    size_t[1] cycleOf;
    ExactFaceBoundaryCycle[1] cycles;
    size_t cycleCount;

    assert(
        !tryBuildExactFaceBoundaryCycles(
            halfEdges[],
            cycleOf[],
            cycles[],
            cycleCount
        )
    );

    assert(cycleCount == 0);
}
