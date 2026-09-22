/**
 * Durable 2D/3D Euclidean family coexistence verification.
 *
 * The root consumer imports both dimensional public facades simultaneously.
 * euclid-core-d is deliberately not a direct dependency of this consumer.
 */
module app;

import geo;
import geo3;


/*
 * All seven admitted dimension-neutral contracts must have one common
 * declaration identity across both dimensional siblings.
 */
static assert(
    __traits(isSame, geo.isGeoScalar, geo3.isGeoScalar)
);

static assert(
    __traits(isSame, geo.MetricScalar, geo3.MetricScalar)
);

static assert(
    __traits(
        isSame,
        geo.IntersectionScalar,
        geo3.IntersectionScalar
    )
);

static assert(
    __traits(
        isSame,
        geo.SegmentIntersectionKind,
        geo3.SegmentIntersectionKind
    )
);

static assert(
    __traits(
        isSame,
        geo.RingValidationIssue,
        geo3.RingValidationIssue
    )
);

static assert(
    __traits(
        isSame,
        geo.RingValidationResult,
        geo3.RingValidationResult
    )
);

static assert(
    __traits(
        isSame,
        geo.douglasPeuckerWorkspaceSize,
        geo3.douglasPeuckerWorkspaceSize
    )
);


/*
 * Shared names must remain usable without qualification after importing both
 * package facades.
 */
static assert(isGeoScalar!double);
static assert(is(MetricScalar!double == double));
static assert(is(IntersectionScalar!double == double));

static assert(
    SegmentIntersectionKind.init ==
    SegmentIntersectionKind.none
);

static assert(
    RingValidationIssue.init ==
    RingValidationIssue.none
);

static assert(RingValidationResult.init.valid);

static assert(
    douglasPeuckerWorkspaceSize(5) == 3
);


/*
 * Dimension-specific geometry and genuine shared operation families must
 * coexist in one compilation unit.
 */
alias P2 = Point2!double;
alias P3 = Point3!double;

static assert(
    is(typeof(distance(P2.init, P2.init)) == double)
);

static assert(
    is(typeof(distance(P3.init, P3.init)) == double)
);


@safe void main()
{
    P2 a2;
    P2 b2;

    P3 a3;
    P3 b3;

    assert(distance(a2, b2) == 0.0);
    assert(distance(a3, b3) == 0.0);

    RingValidationResult result;
    assert(result.valid);

    assert(
        douglasPeuckerWorkspaceSize(10) == 8
    );
}
