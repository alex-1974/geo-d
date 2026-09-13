/*
 * Public-API benchmark for robust LinearRingView topology validation.
 *
 * Covers:
 *
 * - valid convex rings with 16, 64 and 256 vertices;
 * - too-few-vertices failure;
 * - late non-finite coordinate failure;
 * - late zero-length edge failure;
 * - self-intersection;
 * - adjacent positive-length overlap.
 *
 * Valid-ring cases are compared with a diagnostic implementation that
 * preserves validateRing() semantics but first rejects segment pairs whose
 * closed axis-aligned bounding boxes are disjoint.
 *
 * Bounding-box rejection uses comparisons only and cannot discard a real
 * segment intersection.
 *
 * All allocation and geometry construction occur before timing.
 */
module ring_validation_bench;

import geo.intersection :
    SegmentIntersectionKind,
    segmentIntersectionKind;

import geo.linear_ring_view :
    LinearRingView;

import geo.point :
    Point2;

import geo.segment :
    Segment2;

import geo.topology_validation :
    RingValidationIssue,
    RingValidationResult,
    validateRing;

import std.algorithm.sorting :
    sort;

import std.datetime.stopwatch :
    StopWatch;

import std.math :
    PI,
    cos,
    sin;

import std.stdio :
    writefln,
    writeln;


alias P = Point2!double;
alias R = LinearRingView!double;
alias S = Segment2!double;

enum size_t repetitions = 7;

__gshared ulong benchmarkSink;


/*
 * Two runtime-distinct rings per size prevent loop-invariant validation
 * from being hoisted out of timed loops.
 */
__gshared P[] points16a;
__gshared P[] points16b;
__gshared R[2] rings16;

__gshared P[] points64a;
__gshared P[] points64b;
__gshared R[2] rings64;

__gshared P[] points256a;
__gshared P[] points256b;
__gshared R[2] rings256;


/*
 * Invalid cases.
 */
__gshared P[] tooFewPoints;
__gshared R tooFewRing;

__gshared P[] nonFinitePoints;
__gshared R nonFiniteRing;

__gshared P[] zeroLengthPoints;
__gshared R zeroLengthRing;

__gshared P[] crossingPoints;
__gshared R crossingRing;

__gshared P[] overlapPoints;
__gshared R overlapRing;


private P[] makeConvexRing(
    size_t count,
    double radius,
    double phase
)
{
    auto result =
        new P[count];

    foreach (i; 0 .. count)
    {
        const double angle =
            phase +
            2.0 * PI *
            cast(double) i /
            cast(double) count;

        result[i] =
            P(
                radius * cos(angle),
                radius * sin(angle)
            );
    }

    return result;
}


private S ringEdge(
    R ring,
    size_t index
)
    pure nothrow @safe @nogc
{
    const size_t next =
        index + 1 == ring.length
            ? 0
            : index + 1;

    return
        S(
            ring[index],
            ring[next]
        );
}


private bool adjacentRingEdges(
    size_t first,
    size_t second,
    size_t count
)
    pure nothrow @safe @nogc
{
    return
        second == first + 1 ||
        (
            first == 0 &&
            second + 1 == count
        );
}


private RingValidationResult issue(
    RingValidationIssue kind,
    size_t primary = size_t.max,
    size_t secondary = size_t.max
)
    pure nothrow @safe @nogc
{
    return
        RingValidationResult(
            kind,
            primary,
            secondary
        );
}


private bool intervalsOverlap(
    double a,
    double b,
    double c,
    double d
)
    pure nothrow @safe @nogc
{
    const double firstMin =
        a < b ? a : b;

    const double firstMax =
        a > b ? a : b;

    const double secondMin =
        c < d ? c : d;

    const double secondMax =
        c > d ? c : d;

    return
        firstMax >= secondMin &&
        secondMax >= firstMin;
}


/*
 * Safe closed-AABB overlap test.
 *
 * validateRing() has already established finite coordinates before this
 * helper is reached.
 */
private bool segmentBoxesOverlap(
    S first,
    S second
)
    pure nothrow @safe @nogc
{
    return
        intervalsOverlap(
            first.a.x,
            first.b.x,
            second.a.x,
            second.b.x
        ) &&
        intervalsOverlap(
            first.a.y,
            first.b.y,
            second.a.y,
            second.b.y
        );
}


/*
 * Diagnostic candidate equivalent to validateRing(), with one additional
 * safe rejection step before robust segment-intersection classification.
 */
private RingValidationResult validateRingAabb(
    R ring
)
    pure nothrow @safe @nogc
{
    const size_t count =
        ring.length;

    if (count < 3)
    {
        return issue(
            RingValidationIssue.tooFewVertices
        );
    }


    foreach (i; 0 .. count)
    {
        if (!ring[i].isFinite)
        {
            return issue(
                RingValidationIssue.nonFiniteCoordinate,
                i
            );
        }
    }


    foreach (i; 0 .. count)
    {
        const auto edge =
            ringEdge(
                ring,
                i
            );

        if (edge.a == edge.b)
        {
            return issue(
                RingValidationIssue.zeroLengthEdge,
                i
            );
        }
    }


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

            /*
             * Closed segments with disjoint closed AABBs cannot intersect.
             *
             * Adjacent edges naturally survive this test because their
             * shared endpoint belongs to both boxes.
             */
            if (
                !segmentBoxesOverlap(
                    first,
                    second
                )
            )
            {
                continue;
            }

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
                    return issue(
                        RingValidationIssue.selfOverlap,
                        i,
                        j
                    );
                }

                if (
                    kind !=
                    SegmentIntersectionKind.point
                )
                {
                    return issue(
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
                return issue(
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
                return issue(
                    RingValidationIssue.selfOverlap,
                    i,
                    j
                );
            }
        }
    }

    return RingValidationResult.init;
}


private ulong encode(
    RingValidationResult result
)
    pure nothrow @safe @nogc
{
    return
        cast(ulong) result.issue ^
        (
            cast(ulong) result.primaryIndex *
            0x9e37_79b9_7f4a_7c15UL
        ) ^
        (
            cast(ulong) result.secondaryIndex *
            0xbf58_476d_1ce4_e5b9UL
        );
}


private void assertSame(
    R ring
)
{
    const auto publicResult =
        validateRing(ring);

    const auto candidateResult =
        validateRingAabb(ring);

    assert(
        publicResult.issue ==
        candidateResult.issue
    );

    assert(
        publicResult.primaryIndex ==
        candidateResult.primaryIndex
    );

    assert(
        publicResult.secondaryIndex ==
        candidateResult.secondaryIndex
    );
}


private void prepareCases()
{
    points16a =
        makeConvexRing(
            16,
            1000.0,
            0.0
        );

    points16b =
        makeConvexRing(
            16,
            1100.0,
            0.03125
        );

    rings16 = [
        R(points16a),
        R(points16b)
    ];


    points64a =
        makeConvexRing(
            64,
            1000.0,
            0.0
        );

    points64b =
        makeConvexRing(
            64,
            1100.0,
            0.015625
        );

    rings64 = [
        R(points64a),
        R(points64b)
    ];


    points256a =
        makeConvexRing(
            256,
            1000.0,
            0.0
        );

    points256b =
        makeConvexRing(
            256,
            1100.0,
            0.0078125
        );

    rings256 = [
        R(points256a),
        R(points256b)
    ];


    tooFewPoints = [
        P(0.0, 0.0),
        P(1.0, 0.0)
    ];

    tooFewRing =
        R(tooFewPoints);


    nonFinitePoints =
        makeConvexRing(
            256,
            1000.0,
            0.0
        );

    nonFinitePoints[$ - 1] =
        P(
            double.nan,
            nonFinitePoints[$ - 1].y
        );

    nonFiniteRing =
        R(nonFinitePoints);


    zeroLengthPoints =
        makeConvexRing(
            256,
            1000.0,
            0.0
        );

    zeroLengthPoints[$ - 1] =
        zeroLengthPoints[$ - 2];

    zeroLengthRing =
        R(zeroLengthPoints);


    crossingPoints = [
        P(0.0, 0.0),
        P(4.0, 4.0),
        P(0.0, 4.0),
        P(4.0, 0.0)
    ];

    crossingRing =
        R(crossingPoints);


    /*
     * Edge 0: (0,0) -> (4,0)
     * Edge 1: (4,0) -> (2,0)
     *
     * Adjacent edges overlap over positive length.
     */
    overlapPoints = [
        P(0.0, 0.0),
        P(4.0, 0.0),
        P(2.0, 0.0),
        P(4.0, 4.0),
        P(0.0, 4.0)
    ];

    overlapRing =
        R(overlapPoints);
}


private void verifyCases()
{
    writeln("Reference verification:");

    foreach (ring; rings16)
    {
        assertSame(ring);
        assert(validateRing(ring).valid);
    }

    foreach (ring; rings64)
    {
        assertSame(ring);
        assert(validateRing(ring).valid);
    }

    foreach (ring; rings256)
    {
        assertSame(ring);
        assert(validateRing(ring).valid);
    }

    assertSame(tooFewRing);
    assert(
        validateRing(tooFewRing).issue ==
        RingValidationIssue.tooFewVertices
    );

    assertSame(nonFiniteRing);
    assert(
        validateRing(nonFiniteRing).issue ==
        RingValidationIssue.nonFiniteCoordinate
    );

    assertSame(zeroLengthRing);
    assert(
        validateRing(zeroLengthRing).issue ==
        RingValidationIssue.zeroLengthEdge
    );

    assertSame(crossingRing);
    assert(
        validateRing(crossingRing).issue ==
        RingValidationIssue.selfIntersection
    );

    assertSame(overlapRing);
    assert(
        validateRing(overlapRing).issue ==
        RingValidationIssue.selfOverlap
    );

    writeln("  PASS");
}


pragma(inline, false)
private ulong public16(size_t i)
{
    return
        encode(
            validateRing(
                rings16[i & 1]
            )
        );
}


pragma(inline, false)
private ulong candidate16(size_t i)
{
    return
        encode(
            validateRingAabb(
                rings16[i & 1]
            )
        );
}


pragma(inline, false)
private ulong public64(size_t i)
{
    return
        encode(
            validateRing(
                rings64[i & 1]
            )
        );
}


pragma(inline, false)
private ulong candidate64(size_t i)
{
    return
        encode(
            validateRingAabb(
                rings64[i & 1]
            )
        );
}


pragma(inline, false)
private ulong public256(size_t i)
{
    return
        encode(
            validateRing(
                rings256[i & 1]
            )
        );
}


pragma(inline, false)
private ulong candidate256(size_t i)
{
    return
        encode(
            validateRingAabb(
                rings256[i & 1]
            )
        );
}


pragma(inline, false)
private ulong publicTooFew(size_t)
{
    return encode(
        validateRing(tooFewRing)
    );
}


pragma(inline, false)
private ulong publicNonFinite(size_t)
{
    return encode(
        validateRing(nonFiniteRing)
    );
}


pragma(inline, false)
private ulong publicZeroLength(size_t)
{
    return encode(
        validateRing(zeroLengthRing)
    );
}


pragma(inline, false)
private ulong publicCrossing(size_t)
{
    return encode(
        validateRing(crossingRing)
    );
}


pragma(inline, false)
private ulong publicOverlap(size_t)
{
    return encode(
        validateRing(overlapRing)
    );
}


private void runBenchmark(alias operation)(
    string name,
    size_t iterations,
    size_t pairCount = 0
)
{
    const size_t warmupIterations =
        iterations / 10;

    ulong localSink;

    foreach (i; 0 .. warmupIterations)
        localSink ^= operation(i);

    long[repetitions] samples;

    foreach (sample; 0 .. repetitions)
    {
        StopWatch stopwatch;
        stopwatch.start();

        foreach (i; 0 .. iterations)
            localSink ^= operation(i);

        stopwatch.stop();

        samples[sample] =
            stopwatch.peek.total!"nsecs";
    }

    benchmarkSink ^= localSink;

    sort(samples[]);

    const double nsPerOperation =
        cast(double) samples[repetitions / 2] /
        cast(double) iterations;

    if (pairCount == 0)
    {
        writefln(
            "%-36s %12.2f ns/op",
            name,
            nsPerOperation
        );

        return;
    }

    const double nsPerPair =
        nsPerOperation /
        cast(double) pairCount;

    writefln(
        "%-36s %12.2f ns/op %8.3f ns/pair",
        name,
        nsPerOperation,
        nsPerPair
    );
}


void main()
{
    prepareCases();
    verifyCases();

    writeln();
    writeln("Valid-ring scaling:");

    enum size_t pairs16 =
        16 * 15 / 2;

    enum size_t pairs64 =
        64 * 63 / 2;

    enum size_t pairs256 =
        256 * 255 / 2;


    runBenchmark!public16(
        "public n=16",
        100_000,
        pairs16
    );

    runBenchmark!candidate16(
        "AABB candidate n=16",
        100_000,
        pairs16
    );


    runBenchmark!public64(
        "public n=64",
        8_000,
        pairs64
    );

    runBenchmark!candidate64(
        "AABB candidate n=64",
        8_000,
        pairs64
    );


    runBenchmark!public256(
        "public n=256",
        500,
        pairs256
    );

    runBenchmark!candidate256(
        "AABB candidate n=256",
        500,
        pairs256
    );


    writeln();
    writeln("Failure paths:");

    runBenchmark!publicTooFew(
        "public too few vertices",
        2_000_000
    );

    runBenchmark!publicNonFinite(
        "public late non-finite n=256",
        200_000
    );

    runBenchmark!publicZeroLength(
        "public late zero-length n=256",
        100_000
    );

    runBenchmark!publicCrossing(
        "public bow-tie crossing",
        500_000
    );

    runBenchmark!publicOverlap(
        "public adjacent overlap",
        500_000
    );


    writeln();
    writefln(
        "sink=%s",
        benchmarkSink
    );
}
