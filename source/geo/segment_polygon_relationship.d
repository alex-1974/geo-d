/**
 * Exact reduced relationship classification between a closed segment
 * and a prevalidated polygon.
 *
 * Authors:
 *     Alexander Bernardi
 *
 * Copyright:
 *     Copyright © 2026 Alexander Bernardi
 *
 * License:
 *     MIT
 *
 * Date:
 *     September 30, 2026
 */
module geo.segment_polygon_relationship;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind,
    trySegmentTouchPoint;

import geo.internal.polygon_union_input :
    exactRingOrientationSign;

import geo.orientation :
    Orientation2,
    orientation;

import geo.point :
    Point2;

import geo.point_in_polygon :
    PointPolygonLocation,
    tryClassifyPointInPolygon;

import geo.polygon_view :
    Polygon2View;

import geo.segment :
    Segment2;


/**
 * Reduced topological relationship of a closed segment to a polygon.
 *
 * Each field is an existential fact over the complete closed segment.
 *
 * No contact counts, ordering, coordinates, contacted-ring identity,
 * clipping geometry, or application-specific policy are retained.
 *
 * `SegmentPolygonRelationship.init` contains four false facts.
 * A successful classification of a finite segment against a valid polygon
 * always has at least one of `hasExterior`, `hasBoundary`, or `hasInterior`
 * set.
 */
struct SegmentPolygonRelationship
{
    /**
     * True when at least one segment point lies in the polygon exterior.
     */
    bool hasExterior;

    /**
     * True when at least one segment point lies on the polygon boundary.
     */
    bool hasBoundary;

    /**
     * True when at least one segment point lies in the polygon interior.
     */
    bool hasInterior;

    /**
     * True when a positive-length subsegment lies on the polygon boundary.
     */
    bool hasBoundaryOverlap;
}


/*
 * Adds one exact point-in-polygon location to the relationship facts.
 */
private void markPointLocation(
    ref SegmentPolygonRelationship relationship,
    PointPolygonLocation location
)
    pure nothrow @safe @nogc
{
    final switch (location)
    {
        case PointPolygonLocation.outside:
            relationship.hasExterior = true;
            break;

        case PointPolygonLocation.boundary:
            relationship.hasBoundary = true;
            break;

        case PointPolygonLocation.inside:
            relationship.hasInterior = true;
            break;
    }
}


/*
 * Classifies the non-boundary ray leaving a touch point that lies in the
 * strict interior of one polygon boundary edge.
 *
 * Preconditions:
 *
 * - contact != target;
 * - contact lies in the strict interior of edge;
 * - edge belongs to a valid polygon ring;
 * - the query does not overlap edge over positive length along this ray.
 */
private void markEdgeInteriorRay(T)(
    ref SegmentPolygonRelationship relationship,
    Segment2!T edge,
    Point2!T contact,
    Point2!T target,
    bool interiorOnSourceLeft
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    assert(contact != target);

    const Orientation2 side =
        orientation(
            edge.a,
            edge.b,
            target
        );

    /*
     * A touch in the strict interior of an edge cannot continue
     * collinearly without becoming a positive-length overlap.
     */
    assert(side != Orientation2.collinear);

    const bool inside =
        interiorOnSourceLeft
            ? side == Orientation2.left
            : side == Orientation2.right;

    if (inside)
        relationship.hasInterior = true;
    else
        relationship.hasExterior = true;
}


/*
 * Classifies one query ray leaving a polygon vertex.
 *
 * The incident boundary edges define either a convex or reflex local polygon
 * wedge. Their exact orientation and the role-derived polygon-interior side
 * determine whether the query ray locally enters polygon interior or exterior.
 *
 * A query ray that follows either incident edge over positive length is
 * boundary and is handled as such.
 */
private void markVertexRay(T)(
    ref SegmentPolygonRelationship relationship,
    Point2!T previous,
    Point2!T vertex,
    Point2!T next,
    Point2!T target,
    bool interiorOnSourceLeft
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    alias S = Segment2!T;

    assert(vertex != target);

    const S ray =
        S(
            vertex,
            target
        );

    if (
        segmentContactKind(
            ray,
            S(vertex, previous)
        ) == SegmentContactKind.overlap ||
        segmentContactKind(
            ray,
            S(vertex, next)
        ) == SegmentContactKind.overlap
    )
    {
        relationship.hasBoundary = true;
        return;
    }

    const Orientation2 previousSide =
        orientation(
            previous,
            vertex,
            target
        );

    const Orientation2 nextSide =
        orientation(
            vertex,
            next,
            target
        );

    const bool insidePreviousHalfPlane =
        interiorOnSourceLeft
            ? previousSide == Orientation2.left
            : previousSide == Orientation2.right;

    const bool insideNextHalfPlane =
        interiorOnSourceLeft
            ? nextSide == Orientation2.left
            : nextSide == Orientation2.right;

    const Orientation2 turn =
        orientation(
            previous,
            vertex,
            next
        );

    bool inside;

    if (turn == Orientation2.collinear)
    {
        /*
         * Polygon validity excludes a reversing/backtracking boundary.
         * A collinear stored vertex is therefore a redundant straight vertex.
         */
        inside =
            insidePreviousHalfPlane ||
            insideNextHalfPlane;
    }
    else
    {
        const bool convexForPolygonInterior =
            interiorOnSourceLeft
                ? turn == Orientation2.left
                : turn == Orientation2.right;

        if (convexForPolygonInterior)
        {
            inside =
                insidePreviousHalfPlane &&
                insideNextHalfPlane;
        }
        else
        {
            inside =
                insidePreviousHalfPlane ||
                insideNextHalfPlane;
        }
    }

    if (inside)
        relationship.hasInterior = true;
    else
        relationship.hasExterior = true;
}


/**
 * Classifies a closed segment relative to a prevalidated polygon.
 *
 * Supported scalar types are `int`, `long`, `float`, and `double`.
 * `real` is deliberately outside the robust topology domain.
 *
 * Preconditions:
 *
 * - `polygon` is valid according to `validatePolygon(polygon).valid`;
 * - for floating scalar domains, both segment endpoints are finite.
 *
 * Polygon validation is deliberately outside this query. This permits one
 * validated polygon to be reused for many segment queries without repeating
 * validation work.
 *
 * An empty polygon is valid. Every finite segment against an empty polygon
 * has `hasExterior == true` and all other facts false.
 *
 * A degenerate segment represents one point. Exactly one of
 * `hasExterior`, `hasBoundary`, or `hasInterior` is then true, and
 * `hasBoundaryOverlap` is false.
 *
 * Topological decisions are exact. No epsilon, rounded proper-intersection
 * coordinate, event sorting, or polygon-pair arrangement is used.
 *
 * No allocation is performed.
 *
 * Reversing segment endpoints does not change the result. Reversing any ring
 * of a valid polygon does not change the result.
 *
 * Complexity:
 *     O(n) time and O(1) auxiliary space for n represented polygon
 *     boundary edges.
 *
 * Returns:
 *     The four reduced existential relationship facts.
 */
SegmentPolygonRelationship classifySegmentPolygonRelationship(T)(
    Segment2!T segment,
    scope Polygon2View!T polygon
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    alias S = Segment2!T;

    /*
     * Finiteness is part of the frozen public precondition.
     *
     * Keeping this assertion provides a development-time guard without
     * turning the hot query into a checked-result API.
     */
    assert(segment.isFinite);

    SegmentPolygonRelationship relationship;


    PointPolygonLocation firstLocation;

    const bool haveFirstLocation =
        tryClassifyPointInPolygon(
            polygon,
            segment.a,
            firstLocation
        );

    /*
     * A valid polygon and finite query endpoint are classifiable.
     */
    assert(haveFirstLocation);

    markPointLocation(
        relationship,
        firstLocation
    );


    if (segment.a == segment.b)
        return relationship;


    PointPolygonLocation secondLocation;

    const bool haveSecondLocation =
        tryClassifyPointInPolygon(
            polygon,
            segment.b,
            secondLocation
        );

    assert(haveSecondLocation);

    markPointLocation(
        relationship,
        secondLocation
    );


    foreach (ringIndex; 0 .. polygon.length)
    {
        const auto ring =
            polygon[ringIndex];

        const int orientationSign =
            exactRingOrientationSign(
                ring
            );

        /*
         * Every non-empty ring of a valid polygon has non-zero exact area.
         */
        assert(
            ring.empty ||
            orientationSign != 0
        );

        const bool counterClockwise =
            orientationSign > 0;

        const bool isHole =
            ringIndex != 0;

        /*
         * Exterior and interior rings use their structural polygon role,
         * not a required winding convention.
         */
        const bool interiorOnSourceLeft =
            counterClockwise !=
            isHole;


        /*
         * First pass:
         *
         * - establish boundary existence;
         * - proper crossings immediately witness both interior and exterior;
         * - positive-length overlap establishes boundary overlap;
         * - strict edge-interior endpoint touches determine their adjacent
         *   non-boundary ray directly.
         */
        foreach (edgeIndex; 0 .. ring.segmentCount)
        {
            const S edge =
                ring.segment(
                    edgeIndex
                );

            const SegmentContactKind contact =
                segmentContactKind(
                    segment,
                    edge
                );

            final switch (contact)
            {
                case SegmentContactKind.none:
                    break;

                case SegmentContactKind.properCrossing:
                    relationship.hasBoundary = true;
                    relationship.hasExterior = true;
                    relationship.hasInterior = true;
                    break;

                case SegmentContactKind.overlap:
                    relationship.hasBoundary = true;
                    relationship.hasBoundaryOverlap = true;
                    break;

                case SegmentContactKind.touch:
                {
                    relationship.hasBoundary = true;

                    Point2!T point;

                    const bool havePoint =
                        trySegmentTouchPoint(
                            segment,
                            edge,
                            point
                        );

                    assert(havePoint);

                    /*
                     * Polygon-vertex contacts need both incident edges and
                     * are resolved in the second pass.
                     */
                    if (
                        point == edge.a ||
                        point == edge.b
                    )
                    {
                        break;
                    }

                    /*
                     * The touch lies in the strict interior of the polygon
                     * edge, so it must be one of the query endpoints.
                     */
                    if (point == segment.a)
                    {
                        markEdgeInteriorRay(
                            relationship,
                            edge,
                            point,
                            segment.b,
                            interiorOnSourceLeft
                        );
                    }
                    else
                    {
                        assert(point == segment.b);

                        markEdgeInteriorRay(
                            relationship,
                            edge,
                            point,
                            segment.a,
                            interiorOnSourceLeft
                        );
                    }

                    break;
                }
            }
        }


        /*
         * Second pass:
         *
         * Every polygon vertex lying on the query is classified locally
         * along each available query ray.
         *
         * This resolves crossings/tangencies through vertices and the
         * non-boundary side adjacent to boundary-overlap endpoints without
         * requiring an ordered event list.
         */
        if (ring.length != 0)
        {
            foreach (vertexIndex; 0 .. ring.length)
            {
                const Point2!T vertex =
                    ring[vertexIndex];

                if (
                    segmentContactKind(
                        segment,
                        S(vertex, vertex)
                    ) == SegmentContactKind.none
                )
                {
                    continue;
                }

                const size_t previousIndex =
                    vertexIndex == 0
                        ? ring.length - 1
                        : vertexIndex - 1;

                const size_t nextIndex =
                    vertexIndex + 1 == ring.length
                        ? 0
                        : vertexIndex + 1;

                const Point2!T previous =
                    ring[previousIndex];

                const Point2!T next =
                    ring[nextIndex];


                if (vertex != segment.a)
                {
                    markVertexRay(
                        relationship,
                        previous,
                        vertex,
                        next,
                        segment.a,
                        interiorOnSourceLeft
                    );
                }

                if (vertex != segment.b)
                {
                    markVertexRay(
                        relationship,
                        previous,
                        vertex,
                        next,
                        segment.b,
                        interiorOnSourceLeft
                    );
                }
            }
        }
    }

    return relationship;
}


/// Example classifying a road-like segment that crosses a polygonal area.
pure nothrow @safe @nogc unittest
{
    import geo;

    alias P = Point2!double;
    alias R = LinearRing2View!double;
    alias G = Polygon2View!double;
    alias S = Segment2!double;

    P[4] points = [
        P(0.0, 0.0),
        P(10.0, 0.0),
        P(10.0, 10.0),
        P(0.0, 10.0)
    ];

    R[1] rings = [
        R(points[])
    ];

    const G polygon =
        G(rings[]);

    const S segment =
        S(
            P(-5.0, 5.0),
            P(15.0, 5.0)
        );

    const relationship =
        segment.classifySegmentPolygonRelationship(
            polygon
        );

    assert(relationship.hasExterior);
    assert(relationship.hasBoundary);
    assert(relationship.hasInterior);
    assert(!relationship.hasBoundaryOverlap);
}


pure nothrow @safe @nogc unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    import std.meta :
        AliasSeq;

    static foreach (
        T;
        AliasSeq!(
            int,
            long,
            float,
            double
        )
    )
    {{
        alias P = Point2!T;
        alias R = LinearRing2View!T;
        alias G = Polygon2View!T;
        alias S = Segment2!T;

        P[4] points = [
            P(T(0),  T(0)),
            P(T(10), T(0)),
            P(T(10), T(10)),
            P(T(0),  T(10))
        ];

        R[1] rings = [
            R(points[])
        ];

        const G polygon =
            G(rings[]);


        /*
         * Proper crossing.
         */
        const crossing =
            classifySegmentPolygonRelationship(
                S(
                    P(T(-5), T(5)),
                    P(T(15), T(5))
                ),
                polygon
            );

        assert(
            crossing ==
            SegmentPolygonRelationship(
                true,
                true,
                true,
                false
            )
        );


        /*
         * Point-only tangency at a convex polygon vertex.
         */
        const tangent =
            classifySegmentPolygonRelationship(
                S(
                    P(T(-5), T(5)),
                    P(T(5), T(-5))
                ),
                polygon
            );

        assert(
            tangent ==
            SegmentPolygonRelationship(
                true,
                true,
                false,
                false
            )
        );


        /*
         * Segment joining two boundary points through polygon interior.
         */
        const interiorChord =
            classifySegmentPolygonRelationship(
                S(
                    P(T(0), T(5)),
                    P(T(10), T(5))
                ),
                polygon
            );

        assert(
            interiorChord ==
            SegmentPolygonRelationship(
                false,
                true,
                true,
                false
            )
        );


        /*
         * Positive-length boundary overlap.
         */
        const boundaryOverlap =
            classifySegmentPolygonRelationship(
                S(
                    P(T(0), T(2)),
                    P(T(0), T(8))
                ),
                polygon
            );

        assert(
            boundaryOverlap ==
            SegmentPolygonRelationship(
                false,
                true,
                false,
                true
            )
        );


        /*
         * Degenerate interior segment.
         */
        const degenerate =
            classifySegmentPolygonRelationship(
                S(
                    P(T(5), T(5)),
                    P(T(5), T(5))
                ),
                polygon
            );

        assert(
            degenerate ==
            SegmentPolygonRelationship(
                false,
                false,
                true,
                false
            )
        );


        /*
         * Segment reversal is relationship-invariant.
         */
        const forward =
            classifySegmentPolygonRelationship(
                S(
                    P(T(-5), T(5)),
                    P(T(15), T(5))
                ),
                polygon
            );

        const reverse =
            classifySegmentPolygonRelationship(
                S(
                    P(T(15), T(5)),
                    P(T(-5), T(5))
                ),
                polygon
            );

        assert(forward == reverse);


        /*
         * Frozen implication laws.
         */
        assert(
            !forward.hasBoundaryOverlap ||
            forward.hasBoundary
        );

        assert(
            !(
                forward.hasExterior &&
                forward.hasInterior
            ) ||
            forward.hasBoundary
        );
    }}


    /*
     * Empty polygon is valid and every finite segment lies in its exterior.
     */
    {
        alias P = Point2!double;
        alias R = LinearRing2View!double;
        alias G = Polygon2View!double;
        alias S = Segment2!double;

        R[] rings;

        const G empty =
            G(rings);

        const relationship =
            classifySegmentPolygonRelationship(
                S(
                    P(1.0, 2.0),
                    P(3.0, 4.0)
                ),
                empty
            );

        assert(
            relationship ==
            SegmentPolygonRelationship(
                true,
                false,
                false,
                false
            )
        );
    }


    /*
     * `real` is deliberately outside the robust relationship domain.
     */
    static assert(
        !__traits(
            compiles,
            {
                Segment2!real segment;
                Polygon2View!real polygon;

                classifySegmentPolygonRelationship(
                    segment,
                    polygon
                );
            }
        )
    );
}


pure nothrow @safe @nogc unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;
    alias S = Segment2!int;


    /*
     * Concave U polygon.
     *
     * The opening from x=3..7 above y=3 is polygon exterior.
     */
    P[8] uPoints = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(7, 10),
        P(7, 3),
        P(3, 3),
        P(3, 10),
        P(0, 10)
    ];

    R[1] uRings = [
        R(uPoints[])
    ];

    const G uPolygon =
        G(uRings[]);


    /*
     * Both endpoints are on polygon boundary, while the open segment
     * lies entirely in the concave exterior.
     */
    assert(
        classifySegmentPolygonRelationship(
            S(
                P(3, 5),
                P(7, 5)
            ),
            uPolygon
        ) ==
        SegmentPolygonRelationship(
            true,
            true,
            false,
            false
        )
    );


    /*
     * Both endpoints are on polygon boundary, while the open segment
     * lies entirely in polygon interior.
     */
    assert(
        classifySegmentPolygonRelationship(
            S(
                P(0, 2),
                P(10, 2)
            ),
            uPolygon
        ) ==
        SegmentPolygonRelationship(
            false,
            true,
            true,
            false
        )
    );


    /*
     * Two separated positive-length boundary overlaps with an exterior
     * interval between them.
     *
     * This is the important no-event-sorting case.
     */
    assert(
        classifySegmentPolygonRelationship(
            S(
                P(0, 10),
                P(10, 10)
            ),
            uPolygon
        ) ==
        SegmentPolygonRelationship(
            true,
            true,
            false,
            true
        )
    );


    /*
     * Polygon with one hole.
     *
     * Exterior and hole intentionally use the same winding direction;
     * structural ring role, not winding convention, defines polygon interior.
     */
    P[4] outerPoints = [
        P(0, 0),
        P(20, 0),
        P(20, 20),
        P(0, 20)
    ];

    P[4] holePoints = [
        P(5, 5),
        P(15, 5),
        P(15, 15),
        P(5, 15)
    ];

    R[2] holeRings = [
        R(outerPoints[]),
        R(holePoints[])
    ];

    const G withHole =
        G(holeRings[]);


    /*
     * A segment wholly inside the hole lies in polygon exterior.
     */
    assert(
        classifySegmentPolygonRelationship(
            S(
                P(6, 10),
                P(14, 10)
            ),
            withHole
        ) ==
        SegmentPolygonRelationship(
            true,
            false,
            false,
            false
        )
    );


    /*
     * Both endpoints lie on the hole boundary and the open segment lies
     * inside the hole, hence in polygon exterior.
     */
    assert(
        classifySegmentPolygonRelationship(
            S(
                P(5, 10),
                P(15, 10)
            ),
            withHole
        ) ==
        SegmentPolygonRelationship(
            true,
            true,
            false,
            false
        )
    );


    /*
     * Segment from exterior boundary to hole boundary lies otherwise
     * entirely in polygon interior.
     */
    assert(
        classifySegmentPolygonRelationship(
            S(
                P(0, 10),
                P(5, 10)
            ),
            withHole
        ) ==
        SegmentPolygonRelationship(
            false,
            true,
            true,
            false
        )
    );


    /*
     * Crossing the complete polygon and its hole witnesses exterior,
     * boundary, and interior.
     */
    assert(
        classifySegmentPolygonRelationship(
            S(
                P(-2, 10),
                P(22, 10)
            ),
            withHole
        ) ==
        SegmentPolygonRelationship(
            true,
            true,
            true,
            false
        )
    );


    /*
     * Positive-length overlap with the hole boundary.
     */
    assert(
        classifySegmentPolygonRelationship(
            S(
                P(5, 6),
                P(5, 14)
            ),
            withHole
        ) ==
        SegmentPolygonRelationship(
            false,
            true,
            false,
            true
        )
    );


    /*
     * Reverse exterior and hole winding independently.
     */
    P[4] outerReversePoints = [
        P(0, 0),
        P(0, 20),
        P(20, 20),
        P(20, 0)
    ];

    P[4] holeReversePoints = [
        P(5, 5),
        P(5, 15),
        P(15, 15),
        P(15, 5)
    ];

    R[2] reverseRings = [
        R(outerReversePoints[]),
        R(holeReversePoints[])
    ];

    const G reversedPolygon =
        G(reverseRings[]);

    const S orientationProbe =
        S(
            P(-2, 10),
            P(22, 10)
        );

    assert(
        classifySegmentPolygonRelationship(
            orientationProbe,
            reversedPolygon
        ) ==
        classifySegmentPolygonRelationship(
            orientationProbe,
            withHole
        )
    );


    /*
     * Redundant collinear boundary vertex in an otherwise valid ring.
     */
    P[5] splitTopPoints = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(5, 10),
        P(0, 10)
    ];

    R[1] splitTopRings = [
        R(splitTopPoints[])
    ];

    const G splitTop =
        G(splitTopRings[]);

    assert(
        classifySegmentPolygonRelationship(
            S(
                P(0, 10),
                P(10, 10)
            ),
            splitTop
        ) ==
        SegmentPolygonRelationship(
            false,
            true,
            false,
            true
        )
    );
}
