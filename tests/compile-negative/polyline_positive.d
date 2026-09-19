module polyline_positive;

import geo;

@safe void probe()
{
    Point2!double[2] local;

    auto view =
        PolylineView!double(local[]);

    assert(view.length == 2);
}
