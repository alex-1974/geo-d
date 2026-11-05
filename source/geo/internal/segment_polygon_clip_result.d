module geo.internal.segment_polygon_clip_result;

import geo.segment : Segment2;

import std.exception : assumeUnique;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Immutable owning backing for one successfully materialized
 * segment/polygon clipping result.
 */
package(geo)
struct SegmentPolygonClipOwnedResultInternal
{
private:
    immutable(Segment2!double)[] _components;

public:
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _components.length;
    }


    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return _components.length == 0;
    }


    Segment2!double opIndex(size_t index) const
        pure nothrow @safe @nogc
    {
        return _components[index];
    }
}


/*
 * Consumes the sole mutable component array and freezes it without a deep
 * copy. The source slice is null after ownership transfer.
 */
package(geo)
SegmentPolygonClipOwnedResultInternal
takeSegmentPolygonClipOwnedResultInternal(
    ref Segment2!double[] components
)
    @trusted
{
    auto frozen =
        assumeUnique(components);

    assert(components is null);

    return
        SegmentPolygonClipOwnedResultInternal(
            frozen
        );
}


@safe unittest
{
    Segment2!double[] components;

    auto result =
        takeSegmentPolygonClipOwnedResultInternal(
            components
        );

    assert(components is null);
    assert(result.empty);
    assert(result.length == 0);
}
