module geo.internal.polygon_relationship_reducer;

import geo.internal.polygon_pair_topology :
    ExactPolygonPairTopology,
    PolygonPairTopologyStatus,
    tryBuildExactPolygonPairTopology;

import geo.internal.polygon_union_noding :
    polygonUnionOperandA,
    polygonUnionOperandB;

import geo.polygon_view :
    Polygon2View;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Reduces one completely labelled exact two-polygon arrangement to the
 * deliberately small relationship fact set qualified by the v3 research and
 * design work.
 *
 * No constructed coordinates, union boundaries or result components are
 * required.
 */


package(geo)
struct PolygonRelationshipFactsInternal
{
    bool hasFirstOnlyInterior;
    bool hasSecondOnlyInterior;
    bool hasSharedInterior;

    bool hasBoundaryContact;
    bool hasBoundaryOverlap;
}


/*
 * Reduce a completed exact polygon-pair topology.
 *
 * Returns false only when the supplied internal topology violates invariants
 * required by the shared builder.
 *
 * The reducer itself performs no allocation.
 */
package(geo)
bool reducePolygonRelationship(T)(
    ref const ExactPolygonPairTopology!T topology,
    out PolygonRelationshipFactsInternal facts
)
    pure nothrow @safe @nogc
{
    facts =
        PolygonRelationshipFactsInternal.init;

    enum ubyte bothOperands =
        polygonUnionOperandA |
        polygonUnionOperandB;


    /*
     * Each directed arrangement side represents one two-dimensional local
     * region. Complete side labels therefore provide the existential interior
     * occupancy facts directly.
     */
    foreach (const label; topology.sideLabels)
    {
        if (
            (label.knownMask & bothOperands) !=
            bothOperands
        )
        {
            return false;
        }

        const ubyte membership =
            label.insideMask &
            bothOperands;

        if (membership == polygonUnionOperandA)
        {
            facts.hasFirstOnlyInterior =
                true;
        }
        else if (membership == polygonUnionOperandB)
        {
            facts.hasSecondOnlyInterior =
                true;
        }
        else if (membership == bothOperands)
        {
            facts.hasSharedInterior =
                true;
        }
        else if (membership != 0)
        {
            return false;
        }
    }


    /*
     * Positive-length shared boundary is represented directly by one atomic
     * arrangement edge carrying provenance from both operands.
     */
    foreach (
        ref const edge;
        topology.arrangementEdges[
            0 ..
            topology.arrangementEdgeCount
        ]
    )
    {
        if (
            (
                edge.operandMask &
                bothOperands
            ) ==
            bothOperands
        )
        {
            facts.hasBoundaryOverlap =
                true;

            facts.hasBoundaryContact =
                true;

            break;
        }
    }


    /*
     * Point-only contacts and proper crossings do not necessarily produce an
     * A+B edge span. They do produce an exact arrangement vertex incident to
     * edges from both operands.
     *
     * vertexOffsets/outgoing already encode the exact embedding incidence, so
     * no extra search structure is required here.
     */
    if (!facts.hasBoundaryContact)
    {
        if (
            topology.vertexOffsets.length <
            topology.vertexCount + 1
        )
        {
            return false;
        }

        foreach (vertex; 0 .. topology.vertexCount)
        {
            const size_t begin =
                topology.vertexOffsets[vertex];

            const size_t end =
                topology.vertexOffsets[
                    vertex + 1
                ];

            if (
                begin > end ||
                end > topology.outgoing.length
            )
            {
                return false;
            }

            ubyte incidentOperandMask = 0;

            foreach (position; begin .. end)
            {
                const size_t halfEdgeIndex =
                    topology.outgoing[
                        position
                    ];

                if (
                    halfEdgeIndex >=
                    topology.halfEdges.length
                )
                {
                    return false;
                }

                const size_t arrangementEdgeIndex =
                    topology.halfEdges[
                        halfEdgeIndex
                    ].arrangementEdge;

                if (
                    arrangementEdgeIndex >=
                    topology.arrangementEdgeCount
                )
                {
                    return false;
                }

                incidentOperandMask |=
                    topology.arrangementEdges[
                        arrangementEdgeIndex
                    ].operandMask;
            }

            if (
                (
                    incidentOperandMask &
                    bothOperands
                ) ==
                bothOperands
            )
            {
                facts.hasBoundaryContact =
                    true;

                break;
            }
        }
    }

    return true;
}


/*
 * Convenience internal orchestration used by tests and by the future public
 * checked wrapper.
 *
 * Geometry validation and topology construction remain centralized in the
 * shared polygon-pair builder.
 */
package(geo)
PolygonPairTopologyStatus tryClassifyPolygonRelationshipInternal(T)(
    scope Polygon2View!T first,
    scope Polygon2View!T second,
    out PolygonRelationshipFactsInternal facts
)
    @safe
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    facts =
        PolygonRelationshipFactsInternal.init;

    ExactPolygonPairTopology!T topology;

    const status =
        tryBuildExactPolygonPairTopology(
            first,
            second,
            topology
        );

    if (status != PolygonPairTopologyStatus.success)
        return status;

    if (
        !reducePolygonRelationship(
            topology,
            facts
        )
    )
    {
        assert(
            false,
            "polygon relationship reducer invariant failure"
        );

        return
            PolygonPairTopologyStatus
                .internalInvariantFailure;
    }

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


    PolygonRelationshipFactsInternal facts;


    /*
     * Empty / empty is a successful computed all-false relationship.
     */
    R[] noRings;

    const G empty =
        G(noRings);

    assert(
        tryClassifyPolygonRelationshipInternal(
            empty,
            empty,
            facts
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(
        facts ==
        PolygonRelationshipFactsInternal.init
    );


    /*
     * One ordinary square.
     */
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


    /*
     * Empty / non-empty.
     */
    assert(
        tryClassifyPolygonRelationshipInternal(
            empty,
            square,
            facts
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(!facts.hasFirstOnlyInterior);
    assert(facts.hasSecondOnlyInterior);
    assert(!facts.hasSharedInterior);
    assert(!facts.hasBoundaryContact);
    assert(!facts.hasBoundaryOverlap);


    /*
     * Non-empty / empty.
     */
    assert(
        tryClassifyPolygonRelationshipInternal(
            square,
            empty,
            facts
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(facts.hasFirstOnlyInterior);
    assert(!facts.hasSecondOnlyInterior);
    assert(!facts.hasSharedInterior);
    assert(!facts.hasBoundaryContact);
    assert(!facts.hasBoundaryOverlap);
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

    PolygonRelationshipFactsInternal facts;


    /*
     * Shared positive-length boundary, no shared interior.
     */
    P[4] leftPoints = [
        P(0, 0),
        P(2, 0),
        P(2, 2),
        P(0, 2),
    ];

    P[4] rightPoints = [
        P(2, 0),
        P(4, 0),
        P(4, 2),
        P(2, 2),
    ];

    R[1] leftRings = [
        R(leftPoints[])
    ];

    R[1] rightRings = [
        R(rightPoints[])
    ];

    assert(
        tryClassifyPolygonRelationshipInternal(
            G(leftRings[]),
            G(rightRings[]),
            facts
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(facts.hasFirstOnlyInterior);
    assert(facts.hasSecondOnlyInterior);
    assert(!facts.hasSharedInterior);
    assert(facts.hasBoundaryContact);
    assert(facts.hasBoundaryOverlap);


    /*
     * Point-only contact.
     */
    P[4] pointTouchPoints = [
        P(2, 2),
        P(4, 2),
        P(4, 4),
        P(2, 4),
    ];

    R[1] pointTouchRings = [
        R(pointTouchPoints[])
    ];

    assert(
        tryClassifyPolygonRelationshipInternal(
            G(leftRings[]),
            G(pointTouchRings[]),
            facts
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(facts.hasFirstOnlyInterior);
    assert(facts.hasSecondOnlyInterior);
    assert(!facts.hasSharedInterior);
    assert(facts.hasBoundaryContact);
    assert(!facts.hasBoundaryOverlap);
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

    PolygonRelationshipFactsInternal facts;


    /*
     * Proper area overlap.
     */
    P[4] firstPoints = [
        P(0, 0),
        P(4, 0),
        P(4, 4),
        P(0, 4),
    ];

    P[4] secondPoints = [
        P(2, 2),
        P(6, 2),
        P(6, 6),
        P(2, 6),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    assert(
        tryClassifyPolygonRelationshipInternal(
            G(firstRings[]),
            G(secondRings[]),
            facts
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(facts.hasFirstOnlyInterior);
    assert(facts.hasSecondOnlyInterior);
    assert(facts.hasSharedInterior);
    assert(facts.hasBoundaryContact);
    assert(!facts.hasBoundaryOverlap);


    /*
     * Identical polygons.
     */
    assert(
        tryClassifyPolygonRelationshipInternal(
            G(firstRings[]),
            G(firstRings[]),
            facts
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(!facts.hasFirstOnlyInterior);
    assert(!facts.hasSecondOnlyInterior);
    assert(facts.hasSharedInterior);
    assert(facts.hasBoundaryContact);
    assert(facts.hasBoundaryOverlap);
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

    PolygonRelationshipFactsInternal facts;


    /*
     * Strict containment.
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

    assert(
        tryClassifyPolygonRelationshipInternal(
            G(outerRings[]),
            G(innerRings[]),
            facts
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(facts.hasFirstOnlyInterior);
    assert(!facts.hasSecondOnlyInterior);
    assert(facts.hasSharedInterior);
    assert(!facts.hasBoundaryContact);
    assert(!facts.hasBoundaryOverlap);


    /*
     * Swap law.
     */
    PolygonRelationshipFactsInternal swapped;

    assert(
        tryClassifyPolygonRelationshipInternal(
            G(innerRings[]),
            G(outerRings[]),
            swapped
        ) ==
            PolygonPairTopologyStatus.success
    );

    assert(
        facts.hasFirstOnlyInterior ==
        swapped.hasSecondOnlyInterior
    );

    assert(
        facts.hasSecondOnlyInterior ==
        swapped.hasFirstOnlyInterior
    );

    assert(
        facts.hasSharedInterior ==
        swapped.hasSharedInterior
    );

    assert(
        facts.hasBoundaryContact ==
        swapped.hasBoundaryContact
    );

    assert(
        facts.hasBoundaryOverlap ==
        swapped.hasBoundaryOverlap
    );
}
