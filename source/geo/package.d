/**
 * Public package module for geo-d.
 *
 * geo-d provides small, robust, coordinate-system-independent primitives and
 * algorithms for two-dimensional Euclidean geometry.
 *
 * Import this module to access the supported public API:
 *
 * ---
 * import geo;
 * ---
 *
 * The public API includes:
 *
 * - points, vectors, segments, and bounds;
 * - non-owning polyline, linear-ring, and polygon views;
 * - scalar conversion and explicit floating-point quantization;
 * - distance and nearest-point operations;
 * - robust orientation and segment-intersection predicates;
 * - signed and polygon area;
 * - point-in-polygon classification;
 * - ring and polygon topology validation;
 * - Douglas-Peucker polyline simplification.
 *
 * Numerical topology is deliberately separated from rounded geometric
 * construction. Robust predicates do not use a global epsilon.
 *
 * geo-d does not provide coordinate reference systems, projections,
 * ellipsoidal or geodesic calculations, raster processing, spatial indexes,
 * or geospatial file-format support.
 *
 * Variable-size geometry is represented by non-owning views. Low-level
 * numerical operations avoid hidden allocation; algorithms requiring
 * variable temporary storage document that requirement explicitly.
 */
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
    tryNearestPoint,
    tryPointSegmentDistance;

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

public import geo.simplification :
    douglasPeuckerWorkspaceSize,
    trySimplifyDouglasPeuckerInto;
