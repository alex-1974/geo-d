/**
 * Robust one-dimensional segment clipping against a prevalidated polygon.
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
module geo.segment_polygon_clip;

import geo.intersection :
    IntersectionScalar;

import geo.internal.segment_polygon_clip_p1 :
    SegmentPolygonClipInternalStatus;

import geo.internal.segment_polygon_clip_p1_dispatch :
    trySegmentPolygonClipP1DispatchedInternal;

import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;

import geo.polygon_view :
    Polygon2View;

import geo.segment :
    Segment2;


/**
 * Outcome of checked segment/polygon clipping construction.
 *
 * SegmentPolygonClipStatus.init is notComputed, keeping a default result
 * distinct from a successful empty clipping result.
 *
 * Invalid polygon topology and non-finite query coordinates are precondition
 * violations and are not represented by this enum.
 *
 * Runtime allocation/resource exhaustion follows normal D runtime failure
 * semantics and is not represented by this enum.
 */
enum SegmentPolygonClipStatus : ubyte
{
    /// No clipping operation has produced this result.
    notComputed,

    /// A complete one-dimensional clipping result was constructed.
    success,

    /**
     * Exact retained topology exists, but the construction scalar cannot
     * represent it faithfully.
     */
    unrepresentableConstruction,
}


/**
 * Immutable owning result of segment/polygon clipping.
 *
 * Successful results contain zero or more positive-length
 * Segment2!double components in query traversal order.
 *
 * Isolated point contacts are intentionally omitted by the ADR-0024
 * one-dimensional regularization contract.
 *
 * Ordinary copies share immutable GC-backed component storage and do not
 * deep-copy geometry.
 *
 * Geometry access requires succeeded == true. Check status or succeeded
 * before inspecting length, empty, or indexing the result.
 */
struct SegmentPolygonClipResult
{
private:
    SegmentPolygonClipStatus _status =
        SegmentPolygonClipStatus.notComputed;

    SegmentPolygonClipOwnedResultInternal _owned;

public:
    /// Checked construction outcome.
    @property SegmentPolygonClipStatus status() const
        pure nothrow @safe @nogc
    {
        return _status;
    }


    /// True exactly when complete clipping construction succeeded.
    @property bool succeeded() const
        pure nothrow @safe @nogc
    {
        return
            _status ==
            SegmentPolygonClipStatus.success;
    }


    /**
     * Number of positive-length components in a successful result.
     *
     * The result must have succeeded == true.
     */
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        assert(succeeded);

        return _owned.length;
    }


    /**
     * True when a successful clipping result contains no 1D components.
     *
     * The result must have succeeded == true.
     */
    @property bool empty() const
        pure nothrow @safe @nogc
    {
        assert(succeeded);

        return _owned.empty;
    }


    /**
     * Returns one positive-length component in query traversal order.
     *
     * The result must have succeeded == true.
     */
    Segment2!double opIndex(size_t index) const
        pure nothrow @safe @nogc
    {
        assert(succeeded);

        return _owned[index];
    }
}


private enum bool isSegmentPolygonClipScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/**
 * Constructs the positive-length one-dimensional components of a finite
 * segment retained by a prevalidated polygon.
 *
 * Semantically, the operation constructs the closed-set segment/polygon
 * intersection and omits connected components of topological dimension zero.
 *
 * Therefore isolated tangencies and isolated vertex contacts produce no
 * constructed component. Use classifySegmentPolygonRelationship when those
 * contact facts are required.
 *
 * Positive-length portions lying on polygon boundary are retained.
 *
 * Preconditions:
 *
 * - segment is finite;
 * - polygon satisfies validatePolygon(polygon).valid.
 *
 * An empty polygon is valid and yields a successful empty result.
 *
 * A degenerate finite segment is valid input and yields a successful empty
 * result under the one-dimensional regularization contract.
 *
 * Supported input scalar types are int, long, float, and double.
 * real is deliberately outside the robust topology/construction domain.
 *
 * Exact represented geometry determines topology and component order before
 * any coordinate rounding. No global epsilon is used.
 *
 * Constructed coordinates follow IntersectionScalar!T, currently double
 * for every supported input scalar.
 *
 * Materialization is all-or-nothing. Every selected exact endpoint must round
 * finitely, and the complete rounded endpoint sequence must preserve strict
 * query traversal order on the source segment's monotone x/y axis. Otherwise
 * the result status is unrepresentableConstruction and no partial geometry
 * is exposed.
 *
 * The operation allocates O(n) private exact-event workspace for n polygon
 * boundary edges plus immutable result storage. It deliberately does not
 * promise @nogc.
 *
 * The correctness-first implementation collects O(n) exact events and sorts
 * them in O(n log n) time.
 *
 * Params:
 *     segment = finite source segment
 *     polygon = prevalidated polygon
 *
 * Returns:
 *     Checked immutable owning clipping result.
 */
SegmentPolygonClipResult clipSegmentToPolygon(T)(
    Segment2!T segment,
    scope Polygon2View!T polygon
)
    @safe
if (isSegmentPolygonClipScalar!T)
{
    static assert(
        is(
            IntersectionScalar!T ==
            double
        )
    );

    assert(segment.isFinite);

    SegmentPolygonClipOwnedResultInternal owned;

    const internalStatus =
        trySegmentPolygonClipP1DispatchedInternal(
            segment,
            polygon,
            owned
        );

    SegmentPolygonClipResult result;

    final switch (internalStatus)
    {
        case SegmentPolygonClipInternalStatus.success:
            result._status =
                SegmentPolygonClipStatus.success;

            result._owned =
                owned;

            return result;

        case SegmentPolygonClipInternalStatus.unrepresentableConstruction:
            result._status =
                SegmentPolygonClipStatus
                    .unrepresentableConstruction;

            return result;
    }
}


/// Example clipping a crossing segment to one polygon component.
@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    import geo.point :
        Point2;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;
    alias S = Segment2!int;

    P[4] points = [
        P(0, 0),
        P(6, 0),
        P(6, 6),
        P(0, 6),
    ];

    R[1] rings = [
        R(points[])
    ];

    const result =
        clipSegmentToPolygon(
            S(P(-2, 3), P(8, 3)),
            G(rings[])
        );

    assert(result.succeeded);
    assert(result.length == 1);

    assert(
        result[0] ==
        Segment2!double(
            Point2!double(0.0, 3.0),
            Point2!double(6.0, 3.0)
        )
    );
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    import geo.point :
        Point2;

    import geo.topology_validation :
        validatePolygon;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;
    alias S = Segment2!int;


    {
        const result =
            SegmentPolygonClipResult.init;

        assert(
            result.status ==
            SegmentPolygonClipStatus.notComputed
        );

        assert(!result.succeeded);
    }


    P[4] squarePoints = [
        P(0, 0),
        P(6, 0),
        P(6, 6),
        P(0, 6),
    ];

    R[1] squareRings = [
        R(squarePoints[])
    ];

    const G square =
        G(squareRings[]);

    assert(
        validatePolygon(square).valid
    );


    {
        const result =
            clipSegmentToPolygon(
                S(P(-5, -2), P(-1, -2)),
                square
            );

        assert(result.succeeded);
        assert(result.empty);
    }


    {
        const result =
            clipSegmentToPolygon(
                S(P(1, 2), P(5, 2)),
                square
            );

        assert(result.succeeded);
        assert(result.length == 1);

        assert(
            result[0] ==
            Segment2!double(
                Point2!double(1.0, 2.0),
                Point2!double(5.0, 2.0)
            )
        );
    }


    {
        const result =
            clipSegmentToPolygon(
                S(P(-2, 2), P(2, -2)),
                square
            );

        assert(result.succeeded);
        assert(result.empty);
    }


    {
        const result =
            clipSegmentToPolygon(
                S(P(-2, 0), P(8, 0)),
                square
            );

        assert(result.succeeded);
        assert(result.length == 1);

        assert(
            result[0] ==
            Segment2!double(
                Point2!double(0.0, 0.0),
                Point2!double(6.0, 0.0)
            )
        );
    }


    {
        const result =
            clipSegmentToPolygon(
                S(P(8, 3), P(-2, 3)),
                square
            );

        assert(result.succeeded);
        assert(result.length == 1);

        assert(
            result[0] ==
            Segment2!double(
                Point2!double(6.0, 3.0),
                Point2!double(0.0, 3.0)
            )
        );
    }


    {
        const result =
            clipSegmentToPolygon(
                S(P(2, 2), P(2, 2)),
                square
            );

        assert(result.succeeded);
        assert(result.empty);
    }


    {
        R[] emptyRings;

        const result =
            clipSegmentToPolygon(
                S(P(-2, 3), P(8, 3)),
                G(emptyRings)
            );

        assert(result.succeeded);
        assert(result.empty);
    }


    {
        P[4] outerPoints = [
            P(0, 0),
            P(10, 0),
            P(10, 10),
            P(0, 10),
        ];

        P[4] holePoints = [
            P(3, 3),
            P(7, 3),
            P(7, 7),
            P(3, 7),
        ];

        R[2] rings = [
            R(outerPoints[]),
            R(holePoints[])
        ];

        const G polygon =
            G(rings[]);

        assert(
            validatePolygon(polygon).valid
        );

        const result =
            clipSegmentToPolygon(
                S(P(0, 5), P(10, 5)),
                polygon
            );

        assert(result.succeeded);
        assert(result.length == 2);

        assert(
            result[0] ==
            Segment2!double(
                Point2!double(0.0, 5.0),
                Point2!double(3.0, 5.0)
            )
        );

        assert(
            result[1] ==
            Segment2!double(
                Point2!double(7.0, 5.0),
                Point2!double(10.0, 5.0)
            )
        );
    }
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    import geo.point :
        Point2;

    import geo.topology_validation :
        validatePolygon;

    {
        alias P = Point2!long;
        alias R = LinearRing2View!long;
        alias G = Polygon2View!long;
        alias S = Segment2!long;

        enum long x0 =
            long.max - 1;

        enum long x1 =
            long.max;

        P[4] points = [
            P(x0, 0),
            P(x1, 0),
            P(x1, 10),
            P(x0, 10),
        ];

        R[1] rings = [
            R(points[])
        ];

        const G polygon =
            G(rings[]);

        assert(
            validatePolygon(polygon).valid
        );

        const result =
            clipSegmentToPolygon(
                S(P(x0, 5), P(x1, 5)),
                polygon
            );

        assert(!result.succeeded);

        assert(
            result.status ==
            SegmentPolygonClipStatus
                .unrepresentableConstruction
        );
    }


    {
        alias P = Point2!long;
        alias R = LinearRing2View!long;
        alias G = Polygon2View!long;
        alias S = Segment2!long;

        enum long base =
            9_007_199_254_740_992L;

        P[4] outerPoints = [
            P(base - 2, 0),
            P(base + 4, 0),
            P(base + 4, 10),
            P(base - 2, 10),
        ];

        P[4] holePoints = [
            P(base, 2),
            P(base + 1, 2),
            P(base + 1, 8),
            P(base, 8),
        ];

        R[2] rings = [
            R(outerPoints[]),
            R(holePoints[])
        ];

        const G polygon =
            G(rings[]);

        assert(
            validatePolygon(polygon).valid
        );

        const result =
            clipSegmentToPolygon(
                S(
                    P(base - 2, 5),
                    P(base + 4, 5)
                ),
                polygon
            );

        assert(!result.succeeded);

        assert(
            result.status ==
            SegmentPolygonClipStatus
                .unrepresentableConstruction
        );
    }
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
    alias S = Segment2!int;

    P[4] points = [
        P(0, 0),
        P(6, 0),
        P(6, 6),
        P(0, 6),
    ];

    R[1] rings = [
        R(points[])
    ];

    auto original =
        clipSegmentToPolygon(
            S(P(-2, 3), P(8, 3)),
            G(rings[])
        );

    auto copy = original;

    original =
        SegmentPolygonClipResult.init;

    assert(copy.succeeded);
    assert(copy.length == 1);

    assert(
        copy[0] ==
        Segment2!double(
            Point2!double(0.0, 3.0),
            Point2!double(6.0, 3.0)
        )
    );
}
