module ring_positive;

import geo;

@safe void probe()
{
    Point2!double[3] local;

    auto ring =
        LinearRingView!double(local[]);

    assert(ring.length == 3);
}
