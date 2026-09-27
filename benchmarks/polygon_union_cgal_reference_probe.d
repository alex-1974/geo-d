/*
 * Optional external differential probe for the package-internal polygon-union
 * P1 implementation.
 *
 * This executable is not part of the published package or ordinary CI. Its
 * output is compared with the independent CGAL/EPECK reference executable by
 * benchmarks/run_polygon_union_cgal_reference.sh.
 */
module geo.polygon_union_cgal_reference_probe;

import geo.internal.polygon_union_p1 :
    PolygonUnionP1InternalStatus,
    tryPolygonUnionP1Internal;

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


private void emitCase(
    string name,
    scope Polygon2View!int first,
    scope Polygon2View!int second
)
{
    PolygonUnionOwnedResultInternal result;

    const auto status =
        tryPolygonUnionP1Internal(
            first,
            second,
            result
        );

    if (
        status !=
        PolygonUnionP1InternalStatus.success
    )
    {
        writefln(
            "%s|status=%s",
            name,
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

    write(
        name,
        "|components=",
        result.componentCount,
        "|holes=",
        holeCount,
        "|area2=",
        resultTwiceArea(result),
        "|grid="
    );


    /*
     * Representation-independent semantic signature.
     *
     * The integer grid intentionally contains exterior, interior and boundary
     * samples for all retained fixtures. It is dense enough to catch ordinary
     * result-region differences while remaining stable across libraries that
     * simplify collinear boundary vertices differently.
     */
    foreach (y; -2 .. 13)
    {
        foreach (x; -1 .. 16)
        {
            PointPolygonLocation location =
                PointPolygonLocation.outside;

            bool classified = true;

            bool boundary = false;
            bool inside = false;

            foreach (
                componentIndex;
                0 ..
                result.componentCount
            )
            {
                PointPolygonLocation componentLocation;

                if (
                    !tryClassifyPointInPolygon(
                        result.component(
                            componentIndex
                        ),
                        Point2!double(
                            cast(double) x,
                            cast(double) y
                        ),
                        componentLocation
                    )
                )
                {
                    classified = false;
                    break;
                }

                if (
                    componentLocation ==
                    PointPolygonLocation.boundary
                )
                {
                    boundary = true;
                }
                else if (
                    componentLocation ==
                    PointPolygonLocation.inside
                )
                {
                    inside = true;
                }
            }

            assert(classified);

            location =
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
        G(outerRings[]),
        G(innerRings[])
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

    /*
     * Clockwise hole. Polygon2View is role-based and does not require this
     * winding, but it mirrors the CGAL reference fixture.
     */
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

    R[1] horizontalRings = [R(horizontal[])];
    R[1] verticalRings = [R(vertical[])];

    emitCase(
        "plus",
        G(horizontalRings[]),
        G(verticalRings[])
    );
}


void main()
{
    disjoint();
    overlap();
    containment();
    adjacent();
    pointTouch();
    donutFill();
    donutIsland();
    plusShape();
}
