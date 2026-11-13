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
 * - analytic circles with checked construction and direct operations;
 * - explicit caller-owned circle polygonization;
 * - axis-aligned rectangles, fixed-cardinality triangles, and regular
 *   compile-time-cardinality polygons;
 * - non-owning polyline, linear-ring, and polygon views;
 * - scalar conversion and explicit floating-point quantization;
 * - axis-aligned geometry bounds;
 * - distance, vector metric/directional, and nearest-point operations;
 * - robust orientation and segment/line intersection predicates;
 * - signed and polygon area;
 * - point-in-polygon classification;
 * - ring and polygon topology validation;
 * - reduced exact polygon-to-polygon relationship classification;
 * - robust one-dimensional segment-to-polygon clipping construction;
 * - regularized polygon-union construction with immutable owning results;
 * - Douglas-Peucker polyline simplification.
 *
 * Numerical topology is deliberately separated from rounded geometric
 * construction. Robust predicates do not use a global epsilon.
 *
 * geo-d does not provide coordinate reference systems, projections,
 * ellipsoidal or geodesic calculations, raster processing, spatial indexes,
 * or geospatial file-format support.
 *
 * Input variable-size geometry is represented by non-owning views.
 * Constructed operations may return explicit owning immutable results when
 * output size is data dependent. Low-level numerical operations avoid hidden
 * allocation; algorithms requiring variable temporary storage document that
 * requirement explicitly.
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
 *     September 27, 2026
 */
module geo;

public import geo.area :
    AreaScalar,
    polygonArea,
    signedArea;
public import geo.anchor_binding :
    Anchor2,
    AnchorBinding2,
    AnchorKind2;
public import geo.anchor_binding : tryResolve;
public import geo.anchor_binding :
    bind,
    sourceEdge,
    sourceVertex,
    targetEdge,
    targetVertex;

public import geo.bounding_box : tryBounds;
public import geo.bounds : Bounds2;
public import geo.circle : Circle2;
public import geo.circular_arc : CircularArc2;
public import geo.circular_sector : CircularSector2;
public import geo.circular_segment : CircularSegment2;
public import geo.annulus : Annulus2;
public import geo.capsule : Capsule2;
public import geo.rounded_rectangle : RoundedRectangle2;
public import geo.ellipse : Ellipse2;
public import geo.circle : tryPolygonizeCircleInto;
public import geo.rect : Rect2;
public import geo.rectangle_shape : Rectangle2, RectangleLengths, Square2;
public import geo.quadrilateral : Quadrilateral2, QuadrilateralSideLengths;
public import geo.parallelogram : Parallelogram2;
public import geo.rhombus : Rhombus2;
public import geo.kite : Kite2;
public import geo.trapezoid : Trapezoid2;
public import geo.triangle :
    Triangle2,
    TriangleSideLengths;
public import geo.regular_polygon :
    Hexagon2,
    Heptagon2,
    Octagon2,
    Pentagon2,
    RegularPolygon2;
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
public import geo.polygon : Polygon2;
public import geo.polygon : sourceEdge, sourceVertex, targetEdge, targetVertex;

/**
 * Deprecated v1 spelling of `Polygon2View`.
 */
deprecated("Use Polygon2View")
alias PolygonView =
    Polygon2View;

public import geo.point_in_polygon :
    PointPolygonLocation,
    tryClassifyPointInPolygon;

public import geo.polygon_relationship :
    PolygonRelationship,
    PolygonRelationshipResult,
    PolygonRelationshipStatus,
    classifyPolygonRelationship;

public import geo.segment_polygon_relationship :
    SegmentPolygonRelationship,
    classifySegmentPolygonRelationship;

public import geo.segment_polygon_clip :
    SegmentPolygonClipResult,
    SegmentPolygonClipStatus,
    clipSegmentToPolygon;

public import geo.polygon_union :
    PolygonUnionResult,
    PolygonUnionStatus,
    polygonUnion;

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
public import geo.measure :
    Angle,
    Length,
    Size2,
    Size3;
public import geo.transform :
    Rotation2,
    Scale2,
    Transform2,
    Translation2;
public import geo.shape_result :
    ShapeConstructionResult,
    ShapeConstructionStatus;
public import geo.placement :
    CircleAnchor,
    EdgeAngle2,
    Placement2,
    ScalePolicy2,
    vertex,
    edge,
    RectAnchor,
    TriangleAnchor,
    VertexPlacement2;

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
    LineIntersectionKind,
    SegmentIntersectionKind,
    lineIntersectionKind,
    segmentIntersectionKind,
    tryLineIntersectionPoint,
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
