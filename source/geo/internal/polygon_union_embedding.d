module geo.internal.polygon_union_embedding;

import geo.internal.polygon_union_arrangement :
    ExactArrangementEdge,
    compareExactSourceDirectionsCCW,
    exactArrangementEdgeDirection;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact half-edge embedding for the P1 polygon-union arrangement.
 *
 * Every undirected arrangement edge becomes two directed half-edges. Outgoing
 * half-edges are ordered exactly counter-clockwise at each arrangement vertex
 * using represented source-segment directions. No rounded overlay coordinate
 * participates in the rotation system.
 */


private enum bool isPolygonUnionEmbeddingScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/*
 * One directed arrangement half-edge.
 *
 * canonicalForward == true means the half-edge follows the canonical
 * firstVertex -> secondVertex orientation of its owning arrangement edge.
 *
 * nextLeftFace is the next directed edge when tracing the face that lies on
 * this half-edge's left side.
 */
struct ExactArrangementHalfEdge
{
    size_t originVertex;
    size_t destinationVertex;

    size_t twin;
    size_t arrangementEdge;

    size_t nextLeftFace;

    bool canonicalForward;
}


/*
 * Exact angular comparison of two directed half-edges.
 */
private int compareOutgoingHalfEdgesCCW(T)(
    scope const(ExactArrangementEdge!T)[] edges,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    size_t lhsIndex,
    size_t rhsIndex
)
    pure nothrow @safe @nogc
if (isPolygonUnionEmbeddingScalar!T)
{
    const auto lhs =
        exactArrangementEdgeDirection(
            edges[
                halfEdges[
                    lhsIndex
                ].arrangementEdge
            ],
            halfEdges[
                lhsIndex
            ].canonicalForward
        );

    const auto rhs =
        exactArrangementEdgeDirection(
            edges[
                halfEdges[
                    rhsIndex
                ].arrangementEdge
            ],
            halfEdges[
                rhsIndex
            ].canonicalForward
        );

    return
        compareExactSourceDirectionsCCW(
            lhs,
            rhs
        );
}


/*
 * Restores max-heap angular order in one outgoing-index slice.
 */
private void siftDownOutgoing(T)(
    scope const(ExactArrangementEdge!T)[] edges,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope size_t[] outgoing,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
if (isPolygonUnionEmbeddingScalar!T)
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
            compareOutgoingHalfEdgesCCW(
                edges,
                halfEdges,
                outgoing[largest],
                outgoing[left]
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
            compareOutgoingHalfEdgesCCW(
                edges,
                halfEdges,
                outgoing[largest],
                outgoing[right]
            ) < 0
        )
        {
            largest =
                right;
        }

        if (largest == root)
            return;

        const size_t temporary =
            outgoing[root];

        outgoing[root] =
            outgoing[largest];

        outgoing[largest] =
            temporary;

        root =
            largest;
    }
}


/*
 * Sorts one vertex's outgoing half-edge indices in exact CCW order.
 *
 * Returns false if two distinct outgoing edges occupy the same exact ray. A
 * correctly noded/deduplicated arrangement cannot contain that condition.
 */
private bool sortOutgoingHalfEdgesCCW(T)(
    scope const(ExactArrangementEdge!T)[] edges,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope size_t[] outgoing
)
    pure nothrow @safe @nogc
if (isPolygonUnionEmbeddingScalar!T)
{
    if (outgoing.length < 2)
        return true;

    size_t start =
        outgoing.length / 2;

    while (start > 0)
    {
        --start;

        siftDownOutgoing(
            edges,
            halfEdges,
            outgoing,
            start,
            outgoing.length
        );
    }

    size_t end =
        outgoing.length;

    while (end > 1)
    {
        --end;

        const size_t temporary =
            outgoing[0];

        outgoing[0] =
            outgoing[end];

        outgoing[end] =
            temporary;

        siftDownOutgoing(
            edges,
            halfEdges,
            outgoing,
            0,
            end
        );
    }

    foreach (i; 1 .. outgoing.length)
    {
        if (
            compareOutgoingHalfEdgesCCW(
                edges,
                halfEdges,
                outgoing[i - 1],
                outgoing[i]
            ) == 0
        )
        {
            return false;
        }
    }

    return true;
}


/*
 * Builds exact outgoing rotations and left-face continuation for an already
 * noded arrangement.
 *
 * Required capacities:
 *
 *     halfEdges.length        >= 2 * edges.length
 *     outgoing.length         >= 2 * edges.length
 *     halfEdgePosition.length >= 2 * edges.length
 *     vertexOffsets.length    >= vertexCount + 1
 *     vertexCursor.length     >= vertexCount
 *
 * vertexOffsets[v .. v+2] indexes the exact CCW outgoing range for vertex v.
 *
 * The function is allocation-free. P1 may allocate these buffers in its
 * owning overlay state, but the embedding primitive itself hides no
 * allocation.
 */
bool buildExactHalfEdgeEmbedding(T)(
    scope const(ExactArrangementEdge!T)[] edges,
    size_t vertexCount,
    scope ExactArrangementHalfEdge[] halfEdges,
    scope size_t[] outgoing,
    scope size_t[] halfEdgePosition,
    scope size_t[] vertexOffsets,
    scope size_t[] vertexCursor
)
    pure nothrow @safe @nogc
if (isPolygonUnionEmbeddingScalar!T)
{
    if (
        edges.length >
        size_t.max / 2
    )
    {
        return false;
    }

    const size_t halfEdgeCount =
        edges.length * 2;

    if (
        halfEdges.length < halfEdgeCount ||
        outgoing.length < halfEdgeCount ||
        halfEdgePosition.length < halfEdgeCount ||
        vertexOffsets.length < vertexCount + 1 ||
        vertexCursor.length < vertexCount
    )
    {
        return false;
    }

    foreach (vertex; 0 .. vertexCount)
        vertexCursor[vertex] = 0;

    foreach (i, ref const edge; edges)
    {
        if (
            edge.firstVertex >= vertexCount ||
            edge.secondVertex >= vertexCount ||
            edge.firstVertex == edge.secondVertex
        )
        {
            return false;
        }

        if (
            vertexCursor[edge.firstVertex] ==
            size_t.max ||
            vertexCursor[edge.secondVertex] ==
            size_t.max
        )
        {
            return false;
        }

        ++vertexCursor[edge.firstVertex];
        ++vertexCursor[edge.secondVertex];

        const size_t forward =
            i * 2;

        const size_t reverse =
            forward + 1;

        halfEdges[forward] =
            ExactArrangementHalfEdge(
                edge.firstVertex,
                edge.secondVertex,
                reverse,
                i,
                size_t.max,
                true
            );

        halfEdges[reverse] =
            ExactArrangementHalfEdge(
                edge.secondVertex,
                edge.firstVertex,
                forward,
                i,
                size_t.max,
                false
            );
    }

    vertexOffsets[0] = 0;

    foreach (vertex; 0 .. vertexCount)
    {
        if (
            vertexOffsets[vertex] >
            size_t.max -
            vertexCursor[vertex]
        )
        {
            return false;
        }

        vertexOffsets[vertex + 1] =
            vertexOffsets[vertex] +
            vertexCursor[vertex];

        vertexCursor[vertex] =
            vertexOffsets[vertex];
    }

    if (
        vertexOffsets[vertexCount] !=
        halfEdgeCount
    )
    {
        return false;
    }

    foreach (halfEdgeIndex; 0 .. halfEdgeCount)
    {
        const size_t origin =
            halfEdges[
                halfEdgeIndex
            ].originVertex;

        const size_t position =
            vertexCursor[origin]++;

        assert(
            position <
            vertexOffsets[
                origin + 1
            ]
        );

        outgoing[position] =
            halfEdgeIndex;
    }

    foreach (vertex; 0 .. vertexCount)
    {
        const size_t begin =
            vertexOffsets[vertex];

        const size_t end =
            vertexOffsets[vertex + 1];

        if (
            !sortOutgoingHalfEdgesCCW(
                edges,
                halfEdges[0 .. halfEdgeCount],
                outgoing[begin .. end]
            )
        )
        {
            return false;
        }

        foreach (position; begin .. end)
        {
            halfEdgePosition[
                outgoing[position]
            ] =
                position;
        }
    }

    foreach (halfEdgeIndex; 0 .. halfEdgeCount)
    {
        const size_t destination =
            halfEdges[
                halfEdgeIndex
            ].destinationVertex;

        const size_t twin =
            halfEdges[
                halfEdgeIndex
            ].twin;

        const size_t twinPosition =
            halfEdgePosition[twin];

        const size_t begin =
            vertexOffsets[destination];

        const size_t end =
            vertexOffsets[
                destination + 1
            ];

        if (
            twinPosition < begin ||
            twinPosition >= end ||
            begin == end
        )
        {
            return false;
        }

        const size_t clockwisePosition =
            twinPosition == begin
                ? end - 1
                : twinPosition - 1;

        halfEdges[
            halfEdgeIndex
        ].nextLeftFace =
            outgoing[
                clockwisePosition
            ];
    }

    return true;
}


@safe unittest
{
    import geo.internal.polygon_union_noding :
        polygonUnionOperandA;

    import geo.point :
        Point2;

    alias P = Point2!int;
    alias S = Segment2!int;
    alias E = ExactArrangementEdge!int;


    /*
     * One CCW square.
     *
     * Lexicographic exact vertex IDs:
     *
     *     1 TL ---- 3 TR
     *       |         |
     *       |         |
     *     0 BL ---- 2 BR
     *
     * Interior-left boundary half-edges are:
     *
     *     bottom forward  0
     *     right  forward  2
     *     top    reverse  5
     *     left   reverse  7
     */
    const E[4] edges = [
        E(
            0,
            2,
            polygonUnionOperandA,
            S(
                P(0, 0),
                P(1, 0)
            ),
            true
        ),
        E(
            2,
            3,
            polygonUnionOperandA,
            S(
                P(1, 0),
                P(1, 1)
            ),
            true
        ),
        E(
            1,
            3,
            polygonUnionOperandA,
            S(
                P(1, 1),
                P(0, 1)
            ),
            false
        ),
        E(
            0,
            1,
            polygonUnionOperandA,
            S(
                P(0, 1),
                P(0, 0)
            ),
            false
        ),
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

    assert(
        halfEdges[0].nextLeftFace ==
        2
    );

    assert(
        halfEdges[2].nextLeftFace ==
        5
    );

    assert(
        halfEdges[5].nextLeftFace ==
        7
    );

    assert(
        halfEdges[7].nextLeftFace ==
        0
    );

    /*
     * The exterior face is traced by the opposite four half-edges.
     */
    assert(
        halfEdges[1].nextLeftFace ==
        6
    );

    assert(
        halfEdges[6].nextLeftFace ==
        4
    );

    assert(
        halfEdges[4].nextLeftFace ==
        3
    );

    assert(
        halfEdges[3].nextLeftFace ==
        1
    );
}


@safe unittest
{
    import geo.internal.polygon_union_noding :
        polygonUnionOperandA,
        polygonUnionOperandB;

    import geo.point :
        Point2;

    alias P = Point2!int;
    alias S = Segment2!int;
    alias E = ExactArrangementEdge!int;


    /*
     * Four rays at one exact crossing vertex are ordered:
     *
     *     east, north, west, south
     *
     * from +x in exact CCW order.
     */
    const E[4] edges = [
        E(
            2,
            4,
            polygonUnionOperandA,
            S(
                P(0, 0),
                P(1, 0)
            ),
            true
        ),
        E(
            2,
            3,
            polygonUnionOperandB,
            S(
                P(0, 0),
                P(0, 1)
            ),
            true
        ),
        E(
            1,
            2,
            polygonUnionOperandA,
            S(
                P(-1, 0),
                P(0, 0)
            ),
            true
        ),
        E(
            0,
            2,
            polygonUnionOperandB,
            S(
                P(0, -1),
                P(0, 0)
            ),
            true
        ),
    ];

    ExactArrangementHalfEdge[8] halfEdges;
    size_t[8] outgoing;
    size_t[8] position;
    size_t[6] offsets;
    size_t[5] cursor;

    assert(
        buildExactHalfEdgeEmbedding(
            edges[],
            5,
            halfEdges[],
            outgoing[],
            position[],
            offsets[],
            cursor[]
        )
    );

    const size_t begin =
        offsets[2];

    const size_t end =
        offsets[3];

    assert(end - begin == 4);

    foreach (i; begin + 1 .. end)
    {
        const size_t previousIndex =
            outgoing[i - 1];

        const size_t currentIndex =
            outgoing[i];

        const auto previous =
            exactArrangementEdgeDirection(
                edges[
                    halfEdges[
                        previousIndex
                    ].arrangementEdge
                ],
                halfEdges[
                    previousIndex
                ].canonicalForward
            );

        const auto current =
            exactArrangementEdgeDirection(
                edges[
                    halfEdges[
                        currentIndex
                    ].arrangementEdge
                ],
                halfEdges[
                    currentIndex
                ].canonicalForward
            );

        assert(
            compareExactSourceDirectionsCCW(
                previous,
                current
            ) < 0
        );
    }

    /*
     * The expected concrete order is east / north / west / south.
     */
    assert(outgoing[begin + 0] == 0);
    assert(outgoing[begin + 1] == 2);
    assert(outgoing[begin + 2] == 5);
    assert(outgoing[begin + 3] == 7);
}


@safe unittest
{
    import geo.internal.polygon_union_noding :
        polygonUnionOperandA;

    import geo.point :
        Point2;

    alias P = Point2!int;
    alias S = Segment2!int;
    alias E = ExactArrangementEdge!int;


    /*
     * Same-ray duplicate outgoing edges are rejected as an invalid
     * pre-embedding arrangement state.
     */
    const E[2] edges = [
        E(
            0,
            1,
            polygonUnionOperandA,
            S(
                P(0, 0),
                P(1, 0)
            ),
            true
        ),
        E(
            0,
            2,
            polygonUnionOperandA,
            S(
                P(0, 0),
                P(2, 0)
            ),
            true
        ),
    ];

    ExactArrangementHalfEdge[4] halfEdges;
    size_t[4] outgoing;
    size_t[4] position;
    size_t[4] offsets;
    size_t[3] cursor;

    assert(
        !buildExactHalfEdgeEmbedding(
            edges[],
            3,
            halfEdges[],
            outgoing[],
            position[],
            offsets[],
            cursor[]
        )
    );
}
