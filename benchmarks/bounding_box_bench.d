/*
 * Public-API benchmark for geometry bounding-box computation.
 *
 * The benchmark compares:
 *
 * - tryBounds(PolylineView!double);
 * - a raw-slice reduction using Bounds2.tryExtend();
 * - a direct raw-slice extrema loop with equivalent NaN failure semantics.
 *
 * It also measures PolygonView traversal over a representative multi-ring
 * polygon against a raw nested-ring reduction.
 *
 * All dynamic test-data allocation occurs before timing.
 */
module bounding_box_bench;

import geo.bounding_box :
    tryBounds;

import geo.bounds :
    Bounds2;

import geo.linear_ring_view :
    LinearRingView;

import geo.point :
    Point2;

import geo.polygon_view :
    PolygonView;

import geo.polyline_view :
    PolylineView;

import std.algorithm.sorting :
    sort;

import std.bitmanip :
    DoubleRep;

import std.datetime.stopwatch :
    StopWatch;

import std.stdio :
    writefln;


enum size_t repetitions = 7;

/*
 * Each polyline case performs roughly two million point visits per timed
 * sample. This keeps total work comparable across geometry sizes.
 */
enum size_t iterations10     = 200_000;
enum size_t iterations100    =  20_000;
enum size_t iterations1000   =   2_000;
enum size_t iterations10000  =     200;
enum size_t iterations100000 =      20;

enum size_t polygonIterations = 200;

__gshared ulong benchmarkSink;


__gshared Point2!double[] points10A;
__gshared Point2!double[] points10B;

__gshared Point2!double[] points100A;
__gshared Point2!double[] points100B;

__gshared Point2!double[] points1000A;
__gshared Point2!double[] points1000B;

__gshared Point2!double[] points10000A;
__gshared Point2!double[] points10000B;

__gshared Point2!double[] points100000A;
__gshared Point2!double[] points100000B;


/*
 * Four rings of 2,500 vertices each.
 */
__gshared Point2!double[][] polygonPointsA;
__gshared Point2!double[][] polygonPointsB;

__gshared LinearRingView!double[] polygonRingsA;
__gshared LinearRingView!double[] polygonRingsB;


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


private ulong encodeBounds(
    bool success,
    Bounds2!double bounds
)
    pure nothrow @safe @nogc
{
    if (!success)
        return 0x9e37_79b9_7f4a_7c15UL;

    if (bounds.empty)
        return 0x243f_6a88_85a3_08d3UL;

    return
        bits(bounds.min.x) ^
        (bits(bounds.min.y) * 3UL) ^
        (bits(bounds.max.x) * 5UL) ^
        (bits(bounds.max.y) * 7UL);
}


/*
 * Direct raw-slice equivalent of the Bounds2.tryExtend reduction.
 *
 * This isolates PolylineView/public-function overhead while retaining the
 * same Bounds2 primitive used by the production implementation.
 */
private bool tryBoundsRawExtend(
    scope const(Point2!double)[] points,
    out Bounds2!double result
)
    pure nothrow @safe @nogc
{
    Bounds2!double accumulated;

    foreach (point; points)
    {
        if (!accumulated.tryExtend(point))
            return false;
    }

    result = accumulated;

    return true;
}


/*
 * Direct coordinate extrema loop.
 *
 * This is a benchmark reference only. It implements the same relevant
 * contract for the benchmarked finite/non-empty data and also rejects NaN.
 */
private bool tryBoundsDirect(
    scope const(Point2!double)[] points,
    out Bounds2!double result
)
    pure nothrow @safe @nogc
{
    if (points.length == 0)
        return true;

    const first = points[0];

    if (first.x != first.x || first.y != first.y)
        return false;

    double minX = first.x;
    double minY = first.y;
    double maxX = first.x;
    double maxY = first.y;

    foreach (point; points[1 .. $])
    {
        if (point.x != point.x || point.y != point.y)
            return false;

        if (point.x < minX)
            minX = point.x;

        if (point.y < minY)
            minY = point.y;

        if (point.x > maxX)
            maxX = point.x;

        if (point.y > maxY)
            maxY = point.y;
    }

    return Bounds2!double.tryFromMinMax(
        Point2!double(minX, minY),
        Point2!double(maxX, maxY),
        result
    );
}


private bool tryPolygonBoundsRaw(
    scope Point2!double[][] rings,
    out Bounds2!double result
)
    pure nothrow @safe @nogc
{
    Bounds2!double accumulated;

    foreach (ring; rings)
    {
        foreach (point; ring)
        {
            if (!accumulated.tryExtend(point))
                return false;
        }
    }

    result = accumulated;

    return true;
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
         * Deterministic irregular finite data. The two modular components
         * avoid a monotonic input that might favour a particular branch
         * pattern.
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
            Point2!double(x, y);
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

    points100000A =
        makePoints(100_000, 0.0);

    points100000B =
        makePoints(100_000, 1000.0);


    enum size_t ringCount = 4;
    enum size_t verticesPerRing = 2_500;

    polygonPointsA =
        new Point2!double[][ringCount];

    polygonPointsB =
        new Point2!double[][ringCount];

    polygonRingsA =
        new LinearRingView!double[ringCount];

    polygonRingsB =
        new LinearRingView!double[ringCount];

    foreach (ringIndex; 0 .. ringCount)
    {
        polygonPointsA[ringIndex] =
            makePoints(
                verticesPerRing,
                cast(double) ringIndex * 10_000.0
            );

        polygonPointsB[ringIndex] =
            makePoints(
                verticesPerRing,
                1000.0 +
                    cast(double) ringIndex * 10_000.0
            );

        polygonRingsA[ringIndex] =
            LinearRingView!double(
                polygonPointsA[ringIndex]
            );

        polygonRingsB[ringIndex] =
            LinearRingView!double(
                polygonPointsB[ringIndex]
            );
    }
}

private bool tryPolygonBoundsDirect(
    scope Point2!double[][] rings,
    out Bounds2!double result
)
    pure nothrow @safe @nogc
{
    bool hasValue;

    double minX;
    double minY;
    double maxX;
    double maxY;

    foreach (ring; rings)
    {
        foreach (point; ring)
        {
            if (point.x != point.x ||
                point.y != point.y)
            {
                return false;
            }

            if (!hasValue)
            {
                minX = point.x;
                minY = point.y;
                maxX = point.x;
                maxY = point.y;

                hasValue = true;

                continue;
            }

            if (point.x < minX)
                minX = point.x;

            if (point.y < minY)
                minY = point.y;

            if (point.x > maxX)
                maxX = point.x;

            if (point.y > maxY)
                maxY = point.y;
        }
    }

    if (!hasValue)
        return true;

    return Bounds2!double.tryFromMinMax(
        Point2!double(minX, minY),
        Point2!double(maxX, maxY),
        result
    );
}


pragma(inline, false)
private ulong directPolygon(
    scope Point2!double[][] rings
)
{
    Bounds2!double result;

    const bool success =
        tryPolygonBoundsDirect(
            rings,
            result
        );

    return encodeBounds(
        success,
        result
    );
}

pragma(inline, false)
private ulong publicPolyline(
    scope Point2!double[] points
)
{
    Bounds2!double result;

    const bool success =
        tryBounds(
            PolylineView!double(points),
            result
        );

    return encodeBounds(
        success,
        result
    );
}


pragma(inline, false)
private ulong rawExtendPolyline(
    scope const(Point2!double)[] points
)
{
    Bounds2!double result;

    const bool success =
        tryBoundsRawExtend(
            points,
            result
        );

    return encodeBounds(
        success,
        result
    );
}


pragma(inline, false)
private ulong directPolyline(
    scope const(Point2!double)[] points
)
{
    Bounds2!double result;

    const bool success =
        tryBoundsDirect(
            points,
            result
        );

    return encodeBounds(
        success,
        result
    );
}


pragma(inline, false)
private ulong publicPolygon(
    scope LinearRingView!double[] rings
)
{
    Bounds2!double result;

    const bool success =
        tryBounds(
            PolygonView!double(rings),
            result
        );

    return encodeBounds(
        success,
        result
    );
}


pragma(inline, false)
private ulong rawPolygon(
    scope Point2!double[][] rings
)
{
    Bounds2!double result;

    const bool success =
        tryPolygonBoundsRaw(
            rings,
            result
        );

    return encodeBounds(
        success,
        result
    );
}


private void runBenchmark(alias operation)(
    string name,
    size_t iterations,
    size_t pointsPerOperation
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

    const double nanosecondsPerOperation =
        cast(double) samples[repetitions / 2] /
        cast(double) iterations;

    const double nanosecondsPerPoint =
        nanosecondsPerOperation /
        cast(double) pointsPerOperation;

    writefln(
        "%-32s %12.2f ns/op  %8.3f ns/point  n=%s",
        name,
        nanosecondsPerOperation,
        nanosecondsPerPoint,
        pointsPerOperation
    );
}


void main()
{
    prepareCases();

    runBenchmark!(
        i => publicPolyline(
            (i & 1) == 0
                ? points10A
                : points10B
        )
    )(
        "tryBounds polyline 10",
        iterations10,
        10
    );

    runBenchmark!(
        i => rawExtendPolyline(
            (i & 1) == 0
                ? points10A
                : points10B
        )
    )(
        "raw extend polyline 10",
        iterations10,
        10
    );

    runBenchmark!(
        i => directPolyline(
            (i & 1) == 0
                ? points10A
                : points10B
        )
    )(
        "direct extrema polyline 10",
        iterations10,
        10
    );


    runBenchmark!(
        i => publicPolyline(
            (i & 1) == 0
                ? points100A
                : points100B
        )
    )(
        "tryBounds polyline 100",
        iterations100,
        100
    );

    runBenchmark!(
        i => rawExtendPolyline(
            (i & 1) == 0
                ? points100A
                : points100B
        )
    )(
        "raw extend polyline 100",
        iterations100,
        100
    );

    runBenchmark!(
        i => directPolyline(
            (i & 1) == 0
                ? points100A
                : points100B
        )
    )(
        "direct extrema polyline 100",
        iterations100,
        100
    );


    runBenchmark!(
        i => publicPolyline(
            (i & 1) == 0
                ? points1000A
                : points1000B
        )
    )(
        "tryBounds polyline 1000",
        iterations1000,
        1_000
    );

    runBenchmark!(
        i => rawExtendPolyline(
            (i & 1) == 0
                ? points1000A
                : points1000B
        )
    )(
        "raw extend polyline 1000",
        iterations1000,
        1_000
    );

    runBenchmark!(
        i => directPolyline(
            (i & 1) == 0
                ? points1000A
                : points1000B
        )
    )(
        "direct extrema polyline 1000",
        iterations1000,
        1_000
    );


    runBenchmark!(
        i => publicPolyline(
            (i & 1) == 0
                ? points10000A
                : points10000B
        )
    )(
        "tryBounds polyline 10000",
        iterations10000,
        10_000
    );

    runBenchmark!(
        i => rawExtendPolyline(
            (i & 1) == 0
                ? points10000A
                : points10000B
        )
    )(
        "raw extend polyline 10000",
        iterations10000,
        10_000
    );

    runBenchmark!(
        i => directPolyline(
            (i & 1) == 0
                ? points10000A
                : points10000B
        )
    )(
        "direct extrema polyline 10000",
        iterations10000,
        10_000
    );


    runBenchmark!(
        i => publicPolyline(
            (i & 1) == 0
                ? points100000A
                : points100000B
        )
    )(
        "tryBounds polyline 100000",
        iterations100000,
        100_000
    );

    runBenchmark!(
        i => rawExtendPolyline(
            (i & 1) == 0
                ? points100000A
                : points100000B
        )
    )(
        "raw extend polyline 100000",
        iterations100000,
        100_000
    );

    runBenchmark!(
        i => directPolyline(
            (i & 1) == 0
                ? points100000A
                : points100000B
        )
    )(
        "direct extrema polyline 100000",
        iterations100000,
        100_000
    );


    runBenchmark!(
        i => publicPolygon(
            (i & 1) == 0
                ? polygonRingsA
                : polygonRingsB
        )
    )(
        "tryBounds polygon 4x2500",
        polygonIterations,
        10_000
    );

    runBenchmark!(
        i => rawPolygon(
            (i & 1) == 0
                ? polygonPointsA
                : polygonPointsB
        )
    )(
        "raw polygon 4x2500",
        polygonIterations,
        10_000
    );
    
    runBenchmark!(
    i => directPolygon(
        (i & 1) == 0
            ? polygonPointsA
            : polygonPointsB
    )
)(
    "direct polygon 4x2500",
    polygonIterations,
    10_000
);


    writefln(
        "sink: %s",
        benchmarkSink
    );
}
