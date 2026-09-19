/**
 * External compatibility checks for public enum `.init` semantics.
 */
module init_contract;

import geo;


/*
 * Orientation has a valid but deliberately non-neutral default because
 * `right` is the first enum member.
 */
static assert(
    Orientation.init ==
    Orientation.right
);

static assert(
    SegmentIntersectionKind.init ==
    SegmentIntersectionKind.none
);

static assert(
    PointPolygonLocation.init ==
    PointPolygonLocation.outside
);

static assert(
    RingValidationIssue.init ==
    RingValidationIssue.none
);

static assert(
    PolygonValidationIssue.init ==
    PolygonValidationIssue.none
);
