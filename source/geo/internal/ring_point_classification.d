module geo.internal.ring_point_classification;

import geo.linear_ring_view :
    LinearRingView;

import geo.orientation :
    Orientation,
    orientation;

import geo.point :
    Point2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact point classification against one LinearRingView.
 *
 * This module implements representation-level even-odd semantics. It does
 * not validate ring topology.
 */


/**
 * Location of a point relative to one ring.
 */
enum RingPointLocation : ubyte
{
    outside,
    boundary,
    inside,
}


/*
 * Returns true when value lies in the closed interval with endpoints first
 * and second.
 *
 * The endpoint order is irrelevant.
 */
private bool withinClosedBounds(T)(
    T value,
    T first,
    T second
)
    pure nothrow @safe @nogc
{
    return
        (
            first <= value &&
            value <= second
        ) ||
        (
            second <= value &&
            value <= first
        );
}


/*
 * Tests the coordinate bounds of a point already known to be collinear
 * with segment a -> b.
 *
 * No subtraction is used, so the complete integer scalar domain remains
 * safe from overflow.
 */
private bool withinClosedSegmentBounds(T)(
    Point2!T a,
    Point2!T b,
    Point2!T point
)
    pure nothrow @safe @nogc
{
    return
        withinClosedBounds(
            point.x,
            a.x,
            b.x
        ) &&
        withinClosedBounds(
            point.y,
            a.y,
            b.y
        );
}


/**
 * Classifies a point relative to one linear ring.
 *
 * Returns false when the query point or any stored ring coordinate is
 * non-finite.
 *
 * For finite supported input:
 *
 *     outside
 *     boundary
 *     inside
 *
 * are determined exactly.
 *
 * Boundary testing has precedence over even-odd interior classification.
 *
 * The even-odd crossing rule uses no division and constructs no ray/edge
 * intersection coordinate.
 */
bool tryClassifyPointInRing(T)(
    scope const(LinearRingView!T) ring,
    Point2!T point,
    out RingPointLocation location
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    if (!point.isFinite)
        return false;


    /*
     * Empty rings have neither boundary nor interior.
     *
     * The out parameter is already initialized to outside because that is
     * the first enum value.
     */
    if (ring.empty)
        return true;


    auto first =
        ring[0];

    if (!first.isFinite)
        return false;


    auto previous =
        first;

    bool inside = false;
    bool boundaryFound = false;


    /*
     * Process every stored edge except the implicit closing edge.
     *
     * Even after a boundary has been found, remaining vertices are still
     * inspected for finiteness. A later non-finite coordinate invalidates
     * the complete classification.
     */
    foreach (i; 1 .. ring.length)
    {
        auto current =
            ring[i];

        if (!current.isFinite)
            return false;

        if (
            !boundaryFound &&
            withinClosedBounds(
                point.y,
                previous.y,
                current.y
            )
        )
        {
            const Orientation side =
                orientation(
                    previous,
                    current,
                    point
                );

            if (
                side == Orientation.collinear &&
                withinClosedSegmentBounds(
                    previous,
                    current,
                    point
                )
            )
            {
                boundaryFound = true;
            }
            else if (
                previous.y <= point.y &&
                point.y < current.y
            )
            {
                /*
                 * Upward half-open crossing.
                 */
                if (side == Orientation.left)
                    inside = !inside;
            }
            else if (
                current.y <= point.y &&
                point.y < previous.y
            )
            {
                /*
                 * Downward half-open crossing.
                 */
                if (side == Orientation.right)
                    inside = !inside;
            }
        }

        previous =
            current;
    }


    /*
     * The final stored vertex closes implicitly back to the first.
     *
     * For a singleton this is the degenerate segment P -> P.
     */
    if (
        !boundaryFound &&
        withinClosedBounds(
            point.y,
            previous.y,
            first.y
        )
    )
    {
        const Orientation side =
            orientation(
                previous,
                first,
                point
            );

        if (
            side == Orientation.collinear &&
            withinClosedSegmentBounds(
                previous,
                first,
                point
            )
        )
        {
            boundaryFound = true;
        }
        else if (
            previous.y <= point.y &&
            point.y < first.y
        )
        {
            if (side == Orientation.left)
                inside = !inside;
        }
        else if (
            first.y <= point.y &&
            point.y < previous.y
        )
        {
            if (side == Orientation.right)
                inside = !inside;
        }
    }


    if (boundaryFound)
    {
        location =
            RingPointLocation.boundary;
    }
    else if (inside)
    {
        location =
            RingPointLocation.inside;
    }
    else
    {
        location =
            RingPointLocation.outside;
    }

    return true;
}


@safe unittest
{
    import std.meta :
        AliasSeq;


    /*
     * Classification supports the robust predicate scalar domain.
     */
    static foreach (T; AliasSeq!(int, long, float, double))
    {
        {
            alias P = Point2!T;
            alias R = LinearRingView!T;

            P[3] points = [
                P(T(0), T(0)),
                P(T(4), T(0)),
                P(T(0), T(4))
            ];

            auto ring =
                R(points[]);

            RingPointLocation location;

            assert(
                tryClassifyPointInRing(
                    ring,
                    P(T(1), T(1)),
                    location
                )
            );

            assert(
                location ==
                RingPointLocation.inside
            );

            assert(
                tryClassifyPointInRing(
                    ring,
                    P(T(4), T(4)),
                    location
                )
            );

            assert(
                location ==
                RingPointLocation.outside
            );

            assert(
                tryClassifyPointInRing(
                    ring,
                    P(T(2), T(0)),
                    location
                )
            );

            assert(
                location ==
                RingPointLocation.boundary
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
                LinearRingView!real ring;
                Point2!real point;
                RingPointLocation location;

                tryClassifyPointInRing(
                    ring,
                    point,
                    location
                );
            }
        )
    );


    alias P = Point2!double;
    alias R = LinearRingView!double;


    /*
     * Empty ring.
     */
    {
        P[] points;

        auto ring =
            R(points);

        RingPointLocation location;

        assert(
            tryClassifyPointInRing(
                ring,
                P(12.0, -7.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.outside
        );
    }


    /*
     * Singleton rings contribute only their degenerate point boundary.
     */
    {
        P[1] points = [
            P(2.0, 3.0)
        ];

        auto ring =
            R(points[]);

        RingPointLocation location;

        assert(
            tryClassifyPointInRing(
                ring,
                P(2.0, 3.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.boundary
        );

        assert(
            tryClassifyPointInRing(
                ring,
                P(2.0, 4.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.outside
        );
    }


    /*
     * A two-vertex ring has boundary but no even-odd interior.
     */
    {
        P[2] points = [
            P(0.0, 0.0),
            P(4.0, 0.0)
        ];

        auto ring =
            R(points[]);

        RingPointLocation location;

        assert(
            tryClassifyPointInRing(
                ring,
                P(2.0, 0.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.boundary
        );

        /*
         * Collinear but outside the closed segment.
         */
        assert(
            tryClassifyPointInRing(
                ring,
                P(5.0, 0.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.outside
        );

        assert(
            tryClassifyPointInRing(
                ring,
                P(2.0, 1.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.outside
        );
    }


    /*
     * Vertex boundary is exact.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        RingPointLocation location;

        assert(
            tryClassifyPointInRing(
                ring,
                P(4.0, 4.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.boundary
        );
    }


    /*
     * Horizontal edges do not create ray crossings, but remain boundary.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        RingPointLocation location;

        assert(
            tryClassifyPointInRing(
                ring,
                P(2.0, 0.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.boundary
        );

        assert(
            tryClassifyPointInRing(
                ring,
                P(5.0, 0.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.outside
        );
    }


    /*
     * Half-open crossings count a vertex y-level exactly once.
     */
    {
        P[3] points = [
            P(0.0, 0.0),
            P(4.0, 2.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        RingPointLocation location;

        assert(
            tryClassifyPointInRing(
                ring,
                P(1.0, 2.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.inside
        );

        assert(
            tryClassifyPointInRing(
                ring,
                P(5.0, 2.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.outside
        );
    }


    /*
     * Reversing traversal does not change even-odd classification.
     */
    {
        P[4] ccwPoints = [
            P(0.0, 0.0),
            P(5.0, 0.0),
            P(5.0, 5.0),
            P(0.0, 5.0)
        ];

        P[4] cwPoints = [
            P(0.0, 0.0),
            P(0.0, 5.0),
            P(5.0, 5.0),
            P(5.0, 0.0)
        ];

        auto ccw =
            R(ccwPoints[]);

        auto cw =
            R(cwPoints[]);

        RingPointLocation firstLocation;
        RingPointLocation secondLocation;

        assert(
            tryClassifyPointInRing(
                ccw,
                P(2.0, 3.0),
                firstLocation
            )
        );

        assert(
            tryClassifyPointInRing(
                cw,
                P(2.0, 3.0),
                secondLocation
            )
        );

        assert(
            firstLocation ==
            RingPointLocation.inside
        );

        assert(
            secondLocation ==
            firstLocation
        );
    }


    /*
     * Self-intersecting rings use deterministic even-odd semantics.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0),
            P(4.0, 0.0)
        ];

        auto ring =
            R(points[]);

        RingPointLocation location;

        assert(
            tryClassifyPointInRing(
                ring,
                P(1.0, 3.5),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.inside
        );

        assert(
            tryClassifyPointInRing(
                ring,
                P(1.0, 2.5),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.outside
        );

        assert(
            tryClassifyPointInRing(
                ring,
                P(2.0, 2.0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.boundary
        );
    }


    /*
     * Full-range long coordinates remain exact without scalar overflow.
     */
    {
        alias LP = Point2!long;
        alias LR = LinearRingView!long;

        LP[3] points = [
            LP(long.min, long.min),
            LP(long.max, long.min),
            LP(0, long.max)
        ];

        auto ring =
            LR(points[]);

        RingPointLocation location;

        assert(
            tryClassifyPointInRing(
                ring,
                LP(0, 0),
                location
            )
        );

        assert(
            location ==
            RingPointLocation.inside
        );
    }


    /*
     * A non-finite query point cannot be classified.
     */
    {
        P[3] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        RingPointLocation location;

        assert(
            !tryClassifyPointInRing(
                ring,
                P(double.nan, 1.0),
                location
            )
        );
    }


    /*
     * A later non-finite ring vertex invalidates the complete operation
     * even when an earlier finite edge already contains the query point.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(double.nan, 1.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        RingPointLocation location;

        assert(
            !tryClassifyPointInRing(
                ring,
                P(2.0, 0.0),
                location
            )
        );
    }
}
