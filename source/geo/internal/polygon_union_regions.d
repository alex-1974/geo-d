module geo.internal.polygon_union_regions;

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
