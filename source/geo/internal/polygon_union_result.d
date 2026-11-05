module geo.internal.polygon_union_result;

import geo.linear_ring_view :
    LinearRing2View;

import geo.point :
    Point2;

import geo.polygon_view :
    Polygon2View;

import std.exception :
    assumeUnique;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Immutable owning storage for a successfully materialized polygon-union
 * result.
 *
 * This is deliberately not the final public API name or spelling.
 */


package(geo)
struct PolygonUnionOwnedResultInternal
{
private:
    immutable(Point2!double)[] _points;

    immutable(LinearRing2View!double)[] _rings;

    immutable(size_t)[] _componentRingOffsets;

public:
    @property size_t componentCount() const
        pure nothrow @safe @nogc
    {
        return
            _componentRingOffsets.length > 0
                ? _componentRingOffsets.length - 1
                : 0;
    }


    @property size_t ringCount() const
        pure nothrow @safe @nogc
    {
        return _rings.length;
    }


    @property size_t pointCount() const
        pure nothrow @safe @nogc
    {
        return _points.length;
    }


    Polygon2View!double component(
        size_t index
    ) const
        pure nothrow @safe @nogc
    {
        assert(index < componentCount);

        const size_t begin =
            _componentRingOffsets[index];

        const size_t end =
            _componentRingOffsets[
                index + 1
            ];

        return
            Polygon2View!double(
                _rings[
                    begin ..
                    end
                ]
            );
    }
}


/*
 * Consumes already validated mutable build storage and freezes it into one
 * immutable owning result without a second point copy.
 *
 * Preconditions:
 *
 * - points contains the canonical flat ring-point storage;
 * - ringPointOffsets indexes every ring in points;
 * - componentRingOffsets indexes the canonical exterior+holes ring groups;
 * - the materialization/topology gate has already succeeded;
 * - points and componentRingOffsets have no mutable aliases that outlive this
 *   call.
 *
 * ringPointOffsets is build metadata only and is not retained.
 *
 * @trusted is deliberately narrow:
 *
 * std.exception.assumeUnique transfers the sole mutable access path of the two
 * consumed dynamic arrays into immutable backing and nulls the source slices.
 * Ring descriptors are created only after point backing is immutable, then
 * their sole mutable array is likewise frozen before publication.
 *
 * Resource allocation failure remains a runtime resource failure and is not a
 * geometric construction status.
 */
package(geo)
PolygonUnionOwnedResultInternal
takePolygonUnionOwnedResultInternal(
    ref Point2!double[] points,
    scope const(size_t)[] ringPointOffsets,
    ref size_t[] componentRingOffsets
)
    @trusted
{
    assert(ringPointOffsets.length > 0);
    assert(ringPointOffsets[0] == 0);

    assert(
        ringPointOffsets[$ - 1] ==
        points.length
    );

    foreach (i; 1 .. ringPointOffsets.length)
    {
        assert(
            ringPointOffsets[i - 1] <=
            ringPointOffsets[i]
        );
    }

    const size_t ringCount =
        ringPointOffsets.length - 1;

    assert(
        componentRingOffsets.length > 0
    );

    assert(
        componentRingOffsets[0] == 0
    );

    assert(
        componentRingOffsets[$ - 1] ==
        ringCount
    );

    foreach (i; 1 .. componentRingOffsets.length)
    {
        assert(
            componentRingOffsets[i - 1] <=
            componentRingOffsets[i]
        );
    }


    auto frozenPoints =
        assumeUnique(points);

    assert(points is null);


    auto rings =
        new LinearRing2View!double[
            ringCount
        ];

    foreach (ringIndex; 0 .. ringCount)
    {
        rings[ringIndex] =
            LinearRing2View!double(
                frozenPoints[
                    ringPointOffsets[
                        ringIndex
                    ] ..
                    ringPointOffsets[
                        ringIndex + 1
                    ]
                ]
            );
    }


    auto frozenRings =
        assumeUnique(rings);

    assert(rings is null);


    auto frozenComponentRingOffsets =
        assumeUnique(
            componentRingOffsets
        );

    assert(
        componentRingOffsets is null
    );


    return
        PolygonUnionOwnedResultInternal(
            frozenPoints,
            frozenRings,
            frozenComponentRingOffsets
        );
}


@safe unittest
{
    /*
     * Empty union result owns no points/rings and exposes zero components.
     */
    Point2!double[] points;

    const size_t[1] ringPointOffsets = [
        0,
    ];

    size_t[] componentRingOffsets = [
        0,
    ];

    auto result =
        takePolygonUnionOwnedResultInternal(
            points,
            ringPointOffsets[],
            componentRingOffsets
        );

    assert(points is null);
    assert(componentRingOffsets is null);

    assert(result.componentCount == 0);
    assert(result.ringCount == 0);
    assert(result.pointCount == 0);
}


@safe unittest
{
    alias P = Point2!double;


    /*
     * Two canonical components:
     *
     * component 0
     *     exterior + one hole
     *
     * component 1
     *     exterior only
     */
    P[] points = [
        P(0.0, 0.0),
        P(10.0, 0.0),
        P(10.0, 10.0),
        P(0.0, 10.0),

        P(2.0, 2.0),
        P(2.0, 4.0),
        P(4.0, 4.0),
        P(4.0, 2.0),

        P(20.0, 20.0),
        P(22.0, 20.0),
        P(22.0, 22.0),
        P(20.0, 22.0),
    ];

    const size_t[4] ringPointOffsets = [
        0,
        4,
        8,
        12,
    ];

    size_t[] componentRingOffsets = [
        0,
        2,
        3,
    ];

    auto result =
        takePolygonUnionOwnedResultInternal(
            points,
            ringPointOffsets[],
            componentRingOffsets
        );

    assert(points is null);
    assert(componentRingOffsets is null);

    assert(result.componentCount == 2);
    assert(result.ringCount == 3);
    assert(result.pointCount == 12);


    const auto first =
        result.component(0);

    const auto second =
        result.component(1);

    assert(first.length == 2);
    assert(first.holeCount == 1);

    assert(
        first.exterior[0] ==
        P(0.0, 0.0)
    );

    assert(
        first.hole(0)[2] ==
        P(4.0, 4.0)
    );

    assert(second.length == 1);
    assert(second.holeCount == 0);

    assert(
        second.exterior[2] ==
        P(22.0, 22.0)
    );


    /*
     * Ordinary descriptor copy shares immutable backing.
     */
    auto copy =
        result;

    assert(
        copy._points is
        result._points
    );

    assert(
        copy._rings is
        result._rings
    );

    assert(
        copy._componentRingOffsets is
        result._componentRingOffsets
    );


    /*
     * A borrowed Polygon2View remains valid after the original owning
     * descriptor is dropped because its backing is GC-managed immutable
     * storage.
     */
    auto retained =
        result.component(0);

    result =
        PolygonUnionOwnedResultInternal.init;

    assert(retained.length == 2);

    assert(
        retained.exterior[1] ==
        P(10.0, 0.0)
    );

    assert(
        retained.hole(0)[1] ==
        P(2.0, 4.0)
    );


    /*
     * The copied owner remains usable and did not deep-copy.
     */
    assert(copy.componentCount == 2);

    assert(
        copy.component(1).exterior[0] ==
        P(20.0, 20.0)
    );
}


@safe unittest
{
    alias P = Point2!double;


    /*
     * The exposed component view remains read-only.
     */
    P[] points = [
        P(0.0, 0.0),
        P(1.0, 0.0),
        P(0.0, 1.0),
    ];

    const size_t[2] ringPointOffsets = [
        0,
        3,
    ];

    size_t[] componentRingOffsets = [
        0,
        1,
    ];

    auto result =
        takePolygonUnionOwnedResultInternal(
            points,
            ringPointOffsets[],
            componentRingOffsets
        );

    const auto view =
        result.component(0);

    static assert(
        !__traits(
            compiles,
            {
                view.exterior[0] =
                    P(9.0, 9.0);
            }
        )
    );
}
