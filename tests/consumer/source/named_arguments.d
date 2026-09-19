/**
 * External named-argument source-compatibility probes.
 *
 * The public v1 callable surface is tested through `import geo`.
 * These probes make public parameter names observable compatibility
 * evidence for compiler versions that support named arguments.
 */
module named_arguments;

import geo;

alias P = Point2!double;
alias V = Vector2!double;
alias B = Bounds2!double;
alias S = Segment2!double;
alias L = PolylineView!double;
alias R = LinearRingView!double;
alias G = PolygonView!double;


/*
 * Public constructors.
 */
static assert(__traits(compiles,
    P(x: 1.0, y: 2.0)));

static assert(__traits(compiles,
    V(x: 1.0, y: 2.0)));

static assert(__traits(compiles,
    S(a: P.init, b: P.init)));

static assert(__traits(compiles, {
    P[] points;
    auto value = L(points: points);
}));

static assert(__traits(compiles, {
    P[] points;
    auto value = R(points: points);
}));

static assert(__traits(compiles, {
    R[] rings;
    auto value = G(rings: rings);
}));


/*
 * Conversion.
 */
static assert(__traits(compiles, {
    Point2!int result;

    tryConvert!(int, double)(
        source: P.init,
        result: result
    );
}));

static assert(__traits(compiles, {
    Vector2!int result;

    tryConvert!(int, double)(
        source: V.init,
        result: result
    );
}));

static assert(__traits(compiles, {
    Segment2!int result;

    tryConvert!(int, double)(
        source: S.init,
        result: result
    );
}));


/*
 * Explicit floating-point quantisation.
 */
static assert(__traits(compiles,
    rounded(value: P.init)));

static assert(__traits(compiles,
    floored(value: P.init)));

static assert(__traits(compiles,
    ceiled(value: P.init)));

static assert(__traits(compiles,
    truncated(value: P.init)));


/*
 * Bounds overload family.
 */
static assert(__traits(compiles, {
    B result;

    tryBounds(
        segment: S.init,
        result: result
    );
}));

static assert(__traits(compiles, {
    B result;

    tryBounds(
        polyline: L.init,
        result: result
    );
}));

static assert(__traits(compiles, {
    B result;

    tryBounds(
        ring: R.init,
        result: result
    );
}));

static assert(__traits(compiles, {
    B result;

    tryBounds(
        polygon: G.init,
        result: result
    );
}));


/*
 * Metric surface.
 */
static assert(__traits(compiles,
    squaredDistance(
        a: P.init,
        b: P.init
    )));

static assert(__traits(compiles,
    distance(
        a: P.init,
        b: P.init
    )));

static assert(__traits(compiles, {
    double result;

    tryPointSegmentDistance!(
        double,
        double
    )(
        point: P.init,
        segment: S.init,
        result: result
    );
}));

static assert(__traits(compiles, {
    P result;

    tryNearestPoint!(
        double,
        double
    )(
        segment: S.init,
        point: P.init,
        result: result
    );
}));

static assert(__traits(compiles,
    segmentLength(
        segment: S.init
    )));

static assert(__traits(compiles,
    polylineLength(
        polyline: L.init
    )));


/*
 * Robust orientation.
 */
static assert(__traits(compiles,
    orientation(
        a: P.init,
        b: P.init,
        c: P.init
    )));


/*
 * Segment intersection.
 */
static assert(__traits(compiles,
    segmentIntersectionKind(
        first: S.init,
        second: S.init
    )));

static assert(__traits(compiles, {
    P point;

    trySegmentIntersectionPoint!(
        double,
        double
    )(
        first: S.init,
        second: S.init,
        point: point
    );
}));

static assert(__traits(compiles, {
    S overlap;

    trySegmentIntersectionOverlap(
        first: S.init,
        second: S.init,
        overlap: overlap
    );
}));


/*
 * Area.
 */
static assert(__traits(compiles,
    signedArea(
        ring: R.init
    )));

static assert(__traits(compiles,
    polygonArea(
        polygon: G.init
    )));


/*
 * Point-in-polygon.
 */
static assert(__traits(compiles, {
    PointPolygonLocation location;

    tryClassifyPointInPolygon(
        polygon: G.init,
        point: P.init,
        location: location
    );
}));


/*
 * Topology validation.
 */
static assert(__traits(compiles,
    validateRing(
        ring: R.init
    )));

static assert(__traits(compiles,
    validatePolygon(
        polygon: G.init
    )));


/*
 * Simplification.
 */
static assert(__traits(compiles,
    douglasPeuckerWorkspaceSize(
        pointCount: 3
    )));

static assert(__traits(compiles, {
    P[] destination;
    size_t[] workspace;
    size_t written;

    trySimplifyDouglasPeuckerInto!(
        double,
        double
    )(
        polyline: L.init,
        tolerance: 0.0,
        destination: destination,
        workspace: workspace,
        written: written
    );
}));


/*
 * Point2 public parameter-bearing members.
 */
static assert(__traits(compiles, {
    P p;
    V v;
    auto value = p.opBinary!"+"(rhs: v);
}));

static assert(__traits(compiles, {
    P p;
    V v;
    auto value = p.opBinaryRight!"+"(lhs: v);
}));

static assert(__traits(compiles, {
    P p;
    V v;
    auto value = p.opBinary!"-"(rhs: v);
}));

static assert(__traits(compiles, {
    P p;
    P q;
    auto value = p.opBinary!"-"(rhs: q);
}));

static assert(__traits(compiles, {
    P p;
    V v;
    p.opOpAssign!"+"(rhs: v);
}));

static assert(__traits(compiles, {
    P p;
    V v;
    p.opOpAssign!"-"(rhs: v);
}));


/*
 * Vector2 public parameter-bearing members.
 */
static assert(__traits(compiles, {
    V a;
    V b;
    auto value = a.opBinary!"+"(rhs: b);
}));

static assert(__traits(compiles, {
    V a;
    V b;
    auto value = a.opBinary!"-"(rhs: b);
}));

static assert(__traits(compiles, {
    V v;
    auto value = v.opBinary!"*"(rhs: 2.0);
}));

static assert(__traits(compiles, {
    V v;
    auto value = v.opBinaryRight!"*"(lhs: 2.0);
}));

static assert(__traits(compiles, {
    V v;
    auto value = v.opBinary!"/"(rhs: 2.0);
}));

static assert(__traits(compiles, {
    V a;
    V b;
    a.opOpAssign!"+"(rhs: b);
}));

static assert(__traits(compiles, {
    V a;
    V b;
    a.opOpAssign!"-"(rhs: b);
}));

static assert(__traits(compiles, {
    V v;
    v.opOpAssign!"*"(rhs: 2.0);
}));

static assert(__traits(compiles, {
    V v;
    v.opOpAssign!"/"(rhs: 2.0);
}));


/*
 * Bounds2 public parameter-bearing members.
 */
static assert(__traits(compiles, {
    B bounds;
    bounds.tryExtend(p: P.init);
}));

static assert(__traits(compiles, {
    B bounds;
    B other;
    bounds.extend(other: other);
}));

static assert(__traits(compiles, {
    B bounds;
    auto value = bounds.contains(p: P.init);
}));

static assert(__traits(compiles, {
    B bounds;
    B other;
    auto value = bounds.intersects(other: other);
}));

static assert(__traits(compiles, {
    B bounds;
    B rhs;
    auto value = bounds.opEquals(rhs: rhs);
}));


/*
 * View public parameter-bearing members.
 */
static assert(__traits(compiles, {
    L view;
    auto value = view.segment(index: 0);
}));

static assert(__traits(compiles, {
    L view;
    auto value = view.opIndex(index: 0);
}));

static assert(__traits(compiles, {
    R ring;
    auto value = ring.segment(index: 0);
}));

static assert(__traits(compiles, {
    R ring;
    auto value = ring.opIndex(index: 0);
}));

static assert(__traits(compiles, {
    G polygon;
    auto value = polygon.opIndex(index: 0);
}));

static assert(__traits(compiles, {
    G polygon;
    auto value = polygon.hole(index: 0);
}));
