module polygon_negative;

import geo;

@safe PolygonView!double escape()
{
    LinearRingView!double[1] local;

    return PolygonView!double(local[]);
}
