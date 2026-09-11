import geo;

void main()
{
    alias P = Point2!double;
    alias S = Segment2!double;
    alias R = LinearRingView!double;
    alias V = PolygonView!double;

    /*
     * Exact segment topology and rounded point construction.
     */
    const first =
        S(
            P(0.0, 0.0),
            P(10.0, 10.0)
        );

    const second =
        S(
            P(0.0, 10.0),
            P(10.0, 0.0)
        );

    assert(
        segmentIntersectionKind(
            first,
            second
        ) ==
        SegmentIntersectionKind.point
    );

    P intersection;

    assert(
        trySegmentIntersectionPoint(
            first,
            second,
            intersection
        )
    );

    assert(
        intersection ==
        P(5.0, 5.0)
    );


    /*
     * Non-owning polygon views.
     */
    P[4] exteriorPoints = [
        P(0.0, 0.0),
        P(10.0, 0.0),
        P(10.0, 10.0),
        P(0.0, 10.0)
    ];

    R exterior =
        R(exteriorPoints[]);

    R[1] rings = [
        exterior
    ];

    auto polygon =
        V(rings[]);

    assert(polygonArea(polygon) == 100.0);

    PointPolygonLocation location;

    assert(
        tryClassifyPointInPolygon(
            polygon,
            intersection,
            location
        )
    );

    assert(
        location ==
        PointPolygonLocation.inside
    );


    /*
     * Ordinary metric computation remains separate from topology.
     */
    assert(
        distance(
            P(0.0, 0.0),
            P(3.0, 4.0)
        ) ==
        5.0
    );
}
