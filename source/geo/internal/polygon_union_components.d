module geo.internal.polygon_union_components;

import geo.internal.exact_coordinate :
    compareExactCoordinates;

import geo.internal.polygon_union_boundary :
    ExactUnionBoundaryCycle;

import geo.internal.polygon_union_embedding :
    ExactArrangementHalfEdge;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    compareExactOverlayPoints,
    orientationExactOverlayPoints;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact classification and component grouping of reconstructed regularized
 * union boundary cycles.
 *
 * Selected union half-edges are oriented with union interior on their left.
 * Therefore:
 *
 * - a counter-clockwise simple cycle is an exterior boundary;
 * - a clockwise simple cycle is a hole boundary.
 *
 * Hole assignment is exact: one hole boundary vertex must lie inside exactly
 * one exterior cycle. No rounded construction coordinate participates.
 */


enum ExactUnionCycleRole : ubyte
{
    exterior,
    hole,
}


enum ExactUnionCyclePointLocation : ubyte
{
    outside,
    boundary,
    inside,
}


struct ExactUnionComponent
{
    size_t exteriorCycle;
    size_t holeCount;
}


/*
 * Exact comparison of one overlay point coordinate.
 */
private int compareExactOverlayX(
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
{
    return
        compareExactCoordinates(
            lhs.xNumerator,
            lhs.denominator,
            rhs.xNumerator,
            rhs.denominator
        );
}


private int compareExactOverlayY(
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
{
    return
        compareExactCoordinates(
            lhs.yNumerator,
            lhs.denominator,
            rhs.yNumerator,
            rhs.denominator
        );
}


/*
 * Exact closed-segment membership after collinearity is already established.
 */
private bool exactOverlayPointWithinSegmentBounds(
    ref const ExactOverlayPoint point,
    ref const ExactOverlayPoint a,
    ref const ExactOverlayPoint b
)
    pure nothrow @safe @nogc
{
    const int pointVsAX =
        compareExactOverlayX(
            point,
            a
        );

    const int pointVsBX =
        compareExactOverlayX(
            point,
            b
        );

    if (
        (
            pointVsAX < 0 &&
            pointVsBX < 0
        ) ||
        (
            pointVsAX > 0 &&
            pointVsBX > 0
        )
    )
    {
        return false;
    }

    const int pointVsAY =
        compareExactOverlayY(
            point,
            a
        );

    const int pointVsBY =
        compareExactOverlayY(
            point,
            b
        );

    return
        !(
            (
                pointVsAY < 0 &&
                pointVsBY < 0
            ) ||
            (
                pointVsAY > 0 &&
                pointVsBY > 0
            )
        );
}


/*
 * Exact even-odd classification of one rational overlay point against one
 * exact boundary cycle.
 *
 * The cycle may be stored clockwise or counter-clockwise.
 *
 * Boundary has precedence. Ray crossing uses only:
 *
 * - exact y-coordinate comparison;
 * - exact rational orientation.
 *
 * No division, epsilon, or floating-point construction is used.
 */
bool tryClassifyExactPointInUnionCycle(
    ref const ExactOverlayPoint query,
    ref const ExactUnionBoundaryCycle cycle,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices,
    out ExactUnionCyclePointLocation location
)
    pure nothrow @safe @nogc
{
    location =
        ExactUnionCyclePointLocation.outside;

    if (
        cycle.edgeCount < 3 ||
        cycle.startHalfEdge >= halfEdges.length ||
        nextSelected.length != halfEdges.length
    )
    {
        return false;
    }

    bool inside = false;

    size_t current =
        cycle.startHalfEdge;

    foreach (step; 0 .. cycle.edgeCount)
    {
        if (current >= halfEdges.length)
            return false;

        const auto edge =
            halfEdges[current];

        if (
            edge.originVertex >= vertices.length ||
            edge.destinationVertex >= vertices.length ||
            edge.originVertex == edge.destinationVertex
        )
        {
            return false;
        }

        const auto a =
            vertices[
                edge.originVertex
            ];

        const auto b =
            vertices[
                edge.destinationVertex
            ];

        const int orientation =
            orientationExactOverlayPoints(
                a,
                b,
                query
            );

        if (
            orientation == 0 &&
            exactOverlayPointWithinSegmentBounds(
                query,
                a,
                b
            )
        )
        {
            location =
                ExactUnionCyclePointLocation.boundary;

            return true;
        }

        const int aVsQueryY =
            compareExactOverlayY(
                a,
                query
            );

        const int bVsQueryY =
            compareExactOverlayY(
                b,
                query
            );

        const bool aAbove =
            aVsQueryY > 0;

        const bool bAbove =
            bVsQueryY > 0;

        if (aAbove != bAbove)
        {
            if (orientation == 0)
            {
                /*
                 * The query shares the crossing y-level and is collinear.
                 * The closed-segment boundary check above would already have
                 * caught an on-segment query.
                 */
                return false;
            }

            const bool edgeGoesUp =
                bVsQueryY >
                aVsQueryY;

            if (
                (orientation > 0) ==
                edgeGoesUp
            )
            {
                inside =
                    !inside;
            }
        }

        const size_t next =
            nextSelected[current];

        if (
            next >= halfEdges.length ||
            halfEdges[next].originVertex !=
                edge.destinationVertex
        )
        {
            return false;
        }

        current =
            next;
    }

    if (
        current != cycle.startHalfEdge
    )
    {
        return false;
    }

    location =
        inside
            ? ExactUnionCyclePointLocation.inside
            : ExactUnionCyclePointLocation.outside;

    return true;
}


/*
 * Classifies one simple interior-left union cycle as exterior or hole.
 *
 * At the exact lexicographically smallest cycle vertex, a valid simple cycle
 * has a non-collinear predecessor/current/successor turn:
 *
 * - positive turn -> CCW -> exterior;
 * - negative turn -> CW  -> hole.
 *
 * The lexicographic extremum avoids relying on a global rational signed-area
 * accumulation solely to determine cycle role.
 */
bool tryClassifyExactUnionCycleRole(
    ref const ExactUnionBoundaryCycle cycle,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices,
    out ExactUnionCycleRole role
)
    pure nothrow @safe @nogc
{
    role =
        ExactUnionCycleRole.exterior;

    if (
        cycle.edgeCount < 3 ||
        cycle.startHalfEdge >= halfEdges.length ||
        nextSelected.length != halfEdges.length
    )
    {
        return false;
    }

    size_t current =
        cycle.startHalfEdge;

    size_t previous =
        size_t.max;

    size_t last =
        size_t.max;

    size_t minimumEdge =
        size_t.max;

    size_t minimumPrevious =
        size_t.max;

    foreach (_; 0 .. cycle.edgeCount)
    {
        if (current >= halfEdges.length)
            return false;

        const auto edge =
            halfEdges[current];

        if (
            edge.originVertex >= vertices.length ||
            edge.destinationVertex >= vertices.length ||
            edge.originVertex == edge.destinationVertex
        )
        {
            return false;
        }

        if (
            minimumEdge == size_t.max ||
            compareExactOverlayPoints(
                vertices[
                    edge.originVertex
                ],
                vertices[
                    halfEdges[
                        minimumEdge
                    ].originVertex
                ]
            ) < 0
        )
        {
            minimumEdge =
                current;

            minimumPrevious =
                previous;
        }

        last =
            current;

        const size_t next =
            nextSelected[current];

        if (
            next >= halfEdges.length ||
            halfEdges[next].originVertex !=
                edge.destinationVertex
        )
        {
            return false;
        }

        previous =
            current;

        current =
            next;
    }

    if (
        current != cycle.startHalfEdge ||
        minimumEdge == size_t.max ||
        last == size_t.max
    )
    {
        return false;
    }

    if (minimumPrevious == size_t.max)
        minimumPrevious = last;

    const auto incoming =
        halfEdges[
            minimumPrevious
        ];

    const auto outgoing =
        halfEdges[
            minimumEdge
        ];

    if (
        incoming.destinationVertex !=
            outgoing.originVertex ||
        incoming.originVertex >= vertices.length ||
        outgoing.destinationVertex >= vertices.length
    )
    {
        return false;
    }

    const int orientation =
        orientationExactOverlayPoints(
            vertices[
                incoming.originVertex
            ],
            vertices[
                outgoing.originVertex
            ],
            vertices[
                outgoing.destinationVertex
            ]
        );

    if (orientation == 0)
        return false;

    role =
        orientation > 0
            ? ExactUnionCycleRole.exterior
            : ExactUnionCycleRole.hole;

    return true;
}


/*
 * Classifies one boundary cycle relative to another using a subject vertex
 * that is not merely a point contact with the reference boundary.
 *
 * Valid simple non-coincident cycles may touch at isolated exact vertices.
 * Therefore the stored/canonical start vertex alone is not a sufficient
 * containment representative. Walk the subject cycle until one vertex is
 * strictly inside or outside the reference.
 *
 * If every subject vertex lies on the reference boundary, the cycles are
 * coincident/degenerate for this stage and the relation is rejected.
 */
private bool tryClassifyExactCycleRelativeToCycle(
    ref const ExactUnionBoundaryCycle subject,
    ref const ExactUnionBoundaryCycle reference,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices,
    out ExactUnionCyclePointLocation location
)
    pure nothrow @safe @nogc
{
    location =
        ExactUnionCyclePointLocation.outside;

    if (
        subject.edgeCount < 3 ||
        subject.startHalfEdge >= halfEdges.length ||
        nextSelected.length != halfEdges.length
    )
    {
        return false;
    }

    size_t current =
        subject.startHalfEdge;

    foreach (_; 0 .. subject.edgeCount)
    {
        if (current >= halfEdges.length)
            return false;

        const auto edge =
            halfEdges[current];

        if (edge.originVertex >= vertices.length)
            return false;

        ExactUnionCyclePointLocation candidate;

        if (
            !tryClassifyExactPointInUnionCycle(
                vertices[
                    edge.originVertex
                ],
                reference,
                halfEdges,
                nextSelected,
                vertices,
                candidate
            )
        )
        {
            return false;
        }

        if (
            candidate !=
            ExactUnionCyclePointLocation.boundary
        )
        {
            location =
                candidate;

            return true;
        }

        const size_t next =
            nextSelected[current];

        if (
            next >= halfEdges.length ||
            halfEdges[next].originVertex !=
                edge.destinationVertex
        )
        {
            return false;
        }

        current =
            next;
    }

    return false;
}


/*
 * Number of other exterior cycles that strictly contain this component's
 * exterior cycle.
 *
 * For a valid non-crossing boundary set, strict containing exteriors form a
 * nesting chain. Point contacts do not increase depth.
 */
private bool tryExactExteriorContainmentDepth(
    size_t componentIndex,
    scope const(ExactUnionComponent)[] components,
    scope const(ExactUnionBoundaryCycle)[] cycles,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices,
    out size_t depth
)
    pure nothrow @safe @nogc
{
    depth = 0;

    if (componentIndex >= components.length)
        return false;

    const size_t subjectCycle =
        components[
            componentIndex
        ].exteriorCycle;

    if (subjectCycle >= cycles.length)
        return false;

    foreach (otherComponent; 0 .. components.length)
    {
        if (otherComponent == componentIndex)
            continue;

        const size_t referenceCycle =
            components[
                otherComponent
            ].exteriorCycle;

        if (referenceCycle >= cycles.length)
            return false;

        ExactUnionCyclePointLocation location;

        if (
            !tryClassifyExactCycleRelativeToCycle(
                cycles[subjectCycle],
                cycles[referenceCycle],
                halfEdges,
                nextSelected,
                vertices,
                location
            )
        )
        {
            return false;
        }

        if (
            location ==
            ExactUnionCyclePointLocation.inside
        )
        {
            ++depth;
        }
    }

    return true;
}


/*
 * Classifies all cycles and groups every hole into exactly one exterior
 * component.
 *
 * Components are created in ascending cycle-index order of their exterior
 * cycles. componentOfCycle maps both an exterior and each of its holes to the
 * same deterministic component index.
 *
 * Exterior cycles may be geometrically nested when a separate union component
 * lies inside a hole of another component. Point-only contacts are likewise
 * allowed.
 *
 * A hole is assigned to the deepest (immediate) exterior cycle that strictly
 * contains it. This is required for nested components whose own holes are also
 * geometrically inside ancestor exterior cycles.
 *
 * After hole assignment, every geometrically nested exterior is checked to
 * lie inside a hole of each containing ancestor component. Thus an exterior
 * cannot redundantly appear inside another component's filled interior.
 */
bool tryBuildExactUnionComponents(
    scope const(ExactUnionBoundaryCycle)[] cycles,
    scope const(ExactArrangementHalfEdge)[] halfEdges,
    scope const(size_t)[] nextSelected,
    scope const(ExactOverlayPoint)[] vertices,
    scope ExactUnionCycleRole[] roles,
    scope size_t[] componentOfCycle,
    scope ExactUnionComponent[] components,
    out size_t componentCount
)
    pure nothrow @safe @nogc
{
    componentCount = 0;

    if (
        roles.length != cycles.length ||
        componentOfCycle.length != cycles.length ||
        components.length < cycles.length
    )
    {
        return false;
    }

    foreach (ref value; componentOfCycle)
        value = size_t.max;


    foreach (cycleIndex; 0 .. cycles.length)
    {
        if (
            !tryClassifyExactUnionCycleRole(
                cycles[cycleIndex],
                halfEdges,
                nextSelected,
                vertices,
                roles[cycleIndex]
            )
        )
        {
            componentCount = 0;
            return false;
        }

        if (
            roles[cycleIndex] ==
            ExactUnionCycleRole.exterior
        )
        {
            components[componentCount] =
                ExactUnionComponent(
                    cycleIndex,
                    0
                );

            componentOfCycle[cycleIndex] =
                componentCount;

            ++componentCount;
        }
    }


    /*
     * Assign every hole to the deepest exterior cycle that strictly contains
     * it.
     *
     * A hole of a nested component may be inside both that component's
     * exterior and one or more ancestor exteriors. The greatest exterior
     * nesting depth identifies the immediate owner.
     */
    foreach (cycleIndex; 0 .. cycles.length)
    {
        if (
            roles[cycleIndex] !=
            ExactUnionCycleRole.hole
        )
        {
            continue;
        }

        size_t containingComponent =
            size_t.max;

        size_t containingDepth = 0;

        bool haveContainingDepth = false;

        foreach (componentIndex; 0 .. componentCount)
        {
            const size_t exteriorCycle =
                components[
                    componentIndex
                ].exteriorCycle;

            ExactUnionCyclePointLocation location;

            if (
                !tryClassifyExactCycleRelativeToCycle(
                    cycles[cycleIndex],
                    cycles[exteriorCycle],
                    halfEdges,
                    nextSelected,
                    vertices,
                    location
                )
            )
            {
                componentCount = 0;
                return false;
            }

            if (
                location !=
                ExactUnionCyclePointLocation.inside
            )
            {
                continue;
            }

            size_t depth;

            if (
                !tryExactExteriorContainmentDepth(
                    componentIndex,
                    components[
                        0 ..
                        componentCount
                    ],
                    cycles,
                    halfEdges,
                    nextSelected,
                    vertices,
                    depth
                )
            )
            {
                componentCount = 0;
                return false;
            }

            if (
                !haveContainingDepth ||
                depth >
                    containingDepth
            )
            {
                containingComponent =
                    componentIndex;

                containingDepth =
                    depth;

                haveContainingDepth =
                    true;
            }
            else if (
                depth ==
                    containingDepth
            )
            {
                /*
                 * Two non-nested exterior components at the same depth cannot
                 * both strictly contain one simple hole boundary.
                 */
                componentCount = 0;
                return false;
            }
        }

        if (
            containingComponent ==
            size_t.max
        )
        {
            componentCount = 0;
            return false;
        }

        componentOfCycle[cycleIndex] =
            containingComponent;

        ++components[
            containingComponent
        ].holeCount;
    }


    /*
     * Validate geometrically nested exterior components against the now-known
     * hole ownership.
     *
     * If inner exterior I is strictly inside outer exterior O, I must lie
     * inside exactly one hole assigned to O. Otherwise I would be embedded in
     * O's filled union interior and could not be a distinct result component.
     */
    foreach (innerComponent; 0 .. componentCount)
    {
        const size_t innerExterior =
            components[
                innerComponent
            ].exteriorCycle;

        foreach (outerComponent; 0 .. componentCount)
        {
            if (
                outerComponent ==
                innerComponent
            )
            {
                continue;
            }

            const size_t outerExterior =
                components[
                    outerComponent
                ].exteriorCycle;

            ExactUnionCyclePointLocation exteriorLocation;

            if (
                !tryClassifyExactCycleRelativeToCycle(
                    cycles[innerExterior],
                    cycles[outerExterior],
                    halfEdges,
                    nextSelected,
                    vertices,
                    exteriorLocation
                )
            )
            {
                componentCount = 0;
                return false;
            }

            if (
                exteriorLocation !=
                ExactUnionCyclePointLocation.inside
            )
            {
                continue;
            }

            size_t containingHoleCount = 0;

            foreach (holeCycle; 0 .. cycles.length)
            {
                if (
                    roles[holeCycle] !=
                        ExactUnionCycleRole.hole ||
                    componentOfCycle[holeCycle] !=
                        outerComponent
                )
                {
                    continue;
                }

                ExactUnionCyclePointLocation holeLocation;

                if (
                    !tryClassifyExactCycleRelativeToCycle(
                        cycles[innerExterior],
                        cycles[holeCycle],
                        halfEdges,
                        nextSelected,
                        vertices,
                        holeLocation
                    )
                )
                {
                    componentCount = 0;
                    return false;
                }

                if (
                    holeLocation ==
                    ExactUnionCyclePointLocation.inside
                )
                {
                    ++containingHoleCount;
                }
            }

            if (containingHoleCount != 1)
            {
                componentCount = 0;
                return false;
            }
        }
    }


    foreach (cycleIndex; 0 .. cycles.length)
    {
        if (
            componentOfCycle[cycleIndex] ==
            size_t.max
        )
        {
            componentCount = 0;
            return false;
        }
    }

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
     * Exact point-in-cycle works for inside / boundary / outside and is
     * independent of ring orientation.
     */
    const ExactOverlayPoint[4] vertices = [
        exactOverlayPoint(P(0, 0)),
        exactOverlayPoint(P(6, 0)),
        exactOverlayPoint(P(6, 6)),
        exactOverlayPoint(P(0, 6)),
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

    ExactUnionCyclePointLocation location;

    auto query =
        exactOverlayPoint(
            P(2, 3)
        );

    assert(
        tryClassifyExactPointInUnionCycle(
            query,
            cycle,
            halfEdges[],
            nextSelected[],
            vertices[],
            location
        )
    );

    assert(
        location ==
        ExactUnionCyclePointLocation.inside
    );

    query =
        exactOverlayPoint(
            P(6, 3)
        );

    assert(
        tryClassifyExactPointInUnionCycle(
            query,
            cycle,
            halfEdges[],
            nextSelected[],
            vertices[],
            location
        )
    );

    assert(
        location ==
        ExactUnionCyclePointLocation.boundary
    );

    query =
        exactOverlayPoint(
            P(8, 3)
        );

    assert(
        tryClassifyExactPointInUnionCycle(
            query,
            cycle,
            halfEdges[],
            nextSelected[],
            vertices[],
            location
        )
    );

    assert(
        location ==
        ExactUnionCyclePointLocation.outside
    );
}


@safe unittest
{
    import geo.internal.intersection_exact :
        ExactProperIntersection,
        tryProperIntersectionExact;

    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    import geo.point :
        Point2;

    import geo.segment :
        Segment2;

    alias P = Point2!int;
    alias S = Segment2!int;


    /*
     * A non-binary rational query point (2/3, 2/3) is classified directly
     * against an exact cycle without materialization.
     */
    const S first =
        S(
            P(0, 0),
            P(2, 2)
        );

    const S second =
        S(
            P(0, 1),
            P(2, 0)
        );

    ExactProperIntersection intersection;

    assert(
        tryProperIntersectionExact(
            first,
            second,
            intersection
        )
    );

    const ExactOverlayPoint[3] vertices = [
        exactOverlayPoint(P(0, 0)),
        exactOverlayPoint(P(3, 0)),
        exactOverlayPoint(P(0, 3)),
    ];

    ExactArrangementHalfEdge[3] halfEdges;

    halfEdges[0].originVertex = 0;
    halfEdges[0].destinationVertex = 1;

    halfEdges[1].originVertex = 1;
    halfEdges[1].destinationVertex = 2;

    halfEdges[2].originVertex = 2;
    halfEdges[2].destinationVertex = 0;

    const size_t[3] nextSelected = [
        1,
        2,
        0,
    ];

    const ExactUnionBoundaryCycle cycle =
        ExactUnionBoundaryCycle(
            0,
            3
        );

    const auto query =
        exactOverlayPoint(
            intersection
        );

    ExactUnionCyclePointLocation location;

    assert(
        tryClassifyExactPointInUnionCycle(
            query,
            cycle,
            halfEdges[],
            nextSelected[],
            vertices[],
            location
        )
    );

    assert(
        location ==
        ExactUnionCyclePointLocation.inside
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
     * One CCW exterior and one CW hole become one component with one hole.
     */
    const ExactOverlayPoint[8] vertices = [
        exactOverlayPoint(P(0, 0)),
        exactOverlayPoint(P(10, 0)),
        exactOverlayPoint(P(10, 10)),
        exactOverlayPoint(P(0, 10)),

        exactOverlayPoint(P(2, 2)),
        exactOverlayPoint(P(2, 4)),
        exactOverlayPoint(P(4, 4)),
        exactOverlayPoint(P(4, 2)),
    ];

    ExactArrangementHalfEdge[8] halfEdges;

    foreach (i; 0 .. 4)
    {
        halfEdges[i].originVertex =
            i;

        halfEdges[i].destinationVertex =
            (i + 1) % 4;
    }

    foreach (i; 0 .. 4)
    {
        halfEdges[4 + i].originVertex =
            4 + i;

        halfEdges[4 + i].destinationVertex =
            4 + ((i + 1) % 4);
    }

    const size_t[8] nextSelected = [
        1, 2, 3, 0,
        5, 6, 7, 4,
    ];

    const ExactUnionBoundaryCycle[2] cycles = [
        ExactUnionBoundaryCycle(0, 4),
        ExactUnionBoundaryCycle(4, 4),
    ];

    ExactUnionCycleRole[2] roles;
    size_t[2] componentOfCycle;
    ExactUnionComponent[2] components;
    size_t componentCount;

    assert(
        tryBuildExactUnionComponents(
            cycles[],
            halfEdges[],
            nextSelected[],
            vertices[],
            roles[],
            componentOfCycle[],
            components[],
            componentCount
        )
    );

    assert(componentCount == 1);

    assert(
        roles[0] ==
        ExactUnionCycleRole.exterior
    );

    assert(
        roles[1] ==
        ExactUnionCycleRole.hole
    );

    assert(componentOfCycle[0] == 0);
    assert(componentOfCycle[1] == 0);

    assert(components[0].exteriorCycle == 0);
    assert(components[0].holeCount == 1);
}


@safe unittest
{
    import geo.internal.polygon_union_exact :
        exactOverlayPoint;

    import geo.point :
        Point2;

    alias P = Point2!int;


    /*
     * Two CCW exterior components may touch at one exact vertex and remain
     * two deterministic components.
     */
    const ExactOverlayPoint[7] vertices = [
        exactOverlayPoint(P(0, 0)),
        exactOverlayPoint(P(2, 0)),
        exactOverlayPoint(P(2, 2)),
        exactOverlayPoint(P(0, 2)),

        exactOverlayPoint(P(4, 2)),
        exactOverlayPoint(P(4, 4)),
        exactOverlayPoint(P(2, 4)),
    ];

    ExactArrangementHalfEdge[8] halfEdges;

    halfEdges[0].originVertex = 0;
    halfEdges[0].destinationVertex = 1;

    halfEdges[1].originVertex = 1;
    halfEdges[1].destinationVertex = 2;

    halfEdges[2].originVertex = 2;
    halfEdges[2].destinationVertex = 3;

    halfEdges[3].originVertex = 3;
    halfEdges[3].destinationVertex = 0;

    halfEdges[4].originVertex = 2;
    halfEdges[4].destinationVertex = 4;

    halfEdges[5].originVertex = 4;
    halfEdges[5].destinationVertex = 5;

    halfEdges[6].originVertex = 5;
    halfEdges[6].destinationVertex = 6;

    halfEdges[7].originVertex = 6;
    halfEdges[7].destinationVertex = 2;

    const size_t[8] nextSelected = [
        1, 2, 3, 0,
        5, 6, 7, 4,
    ];

    const ExactUnionBoundaryCycle[2] cycles = [
        ExactUnionBoundaryCycle(0, 4),
        ExactUnionBoundaryCycle(4, 4),
    ];

    ExactUnionCycleRole[2] roles;
    size_t[2] componentOfCycle;
    ExactUnionComponent[2] components;
    size_t componentCount;

    assert(
        tryBuildExactUnionComponents(
            cycles[],
            halfEdges[],
            nextSelected[],
            vertices[],
            roles[],
            componentOfCycle[],
            components[],
            componentCount
        )
    );

    assert(componentCount == 2);

    assert(
        roles[0] ==
        ExactUnionCycleRole.exterior
    );

    assert(
        roles[1] ==
        ExactUnionCycleRole.exterior
    );

    assert(componentOfCycle[0] == 0);
    assert(componentOfCycle[1] == 1);

    assert(components[0].holeCount == 0);
    assert(components[1].holeCount == 0);
}
