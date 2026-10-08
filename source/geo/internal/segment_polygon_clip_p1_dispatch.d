module geo.internal.segment_polygon_clip_p1_dispatch;

import geo.bounding_box : tryBounds;
import geo.bounds : Bounds2;

import geo.internal.segment_polygon_clip_p1 :
    SegmentPolygonClipInternalStatus,
    trySegmentPolygonClipP1Internal;

import geo.internal.segment_polygon_clip_p1_boundary_specialized :
    trySegmentPolygonClipP1BoundarySpecializedInternal;

import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;

import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;


/*
 * Research-only outer dispatcher for #165.
 *
 * The qualified baseline P1 implementation remains source-identical to
 * develop. Only a narrow small-boundary family is routed to the separate
 * specialized implementation.
 */
private enum bool isSegmentPolygonClipScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


private bool edgeBoundsMayMeetQueryDispatch(T)(
    Bounds2!T queryBounds,
    Segment2!T edge
)
    pure nothrow @safe @nogc
if (isSegmentPolygonClipScalar!T)
{
    const lower = queryBounds.min;
    const upper = queryBounds.max;

    return !(
        (edge.a.x < lower.x && edge.b.x < lower.x) ||
        (edge.a.x > upper.x && edge.b.x > upper.x) ||
        (edge.a.y < lower.y && edge.b.y < lower.y) ||
        (edge.a.y > upper.y && edge.b.y > upper.y)
    );
}


/*
 * Returns true only for the deliberately narrow first outer-specialization
 * experiment:
 *
 * - non-degenerate query;
 * - non-empty polygon;
 * - at most eight represented boundary edges;
 * - conservative raw event capacity exactly eight.
 *
 * The selector uses only represented comparisons and no robust topology
 * predicates. False positives remain semantically safe because the separate
 * implementation is a complete clipping kernel.
 */
pragma(inline, false)
private bool useBoundarySpecializedP1(T)(
    Segment2!T query,
    scope Polygon2View!T polygon
)
    @safe
if (isSegmentPolygonClipScalar!T)
{
    if (query.a == query.b || polygon.length == 0)
        return false;

    size_t edgeCount;

    foreach (ringIndex; 0 .. polygon.length)
    {
        const size_t ringEdges =
            polygon[ringIndex].segmentCount;

        if (ringEdges > 8 - edgeCount)
            return false;

        edgeCount += ringEdges;
    }

    if (edgeCount == 0)
        return false;

    Bounds2!T queryBounds;

    if (!tryBounds(query, queryBounds))
        return false;

    size_t eventCapacity = 2;

    foreach (ringIndex; 0 .. polygon.length)
    {
        const auto ring = polygon[ringIndex];

        foreach (edgeIndex; 0 .. ring.segmentCount)
        {
            if (
                edgeBoundsMayMeetQueryDispatch(
                    queryBounds,
                    ring.segment(edgeIndex)
                )
            )
            {
                eventCapacity += 2;

                if (eventCapacity > 8)
                    return false;
            }
        }
    }

    return eventCapacity == 8;
}


package(geo)
SegmentPolygonClipInternalStatus
trySegmentPolygonClipP1DispatchedInternal(T)(
    Segment2!T query,
    scope Polygon2View!T polygon,
    out SegmentPolygonClipOwnedResultInternal owned
)
    @safe
if (isSegmentPolygonClipScalar!T)
{
    /*
     * Selector-only control: execute the exact outer selection work but route
     * both outcomes to the untouched baseline kernel. This isolates selector
     * cost from specialized-kernel cost and code layout.
     */
    if (
        useBoundarySpecializedP1(
            query,
            polygon
        )
    )
    {
        return
            trySegmentPolygonClipP1Internal(
                query,
                polygon,
                owned
            );
    }

    return
        trySegmentPolygonClipP1Internal(
            query,
            polygon,
            owned
        );
}
