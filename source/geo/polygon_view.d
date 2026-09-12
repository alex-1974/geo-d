/**
 * Non-owning views of polygons composed from linear rings.
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
module geo.polygon_view;

import geo.linear_ring_view : LinearRingView;
import geo.scalar : isGeoScalar;


/**
 * Non-owning read-only view of an ordered sequence of polygon rings.
 *
 * Supported scalar types are `int`, `long`, `float`, `double`, and `real`.
 *
 * `PolygonView.init` is an empty polygon view.
 *
 * PolygonView does not allocate or copy ring descriptors or point data.
 * The caller retains ownership of both the backing ring-descriptor storage
 * and the point storage referenced by those descriptors. The ring-descriptor
 * storage must remain valid for the lifetime of the PolygonView. Point
 * storage referenced by a stored ring descriptor must remain valid for as
 * long as that descriptor can be accessed through the PolygonView.
 *
 * The view aliases this backing storage. Changes made through the owners of
 * mutable ring-descriptor or point storage remain visible through an
 * existing PolygonView. Mutation is not exposed through PolygonView itself.
 *
 * For a non-empty polygon, ring zero is the exterior ring. Subsequent rings
 * are interior rings. Ring roles are structural and do not depend on
 * winding direction.
 *
 * PolygonView does not validate topology or normalize ring orientation.
 * Empty and degenerate rings remain representable through LinearRingView.
 */
struct PolygonView(T)
if (isGeoScalar!T)
{
private:
    const(LinearRingView!T)[] _rings;

public:
    /**
     * Constructs a view over contiguous ring-descriptor storage.
     *
     * No ring descriptors or point data are copied and no normalization
     * is performed.
     */
    this(
        return scope const(LinearRingView!T)[] rings
    )
        pure nothrow @safe @nogc
    {
        _rings = rings;
    }


    /// Number of rings, including the exterior ring when present.
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _rings.length;
    }


    /// True when the polygon contains no rings.
    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return _rings.length == 0;
    }


    /**
     * Number of interior rings.
     */
    @property size_t holeCount() const
        pure nothrow @safe @nogc
    {
        return _rings.length > 0
            ? _rings.length - 1
            : 0;
    }


    /**
     * Returns one ring descriptor by value.
     *
     * Ring zero is the exterior ring. Subsequent rings are interior rings.
     */
    const(LinearRingView!T) opIndex(size_t index) const
        pure nothrow @safe @nogc
    {
        return _rings[index];
    }


    /**
     * Returns the exterior ring by value.
     *
     * The polygon must be non-empty. Invalid access retains normal D
     * bounds semantics.
     */
    @property const(LinearRingView!T) exterior() const
        pure nothrow @safe @nogc
    {
        return _rings[0];
    }


    /**
     * Returns one interior ring by zero-based hole index.
     *
     * Valid indices are:
     *
     *     0 .. holeCount
     */
    const(LinearRingView!T) hole(size_t index) const
        pure nothrow @safe @nogc
    {
        /*
         * Slice first so the caller-visible index remains zero-based and
         * no index + 1 arithmetic can wrap.
         */
        return _rings[1 .. $][index];
    }
}


@safe unittest
{
    import geo.point : Point2;
    import std.meta : AliasSeq;


    /*
     * PolygonView follows the LinearRingView scalar domain.
     */
    static foreach (T; AliasSeq!(int, long, float, double, real))
    {
        static assert(PolygonView!T.init.length == 0);
        static assert(PolygonView!T.init.empty);
        static assert(PolygonView!T.init.holeCount == 0);
    }


    /*
     * Unsupported scalar types remain unavailable.
     */
    static assert(!__traits(compiles, PolygonView!byte));
    static assert(!__traits(compiles, PolygonView!short));
    static assert(!__traits(compiles, PolygonView!uint));
    static assert(!__traits(compiles, PolygonView!ulong));


    alias P = Point2!double;
    alias R = LinearRingView!double;
    alias V = PolygonView!double;


    /*
     * Empty descriptor storage produces an empty polygon.
     */
    R[] noRings;

    auto emptyPolygon =
        V(noRings);

    assert(emptyPolygon.empty);
    assert(emptyPolygon.length == 0);
    assert(emptyPolygon.holeCount == 0);


    /*
     * A single ring is the exterior ring and produces no holes.
     */
    P[3] exteriorPoints = [
        P(0.0, 0.0),
        P(6.0, 0.0),
        P(0.0, 6.0)
    ];

    R[1] exteriorOnlyRings = [
        R(exteriorPoints[])
    ];

    auto exteriorOnly =
        V(exteriorOnlyRings[]);

    assert(!exteriorOnly.empty);
    assert(exteriorOnly.length == 1);
    assert(exteriorOnly.holeCount == 0);

    assert(exteriorOnly[0].length == 3);
    assert(exteriorOnly.exterior.length == 3);
    assert(exteriorOnly.exterior[1] == P(6.0, 0.0));


    /*
     * Ring order is preserved. Different rings may use independent point
     * storage.
     */
    P[3] firstHolePoints = [
        P(1.0, 1.0),
        P(2.0, 1.0),
        P(1.0, 2.0)
    ];

    P[4] secondHolePoints = [
        P(3.0, 3.0),
        P(4.0, 3.0),
        P(4.0, 4.0),
        P(3.0, 4.0)
    ];


    /*
     * Alternative backing storage is declared before the descriptor
     * array so its lifetime encloses every descriptor that may refer to
     * it.
     */
    P[3] replacementHolePoints = [
        P(10.0, 10.0),
        P(12.0, 10.0),
        P(10.0, 12.0)
    ];

    immutable P[3] immutableHolePoints = [
        P(-3.0, -3.0),
        P(-2.0, -3.0),
        P(-3.0, -2.0)
    ];


    R[3] rings = [
        R(exteriorPoints[]),
        R(firstHolePoints[]),
        R(secondHolePoints[])
    ];

    auto polygon =
        V(rings[]);

    assert(polygon.length == 3);
    assert(polygon.holeCount == 2);

    assert(polygon[0][0] == exteriorPoints[0]);
    assert(polygon[1][0] == firstHolePoints[0]);
    assert(polygon[2][0] == secondHolePoints[0]);

    assert(polygon.exterior[2] == exteriorPoints[2]);
    assert(polygon.hole(0)[1] == firstHolePoints[1]);
    assert(polygon.hole(1)[2] == secondHolePoints[2]);


    /*
     * The polygon does not own or copy the ring-descriptor storage.
     *
     * Replacing a descriptor through its owner remains visible through
     * the existing polygon view.
     */
    rings[1] =
        R(replacementHolePoints[]);

    assert(
        polygon.hole(0)[0] ==
        P(10.0, 10.0)
    );


    /*
     * Point storage is likewise still owned externally and remains
     * visible through the nested views.
     */
    replacementHolePoints[1] =
        P(20.0, 30.0);

    assert(
        polygon.hole(0)[1] ==
        P(20.0, 30.0)
    );


    /*
     * Rings backed by immutable point storage are directly usable.
     */
    rings[2] =
        R(immutableHolePoints[]);

    assert(
        polygon.hole(1)[2] ==
        P(-3.0, -2.0)
    );


    /*
     * Mutation of ring descriptors is not exposed through PolygonView.
     */
    static assert(
        !__traits(
            compiles,
            {
                R[1] backing;

                auto readOnly =
                    V(backing[]);

                readOnly[0] =
                    R.init;
            }
        )
    );
}
