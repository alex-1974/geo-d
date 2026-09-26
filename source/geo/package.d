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
 * - points, vectors, segments, unbounded lines, and bounds;
 * - non-owning polyline, linear-ring, and polygon views;
 * - scalar conversion and explicit floating-point quantization;
 * - axis-aligned geometry bounds;
 * - distance, vector metric/directional, and nearest-point operations;
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
  *
 * Authors:
 *     Alexander Bernardi
 *
 * Copyright:
 *     Copyright © 2026 Alexander Bernardi
 *
 * License:
 *     MIT
 *
 * Date:
 *     September 25, 2026
 */
module geo;

public import geo.area :
    AreaScalar,
    polygonArea,
    signedArea;

public import geo.bounding_box : tryBounds;
public import geo.bounds : Bounds2;
public import geo.convert :
    ceiled,
    floored,
    rounded,
    truncated,
    tryConvert;

public import geo.linear_ring_view :
    LinearRing2View;

/**
 * Deprecated v1 spelling of `LinearRing2View`.
 */
deprecated("Use LinearRing2View")
alias LinearRingView =
    LinearRing2View;

public import geo.point : Point2;
public import geo.line : Line2;
public import geo.polygon_view :
    Polygon2View;

/**
 * Deprecated v1 spelling of `Polygon2View`.
 */
deprecated("Use Polygon2View")
alias PolygonView =
    Polygon2View;

public import geo.point_in_polygon :
    PointPolygonLocation,
    tryClassifyPointInPolygon;
public import geo.polyline_view :
    Polyline2View;

/**
 * Deprecated v1 spelling of `Polyline2View`.
 */
deprecated("Use Polyline2View")
alias PolylineView =
    Polyline2View;

public import geo.scalar : isGeoScalar;
public import geo.vector :
    Vector2,
    perpendicularCCW;

public import geo.segment : Segment2;

public import geo.metric :
    MetricScalar,
    distance,
    dot,
    norm,
    polylineLength,
    segmentLength,
    squaredDistance,
    squaredNorm,
    tryNearestPoint,
    tryNormalize,
    tryPointSegmentDistance,
    trySignedAngle;

public import geo.orientation :
    Orientation2,
    orientation;

/**
 * Deprecated v1 spelling of `Orientation2`.
 */
deprecated("Use Orientation2")
alias Orientation =
    Orientation2;

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
