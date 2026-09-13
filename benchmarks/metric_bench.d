/*
 * Public-API benchmark for geo-d metric operations.
 *
 * Covers:
 *
 * - squaredDistance();
 * - distance();
 * - segmentLength();
 * - tryPointSegmentDistance();
 * - tryNearestPoint().
 *
 * Ordinary finite binary64 cases are compared with local direct mathematical
 * references. Those references are diagnostic only and are used only where
 * their arithmetic domain is equivalent to the public operation.
 *
 * Large-range cases exercise geo-d's scaled full-range metric paths without
 * a naive reference whose intermediate arithmetic would overflow.
 *
 * All benchmark data is prepared before timing.
 */
module metric_bench;

import geo.metric :
    distance,
    segmentLength,
    squaredDistance,
    tryNearestPoint,
    tryPointSegmentDistance;

import geo.point :
    Point2;

import geo.segment :
    Segment2;

import std.algorithm.sorting :
    sort;

import std.bitmanip :
    DoubleRep;

import std.datetime.stopwatch :
    StopWatch;

import std.math.algebraic :
    hypot;

import std.stdio :
    writefln,
    writeln;


alias P = Point2!double;
alias S = Segment2!double;

alias PL = Point2!long;
alias SL = Segment2!long;


struct PointPair
{
    P a;
    P b;
}


struct LongPointPair
{
    PL a;
    PL b;
}


struct PointSegmentCase
{
    P point;
    S segment;
}


struct LongSegmentCase
{
    SL segment;
}


enum size_t repetitions = 7;

enum size_t primitiveIterations = 3_000_000;
enum size_t segmentMetricIterations = 1_000_000;

__gshared ulong benchmarkSink;

__gshared PointPair[2] doublePairs;
__gshared LongPointPair[2] longPairs;

__gshared S[2] doubleSegments;
__gshared LongSegmentCase[2] longSegments;

__gshared PointSegmentCase[2] interiorCases;
__gshared PointSegmentCase[2] endpointCases;
__gshared PointSegmentCase[2] degenerateCases;
__gshared PointSegmentCase[2] hugeCases;


private ulong bits(double value)
    pure nothrow @safe @nogc
{
    DoubleRep representation;
    representation.value = value;

    return
        representation.fraction ^
        (cast(ulong) representation.exponent << 52) ^
        (cast(ulong) representation.sign << 63);
}


private ulong encodeResult(
    bool success,
    double value
)
    pure nothrow @safe @nogc
{
    return
        bits(value) ^
        (
            success
                ? 0x9e37_79b9_7f4a_7c15UL
                : 0x243f_6a88_85a3_08d3UL
        );
}


private ulong encodePointResult(
    bool success,
    P point
)
    pure nothrow @safe @nogc
{
    return
        bits(point.x) ^
        (bits(point.y) * 0xbf58_476d_1ce4_e5b9UL) ^
        (
            success
                ? 0x94d0_49bb_1331_11ebUL
                : 0x2545_f491_4f6c_dd1dUL
        );
}


/*
 * Exact unsigned magnitude of a signed long.
 *
 * This mirrors the arithmetic requirement of the public metric path without
 * using a signed negation that can overflow for long.min.
 */
private ulong unsignedMagnitudeLong(long value)
    pure nothrow @safe @nogc
{
    if (value >= 0)
        return cast(ulong) value;

    return cast(ulong)(-(value + 1)) + 1UL;
}


/*
 * Signed component difference converted to double only after its exact
 * integral magnitude has been obtained.
 *
 * This is the algorithm-equivalent local reference for the public long
 * metric primitive benchmark.
 */
private double directLongDifference(
    long a,
    long b
)
    pure nothrow @safe @nogc
{
    if (a == b)
        return 0.0;

    ulong magnitude;

    if ((a < 0) != (b < 0))
    {
        magnitude =
            unsignedMagnitudeLong(a) +
            unsignedMagnitudeLong(b);
    }
    else if (a >= b)
    {
        magnitude =
            cast(ulong)(a - b);
    }
    else
    {
        magnitude =
            cast(ulong)(b - a);
    }

    const double converted =
        cast(double) magnitude;

    return a > b
        ? converted
        : -converted;
}


private double directSquaredDistance(
    P a,
    P b
)
    pure nothrow @safe @nogc
{
    const double dx =
        a.x - b.x;

    const double dy =
        a.y - b.y;

    return
        dx * dx +
        dy * dy;
}


private double directDistance(
    P a,
    P b
)
    pure nothrow @safe @nogc
{
    return hypot(
        a.x - b.x,
        a.y - b.y
    );
}


private double directLongDistance(
    PL a,
    PL b
)
    pure nothrow @safe @nogc
{
    return hypot(
        directLongDifference(a.x, b.x),
        directLongDifference(a.y, b.y)
    );
}


private double directSegmentLength(S segment)
    pure nothrow @safe @nogc
{
    return directDistance(
        segment.a,
        segment.b
    );
}


private double directLongSegmentLength(SL segment)
    pure nothrow @safe @nogc
{
    return directLongDistance(
        segment.a,
        segment.b
    );
}


/*
 * Direct finite-range point-to-segment distance reference.
 *
 * This reference is used only for ordinary moderate binary64 benchmark
 * inputs where its unscaled dot/cross arithmetic cannot overflow.
 *
 * It is not a replacement implementation for geo-d's full-range public
 * contract.
 */
private bool directPointSegmentDistance(
    P point,
    S segment,
    out double result
)
    pure nothrow @safe @nogc
{
    const double dx =
        segment.b.x - segment.a.x;

    const double dy =
        segment.b.y - segment.a.y;

    const double rx =
        point.x - segment.a.x;

    const double ry =
        point.y - segment.a.y;

    if (dx == 0.0 && dy == 0.0)
    {
        result =
            hypot(
                rx,
                ry
            );

        return true;
    }

    const double denominator =
        dx * dx +
        dy * dy;

    const double t =
        (
            rx * dx +
            ry * dy
        ) /
        denominator;

    if (t <= 0.0)
    {
        result =
            hypot(
                rx,
                ry
            );

        return true;
    }

    if (t >= 1.0)
    {
        result =
            hypot(
                point.x - segment.b.x,
                point.y - segment.b.y
            );

        return true;
    }

    double cross =
        dx * ry -
        dy * rx;

    if (cross < 0.0)
        cross = -cross;

    result =
        cross /
        hypot(
            dx,
            dy
        );

    return true;
}


/*
 * Direct finite-range nearest-point reference.
 *
 * As above, this is used only for moderate finite benchmark geometry.
 */
private bool directNearestPoint(
    S segment,
    P point,
    out P result
)
    pure nothrow @safe @nogc
{
    const double dx =
        segment.b.x - segment.a.x;

    const double dy =
        segment.b.y - segment.a.y;

    if (dx == 0.0 && dy == 0.0)
    {
        result =
            segment.a;

        return true;
    }

    const double rx =
        point.x - segment.a.x;

    const double ry =
        point.y - segment.a.y;

    const double denominator =
        dx * dx +
        dy * dy;

    const double t =
        (
            rx * dx +
            ry * dy
        ) /
        denominator;

    if (t <= 0.0)
    {
        result =
            segment.a;

        return true;
    }

    if (t >= 1.0)
    {
        result =
            segment.b;

        return true;
    }

    result =
        P(
            segment.a.x + t * dx,
            segment.a.y + t * dy
        );

    return true;
}


private void prepareCases()
{
    doublePairs[0] =
        PointPair(
            P(1.25, -2.5),
            P(101.25, 197.5)
        );

    doublePairs[1] =
        PointPair(
            P(-31.75, 40.5),
            P(68.25, -159.5)
        );


    /*
     * Small geometric differences near opposite ends of the long domain.
     *
     * These exercise exact integral component-difference handling before
     * conversion to double.
     */
    longPairs[0] =
        LongPointPair(
            PL(long.max, long.min + 8192),
            PL(long.max - 4096, long.min + 4096)
        );

    longPairs[1] =
        LongPointPair(
            PL(long.min + 16384, long.max),
            PL(long.min + 8192, long.max - 8192)
        );


    doubleSegments[0] =
        S(
            P(1.25, -2.5),
            P(101.25, 197.5)
        );

    doubleSegments[1] =
        S(
            P(-31.75, 40.5),
            P(68.25, -159.5)
        );


    longSegments[0] =
        LongSegmentCase(
            SL(
                PL(long.max, 0),
                PL(long.max - 4096, 4096)
            )
        );

    longSegments[1] =
        LongSegmentCase(
            SL(
                PL(long.min + 8192, -4096),
                PL(long.min + 16384, 4096)
            )
        );


    /*
     * Ordinary interior projection.
     */
    interiorCases[0] =
        PointSegmentCase(
            P(5.0, 3.0),
            S(
                P(0.0, 0.0),
                P(10.0, 0.0)
            )
        );

    interiorCases[1] =
        PointSegmentCase(
            P(7.0, -4.0),
            S(
                P(0.0, 0.0),
                P(12.0, 0.0)
            )
        );


    /*
     * Projection clamps to an endpoint.
     */
    endpointCases[0] =
        PointSegmentCase(
            P(-3.0, 4.0),
            S(
                P(0.0, 0.0),
                P(10.0, 0.0)
            )
        );

    endpointCases[1] =
        PointSegmentCase(
            P(15.0, 8.0),
            S(
                P(0.0, 0.0),
                P(10.0, 0.0)
            )
        );


    /*
     * Degenerate segment.
     */
    degenerateCases[0] =
        PointSegmentCase(
            P(4.0, 6.0),
            S(
                P(1.0, 2.0),
                P(1.0, 2.0)
            )
        );

    degenerateCases[1] =
        PointSegmentCase(
            P(-8.0, 9.0),
            S(
                P(-2.0, 1.0),
                P(-2.0, 1.0)
            )
        );


    /*
     * Numerically large interior projection.
     *
     * Naive unscaled dot/cross intermediates can overflow here, so these
     * cases deliberately have no direct reference benchmark.
     */
    hugeCases[0] =
        PointSegmentCase(
            P(5.0e299, 6.0e299),
            S(
                P(0.0, 0.0),
                P(1.0e300, 1.0e300)
            )
        );

    hugeCases[1] =
        PointSegmentCase(
            P(-4.0e299, -5.0e299),
            S(
                P(-9.0e299, -9.0e299),
                P(1.0e299, 1.0e299)
            )
        );
}


private void verifyReferences()
{
    writeln("Reference verification:");

    {
        const auto pair =
            doublePairs[0];

        assert(
            squaredDistance(
                pair.a,
                pair.b
            ) ==
            directSquaredDistance(
                pair.a,
                pair.b
            )
        );

        assert(
            distance(
                pair.a,
                pair.b
            ) ==
            directDistance(
                pair.a,
                pair.b
            )
        );
    }


    {
        const auto pair =
            longPairs[0];

        assert(
            distance(
                pair.a,
                pair.b
            ) ==
            directLongDistance(
                pair.a,
                pair.b
            )
        );
    }


    {
        const auto value =
            interiorCases[0];

        double publicResult;
        double directResult;

        assert(
            tryPointSegmentDistance(
                value.point,
                value.segment,
                publicResult
            )
        );

        assert(
            directPointSegmentDistance(
                value.point,
                value.segment,
                directResult
            )
        );

        assert(publicResult == 3.0);
        assert(directResult == 3.0);


        P publicNearest;
        P directNearest;

        assert(
            tryNearestPoint(
                value.segment,
                value.point,
                publicNearest
            )
        );

        assert(
            directNearestPoint(
                value.segment,
                value.point,
                directNearest
            )
        );

        assert(
            publicNearest ==
            P(5.0, 0.0)
        );

        assert(
            directNearest ==
            publicNearest
        );
    }


    {
        double result;

        const auto value =
            hugeCases[0];

        assert(
            tryPointSegmentDistance(
                value.point,
                value.segment,
                result
            )
        );

        assert(result > 7.0e298);
        assert(result < 7.2e298);


        P nearest;

        assert(
            tryNearestPoint(
                value.segment,
                value.point,
                nearest
            )
        );

        assert(nearest.x > 5.49e299);
        assert(nearest.x < 5.51e299);
        assert(nearest.y > 5.49e299);
        assert(nearest.y < 5.51e299);
    }

    writeln("  PASS");
}


pragma(inline, false)
private ulong publicSquaredDouble(size_t i)
{
    const auto value =
        doublePairs[i & 1];

    return bits(
        squaredDistance(
            value.a,
            value.b
        )
    );
}


pragma(inline, false)
private ulong directSquaredDouble(size_t i)
{
    const auto value =
        doublePairs[i & 1];

    return bits(
        directSquaredDistance(
            value.a,
            value.b
        )
    );
}


pragma(inline, false)
private ulong publicDistanceDouble(size_t i)
{
    const auto value =
        doublePairs[i & 1];

    return bits(
        distance(
            value.a,
            value.b
        )
    );
}


pragma(inline, false)
private ulong directDistanceDouble(size_t i)
{
    const auto value =
        doublePairs[i & 1];

    return bits(
        directDistance(
            value.a,
            value.b
        )
    );
}


pragma(inline, false)
private ulong publicDistanceLong(size_t i)
{
    const auto value =
        longPairs[i & 1];

    return bits(
        distance(
            value.a,
            value.b
        )
    );
}


pragma(inline, false)
private ulong directDistanceLong(size_t i)
{
    const auto value =
        longPairs[i & 1];

    return bits(
        directLongDistance(
            value.a,
            value.b
        )
    );
}


pragma(inline, false)
private ulong publicSegmentDouble(size_t i)
{
    return bits(
        segmentLength(
            doubleSegments[i & 1]
        )
    );
}


pragma(inline, false)
private ulong directSegmentDouble(size_t i)
{
    return bits(
        directSegmentLength(
            doubleSegments[i & 1]
        )
    );
}


pragma(inline, false)
private ulong publicSegmentLong(size_t i)
{
    return bits(
        segmentLength(
            longSegments[i & 1].segment
        )
    );
}


pragma(inline, false)
private ulong directSegmentLong(size_t i)
{
    return bits(
        directLongSegmentLength(
            longSegments[i & 1].segment
        )
    );
}


pragma(inline, false)
private ulong publicPointSegmentInterior(size_t i)
{
    const auto value =
        interiorCases[i & 1];

    double result;

    const bool success =
        tryPointSegmentDistance(
            value.point,
            value.segment,
            result
        );

    return encodeResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong directPointSegmentInterior(size_t i)
{
    const auto value =
        interiorCases[i & 1];

    double result;

    const bool success =
        directPointSegmentDistance(
            value.point,
            value.segment,
            result
        );

    return encodeResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong publicPointSegmentEndpoint(size_t i)
{
    const auto value =
        endpointCases[i & 1];

    double result;

    const bool success =
        tryPointSegmentDistance(
            value.point,
            value.segment,
            result
        );

    return encodeResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong directPointSegmentEndpoint(size_t i)
{
    const auto value =
        endpointCases[i & 1];

    double result;

    const bool success =
        directPointSegmentDistance(
            value.point,
            value.segment,
            result
        );

    return encodeResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong publicPointSegmentDegenerate(size_t i)
{
    const auto value =
        degenerateCases[i & 1];

    double result;

    const bool success =
        tryPointSegmentDistance(
            value.point,
            value.segment,
            result
        );

    return encodeResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong directPointSegmentDegenerate(size_t i)
{
    const auto value =
        degenerateCases[i & 1];

    double result;

    const bool success =
        directPointSegmentDistance(
            value.point,
            value.segment,
            result
        );

    return encodeResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong publicPointSegmentHuge(size_t i)
{
    const auto value =
        hugeCases[i & 1];

    double result;

    const bool success =
        tryPointSegmentDistance(
            value.point,
            value.segment,
            result
        );

    return encodeResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong publicNearestInterior(size_t i)
{
    const auto value =
        interiorCases[i & 1];

    P result;

    const bool success =
        tryNearestPoint(
            value.segment,
            value.point,
            result
        );

    return encodePointResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong directNearestInterior(size_t i)
{
    const auto value =
        interiorCases[i & 1];

    P result;

    const bool success =
        directNearestPoint(
            value.segment,
            value.point,
            result
        );

    return encodePointResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong publicNearestEndpoint(size_t i)
{
    const auto value =
        endpointCases[i & 1];

    P result;

    const bool success =
        tryNearestPoint(
            value.segment,
            value.point,
            result
        );

    return encodePointResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong directNearestEndpoint(size_t i)
{
    const auto value =
        endpointCases[i & 1];

    P result;

    const bool success =
        directNearestPoint(
            value.segment,
            value.point,
            result
        );

    return encodePointResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong publicNearestDegenerate(size_t i)
{
    const auto value =
        degenerateCases[i & 1];

    P result;

    const bool success =
        tryNearestPoint(
            value.segment,
            value.point,
            result
        );

    return encodePointResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong directNearestDegenerate(size_t i)
{
    const auto value =
        degenerateCases[i & 1];

    P result;

    const bool success =
        directNearestPoint(
            value.segment,
            value.point,
            result
        );

    return encodePointResult(
        success,
        result
    );
}


pragma(inline, false)
private ulong publicNearestHuge(size_t i)
{
    const auto value =
        hugeCases[i & 1];

    P result;

    const bool success =
        tryNearestPoint(
            value.segment,
            value.point,
            result
        );

    return encodePointResult(
        success,
        result
    );
}


private void runBenchmark(alias operation)(
    string name,
    size_t iterations
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

    writefln(
        "%-38s %10.2f ns/op",
        name,
        nsPerOperation
    );
}


void main()
{
    prepareCases();
    verifyReferences();

    writeln();
    writeln("Metric primitives:");

    runBenchmark!publicSquaredDouble(
        "squaredDistance double",
        primitiveIterations
    );

    runBenchmark!directSquaredDouble(
        "direct squared double",
        primitiveIterations
    );


    runBenchmark!publicDistanceDouble(
        "distance double",
        primitiveIterations
    );

    runBenchmark!directDistanceDouble(
        "direct distance double",
        primitiveIterations
    );


    runBenchmark!publicDistanceLong(
        "distance long",
        primitiveIterations
    );

    runBenchmark!directDistanceLong(
        "direct distance long",
        primitiveIterations
    );


    runBenchmark!publicSegmentDouble(
        "segmentLength double",
        primitiveIterations
    );

    runBenchmark!directSegmentDouble(
        "direct segment double",
        primitiveIterations
    );


    runBenchmark!publicSegmentLong(
        "segmentLength long",
        primitiveIterations
    );

    runBenchmark!directSegmentLong(
        "direct segment long",
        primitiveIterations
    );


    writeln();
    writeln("Point-to-segment distance:");

    runBenchmark!publicPointSegmentInterior(
        "public interior",
        segmentMetricIterations
    );


    runBenchmark!directPointSegmentInterior(
        "direct interior",
        segmentMetricIterations
    );


    runBenchmark!publicPointSegmentEndpoint(
        "public endpoint clamp",
        segmentMetricIterations
    );


    runBenchmark!directPointSegmentEndpoint(
        "direct endpoint clamp",
        segmentMetricIterations
    );


    runBenchmark!publicPointSegmentDegenerate(
        "public degenerate",
        segmentMetricIterations
    );


    runBenchmark!directPointSegmentDegenerate(
        "direct degenerate",
        segmentMetricIterations
    );


    runBenchmark!publicPointSegmentHuge(
        "public huge-range interior",
        segmentMetricIterations
    );



    writeln();
    writeln("Nearest point:");

    runBenchmark!publicNearestInterior(
        "public interior",
        segmentMetricIterations
    );


    runBenchmark!directNearestInterior(
        "direct interior",
        segmentMetricIterations
    );


    runBenchmark!publicNearestEndpoint(
        "public endpoint clamp",
        segmentMetricIterations
    );


    runBenchmark!directNearestEndpoint(
        "direct endpoint clamp",
        segmentMetricIterations
    );


    runBenchmark!publicNearestDegenerate(
        "public degenerate",
        segmentMetricIterations
    );


    runBenchmark!directNearestDegenerate(
        "direct degenerate",
        segmentMetricIterations
    );


    runBenchmark!publicNearestHuge(
        "public huge-range interior",
        segmentMetricIterations
    );



    writeln();
    writefln(
        "sink=%s",
        benchmarkSink
    );
}
