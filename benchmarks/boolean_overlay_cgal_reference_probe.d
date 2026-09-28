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


private void emitCase(
    string name,
    scope const(int)[] expectedComponents,
    scope const(int)[] expectedHoles,
    scope Polygon2View!int first,
    scope Polygon2View!int second
)
{
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


void main()
{
    disjoint();
    overlap();
    containment();
    identical();
    adjacent();
    pointTouch();
    donutFill();
    donutIsland();
    plusShape();
}
