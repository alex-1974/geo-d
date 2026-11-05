/**
 * External consumer verification of the two existing immutable owning results.
 *
 * This module intentionally imports only the public geo-d package surface.
 * It does not introduce a new public geometry abstraction.
 */
module ownership_contract;

import geo;
import core.memory : GC;


/*
 * The returned owner must not borrow either stack-allocated input points or
 * the temporary ring-descriptor array.  This positive source-level probe is
 * deliberately @safe, so it is also compiled by the ordinary consumer gate.
 */
private @safe PolygonUnionResult unionFromLocalInputs()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] points = [
        P(0, 0),
        P(6, 0),
        P(6, 6),
        P(0, 6),
    ];

    R[1] rings = [R(points[])];

    return polygonUnion(
        G(rings[]),
        G.init
    );
}


private @safe SegmentPolygonClipResult clippingFromLocalInputs()
{
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

    R[1] rings = [R(points[])];

    return clipSegmentToPolygon(
        S(P(-2, 3), P(8, 3)),
        G(rings[])
    );
}


/**
 * Verifies the owning-result contract through the external `import geo;` API.
 * The runtime test is intended for both baseline DMD and LDC consumers.
 * A forced collection probes GC reachability; it is not a proof that every
 * internal `assumeUnique` precondition holds.
 */
@safe void verifyOwnershipResultContracts()
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const defaultUnion = PolygonUnionResult.init;
    assert(defaultUnion.status == PolygonUnionStatus.notComputed);
    assert(!defaultUnion.succeeded);

    const defaultClip = SegmentPolygonClipResult.init;
    assert(defaultClip.status == SegmentPolygonClipStatus.notComputed);
    assert(!defaultClip.succeeded);

    /* A view must continue to hold immutable result backing after the owner
     * descriptors and all the original caller-owned inputs have gone away. */
    auto unionOriginal = unionFromLocalInputs();
    assert(unionOriginal.succeeded);
    assert(unionOriginal.status == PolygonUnionStatus.success);
    assert(unionOriginal.length == 1);

    auto unionCopy = unionOriginal;
    const retained = unionOriginal[0];
    unionOriginal = PolygonUnionResult.init;

    assert(!unionOriginal.succeeded);
    assert(unionCopy.succeeded);
    assert(unionCopy.length == 1);

    unionCopy = PolygonUnionResult.init;
    GC.collect();

    assert(retained.length == 1);
    assert(retained.exterior.length == 4);
    assert(retained.exterior[0] == P(0.0, 0.0));

    /* The clipping result returns a value, not an alias to a writable
     * component.  The copied owner remains valid after resetting original. */
    auto clipOriginal = clippingFromLocalInputs();
    assert(clipOriginal.succeeded);
    assert(clipOriginal.status == SegmentPolygonClipStatus.success);
    assert(clipOriginal.length == 1);

    auto clipCopy = clipOriginal;
    clipOriginal = SegmentPolygonClipResult.init;

    assert(!clipOriginal.succeeded);
    assert(clipCopy.succeeded);
    assert(clipCopy.length == 1);
    assert(clipCopy[0] == S(P(0.0, 3.0), P(6.0, 3.0)));

    clipCopy = SegmentPolygonClipResult.init;
    assert(clipCopy.status == SegmentPolygonClipStatus.notComputed);
}
