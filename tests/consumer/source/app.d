/**
 * External compile-time consumer verification for geo-d.
 *
 * This package deliberately imports only the supported package entry point:
 *
 *     import geo;

import init_contract;
import named_arguments;
 *
 * It verifies the frozen v1 public names from outside the geo-d package and
 * compiles representative operations through that surface.
 */
module app;

import geo;


/*
 * Frozen v1 public top-level surface.
 *
 * Keep this list synchronized with docs/api-freeze-v1.0.0.md and
 * source/geo/package.d. Changing it requires reopening the API freeze.
 */
enum string[] frozenPublicNames = [
    "Point2",
    "Vector2",
    "Bounds2",
    "Segment2",
    "PolylineView",
    "LinearRingView",
    "PolygonView",

    "isGeoScalar",
    "tryConvert",
    "rounded",
    "floored",
    "ceiled",
    "truncated",

    "tryBounds",

    "MetricScalar",
    "distance",
    "squaredDistance",
    "segmentLength",
    "polylineLength",
    "tryNearestPoint",
    "tryPointSegmentDistance",

    "Orientation",
    "orientation",

    "IntersectionScalar",
    "SegmentIntersectionKind",
    "segmentIntersectionKind",
    "trySegmentIntersectionPoint",
    "trySegmentIntersectionOverlap",

    "AreaScalar",
    "signedArea",
    "polygonArea",

    "PointPolygonLocation",
    "tryClassifyPointInPolygon",

    "RingValidationIssue",
    "RingValidationResult",
    "PolygonValidationIssue",
    "PolygonValidationResult",
    "validateRing",
    "validatePolygon",

    "douglasPeuckerWorkspaceSize",
    "trySimplifyDouglasPeuckerInto",
];

static assert(frozenPublicNames.length == 41);

static foreach (name; frozenPublicNames)
{
    static assert(
        __traits(hasMember, geo, name),
        "frozen public name missing from import geo: " ~ name
    );
}


/*
 * Consumer-driven vector primitive family added after the v2.0 freeze.
 */
enum string[] a1VectorPrimitiveNames = [
    "dot",
    "squaredNorm",
    "norm",
    "tryNormalize",
    "trySignedAngle",
    "perpendicularCCW",
];

static foreach (name; a1VectorPrimitiveNames)
{
    static assert(
        __traits(hasMember, geo, name),
        "A1 public name missing from import geo: " ~ name
    );
}


/*
 * Representative type and policy instantiation through import geo.
 */
static assert(isGeoScalar!int);
static assert(isGeoScalar!long);
static assert(isGeoScalar!float);
static assert(isGeoScalar!double);
static assert(isGeoScalar!real);

static assert(is(MetricScalar!int == double));
static assert(is(IntersectionScalar!double == double));
static assert(is(AreaScalar!long == double));

static assert(is(typeof(Point2!double.init) == Point2!double));
static assert(is(typeof(Vector2!double.init) == Vector2!double));
static assert(is(typeof(Segment2!double.init) == Segment2!double));
static assert(is(typeof(Bounds2!double.init) == Bounds2!double));
static assert(is(typeof(PolylineView!double.init) == PolylineView!double));
static assert(is(typeof(LinearRingView!double.init) == LinearRingView!double));
static assert(is(typeof(PolygonView!double.init) == PolygonView!double));


/*
 * Scalar-domain contract.
 *
 * `real` belongs to the general geo-d scalar domain and is supported by
 * storage, affine geometry, bounds, conversion, metric operations, and
 * metric simplification.
 *
 * Robust topology and exact/correctly-rounded area deliberately exclude
 * `real` until geo-d has a platform-aware exact backend for that scalar.
 */
static assert(isGeoScalar!real);

static assert(is(Point2!real));
static assert(is(Vector2!real));
static assert(is(Segment2!real));
static assert(is(Bounds2!real));
static assert(is(PolylineView!real));
static assert(is(LinearRingView!real));
static assert(is(PolygonView!real));

static assert(is(MetricScalar!real == real));

static assert(
    __traits(
        compiles,
        {
            Bounds2!real result;

            tryBounds(
                Segment2!real.init,
                result
            );
        }
    )
);

static assert(
    __traits(
        compiles,
        {
            Point2!double result;

            tryConvert!double(
                Point2!real.init,
                result
            );
        }
    )
);

static assert(
    __traits(
        compiles,
        {
            const real value =
                distance(
                    Point2!real.init,
                    Point2!real.init
                );
        }
    )
);

static assert(
    __traits(
        compiles,
        {
            Point2!real[3] input;
            Point2!real[3] output;
            size_t[1] workspace;
            size_t written;

            trySimplifyDouglasPeuckerInto(
                PolylineView!real(input[]),
                real(0),
                output[],
                workspace[],
                written
            );
        }
    )
);


/*
 * Robust topology and exact area currently have the narrower scalar
 * domain int | long | float | double.
 */
static assert(
    !__traits(
        compiles,
        {
            const value =
                orientation(
                    Point2!real.init,
                    Point2!real.init,
                    Point2!real.init
                );
        }
    )
);

static assert(
    !__traits(
        compiles,
        {
            const value =
                segmentIntersectionKind(
                    Segment2!real.init,
                    Segment2!real.init
                );
        }
    )
);

static assert(
    !__traits(
        compiles,
        {
            Point2!double point;

            trySegmentIntersectionPoint(
                Segment2!real.init,
                Segment2!real.init,
                point
            );
        }
    )
);

static assert(
    !__traits(
        compiles,
        {
            Segment2!real overlap;

            trySegmentIntersectionOverlap(
                Segment2!real.init,
                Segment2!real.init,
                overlap
            );
        }
    )
);

static assert(
    !__traits(
        compiles,
        {
            const value =
                signedArea(
                    LinearRingView!real.init
                );
        }
    )
);

static assert(
    !__traits(
        compiles,
        {
            const value =
                polygonArea(
                    PolygonView!real.init
                );
        }
    )
);

static assert(
    !__traits(
        compiles,
        {
            PointPolygonLocation location;

            tryClassifyPointInPolygon(
                PolygonView!real.init,
                Point2!real.init,
                location
            );
        }
    )
);

static assert(
    !__traits(
        compiles,
        {
            const result =
                validateRing(
                    LinearRingView!real.init
                );
        }
    )
);

static assert(
    !__traits(
        compiles,
        {
            const result =
                validatePolygon(
                    PolygonView!real.init
                );
        }
    )
);


@safe void main()
{
    alias P = Point2!double;
    alias S = Segment2!double;
    alias R = LinearRingView!double;
    alias G = PolygonView!double;

    /*
     * Core affine and metric surface.
     */
    const P a = P(0.0, 0.0);
    const P b = P(3.0, 4.0);

    assert(distance(a, b) == 5.0);
    assert(squaredDistance(a, b) == 25.0);

    const S segment = S(a, b);

    assert(segmentLength(segment) == 5.0);

    Bounds2!double bounds;

    assert(tryBounds(segment, bounds));
    assert(bounds.contains(a));
    assert(bounds.contains(b));


    /*
     * Conversion and quantisation surface.
     */
    Point2!int converted;

    assert(
        tryConvert!int(
            P(2.0, -3.0),
            converted
        )
    );

    assert(converted == Point2!int(2, -3));

    const P quantised =
        P(1.5, -2.5).rounded;

    assert(quantised == P(2.0, -3.0));


    /*
     * Robust topology surface.
     */
    assert(
        orientation(
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(0.0, 4.0)
        ) == Orientation.left
    );

    const S first = S(
        P(0.0, 0.0),
        P(4.0, 4.0)
    );

    const S second = S(
        P(0.0, 4.0),
        P(4.0, 0.0)
    );

    assert(
        segmentIntersectionKind(
            first,
            second
        ) == SegmentIntersectionKind.point
    );


    /*
     * Ring, polygon, area, classification, and validation surface.
     */
    P[4] exteriorPoints = [
        P(0.0, 0.0),
        P(10.0, 0.0),
        P(10.0, 10.0),
        P(0.0, 10.0)
    ];

    R exterior =
        R(exteriorPoints[]);

    assert(signedArea(exterior) == 100.0);

    R[1] rings = [
        exterior
    ];

    G polygon =
        G(rings[]);

    assert(polygonArea(polygon) == 100.0);

    PointPolygonLocation location;

    assert(
        tryClassifyPointInPolygon(
            polygon,
            P(5.0, 5.0),
            location
        )
    );

    assert(
        location ==
        PointPolygonLocation.inside
    );

    const ringValidation =
        validateRing(exterior);

    assert(ringValidation.valid);

    const polygonValidation =
        validatePolygon(polygon);

    assert(polygonValidation.valid);


    /*
     * Simplification surface.
     */
    P[3] simplifyInput = [
        P(0.0, 0.0),
        P(1.0, 0.0),
        P(2.0, 0.0)
    ];

    P[3] simplifyOutput;
    size_t[1] workspace;
    size_t written;

    assert(
        douglasPeuckerWorkspaceSize(
            simplifyInput.length
        ) == 1
    );

    assert(
        trySimplifyDouglasPeuckerInto(
            PolylineView!double(
                simplifyInput[]
            ),
            0.0,
            simplifyOutput[],
            workspace[],
            written
        )
    );

    assert(written == 2);
    assert(simplifyOutput[0] == simplifyInput[0]);
    assert(simplifyOutput[1] == simplifyInput[$ - 1]);
}
