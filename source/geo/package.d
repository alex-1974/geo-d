module geo;

public import geo.area :
    AreaScalar,
    polygonArea,
    signedArea;

public import geo.bounds : Bounds2;
public import geo.convert :
    ceiled,
    floored,
    rounded,
    truncated,
    tryConvert;

public import geo.linear_ring_view : LinearRingView;
public import geo.point : Point2;
public import geo.polygon_view : PolygonView;

public import geo.point_in_polygon :
    PointPolygonLocation,
    tryClassifyPointInPolygon;
public import geo.polyline_view : PolylineView;
public import geo.scalar : isGeoScalar;
public import geo.vector : Vector2;

public import geo.segment : Segment2;

public import geo.metric :
    MetricScalar,
    distance,
    polylineLength,
    segmentLength,
    squaredDistance,
    tryNearestPoint;

public import geo.orientation :
    Orientation,
    orientation;
public import geo.intersection :
    IntersectionScalar,
    SegmentIntersectionKind,
    segmentIntersectionKind,
    trySegmentIntersectionOverlap,
    trySegmentIntersectionPoint;

public import geo.topology_validation :
    PolygonValidationIssue,
    PolygonValidationResult,
    RingValidationIssue,
    RingValidationResult,
    validatePolygon,
    validateRing;
