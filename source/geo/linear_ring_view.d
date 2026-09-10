module geo.linear_ring_view;

import geo.point : Point2;
import geo.scalar : isGeoScalar;
import geo.segment : Segment2;


/**
 * Non-owning read-only view of an ordered cyclic sequence of 2D points.
 *
 * LinearRingView does not allocate or copy point data. The caller retains
 * ownership of the backing storage, which must remain valid for the
 * lifetime of the view.
 *
 * Closure is implicit: for a non-empty ring the final stored vertex is
 * connected back to the first stored vertex.
 *
 * Empty and degenerate rings are valid representations.
 */
struct LinearRingView(T)
if (isGeoScalar!T)
{
private:
    const(Point2!T)[] _points;

public:
    /**
     * Constructs a view over contiguous point storage.
     *
     * No point data is copied and no normalization is performed.
     */
    this(return scope const(Point2!T)[] points)
        pure nothrow @safe @nogc
    {
        _points = points;
    }


    /// Number of stored vertices.
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        return _points.length;
    }


    /// True when the ring contains no stored vertices.
    @property bool empty() const
        pure nothrow @safe @nogc
    {
        return _points.length == 0;
    }


    /**
     * Number of segments in the cyclic traversal.
     *
     * An empty ring contains no segments. Every non-empty ring contains
     * one segment per stored vertex, including the implicit closing
     * segment.
     */
    @property size_t segmentCount() const
        pure nothrow @safe @nogc
    {
        return _points.length;
    }


    /**
     * Returns one vertex by value.
     */
    Point2!T opIndex(size_t index) const
        pure nothrow @safe @nogc
    {
        return Point2!T(
            _points[index].x,
            _points[index].y
        );
    }


    /**
     * Returns one segment in stored traversal order.
     *
     * The final segment closes the ring by connecting the final stored
     * vertex back to the first stored vertex.
     *
     * Valid indices are:
     *
     *     0 .. segmentCount
     */
    Segment2!T segment(size_t index) const
        pure nothrow @safe @nogc
    {
        /*
         * Access first so an invalid index retains the normal D bounds
         * semantics before calculating the cyclic successor.
         */
        const current = _points[index];

        const size_t next =
            index + 1 == _points.length
                ? 0
                : index + 1;

        return Segment2!T(
            Point2!T(current.x, current.y),
            Point2!T(
                _points[next].x,
                _points[next].y
            )
        );
    }
}


@safe unittest
{
    import std.meta : AliasSeq;


    /*
     * LinearRingView follows the Point2 scalar domain.
     */
    static foreach (T; AliasSeq!(int, long, float, double, real))
    {
        static assert(LinearRingView!T.init.length == 0);
        static assert(LinearRingView!T.init.empty);
        static assert(LinearRingView!T.init.segmentCount == 0);
    }


    /*
     * Unsupported scalar types remain unavailable.
     */
    static assert(!__traits(compiles, LinearRingView!byte));
    static assert(!__traits(compiles, LinearRingView!short));
    static assert(!__traits(compiles, LinearRingView!uint));
    static assert(!__traits(compiles, LinearRingView!ulong));


    alias P = Point2!double;
    alias S = Segment2!double;
    alias R = LinearRingView!double;


    /*
     * Empty storage produces an empty ring with no segments.
     */
    P[] noPoints;

    auto emptyRing =
        R(noPoints);

    assert(emptyRing.empty);
    assert(emptyRing.length == 0);
    assert(emptyRing.segmentCount == 0);


    /*
     * A singleton is a valid degenerate ring.
     *
     * Its only segment closes the sole vertex onto itself.
     */
    P[1] singletonPoints = [
        P(1.0, 2.0)
    ];

    auto singleton =
        R(singletonPoints[]);

    assert(!singleton.empty);
    assert(singleton.length == 1);
    assert(singleton.segmentCount == 1);
    assert(singleton[0] == P(1.0, 2.0));
    assert(
        singleton.segment(0) ==
        S(
            P(1.0, 2.0),
            P(1.0, 2.0)
        )
    );


    /*
     * Two vertices produce two opposite directed segments.
     */
    P[2] twoPoints = [
        P(1.0, 2.0),
        P(3.0, 4.0)
    ];

    auto twoVertexRing =
        R(twoPoints[]);

    assert(twoVertexRing.length == 2);
    assert(twoVertexRing.segmentCount == 2);

    assert(
        twoVertexRing.segment(0) ==
        S(
            P(1.0, 2.0),
            P(3.0, 4.0)
        )
    );

    assert(
        twoVertexRing.segment(1) ==
        S(
            P(3.0, 4.0),
            P(1.0, 2.0)
        )
    );


    /*
     * Ordinary rings preserve stored vertex order and close implicitly.
     */
    P[3] points = [
        P(0.0, 0.0),
        P(4.0, 0.0),
        P(0.0, 3.0)
    ];

    auto ring =
        R(points[]);

    assert(ring.length == 3);
    assert(ring.segmentCount == 3);

    assert(ring[0] == points[0]);
    assert(ring[1] == points[1]);
    assert(ring[2] == points[2]);

    assert(
        ring.segment(0) ==
        S(points[0], points[1])
    );

    assert(
        ring.segment(1) ==
        S(points[1], points[2])
    );

    assert(
        ring.segment(2) ==
        S(points[2], points[0])
    );


    /*
     * A repeated final vertex is retained as supplied.
     *
     * It is not interpreted or removed as an explicit closure marker.
     */
    P[4] explicitlyClosed = [
        P(0.0, 0.0),
        P(4.0, 0.0),
        P(0.0, 3.0),
        P(0.0, 0.0)
    ];

    auto repeated =
        R(explicitlyClosed[]);

    assert(repeated.length == 4);
    assert(repeated.segmentCount == 4);

    assert(
        repeated.segment(2) ==
        S(
            P(0.0, 3.0),
            P(0.0, 0.0)
        )
    );

    assert(
        repeated.segment(3) ==
        S(
            P(0.0, 0.0),
            P(0.0, 0.0)
        )
    );


    /*
     * The ring view aliases rather than copies mutable backing storage.
     */
    points[1] =
        P(8.0, 0.0);

    assert(ring[1] == P(8.0, 0.0));

    assert(
        ring.segment(0) ==
        S(
            P(0.0, 0.0),
            P(8.0, 0.0)
        )
    );


    /*
     * Mutation is not available through LinearRingView.
     */
    static assert(
        !__traits(
            compiles,
            {
                P[1] backing;

                auto readOnly =
                    R(backing[]);

                readOnly[0] =
                    P(7.0, 8.0);
            }
        )
    );


    /*
     * Immutable backing storage is directly viewable.
     */
    immutable P[3] immutablePoints = [
        P(-1.0, 0.0),
        P(1.0, 0.0),
        P(0.0, 2.0)
    ];

    auto immutableRing =
        R(immutablePoints[]);

    assert(immutableRing.length == 3);
    assert(immutableRing.segmentCount == 3);
    assert(immutableRing[0] == P(-1.0, 0.0));


    /*
     * DIP1000 must reject a view escaping stack-owned backing storage.
     */
    static assert(
        !__traits(
            compiles,
            {
                @safe R invalidEscape()
                {
                    P[3] local;

                    return R(local[]);
                }
            }
        )
    );
}
