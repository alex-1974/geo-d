module intersection_bench;

import geo.intersection :
    SegmentIntersectionKind,
    segmentIntersectionKind,
    trySegmentIntersectionPoint;

import geo.point : Point2;
import geo.segment : Segment2;

import std.bitmanip : DoubleRep;
import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;


enum size_t classificationIterations = 1_000_000;
enum size_t constructionIterations   =   100_000;
enum size_t warmupIterations         =     2_000;

__gshared ulong benchmarkSink;


private ulong doubleBits(double value)
{
    DoubleRep representation;
    representation.value = value;

    return
        representation.fraction ^
        (cast(ulong) representation.exponent << 52) ^
        (cast(ulong) representation.sign << 63);
}


private ulong pointBits(Point2!double point)
{
    return
        doubleBits(point.x) ^
        (doubleBits(point.y) * 0x9e37_79b9_7f4a_7c15UL);
}


private void runBenchmark(alias operation)(
    string name,
    size_t iterations
)
{
    ulong localSink;

    foreach (i; 0 .. warmupIterations)
        localSink ^= operation(i);

    StopWatch stopwatch;
    stopwatch.start();

    foreach (i; 0 .. iterations)
        localSink ^= operation(i);

    stopwatch.stop();

    benchmarkSink ^= localSink;

    const long nanoseconds =
        stopwatch.peek.total!"nsecs";

    writefln(
        "%-36s %12.2f ns/op   n=%s",
        name,
        cast(double) nanoseconds /
            cast(double) iterations,
        iterations
    );
}


pragma(inline, false)
private ulong classifyOrdinaryNone(size_t i)
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const double offset =
        cast(double)(i & 1);

    const auto kind =
        segmentIntersectionKind(
            S(
                P(offset, 0.0),
                P(offset + 10.0, 0.0)
            ),
            S(
                P(offset, 2.0),
                P(offset + 10.0, 2.0)
            )
        );

    return cast(ulong) kind;
}


pragma(inline, false)
private ulong classifyOrdinaryCrossing(size_t i)
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const double offset =
        cast(double)(i & 1);

    const auto kind =
        segmentIntersectionKind(
            S(
                P(offset, 0.0),
                P(offset + 10.0, 10.0)
            ),
            S(
                P(offset, 10.0),
                P(offset + 10.0, 0.0)
            )
        );

    return cast(ulong) kind;
}


pragma(inline, false)
private ulong classifyOverlap(size_t i)
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const double offset =
        cast(double)(i & 1);

    const auto kind =
        segmentIntersectionKind(
            S(
                P(offset, 0.0),
                P(offset + 10.0, 0.0)
            ),
            S(
                P(offset + 5.0, 0.0),
                P(offset + 15.0, 0.0)
            )
        );

    return cast(ulong) kind;
}


pragma(inline, false)
private ulong classifyNearParallel(size_t i)
{
    enum double halfUlp =
        0x1p-53;

    enum double oneMinusHalfUlp =
        0x1.fffffffffffffp-1;

    alias P = Point2!double;
    alias S = Segment2!double;

    const bool reverse =
        (i & 1) != 0;

    const S first =
        reverse
            ? S(P(1.0, 1.0), P(0.0, 0.0))
            : S(P(0.0, 0.0), P(1.0, 1.0));

    const S second =
        S(
            P(0.0, halfUlp),
            P(1.0, oneMinusHalfUlp)
        );

    return cast(ulong)
        segmentIntersectionKind(
            first,
            second
        );
}


pragma(inline, false)
private ulong classifyFullRange(size_t i)
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const bool reverse =
        (i & 1) != 0;

    const S horizontal =
        reverse
            ? S(
                P(double.max, 0.0),
                P(-double.max, 0.0)
            )
            : S(
                P(-double.max, 0.0),
                P(double.max, 0.0)
            );

    const S vertical =
        S(
            P(0.0, -double.max),
            P(0.0, double.max)
        );

    return cast(ulong)
        segmentIntersectionKind(
            horizontal,
            vertical
        );
}


pragma(inline, false)
private ulong constructEndpoint(size_t i)
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const double offset =
        cast(double)(i & 1);

    Point2!double point;

    const bool success =
        trySegmentIntersectionPoint(
            S(
                P(offset, 0.0),
                P(offset + 10.0, 0.0)
            ),
            S(
                P(offset + 10.0, 0.0),
                P(offset + 10.0, 10.0)
            ),
            point
        );

    return
        pointBits(point) ^
        cast(ulong) success;
}


pragma(inline, false)
private ulong constructTJunction(size_t i)
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const double offset =
        cast(double)(i & 1);

    Point2!double point;

    const bool success =
        trySegmentIntersectionPoint(
            S(
                P(offset, 0.0),
                P(offset + 10.0, 0.0)
            ),
            S(
                P(offset + 5.0, 0.0),
                P(offset + 5.0, 10.0)
            ),
            point
        );

    return
        pointBits(point) ^
        cast(ulong) success;
}


pragma(inline, false)
private ulong constructIntCrossing(size_t i)
{
    alias P = Point2!int;
    alias S = Segment2!int;

    const int offset =
        cast(int)(i & 1);

    Point2!double point;

    const bool success =
        trySegmentIntersectionPoint(
            S(
                P(offset, 0),
                P(offset + 10, 10)
            ),
            S(
                P(offset, 10),
                P(offset + 10, 0)
            ),
            point
        );

    return
        pointBits(point) ^
        cast(ulong) success;
}


pragma(inline, false)
private ulong constructDoubleCrossing(size_t i)
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const double offset =
        cast(double)(i & 1);

    Point2!double point;

    const bool success =
        trySegmentIntersectionPoint(
            S(
                P(offset, 0.0),
                P(offset + 10.0, 10.0)
            ),
            S(
                P(offset, 10.0),
                P(offset + 10.0, 0.0)
            ),
            point
        );

    return
        pointBits(point) ^
        cast(ulong) success;
}


pragma(inline, false)
private ulong constructOneThird(size_t i)
{
    alias P = Point2!int;
    alias S = Segment2!int;

    const int offset =
        cast(int)(i & 1);

    Point2!double point;

    const bool success =
        trySegmentIntersectionPoint(
            S(
                P(offset, 0),
                P(offset + 1, 0)
            ),
            S(
                P(offset, 1),
                P(offset + 1, -2)
            ),
            point
        );

    return
        pointBits(point) ^
        cast(ulong) success;
}


pragma(inline, false)
private ulong constructNearParallel(size_t i)
{
    enum double halfUlp =
        0x1p-53;

    enum double oneMinusHalfUlp =
        0x1.fffffffffffffp-1;

    alias P = Point2!double;
    alias S = Segment2!double;

    const bool reverse =
        (i & 1) != 0;

    const S first =
        reverse
            ? S(P(1.0, 1.0), P(0.0, 0.0))
            : S(P(0.0, 0.0), P(1.0, 1.0));

    const S second =
        S(
            P(0.0, halfUlp),
            P(1.0, oneMinusHalfUlp)
        );

    Point2!double point;

    const bool success =
        trySegmentIntersectionPoint(
            first,
            second,
            point
        );

    return
        pointBits(point) ^
        cast(ulong) success;
}


pragma(inline, false)
private ulong constructFullRange(size_t i)
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const bool reverse =
        (i & 1) != 0;

    const S first =
        reverse
            ? S(
                P(double.max, 0.0),
                P(-double.max, 0.0)
            )
            : S(
                P(-double.max, 0.0),
                P(double.max, 0.0)
            );

    const S second =
        S(
            P(0.0, -double.max),
            P(0.0, double.max)
        );

    Point2!double point;

    const bool success =
        trySegmentIntersectionPoint(
            first,
            second,
            point
        );

    return
        pointBits(point) ^
        cast(ulong) success;
}


pragma(inline, false)
private ulong constructParameterUnderflow(size_t i)
{
    enum double huge =
        0x1p+1023;

    enum double expected =
        0x1p-977;

    alias P = Point2!double;
    alias S = Segment2!double;

    const bool reverse =
        (i & 1) != 0;

    const S first =
        reverse
            ? S(
                P(huge, huge),
                P(0.0, 0.0)
            )
            : S(
                P(0.0, 0.0),
                P(huge, huge)
            );

    const S second =
        S(
            P(expected, -1.0),
            P(expected, 1.0)
        );

    Point2!double point;

    const bool success =
        trySegmentIntersectionPoint(
            first,
            second,
            point
        );

    return
        pointBits(point) ^
        cast(ulong) success;
}


void main()
{
    writefln(
        "geo-d intersection baseline"
    );

    writefln(
        "classification iterations: %s",
        classificationIterations
    );

    writefln(
        "construction iterations:   %s",
        constructionIterations
    );

    writefln("");

    runBenchmark!classifyOrdinaryNone(
        "classify ordinary none",
        classificationIterations
    );

    runBenchmark!classifyOrdinaryCrossing(
        "classify ordinary crossing",
        classificationIterations
    );

    runBenchmark!classifyOverlap(
        "classify collinear overlap",
        classificationIterations
    );

    runBenchmark!classifyNearParallel(
        "classify near-parallel double",
        classificationIterations
    );

    runBenchmark!classifyFullRange(
        "classify full-range double",
        classificationIterations
    );

    writefln("");

    runBenchmark!constructEndpoint(
        "construct shared endpoint",
        constructionIterations
    );

    runBenchmark!constructTJunction(
        "construct T-junction",
        constructionIterations
    );

    runBenchmark!constructIntCrossing(
        "construct int proper crossing",
        constructionIterations
    );

    runBenchmark!constructDoubleCrossing(
        "construct double proper crossing",
        constructionIterations
    );

    runBenchmark!constructOneThird(
        "construct non-dyadic 1/3",
        constructionIterations
    );

    runBenchmark!constructNearParallel(
        "construct near-parallel double",
        constructionIterations
    );

    runBenchmark!constructFullRange(
        "construct full-range double",
        constructionIterations
    );

    runBenchmark!constructParameterUnderflow(
        "construct parameter underflow",
        constructionIterations
    );

    writefln("");
    writefln(
        "sink: %s",
        benchmarkSink
    );
}
