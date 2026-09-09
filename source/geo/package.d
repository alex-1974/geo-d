module geo;

public import geo.bounds : Bounds2;
public import geo.convert :
    ceiled,
    floored,
    rounded,
    truncated,
    tryConvert;

public import geo.point : Point2;
public import geo.scalar : isGeoScalar;
public import geo.vector : Vector2;

public import geo.segment : Segment2;

public import geo.metric :
    MetricScalar,
    distance,
    segmentLength,
    squaredDistance,
    tryNearestPoint;

public import geo.orientation :
    Orientation,
    orientation;
