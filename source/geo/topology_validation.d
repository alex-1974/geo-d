module geo.topology_validation;

import geo.intersection :
    SegmentIntersectionKind,
    segmentIntersectionKind;

import geo.linear_ring_view :
    LinearRingView;

import geo.segment :
    Segment2;


/**
 * Validation issue detected in a LinearRingView.
 */
enum RingValidationIssue : ubyte
{
    none,
    tooFewVertices,
    nonFiniteCoordinate,
    zeroLengthEdge,
    selfIntersection,
    selfOverlap,
}


/**
 * Result of validating one LinearRingView.
 *
 * Ring edge index i denotes the implicit segment from vertex i to vertex
 * (i + 1) % length.
 *
 * size_t.max denotes an index that does not apply to the reported issue.
 */
struct RingValidationResult
{
    RingValidationIssue issue =
        RingValidationIssue.none;

    size_t primaryIndex =
        size_t.max;

    size_t secondaryIndex =
        size_t.max;


    /**
     * True when no validation issue was detected.
     */
    @property bool valid() const
        pure nothrow @safe @nogc
    {
        return issue ==
            RingValidationIssue.none;
    }
}


private enum bool isValidationScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/*
 * Constructs a deterministic diagnostic result.
 */
private RingValidationResult validationIssue(
    RingValidationIssue issue,
    size_t primaryIndex = size_t.max,
    size_t secondaryIndex = size_t.max
)
    pure nothrow @safe @nogc
{
    return RingValidationResult(
        issue,
        primaryIndex,
        secondaryIndex
    );
}


/*
 * Constructs ring edge index from the implicit ring closure.
 *
 * Preconditions:
 *
 *     ring.length > 0
 *     index < ring.length
 */
private Segment2!T ringEdge(T)(
    scope LinearRingView!T ring,
    size_t index
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
    const size_t next =
        index + 1 == ring.length
            ? 0
            : index + 1;

    return Segment2!T(
        ring[index],
        ring[next]
    );
}


/*
 * True when two ring edge indices are adjacent in the cyclic edge
 * sequence.
 *
 * Preconditions:
 *
 *     edgeCount >= 3
 *     first < second
 *     second < edgeCount
 */
private bool adjacentRingEdges(
    size_t first,
    size_t second,
    size_t edgeCount
)
    pure nothrow @safe @nogc
{
    return
        second == first + 1 ||
        (
            first == 0 &&
            second + 1 == edgeCount
        );
}


/**
 * Validates one LinearRingView.
 *
 * A valid ring:
 *
 * - has at least three stored vertices;
 * - contains only finite coordinates;
 * - has no zero-length implicit edge;
 * - is a simple closed polygonal curve.
 *
 * Ring orientation does not affect validity.
 *
 * The stored point sequence is closed implicitly. An explicitly repeated
 * copy of the first vertex therefore creates a zero-length closing edge and
 * is invalid.
 *
 * The first detected issue is returned deterministically.
 *
 * Complexity:
 *
 *     time  O(n^2)
 *     space O(1)
 */
RingValidationResult validateRing(T)(
    scope LinearRingView!T ring
)
    pure nothrow @safe @nogc
if (isValidationScalar!T)
{
    const size_t count =
        ring.length;


    /*
     * Minimum cardinality is checked first.
     */
    if (count < 3)
    {
        return validationIssue(
            RingValidationIssue.tooFewVertices
        );
    }


    /*
     * Establish the finite-coordinate precondition required by the robust
     * segment-intersection predicates.
     */
    foreach (i; 0 .. count)
    {
        if (!ring[i].isFinite)
        {
            return validationIssue(
                RingValidationIssue.nonFiniteCoordinate,
                i
            );
        }
    }


    /*
     * Reject zero-length edges before pairwise topology testing.
     */
    foreach (i; 0 .. count)
    {
        const auto edge =
            ringEdge(
                ring,
                i
            );

        if (edge.a == edge.b)
        {
            return validationIssue(
                RingValidationIssue.zeroLengthEdge,
                i
            );
        }
    }


    /*
     * Test every unordered pair of implicit ring edges.
     *
     * Adjacent edges are expected to meet at exactly their shared stored
     * endpoint. Positive-length overlap is invalid.
     *
     * Non-adjacent edges must be completely disjoint.
     */
    foreach (i; 0 .. count)
    {
        const auto first =
            ringEdge(
                ring,
                i
            );

        foreach (j; i + 1 .. count)
        {
            const auto second =
                ringEdge(
                    ring,
                    j
                );

            const SegmentIntersectionKind kind =
                segmentIntersectionKind(
                    first,
                    second
                );

            if (
                adjacentRingEdges(
                    i,
                    j,
                    count
                )
            )
            {
                if (
                    kind ==
                    SegmentIntersectionKind.overlap
                )
                {
                    return validationIssue(
                        RingValidationIssue.selfOverlap,
                        i,
                        j
                    );
                }

                /*
                 * With finite non-degenerate adjacent edges, their common
                 * stored endpoint guarantees exactly one point
                 * intersection unless they overlap.
                 *
                 * Keep the defensive branch explicit rather than relying on
                 * an assertion for public validation semantics.
                 */
                if (
                    kind !=
                    SegmentIntersectionKind.point
                )
                {
                    return validationIssue(
                        RingValidationIssue.selfIntersection,
                        i,
                        j
                    );
                }

                continue;
            }


            if (
                kind ==
                SegmentIntersectionKind.point
            )
            {
                return validationIssue(
                    RingValidationIssue.selfIntersection,
                    i,
                    j
                );
            }

            if (
                kind ==
                SegmentIntersectionKind.overlap
            )
            {
                return validationIssue(
                    RingValidationIssue.selfOverlap,
                    i,
                    j
                );
            }
        }
    }


    return RingValidationResult.init;
}


@safe unittest
{
    import geo.point :
        Point2;

    import std.meta :
        AliasSeq;


    /*
     * Public result initialization represents a valid result with no
     * applicable diagnostic indices.
     */
    {
        const result =
            RingValidationResult.init;

        assert(result.valid);

        assert(
            result.issue ==
            RingValidationIssue.none
        );

        assert(
            result.primaryIndex ==
            size_t.max
        );

        assert(
            result.secondaryIndex ==
            size_t.max
        );
    }


    /*
     * Ordinary valid rings work across the complete robust scalar domain.
     */
    static foreach (T; AliasSeq!(int, long, float, double))
    {
        {
            alias P = Point2!T;
            alias R = LinearRingView!T;

            P[4] points = [
                P(T(0), T(0)),
                P(T(4), T(0)),
                P(T(4), T(4)),
                P(T(0), T(4))
            ];

            auto ring =
                R(points[]);

            const result =
                validateRing(ring);

            assert(result.valid);

            assert(
                result.issue ==
                RingValidationIssue.none
            );
        }
    }


    /*
     * real remains outside the robust topology domain.
     */
    static assert(
        !__traits(
            compiles,
            {
                LinearRingView!real ring;

                validateRing(ring);
            }
        )
    );


    alias P = Point2!double;
    alias R = LinearRingView!double;


    /*
     * Empty and undersized rings fail without element indices.
     */
    {
        P[] emptyPoints;

        auto emptyRing =
            R(emptyPoints);

        const emptyResult =
            validateRing(emptyRing);

        assert(!emptyResult.valid);

        assert(
            emptyResult.issue ==
            RingValidationIssue.tooFewVertices
        );

        assert(
            emptyResult.primaryIndex ==
            size_t.max
        );

        assert(
            emptyResult.secondaryIndex ==
            size_t.max
        );


        P[2] twoPoints = [
            P(0.0, 0.0),
            P(1.0, 0.0)
        ];

        auto twoRing =
            R(twoPoints[]);

        const twoResult =
            validateRing(twoRing);

        assert(
            twoResult.issue ==
            RingValidationIssue.tooFewVertices
        );
    }


    /*
     * Ring orientation does not affect validity.
     */
    {
        P[4] ccwPoints = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0)
        ];

        P[4] cwPoints = [
            P(0.0, 0.0),
            P(0.0, 4.0),
            P(4.0, 4.0),
            P(4.0, 0.0)
        ];

        auto ccw =
            R(ccwPoints[]);

        auto cw =
            R(cwPoints[]);

        assert(validateRing(ccw).valid);
        assert(validateRing(cw).valid);
    }


    /*
     * Non-finite coordinates are reported before topology predicates are
     * invoked.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(double.nan, 4.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(!result.valid);

        assert(
            result.issue ==
            RingValidationIssue.nonFiniteCoordinate
        );

        assert(
            result.primaryIndex ==
            2
        );

        assert(
            result.secondaryIndex ==
            size_t.max
        );
    }


    /*
     * Consecutive repeated vertices create a zero-length edge.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 0.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.zeroLengthEdge
        );

        assert(
            result.primaryIndex ==
            1
        );
    }


    /*
     * Explicitly repeating the first vertex is invalid because the view
     * already closes implicitly.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(0.0, 4.0),
            P(0.0, 0.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.zeroLengthEdge
        );

        assert(
            result.primaryIndex ==
            3
        );
    }


    /*
     * A bow-tie ring contains a proper non-adjacent self-intersection.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0),
            P(4.0, 0.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.selfIntersection
        );

        assert(
            result.primaryIndex ==
            0
        );

        assert(
            result.secondaryIndex ==
            2
        );
    }


    /*
     * A repeated non-adjacent vertex is a forbidden point
     * self-intersection.
     */
    {
        P[5] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 0.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.selfIntersection
        );
    }


    /*
     * Adjacent collinear edges that retrace positive length overlap and are
     * invalid.
     */
    {
        P[4] points = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(2.0, 0.0),
            P(2.0, 4.0)
        ];

        auto ring =
            R(points[]);

        const result =
            validateRing(ring);

        assert(
            result.issue ==
            RingValidationIssue.selfOverlap
        );

        assert(
            result.primaryIndex ==
            0
        );

        assert(
            result.secondaryIndex ==
            1
        );
    }


    /*
     * Collinear continuation through a redundant vertex is valid when the
     * adjacent edges share only that endpoint.
     */
    {
        P[5] points = [
            P(0.0, 0.0),
            P(2.0, 0.0),
            P(4.0, 0.0),
            P(4.0, 4.0),
            P(0.0, 4.0)
        ];

        auto ring =
            R(points[]);

        assert(
            validateRing(ring).valid
        );
    }


    /*
     * Full-range long coordinates are validated using exact topology
     * without scalar overflow.
     */
    {
        alias LP = Point2!long;
        alias LR = LinearRingView!long;

        LP[3] points = [
            LP(long.min, long.min),
            LP(long.max, long.min),
            LP(0, long.max)
        ];

        auto ring =
            LR(points[]);

        assert(
            validateRing(ring).valid
        );
    }
}
