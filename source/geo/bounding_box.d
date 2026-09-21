/**
 * Axis-aligned bounding-box computation for two-dimensional geometry.
 *
 * The operations in this module compute `Bounds2` directly in the input
 * scalar domain. They perform no coordinate conversion, topology validation,
 * or allocation.
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
module geo.bounding_box;

import geo.bounds : Bounds2;
import geo.linear_ring_view : LinearRing2View;
import geo.point : Point2;
import geo.polygon_view : Polygon2View;
import geo.polyline_view : Polyline2View;
import geo.scalar : isGeoScalar;
import geo.segment : Segment2;

import std.traits : isFloatingPoint;


/*
 * Private accumulator for linear bounds reductions.
 *
 * Bounds2.tryExtend() is the general single-point mutation primitive.
 * Geometry-wide reductions keep extrema in scalar fields instead, avoiding
 * repeated Bounds2 state handling and corner reconstruction in the hot loop.
 */
private struct BoundsAccumulator(T)
if (isGeoScalar!T)
{
    private bool hasValue;

    private T minX;
    private T minY;
    private T maxX;
    private T maxY;


    bool tryAdd(Point2!T point)
        pure nothrow @safe @nogc
    {
        static if (isFloatingPoint!T)
        {
            if (point.x != point.x ||
                point.y != point.y)
            {
                return false;
            }
        }

        if (!hasValue)
        {
            minX = point.x;
            minY = point.y;
            maxX = point.x;
            maxY = point.y;

            hasValue = true;

            return true;
        }

        if (point.x < minX)
            minX = point.x;

        if (point.y < minY)
            minY = point.y;

        if (point.x > maxX)
            maxX = point.x;

        if (point.y > maxY)
            maxY = point.y;

        return true;
    }


    bool finish(out Bounds2!T result) const
        pure nothrow @safe @nogc
    {
        if (!hasValue)
            return true;

        return Bounds2!T.tryFromMinMax(
            Point2!T(minX, minY),
            Point2!T(maxX, maxY),
            result
        );
    }
}


/**
 * Computes the closed axis-aligned bounds of a segment.
 *
 * Both stored endpoints participate in the result. Endpoint order does not
 * affect the geometric bounds.
 *
 * A degenerate segment produces a degenerate non-empty bounds.
 *
 * Returns false when either endpoint contains NaN. Infinity is permitted.
 *
 * On failure, `result` is `Bounds2!T.init`.
 *
 * No allocation is performed.
 *
 * Complexity:
 *
 *     time  O(1)
 *     space O(1)
 */
bool tryBounds(T)(
    Segment2!T segment,
    out Bounds2!T result
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    BoundsAccumulator!T accumulated;

    if (!accumulated.tryAdd(segment.a))
        return false;

    if (!accumulated.tryAdd(segment.b))
        return false;

    return accumulated.finish(result);
}


/**
 * Computes the closed axis-aligned bounds of a polyline.
 *
 * Every stored point participates in the result.
 *
 * An empty polyline succeeds with `Bounds2!T.init`.
 * A singleton polyline produces a degenerate non-empty bounds.
 *
 * Returns false when any stored point contains NaN. Infinity is permitted.
 *
 * Failure is transactional: on failure, `result` is `Bounds2!T.init`.
 *
 * No allocation is performed.
 *
 * Complexity for `n` stored points:
 *
 *     time  O(n)
 *     space O(1)
 */
bool tryBounds(T)(
    scope Polyline2View!T polyline,
    out Bounds2!T result
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    BoundsAccumulator!T accumulated;

    foreach (i; 0 .. polyline.length)
    {
        if (!accumulated.tryAdd(polyline[i]))
            return false;
    }

    return accumulated.finish(result);
}


/**
 * Computes the closed axis-aligned bounds of a linear ring.
 *
 * Every stored vertex participates in the result. The implicit closing
 * segment requires no separate treatment because both of its endpoints are
 * already stored vertices.
 *
 * Ring topology is not validated. Empty, degenerate, and topologically
 * invalid rings may still have well-defined bounds.
 *
 * An empty ring succeeds with `Bounds2!T.init`.
 *
 * Returns false when any stored vertex contains NaN. Infinity is permitted.
 *
 * Failure is transactional: on failure, `result` is `Bounds2!T.init`.
 *
 * No allocation is performed.
 *
 * Complexity for `n` stored vertices:
 *
 *     time  O(n)
 *     space O(1)
 */
bool tryBounds(T)(
    scope LinearRing2View!T ring,
    out Bounds2!T result
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    BoundsAccumulator!T accumulated;

    foreach (i; 0 .. ring.length)
    {
        if (!accumulated.tryAdd(ring[i]))
            return false;
    }

    return accumulated.finish(result);
}


/**
 * Computes the closed axis-aligned bounds of a polygon representation.
 *
 * Every stored vertex of every stored ring participates in the result,
 * including all interior rings.
 *
 * Polygon topology is deliberately not validated. In particular, a stored
 * interior ring outside the exterior ring still contributes to the result.
 *
 * An empty polygon succeeds with `Bounds2!T.init`. Empty constituent rings
 * contribute no points.
 *
 * Returns false when any stored vertex contains NaN. Infinity is permitted.
 *
 * Failure is transactional: on failure, `result` is `Bounds2!T.init`.
 *
 * No allocation is performed.
 *
 * Complexity for `n` total stored vertices across all rings:
 *
 *     time  O(n)
 *     space O(1)
 */
bool tryBounds(T)(
    scope Polygon2View!T polygon,
    out Bounds2!T result
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    BoundsAccumulator!T accumulated;

    foreach (ringIndex; 0 .. polygon.length)
    {
        auto ring =
            polygon[ringIndex];

        foreach (pointIndex; 0 .. ring.length)
        {
            if (!accumulated.tryAdd(ring[pointIndex]))
                return false;
        }
    }

    return accumulated.finish(result);
}


/// Example computing bounds of a non-owning polyline view.
@safe unittest
{
    import geo;

    alias P = Point2!int;

    P[4] points = [
        P(3, 4),
        P(-2, 9),
        P(8, -5),
        P(1, 6)
    ];

    const polyline =
        Polyline2View!int(points[]);

    Bounds2!int bounds;

    assert(
        tryBounds(
            polyline,
            bounds
        )
    );

    assert(bounds.min == P(-2, -5));
    assert(bounds.max == P(8, 9));
}


// Existing exhaustive regression coverage.
@safe unittest
{
    import std.meta : AliasSeq;


    /*
     * Every overload supports the complete geo-d scalar domain.
     */
    static foreach (T; AliasSeq!(int, long, float, double, real))
    {
        {
                alias P = Point2!T;
            alias B = Bounds2!T;
            alias S = Segment2!T;
            alias L = Polyline2View!T;
            alias R = LinearRing2View!T;
            alias G = Polygon2View!T;


            /*
             * Ordinary and reversed segments have identical bounds.
             */
            const S segment =
                S(
                    P(T(4), T(-2)),
                    P(T(-3), T(8))
                );

            const S reversedSegment =
                S(
                    segment.b,
                    segment.a
                );

            B segmentBounds;
            B reversedSegmentBounds;

            assert(
                tryBounds(
                    segment,
                    segmentBounds
                )
            );

            assert(
                tryBounds(
                    reversedSegment,
                    reversedSegmentBounds
                )
            );

            assert(segmentBounds == reversedSegmentBounds);
            assert(segmentBounds.min == P(T(-3), T(-2)));
            assert(segmentBounds.max == P(T(4), T(8)));


            /*
             * Degenerate segment.
             */
            B degenerateBounds;

            assert(
                tryBounds(
                    S(
                        P(T(2), T(3)),
                        P(T(2), T(3))
                    ),
                    degenerateBounds
                )
            );

            assert(!degenerateBounds.empty);
            assert(degenerateBounds.min == P(T(2), T(3)));
            assert(degenerateBounds.max == P(T(2), T(3)));


            /*
             * Empty polyline has empty bounds.
             */
            P[] noPoints;

            auto emptyPolyline =
                L(noPoints);

            B emptyPolylineBounds;

            assert(
                tryBounds(
                    emptyPolyline,
                    emptyPolylineBounds
                )
            );

            assert(emptyPolylineBounds == B.init);


            /*
             * Singleton polyline has degenerate bounds.
             */
            P[1] singletonPoints = [
                P(T(5), T(-7))
            ];

            auto singletonPolyline =
                L(singletonPoints[]);

            B singletonBounds;

            assert(
                tryBounds(
                    singletonPolyline,
                    singletonBounds
                )
            );

            assert(singletonBounds.min == singletonPoints[0]);
            assert(singletonBounds.max == singletonPoints[0]);


            /*
             * Ordinary polyline.
             */
            P[4] polylinePoints = [
                P(T(3),  T(4)),
                P(T(-2), T(9)),
                P(T(8),  T(-5)),
                P(T(1),  T(6))
            ];

            auto polyline =
                L(polylinePoints[]);

            B polylineBounds;

            assert(
                tryBounds(
                    polyline,
                    polylineBounds
                )
            );

            assert(polylineBounds.min == P(T(-2), T(-5)));
            assert(polylineBounds.max == P(T(8), T(9)));

            foreach (point; polylinePoints)
                assert(polylineBounds.contains(point));


            /*
             * Repeated points do not change bounds.
             */
            P[5] repeatedPolylinePoints = [
                polylinePoints[0],
                polylinePoints[1],
                polylinePoints[1],
                polylinePoints[2],
                polylinePoints[3]
            ];

            auto repeatedPolyline =
                L(repeatedPolylinePoints[]);

            B repeatedPolylineBounds;

            assert(
                tryBounds(
                    repeatedPolyline,
                    repeatedPolylineBounds
                )
            );

            assert(repeatedPolylineBounds == polylineBounds);


            /*
             * Reversing stored point order does not change polyline bounds.
             */
            P[4] reversedPolylinePoints = [
                polylinePoints[3],
                polylinePoints[2],
                polylinePoints[1],
                polylinePoints[0]
            ];

            auto reversedPolyline =
                L(reversedPolylinePoints[]);

            B reversedPolylineBounds;

            assert(
                tryBounds(
                    reversedPolyline,
                    reversedPolylineBounds
                )
            );

            assert(reversedPolylineBounds == polylineBounds);


            /*
             * Empty ring has empty bounds.
             */
            auto emptyRing =
                R(noPoints);

            B emptyRingBounds;

            assert(
                tryBounds(
                    emptyRing,
                    emptyRingBounds
                )
            );

            assert(emptyRingBounds == B.init);


            /*
             * Ring bounds depend only on stored vertices. The implicit closing
             * edge requires no special contribution.
             */
            P[4] ringPoints = [
                P(T(-4), T(1)),
                P(T(6),  T(2)),
                P(T(3),  T(10)),
                P(T(-1), T(7))
            ];

            auto ring =
                R(ringPoints[]);

            B ringBounds;

            assert(
                tryBounds(
                    ring,
                    ringBounds
                )
            );

            assert(ringBounds.min == P(T(-4), T(1)));
            assert(ringBounds.max == P(T(6), T(10)));

            foreach (point; ringPoints)
                assert(ringBounds.contains(point));


            /*
             * Reversing ring traversal does not change bounds.
             */
            P[4] reversedRingPoints = [
                ringPoints[3],
                ringPoints[2],
                ringPoints[1],
                ringPoints[0]
            ];

            auto reversedRing =
                R(reversedRingPoints[]);

            B reversedRingBounds;

            assert(
                tryBounds(
                    reversedRing,
                    reversedRingBounds
                )
            );

            assert(reversedRingBounds == ringBounds);


            /*
             * Empty polygon has empty bounds.
             */
            R[] noRings;

            auto emptyPolygon =
                G(noRings);

            B emptyPolygonBounds;

            assert(
                tryBounds(
                    emptyPolygon,
                    emptyPolygonBounds
                )
            );

            assert(emptyPolygonBounds == B.init);


            /*
             * Every stored polygon ring contributes.
             *
             * The second ring deliberately lies outside the first. That makes
             * this an invalid polygon representation, but its representation
             * bounds remain well-defined and must include both rings.
             */
            P[4] exteriorPoints = [
                P(T(0), T(0)),
                P(T(4), T(0)),
                P(T(4), T(4)),
                P(T(0), T(4))
            ];

            P[3] outsideInteriorPoints = [
                P(T(10), T(10)),
                P(T(12), T(10)),
                P(T(11), T(13))
            ];

            R[2] polygonRings = [
                R(exteriorPoints[]),
                R(outsideInteriorPoints[])
            ];

            auto polygon =
                G(polygonRings[]);

            B polygonBounds;

            assert(
                tryBounds(
                    polygon,
                    polygonBounds
                )
            );

            assert(polygonBounds.min == P(T(0), T(0)));
            assert(polygonBounds.max == P(T(12), T(13)));

            foreach (point; exteriorPoints)
                assert(polygonBounds.contains(point));

            foreach (point; outsideInteriorPoints)
                assert(polygonBounds.contains(point));


            /*
             * Stored ring order does not affect representation bounds.
             */
            R[2] reorderedRings = [
                R(outsideInteriorPoints[]),
                R(exteriorPoints[])
            ];

            auto reorderedPolygon =
                G(reorderedRings[]);

            B reorderedPolygonBounds;

            assert(
                tryBounds(
                    reorderedPolygon,
                    reorderedPolygonBounds
                )
            );

            assert(reorderedPolygonBounds == polygonBounds);


            /*
             * Empty constituent rings contribute no points.
             */
            R[2] polygonWithEmptyRing = [
                R(exteriorPoints[]),
                R(noPoints)
            ];

            auto partlyEmptyPolygon =
                G(polygonWithEmptyRing[]);

            B partlyEmptyBounds;

            assert(
                tryBounds(
                    partlyEmptyPolygon,
                    partlyEmptyBounds
                )
            );

            assert(partlyEmptyBounds.min == P(T(0), T(0)));
            assert(partlyEmptyBounds.max == P(T(4), T(4)));


            /*
             * Integral extrema require no arithmetic and are preserved exactly.
             */
            static if (is(T == int) || is(T == long))
            {
                B extremeBounds;

                assert(
                    tryBounds(
                        S(
                            P(T.min, T.max),
                            P(T.max, T.min)
                        ),
                        extremeBounds
                    )
                );

                assert(
                    extremeBounds.min ==
                    P(T.min, T.min)
                );

                assert(
                    extremeBounds.max ==
                    P(T.max, T.max)
                );
            }


            static if (isFloatingPoint!T)
            {
                const T infinity =
                    cast(T) double.infinity;

                /*
                 * Infinity is valid and contributes normally.
                 */
                P[2] infinitePoints = [
                    P(-infinity, T(1)),
                    P( infinity, T(2))
                ];

                auto infinitePolyline =
                    L(infinitePoints[]);

                B infiniteBounds;

                assert(
                    tryBounds(
                        infinitePolyline,
                        infiniteBounds
                    )
                );

                assert(!infiniteBounds.empty);
                assert(!infiniteBounds.isFinite);
                assert(infiniteBounds.min.x == -infinity);
                assert(infiniteBounds.max.x == infinity);


                /*
                 * NaN after valid points must fail transactionally.
                 *
                 * The out parameter is deliberately initialised to a non-empty
                 * sentinel before the call. Failure must leave it at Bounds2.init,
                 * not at either the sentinel or a partial accumulation.
                 */
                P[3] nanPoints = [
                    P(T(1), T(2)),
                    P(T(3), T(4)),
                    P(cast(T) double.nan, T(5))
                ];

                auto nanPolyline =
                    L(nanPoints[]);

                B failedBounds;

                assert(
                    B.tryFromPoint(
                        P(T(99), T(99)),
                        failedBounds
                    )
                );

                assert(!failedBounds.empty);

                assert(
                    !tryBounds(
                        nanPolyline,
                        failedBounds
                    )
                );

                assert(failedBounds == B.init);


                /*
                 * NaN in a later polygon ring is equally transactional.
                 */
                P[3] nanRingPoints = [
                    P(T(20), T(20)),
                    P(T(21), T(20)),
                    P(cast(T) double.nan, T(21))
                ];

                R[2] nanPolygonRings = [
                    R(exteriorPoints[]),
                    R(nanRingPoints[])
                ];

                auto nanPolygon =
                    G(nanPolygonRings[]);

                assert(
                    B.tryFromPoint(
                        P(T(99), T(99)),
                        failedBounds
                    )
                );

                assert(
                    !tryBounds(
                        nanPolygon,
                        failedBounds
                    )
                );

                assert(failedBounds == B.init);


                /*
                 * Segment NaN rejection.
                 */
                assert(
                    B.tryFromPoint(
                        P(T(99), T(99)),
                        failedBounds
                    )
                );

                assert(
                    !tryBounds(
                        S(
                            P(T(0), T(0)),
                            P(cast(T) double.nan, T(1))
                        ),
                        failedBounds
                    )
                );

                assert(failedBounds == B.init);
            }
        }
    }
}
