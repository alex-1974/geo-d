/*
 * Research-only external differential probe for Issue #49.
 *
 * Real Polygon2View inputs are passed through the complete duplicated
 * Boolean-overlay P1 research orchestration and compared with an independent
 * CGAL/EPECK regularized-set oracle.
 *
 * This executable is not part of the package or ordinary CI.
 */
module geo.boolean_overlay_cgal_reference_probe;

import geo.internal.boolean_overlay_p1_research :
    BooleanOverlayP1ResearchStatus,
    BooleanOverlayResearchOperation,
    tryBooleanOverlayP1ResearchInternal;

import geo.internal.polygon_union_result :
    PolygonUnionOwnedResultInternal;

import geo.linear_ring_view :
    LinearRing2View;

import geo.point :
    Point2;

import geo.point_in_polygon :
    PointPolygonLocation,
    tryClassifyPointInPolygon;

import geo.polygon_view :
    Polygon2View;

import std.math :
    fabs;

import std.stdio :
    write,
    writefln;


private string operationName(
    BooleanOverlayResearchOperation operation
)
    pure nothrow @safe @nogc
{
    final switch (operation)
    {
        case BooleanOverlayResearchOperation.unionSet:
            return "union";

        case BooleanOverlayResearchOperation.intersection:
            return "intersection";

        case BooleanOverlayResearchOperation.differenceAB:
            return "difference_ab";

        case BooleanOverlayResearchOperation.differenceBA:
            return "difference_ba";

        case BooleanOverlayResearchOperation.symmetricDifference:
            return "symmetric_difference";
    }
}


private char locationCode(
    PointPolygonLocation location
)
    pure nothrow @safe @nogc
{
    final switch (location)
    {
        case PointPolygonLocation.outside:
            return 'O';

        case PointPolygonLocation.boundary:
            return 'B';

        case PointPolygonLocation.inside:
            return 'I';
    }
}


private double twiceRingArea(
    LinearRing2View!double ring
)
    pure nothrow @safe @nogc
{
    double sum = 0.0;

    foreach (i; 0 .. ring.length)
    {
        const auto a =
            ring[i];

        const auto b =
            ring[
                (i + 1) %
                ring.length
            ];

        sum +=
            a.x * b.y -
            a.y * b.x;
    }

    return sum;
}


private long resultTwiceArea(
    ref const PolygonUnionOwnedResultInternal result
)
    pure nothrow @safe @nogc
{
    double total = 0.0;

    foreach (
        componentIndex;
        0 ..
        result.componentCount
    )
    {
        const auto component =
            result.component(
                componentIndex
            );

        total +=
            fabs(
                twiceRingArea(
                    component.exterior
                )
            );

        foreach (
            holeIndex;
            0 ..
            component.holeCount
        )
        {
            total -=
                fabs(
                    twiceRingArea(
                        component.hole(
                            holeIndex
                        )
                    )
                );
        }
    }

    const long integral =
        cast(long) total;

    assert(
        total ==
        cast(double) integral
    );

    return integral;
}


private void emitOperation(
    string name,
    BooleanOverlayResearchOperation operation,
    int expectedComponents,
    int expectedHoles,
    scope Polygon2View!int first,
    scope Polygon2View!int second
)
{
    PolygonUnionOwnedResultInternal result;

    const auto status =
        tryBooleanOverlayP1ResearchInternal(
            first,
            second,
            operation,
            result
        );

    if (
        status !=
        BooleanOverlayP1ResearchStatus.success
    )
    {
        writefln(
            "%s|op=%s|status=%s",
            name,
            operationName(operation),
            status
        );

        return;
    }

    size_t holeCount = 0;

    foreach (
        componentIndex;
        0 ..
        result.componentCount
    )
    {
        holeCount +=
            result.component(
                componentIndex
            ).holeCount;
    }

    /*
     * geo-d representation expectations are checked independently of CGAL.
     *
     * CGAL may encode the same regularized point set as one relatively-simple
     * Polygon_with_holes where geo-d deliberately retains multiple components
     * meeting only at isolated vertices.
     */
    if (
        expectedComponents < 0 ||
        expectedHoles < 0 ||
        result.componentCount !=
            cast(size_t) expectedComponents ||
        holeCount !=
            cast(size_t) expectedHoles
    )
    {
        writefln(
            "%s|op=%s|structure_mismatch=" ~
            "components:%s/%s,holes:%s/%s",
            name,
            operationName(operation),
            result.componentCount,
            expectedComponents,
            holeCount,
            expectedHoles
        );

        throw new Exception(
            "unexpected geo-d Boolean-overlay result structure"
        );
    }

    write(
        name,
        "|op=",
        operationName(operation),
        "|geo_components=",
        result.componentCount,
        "|holes=",
        holeCount,
        "|area2=",
        resultTwiceArea(result),
        "|grid="
    );


    /*
     * Representation-independent result-set signature.
     *
     * The retained integer grid contains exterior, interior and boundary
     * samples for the complete initial differential corpus.
     */
    foreach (y; -2 .. 13)
    {
        foreach (x; -1 .. 16)
        {
            bool boundary = false;
            bool inside = false;

            foreach (
                componentIndex;
                0 ..
                result.componentCount
            )
            {
                PointPolygonLocation location;

                const bool classified =
                    tryClassifyPointInPolygon(
                        result.component(
                            componentIndex
                        ),
                        Point2!double(
                            cast(double) x,
                            cast(double) y
                        ),
                        location
                    );

                if (!classified)
                {
                    throw new Exception(
                        "Boolean-overlay result point classification failed"
                    );
                }

                if (
                    location ==
                    PointPolygonLocation.boundary
                )
                {
                    boundary = true;
                }
                else if (
                    location ==
                    PointPolygonLocation.inside
                )
                {
                    inside = true;
                }
            }

            const auto location =
                boundary
                    ? PointPolygonLocation.boundary
                    : (
                        inside
                            ? PointPolygonLocation.inside
                            : PointPolygonLocation.outside
                    );

            write(
                locationCode(
                    location
                )
            );
        }
    }

    write("\n");
}


private PolygonUnionOwnedResultInternal requireOverlaySuccess(
    string fixtureName,
    string lawName,
    scope Polygon2View!int first,
    scope Polygon2View!int second,
    BooleanOverlayResearchOperation operation
)
{
    PolygonUnionOwnedResultInternal result;

    const auto status =
        tryBooleanOverlayP1ResearchInternal(
            first,
            second,
            operation,
            result
        );

    if (
        status !=
        BooleanOverlayP1ResearchStatus.success
    )
    {
        throw new Exception(
            fixtureName ~
            ": algebraic law '" ~
            lawName ~
            "' returned non-success status"
        );
    }

    return result;
}


private bool canonicalResultsEqual(
    ref const PolygonUnionOwnedResultInternal first,
    ref const PolygonUnionOwnedResultInternal second
)
    pure nothrow @safe @nogc
{
    if (
        first.componentCount != second.componentCount ||
        first.ringCount != second.ringCount ||
        first.pointCount != second.pointCount
    )
    {
        return false;
    }

    foreach (
        componentIndex;
        0 ..
        first.componentCount
    )
    {
        const auto firstComponent =
            first.component(
                componentIndex
            );

        const auto secondComponent =
            second.component(
                componentIndex
            );

        if (
            firstComponent.length !=
            secondComponent.length
        )
        {
            return false;
        }

        foreach (
            ringIndex;
            0 ..
            firstComponent.length
        )
        {
            const auto firstRing =
                firstComponent[
                    ringIndex
                ];

            const auto secondRing =
                secondComponent[
                    ringIndex
                ];

            if (
                firstRing.length !=
                secondRing.length
            )
            {
                return false;
            }

            foreach (
                pointIndex;
                0 ..
                firstRing.length
            )
            {
                const auto firstPoint =
                    firstRing[
                        pointIndex
                    ];

                const auto secondPoint =
                    secondRing[
                        pointIndex
                    ];

                if (
                    firstPoint.x != secondPoint.x ||
                    firstPoint.y != secondPoint.y
                )
                {
                    return false;
                }
            }
        }
    }

    return true;
}


private void requireCanonicalEquality(
    string fixtureName,
    string lawName,
    ref const PolygonUnionOwnedResultInternal first,
    ref const PolygonUnionOwnedResultInternal second
)
{
    if (
        !canonicalResultsEqual(
            first,
            second
        )
    )
    {
        throw new Exception(
            fixtureName ~
            ": algebraic law failed: " ~
            lawName
        );
    }
}


private void requireEmptyResult(
    string fixtureName,
    string lawName,
    ref const PolygonUnionOwnedResultInternal result
)
{
    if (
        result.componentCount != 0 ||
        result.ringCount != 0 ||
        result.pointCount != 0
    )
    {
        throw new Exception(
            fixtureName ~
            ": algebraic law expected empty result: " ~
            lawName
        );
    }
}


private bool resultContainsPoint(
    ref const PolygonUnionOwnedResultInternal result,
    Point2!double point
)
{
    foreach (
        componentIndex;
        0 ..
        result.componentCount
    )
    {
        PointPolygonLocation location;

        const bool classified =
            tryClassifyPointInPolygon(
                result.component(
                    componentIndex
                ),
                point,
                location
            );

        if (!classified)
        {
            throw new Exception(
                "cross-operation point classification failed"
            );
        }

        if (
            location !=
            PointPolygonLocation.outside
        )
        {
            return true;
        }
    }

    return false;
}


private void checkCrossOperationIdentity(
    string fixtureName,
    scope Polygon2View!int first,
    scope Polygon2View!int second
)
{
    alias Op =
        BooleanOverlayResearchOperation;

    /*
     * Regularized Boolean-set identity:
     *
     *     A xor B = (A minus B) union (B minus A)
     *
     * The research entry point currently accepts one Polygon2View per
     * operand, not an arbitrary polygon set. Therefore the right-hand side
     * is checked as the set union of the two independently produced
     * difference results.
     *
     * Evidence consists of:
     *
     * - additive area equality; and
     * - membership equality on a half-unit grid covering the complete
     *   retained topological corpus.
     *
     * The independent CGAL/EPECK oracle checks the same identity exactly.
     */
    auto xorResult =
        requireOverlaySuccess(
            fixtureName,
            "cross-operation xor",
            first,
            second,
            Op.symmetricDifference
        );

    auto differenceAB =
        requireOverlaySuccess(
            fixtureName,
            "cross-operation difference AB",
            first,
            second,
            Op.differenceAB
        );

    auto differenceBA =
        requireOverlaySuccess(
            fixtureName,
            "cross-operation difference BA",
            first,
            second,
            Op.differenceBA
        );

    const long xorArea =
        resultTwiceArea(
            xorResult
        );

    const long differenceArea =
        resultTwiceArea(
            differenceAB
        ) +
        resultTwiceArea(
            differenceBA
        );

    if (
        xorArea !=
        differenceArea
    )
    {
        throw new Exception(
            fixtureName ~
            ": cross-operation area identity failed"
        );
    }

    /*
     * Half-unit coordinates:
     *
     * x = -1 .. 16
     * y = -2 .. 13
     *
     * Boundary and interior both mean membership in the regularized closed
     * result set. This intentionally avoids treating representation-specific
     * boundary decomposition as set semantics.
     */
    foreach (y2; -4 .. 27)
    {
        foreach (x2; -2 .. 33)
        {
            const auto point =
                Point2!double(
                    cast(double) x2 / 2.0,
                    cast(double) y2 / 2.0
                );

            const bool lhs =
                resultContainsPoint(
                    xorResult,
                    point
                );

            const bool rhs =
                resultContainsPoint(
                    differenceAB,
                    point
                ) ||
                resultContainsPoint(
                    differenceBA,
                    point
                );

            if (lhs != rhs)
            {
                throw new Exception(
                    fixtureName ~
                    ": cross-operation set-membership identity failed"
                );
            }
        }
    }
}


private void checkAlgebraicLaws(
    string fixtureName,
    scope Polygon2View!int first,
    scope Polygon2View!int second
)
{
    alias Op =
        BooleanOverlayResearchOperation;

    const auto empty =
        Polygon2View!int.init;

    /*
     * Canonical representatives of A and B.
     *
     * The empty-input differential fixtures independently establish the
     * regularized union identity used here.
     */
    auto canonicalA =
        requireOverlaySuccess(
            fixtureName,
            "canonical A",
            first,
            empty,
            Op.unionSet
        );

    auto canonicalB =
        requireOverlaySuccess(
            fixtureName,
            "canonical B",
            second,
            empty,
            Op.unionSet
        );


    /*
     * Intersection:
     *
     * A intersect B = B intersect A
     * A intersect A = A
     * A intersect empty = empty
     */
    auto intersectionAB =
        requireOverlaySuccess(
            fixtureName,
            "intersection commutativity AB",
            first,
            second,
            Op.intersection
        );

    auto intersectionBA =
        requireOverlaySuccess(
            fixtureName,
            "intersection commutativity BA",
            second,
            first,
            Op.intersection
        );

    requireCanonicalEquality(
        fixtureName,
        "A intersect B = B intersect A",
        intersectionAB,
        intersectionBA
    );

    auto intersectionAA =
        requireOverlaySuccess(
            fixtureName,
            "intersection idempotence A",
            first,
            first,
            Op.intersection
        );

    requireCanonicalEquality(
        fixtureName,
        "A intersect A = A",
        intersectionAA,
        canonicalA
    );

    auto intersectionBB =
        requireOverlaySuccess(
            fixtureName,
            "intersection idempotence B",
            second,
            second,
            Op.intersection
        );

    requireCanonicalEquality(
        fixtureName,
        "B intersect B = B",
        intersectionBB,
        canonicalB
    );

    auto intersectionEmpty =
        requireOverlaySuccess(
            fixtureName,
            "intersection empty",
            first,
            empty,
            Op.intersection
        );

    requireEmptyResult(
        fixtureName,
        "A intersect empty = empty",
        intersectionEmpty
    );


    /*
     * Difference:
     *
     * A minus A = empty
     * A minus empty = A
     * empty minus A = empty
     *
     * Swapping operands is not an invariance. Instead verify that the
     * direction-specific operation spelling maps consistently:
     *
     * differenceAB(A,B) = differenceBA(B,A)
     */
    auto differenceAA =
        requireOverlaySuccess(
            fixtureName,
            "difference idempotence A",
            first,
            first,
            Op.differenceAB
        );

    requireEmptyResult(
        fixtureName,
        "A minus A = empty",
        differenceAA
    );

    auto differenceAEmpty =
        requireOverlaySuccess(
            fixtureName,
            "difference A-empty",
            first,
            empty,
            Op.differenceAB
        );

    requireCanonicalEquality(
        fixtureName,
        "A minus empty = A",
        differenceAEmpty,
        canonicalA
    );

    auto differenceEmptyA =
        requireOverlaySuccess(
            fixtureName,
            "difference empty-A",
            empty,
            first,
            Op.differenceAB
        );

    requireEmptyResult(
        fixtureName,
        "empty minus A = empty",
        differenceEmptyA
    );

    auto differenceAB =
        requireOverlaySuccess(
            fixtureName,
            "difference AB",
            first,
            second,
            Op.differenceAB
        );

    auto swappedDifferenceBA =
        requireOverlaySuccess(
            fixtureName,
            "swapped difference BA",
            second,
            first,
            Op.differenceBA
        );

    requireCanonicalEquality(
        fixtureName,
        "differenceAB(A,B) = differenceBA(B,A)",
        differenceAB,
        swappedDifferenceBA
    );


    /*
     * Symmetric difference:
     *
     * A xor B = B xor A
     * A xor A = empty
     * A xor empty = A
     */
    auto xorAB =
        requireOverlaySuccess(
            fixtureName,
            "xor commutativity AB",
            first,
            second,
            Op.symmetricDifference
        );

    auto xorBA =
        requireOverlaySuccess(
            fixtureName,
            "xor commutativity BA",
            second,
            first,
            Op.symmetricDifference
        );

    requireCanonicalEquality(
        fixtureName,
        "A xor B = B xor A",
        xorAB,
        xorBA
    );

    auto xorAA =
        requireOverlaySuccess(
            fixtureName,
            "xor idempotence A",
            first,
            first,
            Op.symmetricDifference
        );

    requireEmptyResult(
        fixtureName,
        "A xor A = empty",
        xorAA
    );

    auto xorAEmpty =
        requireOverlaySuccess(
            fixtureName,
            "xor empty identity",
            first,
            empty,
            Op.symmetricDifference
        );

    requireCanonicalEquality(
        fixtureName,
        "A xor empty = A",
        xorAEmpty,
        canonicalA
    );


    /*
     * Union is already the accepted production operation, but checking its
     * commutative canonical output here makes the common Boolean-family
     * canonicalization assumption executable.
     */
    auto unionAB =
        requireOverlaySuccess(
            fixtureName,
            "union commutativity AB",
            first,
            second,
            Op.unionSet
        );

    auto unionBA =
        requireOverlaySuccess(
            fixtureName,
            "union commutativity BA",
            second,
            first,
            Op.unionSet
        );

    requireCanonicalEquality(
        fixtureName,
        "A union B = B union A",
        unionAB,
        unionBA
    );
}


private void emitCase(
    string name,
    scope const(int)[] expectedComponents,
    scope const(int)[] expectedHoles,
    scope Polygon2View!int first,
    scope Polygon2View!int second
)
{
    checkCrossOperationIdentity(
        name,
        first,
        second
    );

    checkAlgebraicLaws(
        name,
        first,
        second
    );

    const BooleanOverlayResearchOperation[5] operations = [
        BooleanOverlayResearchOperation.unionSet,
        BooleanOverlayResearchOperation.intersection,
        BooleanOverlayResearchOperation.differenceAB,
        BooleanOverlayResearchOperation.differenceBA,
        BooleanOverlayResearchOperation.symmetricDifference,
    ];

    if (
        expectedComponents.length != operations.length ||
        expectedHoles.length != operations.length
    )
    {
        throw new Exception(
            "invalid Boolean-overlay expected-structure matrix"
        );
    }

    foreach (operationIndex, operation; operations)
    {
        emitOperation(
            name,
            operation,
            expectedComponents[
                operationIndex
            ],
            expectedHoles[
                operationIndex
            ],
            first,
            second
        );
    }
}


private void disjoint()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] firstPoints = [
        P(0, 0),
        P(4, 0),
        P(4, 4),
        P(0, 4),
    ];

    P[4] secondPoints = [
        P(10, 0),
        P(14, 0),
        P(14, 4),
        P(10, 4),
    ];

    R[1] firstRings = [R(firstPoints[])];
    R[1] secondRings = [R(secondPoints[])];

    emitCase(
        "disjoint",
        [2, 0, 1, 1, 2],
        [0, 0, 0, 0, 0],
        G(firstRings[]),
        G(secondRings[])
    );
}


private void overlap()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] firstPoints = [
        P(0, 0),
        P(4, 0),
        P(4, 4),
        P(0, 4),
    ];

    P[4] secondPoints = [
        P(2, -1),
        P(6, -1),
        P(6, 3),
        P(2, 3),
    ];

    R[1] firstRings = [R(firstPoints[])];
    R[1] secondRings = [R(secondPoints[])];

    emitCase(
        "overlap",
        [1, 1, 1, 1, 2],
        [0, 0, 0, 0, 0],
        G(firstRings[]),
        G(secondRings[])
    );
}


private void containment()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] outer = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(0, 10),
    ];

    P[4] inner = [
        P(2, 2),
        P(4, 2),
        P(4, 4),
        P(2, 4),
    ];

    R[1] outerRings = [R(outer[])];
    R[1] innerRings = [R(inner[])];

    emitCase(
        "containment",
        [1, 1, 1, 0, 1],
        [0, 0, 1, 0, 1],
        G(outerRings[]),
        G(innerRings[])
    );
}


private void identical()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] firstPoints = [
        P(0, 0),
        P(5, 0),
        P(5, 5),
        P(0, 5),
    ];

    P[4] secondPoints = firstPoints;

    R[1] firstRings = [R(firstPoints[])];
    R[1] secondRings = [R(secondPoints[])];

    emitCase(
        "identical",
        [1, 1, 0, 0, 0],
        [0, 0, 0, 0, 0],
        G(firstRings[]),
        G(secondRings[])
    );
}


private void adjacent()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] firstPoints = [
        P(0, 0),
        P(4, 0),
        P(4, 2),
        P(0, 2),
    ];

    P[4] secondPoints = [
        P(4, 0),
        P(8, 0),
        P(8, 2),
        P(4, 2),
    ];

    R[1] firstRings = [R(firstPoints[])];
    R[1] secondRings = [R(secondPoints[])];

    emitCase(
        "adjacent",
        [1, 0, 1, 1, 1],
        [0, 0, 0, 0, 0],
        G(firstRings[]),
        G(secondRings[])
    );
}


private void pointTouch()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] firstPoints = [
        P(0, 0),
        P(2, 0),
        P(2, 2),
        P(0, 2),
    ];

    P[4] secondPoints = [
        P(2, 2),
        P(4, 2),
        P(4, 4),
        P(2, 4),
    ];

    R[1] firstRings = [R(firstPoints[])];
    R[1] secondRings = [R(secondPoints[])];

    emitCase(
        "point_touch",
        [2, 0, 1, 1, 2],
        [0, 0, 0, 0, 0],
        G(firstRings[]),
        G(secondRings[])
    );
}


private void donutFill()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] exterior = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(0, 10),
    ];

    P[4] hole = [
        P(3, 3),
        P(3, 7),
        P(7, 7),
        P(7, 3),
    ];

    P[4] fill = [
        P(3, 3),
        P(7, 3),
        P(7, 7),
        P(3, 7),
    ];

    R[2] donutRings = [
        R(exterior[]),
        R(hole[]),
    ];

    R[1] fillRings = [
        R(fill[])
    ];

    emitCase(
        "donut_fill",
        [1, 0, 1, 1, 1],
        [0, 0, 1, 0, 0],
        G(donutRings[]),
        G(fillRings[])
    );
}


private void donutIsland()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] exterior = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(0, 10),
    ];

    P[4] hole = [
        P(2, 2),
        P(2, 8),
        P(8, 8),
        P(8, 2),
    ];

    P[4] island = [
        P(4, 4),
        P(6, 4),
        P(6, 6),
        P(4, 6),
    ];

    R[2] donutRings = [
        R(exterior[]),
        R(hole[]),
    ];

    R[1] islandRings = [
        R(island[])
    ];

    emitCase(
        "donut_island",
        [2, 0, 1, 1, 2],
        [1, 0, 1, 0, 1],
        G(donutRings[]),
        G(islandRings[])
    );
}


private void plusShape()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] horizontal = [
        P(0, 3),
        P(10, 3),
        P(10, 5),
        P(0, 5),
    ];

    P[4] vertical = [
        P(4, 0),
        P(6, 0),
        P(6, 8),
        P(4, 8),
    ];

    R[1] horizontalRings = [
        R(horizontal[])
    ];

    R[1] verticalRings = [
        R(vertical[])
    ];

    emitCase(
        "plus",
        [1, 1, 2, 2, 4],
        [0, 0, 0, 0, 0],
        G(horizontalRings[]),
        G(verticalRings[])
    );
}


private void emptyFirst()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] points = [
        P(1, 1),
        P(5, 1),
        P(5, 5),
        P(1, 5),
    ];

    R[1] rings = [
        R(points[])
    ];

    emitCase(
        "empty_first",
        [1, 0, 0, 1, 1],
        [0, 0, 0, 0, 0],
        G.init,
        G(rings[])
    );
}


private void emptySecond()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] points = [
        P(1, 1),
        P(5, 1),
        P(5, 5),
        P(1, 5),
    ];

    R[1] rings = [
        R(points[])
    ];

    emitCase(
        "empty_second",
        [1, 0, 1, 0, 1],
        [0, 0, 0, 0, 0],
        G(rings[]),
        G.init
    );
}


private void bothEmpty()
{
    alias G = Polygon2View!int;

    emitCase(
        "both_empty",
        [0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0],
        G.init,
        G.init
    );
}


private void multiplePointContacts()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    /*
     * A is the square x=[0,4], y=[0,4].
     *
     * B remains entirely on or to the right of x=4 and touches A only at
     * (4,1) and (4,3). No edge segment is shared and the interiors are
     * disjoint.
     */
    P[4] firstPoints = [
        P(0, 0),
        P(4, 0),
        P(4, 4),
        P(0, 4),
    ];

    P[8] secondPoints = [
        P(4, 1),
        P(6, 0),
        P(8, 0),
        P(8, 4),
        P(6, 4),
        P(4, 3),
        P(6, 3),
        P(6, 1),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    emitCase(
        "multiple_point_contacts",
        [2, 0, 1, 1, 2],
        [0, 0, 0, 0, 0],
        G(firstRings[]),
        G(secondRings[])
    );
}


private void partialCollinearOverlap()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    /*
     * A occupies y=[0,4], B occupies y=[4,8].
     *
     * Their boundaries overlap collinearly only on the proper subsegment
     * x=[2,6], y=4. Their interiors are disjoint and lie on opposite sides
     * of the shared boundary segment.
     */
    P[4] firstPoints = [
        P(0, 0),
        P(6, 0),
        P(6, 4),
        P(0, 4),
    ];

    P[4] secondPoints = [
        P(2, 4),
        P(8, 4),
        P(8, 8),
        P(2, 8),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    emitCase(
        "partial_collinear_overlap",
        [1, 0, 1, 1, 1],
        [0, 0, 0, 0, 0],
        G(firstRings[]),
        G(secondRings[])
    );
}


private void tJunctionContact()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    /*
     * The triangle vertex (3,4) lies strictly inside the top source edge of
     * the rectangle. The rectangle edge must therefore be noded at that
     * vertex. The interiors remain disjoint and there is no shared edge.
     */
    P[4] firstPoints = [
        P(0, 0),
        P(6, 0),
        P(6, 4),
        P(0, 4),
    ];

    P[3] secondPoints = [
        P(3, 4),
        P(5, 7),
        P(1, 7),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    emitCase(
        "t_junction_contact",
        [2, 0, 1, 1, 2],
        [0, 0, 0, 0, 0],
        G(firstRings[]),
        G(secondRings[])
    );
}


private void holeBoundaryCrossing()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    /*
     * A is an outer square with the square hole [3,7] x [3,7].
     *
     * B crosses the lower hole boundary y=3: its lower part overlaps A while
     * its upper part lies inside the hole. This therefore exercises real
     * noding and Boolean classification across an interior-ring boundary.
     */
    P[4] exterior = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(0, 10),
    ];

    P[4] hole = [
        P(3, 3),
        P(3, 7),
        P(7, 7),
        P(7, 3),
    ];

    P[4] crossing = [
        P(4, 1),
        P(6, 1),
        P(6, 5),
        P(4, 5),
    ];

    R[2] donutRings = [
        R(exterior[]),
        R(hole[]),
    ];

    R[1] crossingRings = [
        R(crossing[])
    ];

    emitCase(
        "hole_boundary_crossing",
        [1, 1, 1, 1, 2],
        [1, 0, 1, 0, 1],
        G(donutRings[]),
        G(crossingRings[])
    );
}


private bool resultContainsVertex(
    ref const PolygonUnionOwnedResultInternal result,
    Point2!double expected
)
    pure nothrow @safe @nogc
{
    foreach (
        componentIndex;
        0 ..
        result.componentCount
    )
    {
        const auto component =
            result.component(
                componentIndex
            );

        foreach (
            ringIndex;
            0 ..
            component.length
        )
        {
            const auto ring =
                component[
                    ringIndex
                ];

            foreach (
                pointIndex;
                0 ..
                ring.length
            )
            {
                if (
                    ring[
                        pointIndex
                    ] ==
                    expected
                )
                {
                    return true;
                }
            }
        }
    }

    return false;
}


private void distinctExactEventsStatusMatrix()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    alias Status =
        BooleanOverlayP1ResearchStatus;

    alias Op =
        BooleanOverlayResearchOperation;

    /*
     * Reuse the established exact event-ordering geometry from
     * intersection_exact.d.
     *
     * A contains the source boundary edge:
     *
     *     (0,0) -> (10,0)
     *
     * B contains, in one valid triangle, two crossing segments with one
     * shared apex:
     *
     *     (0,-1) -> (1,2)   crosses y=0 at x=1/3
     *     (0,-4) -> (1,2)   crosses y=0 at x=2/3
     *
     * This preserves the established 1/3 versus 2/3 exact-event ordering
     * while embedding both events in one valid polygon boundary.
     *
     * The two exact overlay events are distinct and exactly ordered. Unlike
     * the separate collision fixture, their correctly rounded binary64
     * coordinates also remain distinct.
     */
    P[4] firstPoints = [
        P(0, 0),
        P(10, 0),
        P(11, 3),
        P(-1, 3),
    ];

    P[3] secondPoints = [
        P(0, -1),
        P(0, -4),
        P(1, 2),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    const G first =
        G(firstRings[]);

    const G second =
        G(secondRings[]);

    const Op[5] operations = [
        Op.unionSet,
        Op.intersection,
        Op.differenceAB,
        Op.differenceBA,
        Op.symmetricDifference,
    ];

    enum double roundedOneThird =
        0x1.5555555555555p-2;

    enum double roundedTwoThirds =
        0x1.5555555555555p-1;

    static assert(
        roundedOneThird !=
        roundedTwoThirds
    );

    foreach (operation; operations)
    {
        PolygonUnionOwnedResultInternal result;

        const auto status =
            tryBooleanOverlayP1ResearchInternal(
                first,
                second,
                operation,
                result
            );

        if (status != Status.success)
        {
            writefln(
                "distinct_exact_events|op=%s|unexpected_status=%s",
                operationName(operation),
                status
            );

            throw new Exception(
                "distinct exact event status matrix expected success"
            );
        }

        /*
         * Both exact crossing events participate in every regularized Boolean
         * boundary for this geometry. Successful materialization must retain
         * them as two different result vertices.
         */
        const bool hasOneThird =
            resultContainsVertex(
                result,
                Point2!double(
                    roundedOneThird,
                    0.0
                )
            );

        const bool hasTwoThirds =
            resultContainsVertex(
                result,
                Point2!double(
                    roundedTwoThirds,
                    0.0
                )
            );

        if (
            !hasOneThird ||
            !hasTwoThirds
        )
        {
            writefln(
                "distinct_exact_events|op=%s|one_third=%s|two_thirds=%s|components=%s|rings=%s|points=%s",
                operationName(operation),
                hasOneThird,
                hasTwoThirds,
                result.componentCount,
                result.ringCount,
                result.pointCount
            );

            throw new Exception(
                "distinct exact events were not retained as distinct materialized vertices"
            );
        }
    }
}


private void roundedContactStatusMatrix()
{
    alias P = Point2!long;
    alias R = LinearRing2View!long;
    alias G = Polygon2View!long;

    alias Status =
        BooleanOverlayP1ResearchStatus;

    alias Op =
        BooleanOverlayResearchOperation;

    /*
     * Reuse the established materialization hazard from
     * polygon_union_materialization.d.
     *
     * This is a valid exact signed-long ring near 2^53. All four required
     * vertices remain distinct after binary64 rounding, so this is not the
     * long.max vertex-collapse case.
     *
     * Rounding instead makes two exact non-adjacent boundary edges acquire a
     * new binary64 contact. The selected exact result therefore exists, but
     * its boundary-incidence graph cannot be represented faithfully.
     *
     * With B empty:
     *
     * union(A, empty)       -> A       -> unrepresentable
     * intersection(A,empty) -> empty   -> success
     * A minus empty         -> A       -> unrepresentable
     * empty minus A         -> empty   -> success
     * A xor empty           -> A       -> unrepresentable
     */
    enum long n =
        9_007_199_254_740_992L;

    P[4] points = [
        P(n,     n - 3),
        P(n - 2, n - 4),
        P(n + 3, n - 1),
        P(n + 4, n - 2),
    ];

    R[1] rings = [
        R(points[])
    ];

    R[] emptyRings;

    const G first =
        G(rings[]);

    const G empty =
        G(emptyRings);

    const Op[5] operations = [
        Op.unionSet,
        Op.intersection,
        Op.differenceAB,
        Op.differenceBA,
        Op.symmetricDifference,
    ];

    const Status[5] expected = [
        Status.unrepresentableConstruction,
        Status.success,
        Status.unrepresentableConstruction,
        Status.success,
        Status.unrepresentableConstruction,
    ];

    foreach (index, operation; operations)
    {
        PolygonUnionOwnedResultInternal result;

        const auto status =
            tryBooleanOverlayP1ResearchInternal(
                first,
                empty,
                operation,
                result
            );

        if (status != expected[index])
        {
            writefln(
                "rounded_contact|op=%s|unexpected_status=%s",
                operationName(operation),
                status
            );

            throw new Exception(
                "rounding-induced contact status matrix mismatch"
            );
        }

        /*
         * Both successful operations are mathematically empty. Failed
         * materializations must likewise expose no partial polygon set.
         */
        if (
            result.componentCount != 0 ||
            result.ringCount != 0 ||
            result.pointCount != 0
        )
        {
            throw new Exception(
                "rounding-induced contact matrix exposed unexpected result geometry"
            );
        }
    }
}


private void exactEventCollisionStatusMatrix()
{
    alias P = Point2!double;
    alias R = LinearRing2View!double;
    alias G = Polygon2View!double;

    alias Status =
        BooleanOverlayP1ResearchStatus;

    alias Op =
        BooleanOverlayResearchOperation;

    /*
     * Reuse the established exact-event collision construction from
     * intersection_exact.d.
     *
     * On A's source edge
     *
     *     (0,0) -> (1,0)
     *
     * B contributes two distinct crossing edges:
     *
     *     (0,-a0) -> (1,b)
     *     (0,-a1) -> (1,b)
     *
     * where a1 is the next binary64 value above a0.
     *
     * Their exact intersection events on y=0 are distinct and exactly
     * ordered, but both correctly round to x = 0.5.
     *
     * The source edge is embedded as the lower edge of a valid trapezoid.
     * The crossing pair is embedded in a valid very narrow triangle. Its
     * shared right vertex lies strictly inside the trapezoid, avoiding an
     * unrelated boundary contact there.
     */
    enum double a0 =
        0x1p-10;

    enum double a1 =
        0x1.0000000000001p-10;

    enum double b =
        0x1p-10;

    P[4] firstPoints = [
        P(0.0, 0.0),
        P(1.0, 0.0),
        P(2.0, 2.0),
        P(-1.0, 2.0),
    ];

    P[3] secondPoints = [
        P(0.0, -a0),
        P(0.0, -a1),
        P(1.0, b),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    const G first =
        G(firstRings[]);

    const G second =
        G(secondRings[]);

    const Op[5] operations = [
        Op.unionSet,
        Op.intersection,
        Op.differenceAB,
        Op.differenceBA,
        Op.symmetricDifference,
    ];

    foreach (operation; operations)
    {
        PolygonUnionOwnedResultInternal result;

        const auto status =
            tryBooleanOverlayP1ResearchInternal(
                first,
                second,
                operation,
                result
            );

        if (
            status !=
            Status.unrepresentableConstruction
        )
        {
            writefln(
                "exact_event_collision|op=%s|unexpected_status=%s",
                operationName(operation),
                status
            );

            throw new Exception(
                "exact-event collision status matrix mismatch"
            );
        }

        /*
         * ADR-0023 requires all-or-nothing materialization. Even though the
         * exact result topology exists, no partial rounded polygon set may
         * escape once the distinct required vertices collide in binary64.
         */
        if (
            result.componentCount != 0 ||
            result.ringCount != 0 ||
            result.pointCount != 0
        )
        {
            throw new Exception(
                "exact-event collision exposed partial result geometry"
            );
        }
    }
}


private void properRationalMaterializationStatusMatrix()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    alias Status =
        BooleanOverlayP1ResearchStatus;

    alias Op =
        BooleanOverlayResearchOperation;

    /*
     * These two valid triangles contain the already established exact
     * proper-crossing pair:
     *
     *     (0,0) -> (2,2)
     *     (0,1) -> (2,0)
     *
     * Their proper intersection is exactly:
     *
     *     (2/3, 2/3)
     *
     * which is not exactly representable in binary64.
     *
     * Exact topology/noding must therefore use the rational construction
     * point, while final result materialization may round it to the nearest
     * binary64 coordinate.
     */
    P[3] firstPoints = [
        P(0, 0),
        P(2, 2),
        P(0, 2),
    ];

    P[3] secondPoints = [
        P(0, 1),
        P(2, 0),
        P(2, 2),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    const G first =
        G(firstRings[]);

    const G second =
        G(secondRings[]);

    const Op[5] operations = [
        Op.unionSet,
        Op.intersection,
        Op.differenceAB,
        Op.differenceBA,
        Op.symmetricDifference,
    ];

    foreach (operation; operations)
    {
        PolygonUnionOwnedResultInternal result;

        const auto status =
            tryBooleanOverlayP1ResearchInternal(
                first,
                second,
                operation,
                result
            );

        if (status != Status.success)
        {
            throw new Exception(
                "proper rational materialization status matrix expected success"
            );
        }
    }


    /*
     * Check the operation where the rational crossing is necessarily a
     * retained result vertex.
     *
     * 0x1.5555555555555p-1 is the correctly rounded binary64 value of 2/3.
     */
    PolygonUnionOwnedResultInternal intersection;

    const auto intersectionStatus =
        tryBooleanOverlayP1ResearchInternal(
            first,
            second,
            Op.intersection,
            intersection
        );

    if (intersectionStatus != Status.success)
    {
        throw new Exception(
            "proper rational intersection unexpectedly failed"
        );
    }

    enum double roundedTwoThirds =
        0x1.5555555555555p-1;

    if (
        !resultContainsVertex(
            intersection,
            Point2!double(
                roundedTwoThirds,
                roundedTwoThirds
            )
        )
    )
    {
        throw new Exception(
            "proper rational intersection vertex was not materialized as expected"
        );
    }
}


private void longMaxMaterializationStatusMatrix()
{
    alias P = Point2!long;
    alias R = LinearRing2View!long;
    alias G = Polygon2View!long;

    alias Status =
        BooleanOverlayP1ResearchStatus;

    alias Op =
        BooleanOverlayResearchOperation;

    /*
     * This is the established production P1 materialization-failure geometry.
     *
     * The mathematically valid width-one rectangle has distinct exact x
     * coordinates long.max - 1 and long.max, but those required vertices
     * collapse when materialized as binary64.
     *
     * B is empty. Therefore:
     *
     * union(A, empty)       -> A       -> unrepresentable
     * intersection(A,empty) -> empty   -> success
     * A minus empty         -> A       -> unrepresentable
     * empty minus A         -> empty   -> success
     * A xor empty           -> A       -> unrepresentable
     *
     * This verifies that materialization failure depends on the selected
     * result geometry rather than merely on hazardous exact vertices existing
     * somewhere in the input/arrangement.
     */
    P[4] points = [
        P(long.max - 1, 0),
        P(long.max,     0),
        P(long.max,     10),
        P(long.max - 1, 10),
    ];

    R[1] rings = [
        R(points[])
    ];

    R[] emptyRings;

    const G first =
        G(rings[]);

    const G empty =
        G(emptyRings);

    const Op[5] operations = [
        Op.unionSet,
        Op.intersection,
        Op.differenceAB,
        Op.differenceBA,
        Op.symmetricDifference,
    ];

    const Status[5] expected = [
        Status.unrepresentableConstruction,
        Status.success,
        Status.unrepresentableConstruction,
        Status.success,
        Status.unrepresentableConstruction,
    ];

    foreach (index, operation; operations)
    {
        PolygonUnionOwnedResultInternal result;

        const auto status =
            tryBooleanOverlayP1ResearchInternal(
                first,
                empty,
                operation,
                result
            );

        if (status != expected[index])
        {
            throw new Exception(
                "long.max materialization status matrix mismatch"
            );
        }

        /*
         * Failure is all-or-nothing; successful operations in this particular
         * matrix are mathematically empty. In both cases no geometry may be
         * exposed.
         */
        if (
            result.componentCount != 0 ||
            result.ringCount != 0 ||
            result.pointCount != 0
        )
        {
            throw new Exception(
                "long.max materialization status matrix exposed unexpected result geometry"
            );
        }
    }
}


void main()
{
    distinctExactEventsStatusMatrix();
    roundedContactStatusMatrix();
    exactEventCollisionStatusMatrix();
    properRationalMaterializationStatusMatrix();
    longMaxMaterializationStatusMatrix();

    disjoint();
    overlap();
    containment();
    identical();
    adjacent();
    pointTouch();
    donutFill();
    donutIsland();
    plusShape();
    emptyFirst();
    emptySecond();
    bothEmpty();
    multiplePointContacts();
    partialCollinearOverlap();
    tJunctionContact();
    holeBoundaryCrossing();
}
