module polygon_positive;

import geo;

@safe void probe()
{
    LinearRingView!double[1] local;

    auto polygon =
        PolygonView!double(local[]);

    assert(polygon.length == 1);
}
