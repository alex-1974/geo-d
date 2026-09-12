/**
 * Robust point-in-polygon classification.
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
 *     September 12, 2026
 */
module geo.point_in_polygon;

import geo.internal.ring_point_classification :
    RingPointLocation,
    tryClassifyPointInRing;

import geo.point :
    Point2;

import geo.polygon_view :
    PolygonView;


/**
 * Location of a point relative to a polygon.
 */
enum PointPolygonLocation : ubyte
{
    /// The point is outside the role-based polygon interior.
    outside,

    /// The point lies exactly on the boundary of at least one stored ring.
    boundary,

    /// The point is inside the exterior and outside all interior rings.
    inside,
}


/**
 * Classifies a point relative to a polygon.
 *
 * Supported scalar types are `int`, `long`, `float`, and `double`.
 * `real` is deliberately outside the robust predicate domain.
 *
 * Returns false when the query point or any stored polygon coordinate is
 * non-finite.
 *
 * On failure, location is PointPolygonLocation.outside.
 *
 * For finite supported input, classification is exact and returns one of:
 *
 *     outside
 *     boundary
 *     inside
 *
 * A finite query against an empty polygon succeeds and is classified as
 * outside.
 *
 * Boundary has precedence over inside and outside across all stored rings.
 *
 * Ring zero is the exterior ring. Subsequent rings are interior rings.
 * Ring orientation does not affect classification.
 *
 * No topology validation, normalization, tolerance, or floating-point ray
 * intersection is performed.
 *
 * No allocation is performed.
 *
 * Every stored ring is inspected so that non-finite coordinates and
 * boundary precedence are handled globally.
 *
 * Complexity:
 *     O(n) time and O(1) auxiliary space for n stored vertices across all
 *     rings.
 */
bool tryClassifyPointInPolygon(T)(
    scope PolygonView!T polygon,
    Point2!T point,
    out PointPolygonLocation location
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    location =
        PointPolygonLocation.outside;

    /*
     * Empty polygons still require a finite query point.
     */
    if (!point.isFinite)
        return false;

    if (polygon.empty)
        return true;


    auto exterior =
        polygon.exterior;

    RingPointLocation exteriorLocation;

    if (
        !tryClassifyPointInRing(
            exterior,
            point,
            exteriorLocation
        )
    )
    {
        return false;
    }


    bool boundaryFound =
        exteriorLocation ==
        RingPointLocation.boundary;

    const bool insideExterior =
        exteriorLocation ==
        RingPointLocation.inside;

    bool insideInteriorRing = false;


    /*
     * Every interior ring must be inspected.
     *
     * We cannot return early after finding a boundary or determining that
     * the point is outside the exterior:
     *
     * - a later ring may contain a non-finite coordinate, which makes the
     *   complete operation fail;
     * - boundary has global precedence across all stored rings, including
     *   topologically invalid interior rings outside the exterior.
     */
    foreach (i; 0 .. polygon.holeCount)
    {
        auto interior =
            polygon.hole(i);

        RingPointLocation interiorLocation;

        if (
            !tryClassifyPointInRing(
                interior,
                point,
                interiorLocation
            )
        )
        {
            return false;
        }

        if (
            interiorLocation ==
            RingPointLocation.boundary
        )
        {
            boundaryFound = true;
        }
        else if (
            interiorLocation ==
            RingPointLocation.inside
        )
        {
            insideInteriorRing = true;
        }
    }


    if (boundaryFound)
    {
        location =
            PointPolygonLocation.boundary;
    }
    else if (
        insideExterior &&
        !insideInteriorRing
    )
    {
        location =
            PointPolygonLocation.inside;
    }
    else
    {
        location =
            PointPolygonLocation.outside;
    }

    return true;
}


/// Example classifying interior, boundary, and exterior points.
@safe unittest
{
    import geo;

    alias P = Point2!double;
    alias R = LinearRingView!double;
    alias V = PolygonView!double;

    P[4] points = [
        P(0.0, 0.0),
        P(10.0, 0.0),
        P(10.0, 10.0),
        P(0.0, 10.0)
    ];

    R[1] rings = [
        R(points[])
    ];

    auto polygon =
        V(rings[]);

    PointPolygonLocation location;

    assert(
        tryClassifyPointInPolygon(
            polygon,
            P(5.0, 5.0),
            location
        )
    );

    assert(
        location ==
        PointPolygonLocation.inside
    );

    assert(
        tryClassifyPointInPolygon(
            polygon,
            P(0.0, 5.0),
            location
        )
    );

    assert(
        location ==
        PointPolygonLocation.boundary
    );

    assert(
        tryClassifyPointInPolygon(
            polygon,
            P(20.0, 5.0),
            location
        )
    );

    assert(
        location ==
        PointPolygonLocation.outside
    );
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRingView;

    import std.meta :
        AliasSeq;


    /*
     * Basic classification across the supported scalar domain.
     */
    static foreach (T; AliasSeq!(int, long, float, double))
    {
        {
            alias P = Point2!T;
            alias R = LinearRingView!T;
            alias V = PolygonView!T;

            P[4] exteriorPoints = [
                P(T(0), T(0)),
                P(T(10), T(0)),
                P(T(10), T(10)),
                P(T(0), T(10))
            ];

            R exterior =
                R(exteriorPoints[]);

            R[1] rings = [
                exterior
            ];

            auto polygon =
                V(rings[]);

            PointPolygonLocation location;

            assert(
                tryClassifyPointInPolygon(
                    polygon,
                    P(T(5), T(5)),
                    location
                )
            );

            assert(
                location ==
                PointPolygonLocation.inside
            );

            assert(
                tryClassifyPointInPolygon(
                    polygon,
                    P(T(15), T(5)),
                    location
                )
            );

            assert(
                location ==
                PointPolygonLocation.outside
            );

            assert(
                tryClassifyPointInPolygon(
                    polygon,
                    P(T(10), T(5)),
                    location
                )
            );

            assert(
                location ==
                PointPolygonLocation.boundary
            );
        }
    }


    /*
     * real remains outside the robust predicate domain.
     */
    static assert(
        !__traits(
            compiles,
            {
                PolygonView!real polygon;
                Point2!real point;
                PointPolygonLocation location;

                tryClassifyPointInPolygon(
                    polygon,
                    point,
                    location
                );
            }
        )
    );


    alias P = Point2!double;
    alias R = LinearRingView!double;
    alias V = PolygonView!double;


    /*
     * Empty polygon.
     */
    {
        R[] rings;

        auto polygon =
            V(rings);

        PointPolygonLocation location;

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(1.0, 2.0),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.outside
        );
    }


    /*
     * Empty polygons do not make non-finite query points classifiable.
     */
    {
        R[] rings;

        auto polygon =
            V(rings);

        PointPolygonLocation location;

        assert(
            !tryClassifyPointInPolygon(
                polygon,
                P(double.nan, 0.0),
                location
            )
        );
    }


    /*
     * Interior rings subtract their even-odd interiors.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(10.0, 0.0),
            P(10.0, 10.0),
            P(0.0, 10.0)
        ];

        P[4] holePoints = [
            P(3.0, 3.0),
            P(7.0, 3.0),
            P(7.0, 7.0),
            P(3.0, 7.0)
        ];

        R exterior =
            R(exteriorPoints[]);

        R hole =
            R(holePoints[]);

        R[2] rings = [
            exterior,
            hole
        ];

        auto polygon =
            V(rings[]);

        PointPolygonLocation location;

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(1.0, 1.0),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.inside
        );

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(5.0, 5.0),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.outside
        );

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(3.0, 5.0),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.boundary
        );
    }


    /*
     * Interior-ring orientation does not affect polygon classification.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(10.0, 0.0),
            P(10.0, 10.0),
            P(0.0, 10.0)
        ];

        P[4] holeForwardPoints = [
            P(3.0, 3.0),
            P(7.0, 3.0),
            P(7.0, 7.0),
            P(3.0, 7.0)
        ];

        P[4] holeReversePoints = [
            P(3.0, 3.0),
            P(3.0, 7.0),
            P(7.0, 7.0),
            P(7.0, 3.0)
        ];

        R exterior =
            R(exteriorPoints[]);

        R holeForward =
            R(holeForwardPoints[]);

        R holeReverse =
            R(holeReversePoints[]);

        R[2] forwardRings = [
            exterior,
            holeForward
        ];

        R[2] reverseRings = [
            exterior,
            holeReverse
        ];

        auto forwardPolygon =
            V(forwardRings[]);

        auto reversePolygon =
            V(reverseRings[]);

        PointPolygonLocation forwardLocation;
        PointPolygonLocation reverseLocation;

        assert(
            tryClassifyPointInPolygon(
                forwardPolygon,
                P(5.0, 5.0),
                forwardLocation
            )
        );

        assert(
            tryClassifyPointInPolygon(
                reversePolygon,
                P(5.0, 5.0),
                reverseLocation
            )
        );

        assert(
            forwardLocation ==
            PointPolygonLocation.outside
        );

        assert(
            reverseLocation ==
            forwardLocation
        );
    }


    /*
     * Boundary has global precedence even for an invalid interior ring
     * located outside the exterior.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0)
        ];

        P[4] outsideHolePoints = [
            P(10.0, 10.0),
            P(14.0, 10.0),
            P(14.0, 14.0),
            P(10.0, 14.0)
        ];

        R exterior =
            R(exteriorPoints[]);

        R outsideHole =
            R(outsideHolePoints[]);

        R[2] rings = [
            exterior,
            outsideHole
        ];

        auto polygon =
            V(rings[]);

        PointPolygonLocation location;

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(12.0, 10.0),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.boundary
        );

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(12.0, 12.0),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.outside
        );
    }


    /*
     * Overlapping interior rings behave as the union of their interiors:
     * membership in any interior ring removes polygon interior.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(20.0, 0.0),
            P(20.0, 20.0),
            P(0.0, 20.0)
        ];

        P[4] firstHolePoints = [
            P(3.0, 3.0),
            P(12.0, 3.0),
            P(12.0, 12.0),
            P(3.0, 12.0)
        ];

        P[4] secondHolePoints = [
            P(8.0, 8.0),
            P(17.0, 8.0),
            P(17.0, 17.0),
            P(8.0, 17.0)
        ];

        R exterior =
            R(exteriorPoints[]);

        R firstHole =
            R(firstHolePoints[]);

        R secondHole =
            R(secondHolePoints[]);

        R[3] rings = [
            exterior,
            firstHole,
            secondHole
        ];

        auto polygon =
            V(rings[]);

        PointPolygonLocation location;

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(10.0, 10.0),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.outside
        );
    }


    /*
     * Full-range long coordinates remain exactly classifiable at polygon
     * level without scalar overflow.
     */
    {
        alias LP = Point2!long;
        alias LR = LinearRingView!long;
        alias LV = PolygonView!long;

        LP[3] exteriorPoints = [
            LP(long.min, long.min),
            LP(long.max, long.min),
            LP(0, long.max)
        ];

        LR exterior =
            LR(exteriorPoints[]);

        LR[1] rings = [
            exterior
        ];

        auto polygon =
            LV(rings[]);

        PointPolygonLocation location;

        assert(
            tryClassifyPointInPolygon(
                polygon,
                LP(0, 0),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.inside
        );

        assert(
            tryClassifyPointInPolygon(
                polygon,
                LP(long.min, long.min),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.boundary
        );
    }


    /*
     * Reversing the exterior ring does not change polygon classification.
     */
    {
        P[4] forwardPoints = [
            P(0.0, 0.0),
            P(8.0, 0.0),
            P(8.0, 8.0),
            P(0.0, 8.0)
        ];

        P[4] reversePoints = [
            P(0.0, 0.0),
            P(0.0, 8.0),
            P(8.0, 8.0),
            P(8.0, 0.0)
        ];

        R forwardExterior =
            R(forwardPoints[]);

        R reverseExterior =
            R(reversePoints[]);

        R[1] forwardRings = [
            forwardExterior
        ];

        R[1] reverseRings = [
            reverseExterior
        ];

        auto forwardPolygon =
            V(forwardRings[]);

        auto reversePolygon =
            V(reverseRings[]);

        PointPolygonLocation forwardLocation;
        PointPolygonLocation reverseLocation;

        foreach (query; [
            P(3.0, 4.0),
            P(10.0, 4.0),
            P(8.0, 4.0)
        ])
        {
            assert(
                tryClassifyPointInPolygon(
                    forwardPolygon,
                    query,
                    forwardLocation
                )
            );

            assert(
                tryClassifyPointInPolygon(
                    reversePolygon,
                    query,
                    reverseLocation
                )
            );

            assert(
                reverseLocation ==
                forwardLocation
            );
        }
    }


    /*
     * A self-intersecting exterior ring retains the deterministic even-odd
     * semantics of the underlying ring classifier.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0),
            P(4.0, 0.0)
        ];

        R exterior =
            R(exteriorPoints[]);

        R[1] rings = [
            exterior
        ];

        auto polygon =
            V(rings[]);

        PointPolygonLocation location;

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(1.0, 3.5),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.inside
        );

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(1.0, 2.5),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.outside
        );

        assert(
            tryClassifyPointInPolygon(
                polygon,
                P(2.0, 2.0),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.boundary
        );
    }


    /*
     * A non-finite coordinate in a later interior ring invalidates the
     * complete operation even when the exterior already establishes a
     * boundary result.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(10.0, 0.0),
            P(10.0, 10.0),
            P(0.0, 10.0)
        ];

        P[4] holePoints = [
            P(3.0, 3.0),
            P(7.0, 3.0),
            P(double.nan, 7.0),
            P(3.0, 7.0)
        ];

        R exterior =
            R(exteriorPoints[]);

        R hole =
            R(holePoints[]);

        R[2] rings = [
            exterior,
            hole
        ];

        auto polygon =
            V(rings[]);

        PointPolygonLocation location;

        assert(
            !tryClassifyPointInPolygon(
                polygon,
                P(5.0, 0.0),
                location
            )
        );
    }
}
