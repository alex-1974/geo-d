module geo.internal.polygon_union_regions;

import geo.internal.polygon_union_arrangement;
import geo.internal.polygon_union_embedding;

import geo.internal.polygon_union_noding :
    polygonUnionOperandA,
    polygonUnionOperandB;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact two-operand region-parity propagation for polygon union.
 *
 * Geometry has already been resolved by noding/embedding before this layer.
 * Crossing one atomic arrangement boundary toggles the inside parity for every
 * operand whose exact source boundary contributes to that edge.
 */


/*
 * Exact membership state of one two-dimensional arrangement cell.
 */
struct ExactRegionLabel
{
    bool insideA;
    bool insideB;
}


/*
 * One adjacency in the dual arrangement graph.
 *
 * Crossing between the two cells toggles every operand bit present in
 * operandMask.
 */
struct ExactRegionTransition
{
    size_t firstCell;
    size_t secondCell;
    ubyte operandMask;
}


/*
 * Crosses one exact atomic boundary.
 */
ExactRegionLabel crossExactBoundary(
    ExactRegionLabel source,
    ubyte operandMask
)
    pure nothrow @safe @nogc
{
    assert(operandMask != 0);

    assert(
        (
            operandMask &
            ~(
                polygonUnionOperandA |
                polygonUnionOperandB
            )
        ) == 0
    );

    if (
        (
            operandMask &
            polygonUnionOperandA
        ) != 0
    )
    {
        source.insideA =
            !source.insideA;
    }

    if (
        (
            operandMask &
            polygonUnionOperandB
        ) != 0
    )
    {
        source.insideB =
            !source.insideB;
    }

    return source;
}


/*
 * True exactly when one arrangement cell belongs to the regularized union.
 */
bool exactUnionInterior(
    ExactRegionLabel label
)
    pure nothrow @safe @nogc
{
    return
        label.insideA ||
        label.insideB;
}


/*
 * True exactly when a dual transition separates union exterior/interior.
 */
bool exactUnionBoundaryBetween(
    ExactRegionLabel first,
    ExactRegionLabel second
)
    pure nothrow @safe @nogc
{
    return
        exactUnionInterior(first) !=
        exactUnionInterior(second);
}


/*
 * Propagates exact A/B parity over an already constructed dual arrangement.
 *
 * Cell zero is the unbounded exterior and is seeded as outside both operands.
 *
 * This P1 implementation uses repeated relaxation to keep the semantic core
 * explicit and allocation-free. A later queue/stack traversal may replace it
 * without changing the contract.
 *
 * Returns false for:
 * - empty cell storage;
 * - inconsistent storage lengths;
 * - invalid transition indices/masks;
 * - contradictory parity constraints;
 * - disconnected/unreachable dual cells.
 */
bool tryPropagateExactRegionLabels(
    scope const(ExactRegionTransition)[] transitions,
    scope ExactRegionLabel[] labels,
    scope bool[] assigned
)
    pure nothrow @safe @nogc
{
    if (
        labels.length == 0 ||
        assigned.length != labels.length
    )
    {
        return false;
    }

    foreach (i; 0 .. labels.length)
    {
        labels[i] =
            ExactRegionLabel.init;

        assigned[i] =
            false;
    }

    assigned[0] = true;

    bool changed;

    do
    {
        changed = false;

        foreach (transition; transitions)
        {
            if (
                transition.firstCell >= labels.length ||
                transition.secondCell >= labels.length ||
                transition.firstCell == transition.secondCell ||
                transition.operandMask == 0 ||
                (
                    transition.operandMask &
                    ~(
                        polygonUnionOperandA |
                        polygonUnionOperandB
                    )
                ) != 0
            )
            {
                return false;
            }

            const bool firstAssigned =
                assigned[
                    transition.firstCell
                ];

            const bool secondAssigned =
                assigned[
                    transition.secondCell
                ];

            if (
                firstAssigned &&
                !secondAssigned
            )
            {
                labels[
                    transition.secondCell
                ] =
                    crossExactBoundary(
                        labels[
                            transition.firstCell
                        ],
                        transition.operandMask
                    );

                assigned[
                    transition.secondCell
                ] = true;

                changed = true;
            }
            else if (
                !firstAssigned &&
                secondAssigned
            )
            {
                labels[
                    transition.firstCell
                ] =
                    crossExactBoundary(
                        labels[
                            transition.secondCell
                        ],
                        transition.operandMask
                    );

                assigned[
                    transition.firstCell
                ] = true;

                changed = true;
            }
            else if (
                firstAssigned &&
                secondAssigned
            )
            {
                if (
                    crossExactBoundary(
                        labels[
                            transition.firstCell
                        ],
                        transition.operandMask
                    ) !=
                    labels[
                        transition.secondCell
                    ]
                )
                {
                    return false;
                }
            }
        }
    }
    while (changed);

    foreach (isAssigned; assigned)
    {
        if (!isAssigned)
            return false;
    }

    return true;
}


/*
 * Selects which exact dual transitions are regularized-union boundaries.
 *
 * selected.length must equal transitions.length.
 *
 * A transition is selected iff its adjacent exact cells have different union
 * states. Shared A+B boundaries are therefore retained or removed solely by
 * exact side parity, not by special-case source rules.
 */
bool selectExactUnionBoundaryTransitions(
    scope const(ExactRegionTransition)[] transitions,
    scope const(ExactRegionLabel)[] labels,
    scope bool[] selected
)
    pure nothrow @safe @nogc
{
    if (
        selected.length != transitions.length
    )
    {
        return false;
    }

    foreach (i, transition; transitions)
    {
        if (
            transition.firstCell >= labels.length ||
            transition.secondCell >= labels.length ||
            transition.firstCell == transition.secondCell
        )
        {
            return false;
        }

        selected[i] =
            exactUnionBoundaryBetween(
                labels[
                    transition.firstCell
                ],
                labels[
                    transition.secondCell
                ]
            );
    }

    return true;
}


@safe unittest
{
    alias T = ExactRegionTransition;
    alias L = ExactRegionLabel;

    enum ubyte both =
        polygonUnionOperandA |
        polygonUnionOperandB;


    /*
     * Disjoint components share the unbounded exterior.
     */
    {
        const T[2] transitions = [
            T(
                0,
                1,
                polygonUnionOperandA
            ),
            T(
                0,
                2,
                polygonUnionOperandB
            ),
        ];

        L[3] labels;
        bool[3] assigned;

        assert(
            tryPropagateExactRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        assert(
            labels[0] ==
            L(false, false)
        );

        assert(
            labels[1] ==
            L(true, false)
        );

        assert(
            labels[2] ==
            L(false, true)
        );

        bool[2] selected;

        assert(
            selectExactUnionBoundaryTransitions(
                transitions[],
                labels[],
                selected[]
            )
        );

        assert(selected == [true, true]);
    }


    /*
     * B strictly nested inside A:
     *
     * outside --A--> A-only --B--> A+B
     *
     * B's internal boundary is not a union boundary.
     */
    {
        const T[2] transitions = [
            T(
                0,
                1,
                polygonUnionOperandA
            ),
            T(
                1,
                2,
                polygonUnionOperandB
            ),
        ];

        L[3] labels;
        bool[3] assigned;

        assert(
            tryPropagateExactRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        assert(
            labels[1] ==
            L(true, false)
        );

        assert(
            labels[2] ==
            L(true, true)
        );

        bool[2] selected;

        assert(
            selectExactUnionBoundaryTransitions(
                transitions[],
                labels[],
                selected[]
            )
        );

        assert(selected[0]);
        assert(!selected[1]);
    }


    /*
     * Ordinary overlap contains all four exact parity cells.
     */
    {
        const T[4] transitions = [
            T(
                0,
                1,
                polygonUnionOperandA
            ),
            T(
                0,
                2,
                polygonUnionOperandB
            ),
            T(
                1,
                3,
                polygonUnionOperandB
            ),
            T(
                2,
                3,
                polygonUnionOperandA
            ),
        ];

        L[4] labels;
        bool[4] assigned;

        assert(
            tryPropagateExactRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        assert(labels[0] == L(false, false));
        assert(labels[1] == L(true, false));
        assert(labels[2] == L(false, true));
        assert(labels[3] == L(true, true));

        bool[4] selected;

        assert(
            selectExactUnionBoundaryTransitions(
                transitions[],
                labels[],
                selected[]
            )
        );

        assert(selected[0]);
        assert(selected[1]);
        assert(!selected[2]);
        assert(!selected[3]);
    }


    /*
     * Identical polygon boundaries toggle both operands together and remain
     * one union boundary.
     */
    {
        const T[1] transitions = [
            T(
                0,
                1,
                both
            ),
        ];

        L[2] labels;
        bool[2] assigned;

        assert(
            tryPropagateExactRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        assert(
            labels[1] ==
            L(true, true)
        );

        bool[1] selected;

        assert(
            selectExactUnionBoundaryTransitions(
                transitions[],
                labels[],
                selected[]
            )
        );

        assert(selected[0]);
    }


    /*
     * Adjacent polygons sharing an edge:
     *
     * outside --A--> A-only
     * outside --B--> B-only
     * A-only --AB--> B-only
     *
     * The shared AB span has union interior on both sides and disappears.
     */
    {
        const T[3] transitions = [
            T(
                0,
                1,
                polygonUnionOperandA
            ),
            T(
                0,
                2,
                polygonUnionOperandB
            ),
            T(
                1,
                2,
                both
            ),
        ];

        L[3] labels;
        bool[3] assigned;

        assert(
            tryPropagateExactRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );

        bool[3] selected;

        assert(
            selectExactUnionBoundaryTransitions(
                transitions[],
                labels[],
                selected[]
            )
        );

        assert(selected[0]);
        assert(selected[1]);
        assert(!selected[2]);
    }


    /*
     * Contradictory dual parity is rejected.
     */
    {
        const T[3] transitions = [
            T(
                0,
                1,
                polygonUnionOperandA
            ),
            T(
                1,
                2,
                polygonUnionOperandB
            ),
            T(
                0,
                2,
                polygonUnionOperandA
            ),
        ];

        L[3] labels;
        bool[3] assigned;

        assert(
            !tryPropagateExactRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );
    }


    /*
     * Unreachable cell is rejected instead of receiving an implicit label.
     */
    {
        const T[1] transitions = [
            T(
                0,
                1,
                polygonUnionOperandA
            ),
        ];

        L[3] labels;
        bool[3] assigned;

        assert(
            !tryPropagateExactRegionLabels(
                transitions[],
                labels[],
                assigned[]
            )
        );
    }
}


/*
 * Exact parity information for the region immediately left of one directed
 * arrangement half-edge.
 *
 * knownMask records which operand bits are established.
 * insideMask stores the corresponding inside/outside values.
 *
 * Unknown bits are deliberately distinct from outside bits.
 */
struct ExactHalfEdgeSideLabel
{
    ubyte knownMask;
    ubyte insideMask;
}


private enum ubyte polygonUnionOperandMask =
    polygonUnionOperandA |
    polygonUnionOperandB;


/*
 * Adds one or more known operand-side bits and rejects contradictions.
 */
private bool mergeExactSideKnowledge(
    ref ExactHalfEdgeSideLabel label,
    ubyte knownMask,
    ubyte insideMask
)
    pure nothrow @safe @nogc
{
    if (
        knownMask == 0 ||
        (
            knownMask &
            ~polygonUnionOperandMask
        ) != 0 ||
        (
            insideMask &
            ~knownMask
        ) != 0
    )
    {
        return false;
    }

    const ubyte overlap =
        label.knownMask &
        knownMask;

    if (
        (
            (
                label.insideMask ^
                insideMask
            ) &
            overlap
        ) != 0
    )
    {
        return false;
    }

    label.insideMask =
        (
            label.insideMask &
            ~knownMask
        ) |
        (
            insideMask &
            knownMask
        );

    label.knownMask |=
        knownMask;

    return true;
}


/*
 * Clears side labels and seeds every contributing operand from exact
 * source-boundary provenance stored on the arrangement edge.
 *
 * The canonical-forward half-edge sees interiorLeftMask on its left.
 * Its reverse twin sees the complementary contributing bits on its left.
 *
 * Non-contributing operand bits remain unknown and are resolved later by
 * propagation or one containment seed for an otherwise disjoint component.
 */
bool initializeExactHalfEdgeSideLabels(T)(
    scope const(geo.internal.polygon_union_arrangement.ExactArrangementEdge!T)[] edges,
    scope const(geo.internal.polygon_union_embedding.ExactArrangementHalfEdge)[] halfEdges,
    scope ExactHalfEdgeSideLabel[] labels
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
        labels.length != halfEdges.length
    )
    {
        return false;
    }

    foreach (ref label; labels)
        label = ExactHalfEdgeSideLabel.init;

    foreach (halfEdgeIndex, ref const halfEdge; halfEdges)
    {
        if (
            halfEdge.arrangementEdge >= edges.length ||
            halfEdge.twin >= halfEdges.length
        )
        {
            return false;
        }

        const auto edge =
            edges[
                halfEdge.arrangementEdge
            ];

        if (
            edge.operandMask == 0 ||
            (
                edge.operandMask &
                ~polygonUnionOperandMask
            ) != 0 ||
            (
                edge.interiorLeftMask &
                ~edge.operandMask
            ) != 0
        )
        {
            return false;
        }

        const ubyte insideLeft =
            halfEdge.canonicalForward
                ? edge.interiorLeftMask
                : edge.operandMask ^
                    edge.interiorLeftMask;

        if (
            !mergeExactSideKnowledge(
                labels[halfEdgeIndex],
                edge.operandMask,
                insideLeft
            )
        )
        {
            return false;
        }
    }

    return true;
}


/*
 * Adds one caller-proven missing-operand side seed.
 *
 * This is intended for a connected arrangement component that contains no
 * boundary from one operand. In that case the missing operand's parity is
 * constant over the component and may be established by classifying one
 * represented source point against the missing polygon.
 */
bool seedExactHalfEdgeSideBit(
    scope ExactHalfEdgeSideLabel[] labels,
    size_t halfEdgeIndex,
    ubyte operandBit,
    bool inside
)
    pure nothrow @safe @nogc
{
    if (
        halfEdgeIndex >= labels.length ||
        (
            operandBit != polygonUnionOperandA &&
            operandBit != polygonUnionOperandB
        )
    )
    {
        return false;
    }

    return
        mergeExactSideKnowledge(
            labels[halfEdgeIndex],
            operandBit,
            inside
                ? operandBit
                : 0
        );
}


/*
 * Propagates exact side parity through the half-edge embedding.
 *
 * Constraints:
 *
 * 1. h and h.nextLeftFace bound the same local two-dimensional region on
 *    their left, so their side labels are equal.
 *
 * 2. h and h.twin lie on opposite sides of the same atomic boundary.
 *    Crossing toggles exactly edge.operandMask.
 *
 * Existing caller seeds are preserved. The function repeatedly propagates
 * every known bit until fixed point, rejecting contradictory constraints.
 *
 * complete is true iff both A and B are known for every half-edge.
 */
bool tryPropagateExactHalfEdgeSideLabels(T)(
    scope const(geo.internal.polygon_union_arrangement.ExactArrangementEdge!T)[] edges,
    scope const(geo.internal.polygon_union_embedding.ExactArrangementHalfEdge)[] halfEdges,
    scope ExactHalfEdgeSideLabel[] labels,
    out bool complete
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    complete = false;

    if (
        labels.length != halfEdges.length
    )
    {
        return false;
    }

    bool changed;

    do
    {
        changed = false;

        foreach (halfEdgeIndex, ref const halfEdge; halfEdges)
        {
            if (
                halfEdge.arrangementEdge >= edges.length ||
                halfEdge.twin >= halfEdges.length ||
                halfEdge.nextLeftFace >= halfEdges.length
            )
            {
                return false;
            }

            const auto edge =
                edges[
                    halfEdge.arrangementEdge
                ];

            if (
                halfEdges[
                    halfEdge.twin
                ].twin !=
                halfEdgeIndex
            )
            {
                return false;
            }


            /*
             * Same left-side region along the face-boundary walk.
             */
            {
                ref ExactHalfEdgeSideLabel current =
                    labels[halfEdgeIndex];

                ref ExactHalfEdgeSideLabel next =
                    labels[
                        halfEdge.nextLeftFace
                    ];

                const ubyte combinedKnown =
                    current.knownMask |
                    next.knownMask;

                const ubyte currentInside =
                    current.insideMask;

                const ubyte nextInside =
                    next.insideMask;

                if (
                    !mergeExactSideKnowledge(
                        current,
                        next.knownMask,
                        nextInside
                    ) ||
                    !mergeExactSideKnowledge(
                        next,
                        current.knownMask,
                        currentInside
                    )
                )
                {
                    return false;
                }

                if (
                    current.knownMask != combinedKnown ||
                    next.knownMask != combinedKnown
                )
                {
                    changed = true;
                }
            }


            /*
             * Opposite side across the atomic boundary.
             */
            {
                ref ExactHalfEdgeSideLabel current =
                    labels[halfEdgeIndex];

                ref ExactHalfEdgeSideLabel twin =
                    labels[
                        halfEdge.twin
                    ];

                const ubyte currentKnownBefore =
                    current.knownMask;

                const ubyte twinKnownBefore =
                    twin.knownMask;

                const ubyte currentToTwinInside =
                    current.insideMask ^
                    (
                        edge.operandMask &
                        current.knownMask
                    );

                if (
                    !mergeExactSideKnowledge(
                        twin,
                        current.knownMask,
                        currentToTwinInside
                    )
                )
                {
                    return false;
                }

                const ubyte twinToCurrentInside =
                    twin.insideMask ^
                    (
                        edge.operandMask &
                        twin.knownMask
                    );

                if (
                    !mergeExactSideKnowledge(
                        current,
                        twin.knownMask,
                        twinToCurrentInside
                    )
                )
                {
                    return false;
                }

                if (
                    current.knownMask != currentKnownBefore ||
                    twin.knownMask != twinKnownBefore
                )
                {
                    changed = true;
                }
            }
        }
    }
    while (changed);

    complete = true;

    foreach (label; labels)
    {
        if (
            label.knownMask !=
            polygonUnionOperandMask
        )
        {
            complete = false;
            break;
        }
    }

    return true;
}


/*
 * Selects oriented union-boundary half-edges from complete exact side labels.
 *
 * For each arrangement edge:
 * - if union state is equal on both sides, neither half-edge is selected;
 * - otherwise exactly the directed half-edge whose left side is union
 *   interior is selected.
 */
bool selectExactUnionBoundaryHalfEdges(T)(
    scope const(geo.internal.polygon_union_arrangement.ExactArrangementEdge!T)[] edges,
    scope const(geo.internal.polygon_union_embedding.ExactArrangementHalfEdge)[] halfEdges,
    scope const(ExactHalfEdgeSideLabel)[] labels,
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
            label.knownMask != polygonUnionOperandMask ||
            twinLabel.knownMask != polygonUnionOperandMask
        )
        {
            return false;
        }

        const bool leftUnion =
            (
                label.insideMask &
                polygonUnionOperandMask
            ) != 0;

        const bool rightUnion =
            (
                twinLabel.insideMask &
                polygonUnionOperandMask
            ) != 0;

        if (leftUnion == rightUnion)
            continue;

        if (leftUnion)
            selected[halfEdgeIndex] = true;
    }

    return true;
}


@safe unittest
{
    import geo.internal.polygon_union_arrangement :
        ExactArrangementEdge;

    import geo.internal.polygon_union_embedding :
        ExactArrangementHalfEdge;

    import geo.point :
        Point2;

    import geo.segment :
        Segment2;

    alias P = Point2!int;
    alias S = Segment2!int;
    alias E = ExactArrangementEdge!int;


    /*
     * One A-only square. A provenance determines all A bits; one outside-B
     * containment seed determines the missing constant B bit for the whole
     * connected component.
     */
    const E[4] edges = [
        E(0, 2, polygonUnionOperandA, S(P(0, 0), P(1, 0)), true, polygonUnionOperandA),
        E(2, 3, polygonUnionOperandA, S(P(1, 0), P(1, 1)), true, polygonUnionOperandA),
        E(1, 3, polygonUnionOperandA, S(P(1, 1), P(0, 1)), false, polygonUnionOperandA),
        E(0, 1, polygonUnionOperandA, S(P(0, 1), P(0, 0)), false, polygonUnionOperandA),
    ];

    ExactArrangementHalfEdge[8] halfEdges;

    halfEdges[0] = ExactArrangementHalfEdge(0, 2, 1, 0, 2, true);
    halfEdges[1] = ExactArrangementHalfEdge(2, 0, 0, 0, 6, false);

    halfEdges[2] = ExactArrangementHalfEdge(2, 3, 3, 1, 5, true);
    halfEdges[3] = ExactArrangementHalfEdge(3, 2, 2, 1, 1, false);

    halfEdges[4] = ExactArrangementHalfEdge(1, 3, 5, 2, 3, true);
    halfEdges[5] = ExactArrangementHalfEdge(3, 1, 4, 2, 7, false);

    halfEdges[6] = ExactArrangementHalfEdge(0, 1, 7, 3, 4, true);
    halfEdges[7] = ExactArrangementHalfEdge(1, 0, 6, 3, 0, false);

    ExactHalfEdgeSideLabel[8] labels;

    assert(
        initializeExactHalfEdgeSideLabels(
            edges[],
            halfEdges[],
            labels[]
        )
    );

    bool complete;

    assert(
        tryPropagateExactHalfEdgeSideLabels(
            edges[],
            halfEdges[],
            labels[],
            complete
        )
    );

    assert(!complete);

    assert(
        seedExactHalfEdgeSideBit(
            labels[],
            0,
            polygonUnionOperandB,
            false
        )
    );

    assert(
        tryPropagateExactHalfEdgeSideLabels(
            edges[],
            halfEdges[],
            labels[],
            complete
        )
    );

    assert(complete);

    bool[8] selected;

    assert(
        selectExactUnionBoundaryHalfEdges(
            edges[],
            halfEdges[],
            labels[],
            selected[]
        )
    );

    assert(selected[0]);
    assert(selected[2]);
    assert(selected[5]);
    assert(selected[7]);

    assert(!selected[1]);
    assert(!selected[3]);
    assert(!selected[4]);
    assert(!selected[6]);
}


@safe unittest
{
    import geo.internal.polygon_union_arrangement :
        ExactArrangementEdge;

    import geo.internal.polygon_union_embedding :
        ExactArrangementHalfEdge;

    import geo.point :
        Point2;

    import geo.segment :
        Segment2;

    alias P = Point2!int;
    alias S = Segment2!int;
    alias E = ExactArrangementEdge!int;

    enum ubyte both =
        polygonUnionOperandA |
        polygonUnionOperandB;


    /*
     * Identical coincident boundary with both polygon interiors on canonical
     * left remains a union boundary.
     */
    {
        const E[1] edges = [
            E(
                0,
                1,
                both,
                S(P(0, 0), P(1, 0)),
                true,
                both
            ),
        ];

        ExactArrangementHalfEdge[2] halfEdges = [
            ExactArrangementHalfEdge(0, 1, 1, 0, 0, true),
            ExactArrangementHalfEdge(1, 0, 0, 0, 1, false),
        ];

        ExactHalfEdgeSideLabel[2] labels;

        assert(
            initializeExactHalfEdgeSideLabels(
                edges[],
                halfEdges[],
                labels[]
            )
        );

        bool complete;

        assert(
            tryPropagateExactHalfEdgeSideLabels(
                edges[],
                halfEdges[],
                labels[],
                complete
            )
        );

        assert(complete);

        bool[2] selected;

        assert(
            selectExactUnionBoundaryHalfEdges(
                edges[],
                halfEdges[],
                labels[],
                selected[]
            )
        );

        assert(selected[0]);
        assert(!selected[1]);
    }


    /*
     * Adjacent polygons share the same atomic span with opposite interior
     * sides. Both sides are union interior, so the shared span disappears.
     */
    {
        const E[1] edges = [
            E(
                0,
                1,
                both,
                S(P(0, 0), P(1, 0)),
                true,
                polygonUnionOperandA
            ),
        ];

        ExactArrangementHalfEdge[2] halfEdges = [
            ExactArrangementHalfEdge(0, 1, 1, 0, 0, true),
            ExactArrangementHalfEdge(1, 0, 0, 0, 1, false),
        ];

        ExactHalfEdgeSideLabel[2] labels;

        assert(
            initializeExactHalfEdgeSideLabels(
                edges[],
                halfEdges[],
                labels[]
            )
        );

        bool complete;

        assert(
            tryPropagateExactHalfEdgeSideLabels(
                edges[],
                halfEdges[],
                labels[],
                complete
            )
        );

        assert(complete);

        bool[2] selected;

        assert(
            selectExactUnionBoundaryHalfEdges(
                edges[],
                halfEdges[],
                labels[],
                selected[]
            )
        );

        assert(!selected[0]);
        assert(!selected[1]);
    }
}
