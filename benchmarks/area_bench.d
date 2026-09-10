module area_bench;

import geo.area :
    signedArea;

import geo.linear_ring_view :
    LinearRingView;

import geo.point :
    Point2;

import std.bitmanip :
    DoubleRep;

import std.datetime.stopwatch :
    StopWatch;

import std.math :
    cos,
    sin;

import std.stdio :
    writefln;


enum size_t smallIterations = 200_000;
enum size_t ring10Iterations = 100_000;
enum size_t ring100Iterations = 20_000;
enum size_t ring1000Iterations = 2_000;
enum size_t ring10000Iterations = 200;
enum size_t adversarialIterations = 100_000;

__gshared ulong benchmarkSink;


__gshared Point2!int[3] intTriangleA;
__gshared Point2!int[3] intTriangleB;

__gshared Point2!double[3] doubleTriangleA;
__gshared Point2!double[3] doubleTriangleB;

__gshared Point2!long[3] translatedLongA;
__gshared Point2!long[3] translatedLongB;

__gshared Point2!double[3] fullRangeDoubleA;
__gshared Point2!double[3] fullRangeDoubleB;

__gshared Point2!double[] ring10A;
__gshared Point2!double[] ring10B;
__gshared Point2!double[] ring100A;
__gshared Point2!double[] ring100B;
__gshared Point2!double[] ring1000A;
__gshared Point2!double[] ring1000B;
__gshared Point2!double[] ring10000A;
__gshared Point2!double[] ring10000B;


private ulong bits(double value)
{
    DoubleRep representation;
    representation.value = value;

    return
        representation.fraction ^
        (cast(ulong) representation.exponent << 52) ^
        (cast(ulong) representation.sign << 63);
}


private void runBenchmark(alias operation)(
    string name,
    size_t iterations,
    size_t warmupIterations
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
        "%-38s %12.2f ns/op   n=%s",
        name,
        cast(double) nanoseconds /
            cast(double) iterations,
        iterations
    );
}


/*
 * Deliberately naive comparison implementation.
 *
 * This is not geo-d API and does not provide the numerical guarantees of
 * signedArea(). Coordinates are converted to double before ordinary
 * closed-shoelace accumulation.
 */
private double naiveSignedArea(T)(
    LinearRingView!T ring
)
{
    if (ring.length == 0)
        return 0.0;

    double twiceArea = 0.0;

    foreach (i; 0 .. ring.segmentCount)
    {
        const auto segment =
            ring.segment(i);

        twiceArea +=
            cast(double) segment.a.x *
                cast(double) segment.b.y
            -
            cast(double) segment.a.y *
                cast(double) segment.b.x;
    }

    return twiceArea * 0.5;
}


private Point2!double[] makeOrdinaryRing(
    size_t count,
    double offset
)
{
    assert(count >= 3);

    auto points =
        new Point2!double[count];

    enum double tau =
        6.283185307179586476925286766559;

    foreach (i; 0 .. count)
    {
        const double angle =
            tau *
            cast(double) i /
            cast(double) count;

        /*
         * Slight radial variation avoids making every determinant look
         * numerically identical while preserving an ordinary simple ring.
         */
        const double radius =
            1000.0 +
            cast(double)(i % 7) *
            0.125;

        points[i] =
            Point2!double(
                offset +
                    radius * cos(angle),
                offset * 0.5 +
                    radius * sin(angle)
            );
    }

    return points;
}


private void prepareCases()
{
    intTriangleA = [
        Point2!int(0, 0),
        Point2!int(4, 0),
        Point2!int(0, 3)
    ];

    intTriangleB = [
        Point2!int(1, 1),
        Point2!int(5, 1),
        Point2!int(1, 4)
    ];


    doubleTriangleA = [
        Point2!double(0.0, 0.0),
        Point2!double(4.0, 0.0),
        Point2!double(0.0, 3.0)
    ];

    doubleTriangleB = [
        Point2!double(0.25, 0.5),
        Point2!double(4.25, 0.5),
        Point2!double(0.25, 3.5)
    ];


    translatedLongA = [
        Point2!long(
            long.max - 4,
            long.max - 3
        ),
        Point2!long(
            long.max,
            long.max - 3
        ),
        Point2!long(
            long.max - 4,
            long.max
        )
    ];

    translatedLongB = [
        Point2!long(
            long.min,
            long.min
        ),
        Point2!long(
            long.min + 4,
            long.min
        ),
        Point2!long(
            long.min,
            long.min + 3
        )
    ];


    fullRangeDoubleA = [
        Point2!double(0.0, 0.0),
        Point2!double(
            double.max,
            0.0
        ),
        Point2!double(
            0.0,
            double.max
        )
    ];

    fullRangeDoubleB = [
        Point2!double(0.0, 0.0),
        Point2!double(
            0.0,
            double.max
        ),
        Point2!double(
            double.max,
            0.0
        )
    ];


    ring10A =
        makeOrdinaryRing(
            10,
            0.0
        );

    ring10B =
        makeOrdinaryRing(
            10,
            0.25
        );

    ring100A =
        makeOrdinaryRing(
            100,
            0.0
        );

    ring100B =
        makeOrdinaryRing(
            100,
            0.25
        );

    ring1000A =
        makeOrdinaryRing(
            1_000,
            0.0
        );

    ring1000B =
        makeOrdinaryRing(
            1_000,
            0.25
        );

    ring10000A =
        makeOrdinaryRing(
            10_000,
            0.0
        );

    ring10000B =
        makeOrdinaryRing(
            10_000,
            0.25
        );
}


pragma(inline, false)
private ulong exactIntTriangle(size_t i)
{
    const auto points =
        (i & 1) == 0
            ? intTriangleA[]
            : intTriangleB[];

    return bits(
        signedArea(
            LinearRingView!int(points)
        )
    );
}


pragma(inline, false)
private ulong naiveIntTriangle(size_t i)
{
    const auto points =
        (i & 1) == 0
            ? intTriangleA[]
            : intTriangleB[];

    return bits(
        naiveSignedArea(
            LinearRingView!int(points)
        )
    );
}


pragma(inline, false)
private ulong exactDoubleTriangle(size_t i)
{
    const auto points =
        (i & 1) == 0
            ? doubleTriangleA[]
            : doubleTriangleB[];

    return bits(
        signedArea(
            LinearRingView!double(points)
        )
    );
}


pragma(inline, false)
private ulong naiveDoubleTriangle(size_t i)
{
    const auto points =
        (i & 1) == 0
            ? doubleTriangleA[]
            : doubleTriangleB[];

    return bits(
        naiveSignedArea(
            LinearRingView!double(points)
        )
    );
}


pragma(inline, false)
private ulong exactTranslatedLong(size_t i)
{
    const auto points =
        (i & 1) == 0
            ? translatedLongA[]
            : translatedLongB[];

    return bits(
        signedArea(
            LinearRingView!long(points)
        )
    );
}


pragma(inline, false)
private ulong naiveTranslatedLong(size_t i)
{
    const auto points =
        (i & 1) == 0
            ? translatedLongA[]
            : translatedLongB[];

    return bits(
        naiveSignedArea(
            LinearRingView!long(points)
        )
    );
}


private ulong exactOrdinaryDouble(
    size_t i,
    Point2!double[] first,
    Point2!double[] second
)
{
    const auto points =
        (i & 1) == 0
            ? first
            : second;

    return bits(
        signedArea(
            LinearRingView!double(points)
        )
    );
}


private ulong naiveOrdinaryDouble(
    size_t i,
    Point2!double[] first,
    Point2!double[] second
)
{
    const auto points =
        (i & 1) == 0
            ? first
            : second;

    return bits(
        naiveSignedArea(
            LinearRingView!double(points)
        )
    );
}


pragma(inline, false)
private ulong exactRing10(size_t i)
{
    return exactOrdinaryDouble(
        i,
        ring10A,
        ring10B
    );
}


pragma(inline, false)
private ulong naiveRing10(size_t i)
{
    return naiveOrdinaryDouble(
        i,
        ring10A,
        ring10B
    );
}


pragma(inline, false)
private ulong exactRing100(size_t i)
{
    return exactOrdinaryDouble(
        i,
        ring100A,
        ring100B
    );
}


pragma(inline, false)
private ulong naiveRing100(size_t i)
{
    return naiveOrdinaryDouble(
        i,
        ring100A,
        ring100B
    );
}


pragma(inline, false)
private ulong exactRing1000(size_t i)
{
    return exactOrdinaryDouble(
        i,
        ring1000A,
        ring1000B
    );
}


pragma(inline, false)
private ulong naiveRing1000(size_t i)
{
    return naiveOrdinaryDouble(
        i,
        ring1000A,
        ring1000B
    );
}


pragma(inline, false)
private ulong exactRing10000(size_t i)
{
    return exactOrdinaryDouble(
        i,
        ring10000A,
        ring10000B
    );
}


pragma(inline, false)
private ulong naiveRing10000(size_t i)
{
    return naiveOrdinaryDouble(
        i,
        ring10000A,
        ring10000B
    );
}


pragma(inline, false)
private ulong exactFullRangeDouble(size_t i)
{
    const auto points =
        (i & 1) == 0
            ? fullRangeDoubleA[]
            : fullRangeDoubleB[];

    return bits(
        signedArea(
            LinearRingView!double(points)
        )
    );
}


pragma(inline, false)
private ulong naiveFullRangeDouble(size_t i)
{
    const auto points =
        (i & 1) == 0
            ? fullRangeDoubleA[]
            : fullRangeDoubleB[];

    return bits(
        naiveSignedArea(
            LinearRingView!double(points)
        )
    );
}


void main()
{
    prepareCases();

    writefln("signed-area benchmark");
    writefln("");

    runBenchmark!exactIntTriangle(
        "exact int triangle",
        smallIterations,
        2_000
    );

    runBenchmark!naiveIntTriangle(
        "naive int triangle",
        smallIterations,
        2_000
    );

    runBenchmark!exactDoubleTriangle(
        "exact double triangle",
        smallIterations,
        2_000
    );

    runBenchmark!naiveDoubleTriangle(
        "naive double triangle",
        smallIterations,
        2_000
    );

    runBenchmark!exactTranslatedLong(
        "exact translated long triangle",
        adversarialIterations,
        1_000
    );

    runBenchmark!naiveTranslatedLong(
        "naive translated long triangle",
        adversarialIterations,
        1_000
    );

    writefln("");

    runBenchmark!exactRing10(
        "exact ordinary double n=10",
        ring10Iterations,
        1_000
    );

    runBenchmark!naiveRing10(
        "naive ordinary double n=10",
        ring10Iterations,
        1_000
    );

    runBenchmark!exactRing100(
        "exact ordinary double n=100",
        ring100Iterations,
        200
    );

    runBenchmark!naiveRing100(
        "naive ordinary double n=100",
        ring100Iterations,
        200
    );

    runBenchmark!exactRing1000(
        "exact ordinary double n=1000",
        ring1000Iterations,
        20
    );

    runBenchmark!naiveRing1000(
        "naive ordinary double n=1000",
        ring1000Iterations,
        20
    );

    runBenchmark!exactRing10000(
        "exact ordinary double n=10000",
        ring10000Iterations,
        2
    );

    runBenchmark!naiveRing10000(
        "naive ordinary double n=10000",
        ring10000Iterations,
        2
    );

    writefln("");

    runBenchmark!exactFullRangeDouble(
        "exact full-range double triangle",
        adversarialIterations,
        1_000
    );

    runBenchmark!naiveFullRangeDouble(
        "naive full-range double triangle",
        adversarialIterations,
        1_000
    );

    writefln("");
    writefln("sink: %s", benchmarkSink);
}
