/* Public-API benchmark for the v4 structured-shape slices. */
module shape_bench;

import geo;
import std.algorithm.sorting : sort;
import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln, writeln;

enum repetitions = 7;
enum iterations = 100_000;
__gshared ulong benchmarkSink;

alias P = Point2!double;

private void runBenchmark(alias operation)(string name)
{
    ulong sink;
    foreach (i; 0 .. iterations / 10)
        sink += operation(i) ^ cast(ulong) i;

    long[repetitions] samples;
    foreach (sample; 0 .. repetitions)
    {
        StopWatch stopwatch;
        stopwatch.start();
        foreach (i; 0 .. iterations)
            sink += operation(i) ^ cast(ulong) i;
        stopwatch.stop();
        samples[sample] = stopwatch.peek.total!"nsecs";
    }

    benchmarkSink += sink;
    sort(samples[]);
    writefln("%-32s %10.2f ns/op", name,
        cast(double) samples[repetitions / 2] / iterations);
}

Circle2!double circle;
Rect2!double rect;
Triangle2!double triangle;

pragma(inline, false)
ulong circleContains(size_t i)
{
    return circle.contains(P(i & 1, 0.5)) ? 1 : 0;
}

pragma(inline, false)
ulong circleArea(size_t)
{
    return cast(ulong) circle.area();
}

pragma(inline, false)
ulong rectContains(size_t i)
{
    return rect.contains(P(i & 1, 0.5)) ? 1 : 0;
}

pragma(inline, false)
ulong triangleCentroid(size_t)
{
    auto p = triangle.centroid();
    return cast(ulong) (p.x + p.y);
}

pragma(inline, false)
ulong circlePolygonize(size_t i)
{
    P[64] output;
    if (!tryPolygonizeCircleInto(circle, output[]))
        return i;
    ulong result;
    foreach (point; output)
        result += cast(ulong) ((point.x + point.y + 100.0) * 1000.0);
    return result + i;
}

void main()
{
    assert(Circle2!double.tryFromCenterRadius(P(0, 0), 10, circle));
    assert(Rect2!double.tryFromMinMax(P(-10, -10), P(10, 10), rect));
    assert(Triangle2!double.tryFromPoints(P(0, 0), P(10, 0), P(0, 10), triangle));

    writeln("geo-d structured-shape benchmark");
    runBenchmark!circleContains("Circle2.contains");
    runBenchmark!circleArea("Circle2.area");
    runBenchmark!rectContains("Rect2.contains");
    runBenchmark!triangleCentroid("Triangle2.centroid");
    runBenchmark!circlePolygonize("Circle2.polygonize-64");
    writefln("sink=%s", benchmarkSink);
}
