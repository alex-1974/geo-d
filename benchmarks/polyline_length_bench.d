/*
 * Public-API benchmark for polyline length accumulation.
 *
 * Compares the public compensated polylineLength() implementation with the
 * previous ordinary sequential-accumulation policy used as a local diagnostic
 * baseline.
 *
 * The benchmark also verifies a deterministic mixed-scale case in which
 * ordinary sequential accumulation loses representable length while the
 * public compensated implementation retains it.
 *
 * All dynamic test-data allocation occurs before timing.
 */
module polyline_length_bench;

import geo.metric :
    MetricScalar,
    polylineLength,
    segmentLength;

import geo.point :
    Point2;

import geo.polyline_view :
    PolylineView;

import geo.scalar :
    isGeoScalar;

import std.algorithm.sorting :
    sort;

import std.bitmanip :
    DoubleRep;

import std.datetime.stopwatch :
    StopWatch;

import std.stdio :
    writefln,
    writeln;


enum size_t repetitions = 7;

/*
 * Roughly one million segment visits per timed sample.
 */
enum size_t iterations10    = 100_000;
enum size_t iterations100   =  10_000;
enum size_t iterations1000  =   1_000;
enum size_t iterations10000 =     100;

__gshared ulong benchmarkSink;

__gshared Point2!double[] points10A;
__gshared Point2!double[] points10B;

__gshared Point2!double[] points100A;
__gshared Point2!double[] points100B;

__gshared Point2!double[] points1000A;
__gshared Point2!double[] points1000B;

__gshared Point2!double[] points10000A;
__gshared Point2!double[] points10000B;


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


private MetricScalar!T ordinaryPolylineLength(T)(
    scope PolylineView!T polyline
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    MetricScalar!T result = 0;

    foreach (i; 0 .. polyline.segmentCount)
    {
        result +=
            segmentLength(
                polyline.segment(i)
            );
    }

    return result;
}

private Point2!double[] makePoints(
    size_t count,
    double offset
)
{
    auto points =
        new Point2!double[count];

    foreach (i; 0 .. count)
    {
        /*
         * Deterministic irregular geometry.
         *
         * Coordinates stay moderate so this benchmark measures ordinary
         * metric throughput rather than exceptional numerical range.
         */
        const double x =
            offset +
            cast(double)((i * 37 + 11) % 1009) * 0.25 -
            cast(double)((i * 13 + 7) % 127) * 0.5;

        const double y =
            offset * 0.5 +
            cast(double)((i * 53 + 17) % 1013) * 0.375 -
            cast(double)((i * 19 + 3) % 131) * 0.625;

        points[i] =
            Point2!double(
                x,
                y
            );
    }

    return points;
}


private void prepareCases()
{
    points10A =
        makePoints(10, 0.0);

    points10B =
        makePoints(10, 1000.0);

    points100A =
        makePoints(100, 0.0);

    points100B =
        makePoints(100, 1000.0);

    points1000A =
        makePoints(1_000, 0.0);

    points1000B =
        makePoints(1_000, 1000.0);

    points10000A =
        makePoints(10_000, 0.0);

    points10000B =
        makePoints(10_000, 1000.0);
}


private void verifyNumericalDifference()
{
    alias P = Point2!double;
    alias V = PolylineView!double;

    enum size_t blocks = 256;
    enum double large = 0x1p52;
    enum double expected = 0x1p61 + 512.0;

    auto points =
        new P[1 + blocks * 4];

    size_t index;

    points[index++] =
        P(0.0, 0.0);

    foreach (_; 0 .. blocks)
    {
        points[index++] =
            P(large, 0.0);

        points[index++] =
            P(0.0, 0.0);

        points[index++] =
            P(1.0, 0.0);

        points[index++] =
            P(0.0, 0.0);
    }

    const auto view =
        V(points);

    const double ordinary =
        ordinaryPolylineLength(view);

    const double publicResult =
        polylineLength(view);

    writeln("Numerical probe:");

    writefln(
        "  expected     %.17g",
        expected
    );

    writefln(
        "  ordinary     %.17g  error=%g",
        ordinary,
        expected - ordinary
    );

    writefln(
        "  public       %.17g  error=%g",
        publicResult,
        expected - publicResult
    );

    assert(publicResult == expected);
}

pragma(inline, false)
private ulong publicLength(
    scope Point2!double[] points
)
{
    return bits(
        polylineLength(
            PolylineView!double(points)
        )
    );
}


pragma(inline, false)
private ulong ordinaryLength(
    scope Point2!double[] points
)
{
    return bits(
        ordinaryPolylineLength(
            PolylineView!double(points)
        )
    );
}

private void runBenchmark(alias operation)(
    string name,
    size_t iterations,
    size_t pointCount
)
{
    const size_t warmupIterations =
        iterations >= 10
            ? iterations / 10
            : 1;

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

    const size_t segmentCount =
        pointCount > 0
            ? pointCount - 1
            : 0;

    const double nsPerSegment =
        nsPerOperation /
        cast(double) segmentCount;

    writefln(
        "%-32s %12.2f ns/op  %9.3f ns/segment  n=%s",
        name,
        nsPerOperation,
        nsPerSegment,
        pointCount
    );
}


private void runCase(
    string suffix,
    scope Point2!double[] first,
    scope Point2!double[] second,
    size_t iterations
)
{
    const size_t pointCount =
        first.length;

    runBenchmark!(
        i => publicLength(
            (i & 1) == 0
                ? first
                : second
        )
    )(
        "public compensated " ~ suffix,
        iterations,
        pointCount
    );

    runBenchmark!(
        i => ordinaryLength(
            (i & 1) == 0
                ? first
                : second
        )
    )(
        "ordinary baseline " ~ suffix,
        iterations,
        pointCount
    );
}

void main()
{
    prepareCases();

    verifyNumericalDifference();

    writeln();
    writeln("Performance:");

    runCase(
        "polyline 10",
        points10A,
        points10B,
        iterations10
    );

    runCase(
        "polyline 100",
        points100A,
        points100B,
        iterations100
    );

    runCase(
        "polyline 1000",
        points1000A,
        points1000B,
        iterations1000
    );

    runCase(
        "polyline 10000",
        points10000A,
        points10000B,
        iterations10000
    );

    writeln();
    writefln(
        "sink=%s",
        benchmarkSink
    );
}
