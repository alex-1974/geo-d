/*
 * End-to-end benchmark for the public geo.orientation.orientation() API.
 *
 * The benchmark covers exact integer predicates, ordinary floating-point
 * fast paths, expansion fallbacks, and dyadic fallbacks.
 *
 * Reference implementations in benchmarks/reference/ are diagnostic
 * comparisons only; not every public robust path has a semantically
 * equivalent C++ counterpart.
 */
module orientation_bench;

import geo.orientation :
    Orientation,
    orientation;

import geo.point :
    Point2;

import std.algorithm.sorting :
    sort;

import std.datetime.stopwatch :
    StopWatch;

import std.stdio :
    writefln;


enum size_t repetitions = 7;
enum size_t warmupIterations = 1_000_000;

enum size_t cheapIterations = 20_000_000;
enum size_t expansionIterations = 1_000_000;
enum size_t dyadicIterations = 500_000;


__gshared ulong benchmarkSink;


struct OrientationCase(T)
{
    Point2!T a;
    Point2!T b;
    Point2!T c;
}


__gshared OrientationCase!int[2] intOrdinaryCases;
__gshared OrientationCase!int[2] intExtremeCases;

__gshared OrientationCase!long[2] longOrdinaryCases;
__gshared OrientationCase!long[2] longExtremeCases;

__gshared OrientationCase!double[2] doubleFastCases;
__gshared OrientationCase!double[2] doubleExpansionCollinearCases;
__gshared OrientationCase!double[2] doubleExpansionNearCases;
__gshared OrientationCase!double[2] doubleDyadicCollinearCases;
__gshared OrientationCase!double[2] doubleDyadicNearCases;
__gshared OrientationCase!double[2] doubleSubnormalCases;

__gshared OrientationCase!float[2] floatFastCases;


private ulong encode(Orientation value)
    pure nothrow @safe @nogc
{
    return cast(ulong)(
        cast(int) value + 1
    );
}


private void prepareCases()
{
    alias PI = Point2!int;
    alias PL = Point2!long;
    alias PD = Point2!double;
    alias PF = Point2!float;


    intOrdinaryCases[0] =
        OrientationCase!int(
            PI(0, 0),
            PI(10, 0),
            PI(5, 1)
        );

    intOrdinaryCases[1] =
        OrientationCase!int(
            PI(1, 1),
            PI(11, 1),
            PI(6, 0)
        );


    intExtremeCases[0] =
        OrientationCase!int(
            PI(int.min, int.min),
            PI(int.max, int.min),
            PI(int.min, int.max)
        );

    intExtremeCases[1] =
        OrientationCase!int(
            PI(int.max, int.max),
            PI(int.min, int.max),
            PI(int.max, int.min)
        );


    longOrdinaryCases[0] =
        OrientationCase!long(
            PL(0, 0),
            PL(10, 0),
            PL(5, 1)
        );

    longOrdinaryCases[1] =
        OrientationCase!long(
            PL(1, 1),
            PL(11, 1),
            PL(6, 0)
        );


    longExtremeCases[0] =
        OrientationCase!long(
            PL(long.min, long.min),
            PL(long.max, long.min),
            PL(long.min, long.max)
        );

    longExtremeCases[1] =
        OrientationCase!long(
            PL(long.max, long.max),
            PL(long.min, long.max),
            PL(long.max, long.min)
        );


    doubleFastCases[0] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(10.0, 0.0),
            PD(5.0, 1.0)
        );

    doubleFastCases[1] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(10.0, 0.0),
            PD(5.0, -1.0)
        );


    doubleExpansionCollinearCases[0] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(10.0, 10.0),
            PD(5.0, 5.0)
        );

    doubleExpansionCollinearCases[1] =
        OrientationCase!double(
            PD(1.0, 1.0),
            PD(11.0, 11.0),
            PD(6.0, 6.0)
        );


    doubleExpansionNearCases[0] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(10.0, 10.0),
            PD(
                5.0,
                0x1.4000000000001p+2
            )
        );

    doubleExpansionNearCases[1] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(10.0, 10.0),
            PD(
                5.0,
                0x1.3ffffffffffffp+2
            )
        );


    enum double large =
        0x1p+500;

    enum double half =
        0x1p+499;

    enum double halfNext =
        0x1.0000000000001p+499;

    enum double halfPrevious =
        0x1.fffffffffffffp+498;


    doubleDyadicCollinearCases[0] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(large, large),
            PD(half, half)
        );

    doubleDyadicCollinearCases[1] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(-large, -large),
            PD(-half, -half)
        );


    doubleDyadicNearCases[0] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(large, large),
            PD(half, halfNext)
        );

    doubleDyadicNearCases[1] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(large, large),
            PD(half, halfPrevious)
        );


    enum double minSubnormal =
        0x0.0000000000001p-1022;

    doubleSubnormalCases[0] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(minSubnormal, 0.0),
            PD(0.0, minSubnormal)
        );

    doubleSubnormalCases[1] =
        OrientationCase!double(
            PD(0.0, 0.0),
            PD(0.0, minSubnormal),
            PD(minSubnormal, 0.0)
        );


    floatFastCases[0] =
        OrientationCase!float(
            PF(0.0f, 0.0f),
            PF(10.0f, 0.0f),
            PF(5.0f, 1.0f)
        );

    floatFastCases[1] =
        OrientationCase!float(
            PF(0.0f, 0.0f),
            PF(10.0f, 0.0f),
            PF(5.0f, -1.0f)
        );
}


private void runBenchmark(alias operation)(
    string name,
    size_t iterations
)
{
    ulong localSink;

    foreach (i; 0 .. warmupIterations)
        localSink += operation(i);

    long[repetitions] samples;


    foreach (sample; 0 .. repetitions)
    {
        StopWatch stopwatch;
        stopwatch.start();

        foreach (i; 0 .. iterations)
            localSink += operation(i);

        stopwatch.stop();

        samples[sample] =
            stopwatch.peek.total!"nsecs";
    }


    benchmarkSink ^= localSink;

    sort(samples[]);

    const double medianNsPerOperation =
        cast(double) samples[repetitions / 2] /
        cast(double) iterations;

    const double minimumNsPerOperation =
        cast(double) samples[0] /
        cast(double) iterations;

    const double maximumNsPerOperation =
        cast(double) samples[$ - 1] /
        cast(double) iterations;


    writefln(
        "%-31s %10.2f ns/op   min=%8.2f   max=%8.2f   n=%s",
        name,
        medianNsPerOperation,
        minimumNsPerOperation,
        maximumNsPerOperation,
        iterations
    );
}


pragma(inline, false)
private ulong benchIntOrdinary(size_t i)
{
    const auto value =
        intOrdinaryCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchIntExtreme(size_t i)
{
    const auto value =
        intExtremeCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchLongOrdinary(size_t i)
{
    const auto value =
        longOrdinaryCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchLongExtreme(size_t i)
{
    const auto value =
        longExtremeCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchDoubleFast(size_t i)
{
    const auto value =
        doubleFastCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchDoubleExpansionCollinear(size_t i)
{
    const auto value =
        doubleExpansionCollinearCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchDoubleExpansionNear(size_t i)
{
    const auto value =
        doubleExpansionNearCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchDoubleDyadicCollinear(size_t i)
{
    const auto value =
        doubleDyadicCollinearCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchDoubleDyadicNear(size_t i)
{
    const auto value =
        doubleDyadicNearCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchDoubleSubnormal(size_t i)
{
    const auto value =
        doubleSubnormalCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


pragma(inline, false)
private ulong benchFloatFast(size_t i)
{
    const auto value =
        floatFastCases[i & 1];

    return encode(
        orientation(
            value.a,
            value.b,
            value.c
        )
    );
}


void main()
{
    prepareCases();

    writefln("geo-d public orientation() benchmark");
    writefln("median of %s measured runs", repetitions);
    writefln("");


    runBenchmark!benchIntOrdinary(
        "int ordinary",
        cheapIterations
    );

    runBenchmark!benchIntExtreme(
        "int full-range",
        cheapIterations
    );


    runBenchmark!benchLongOrdinary(
        "long ordinary",
        cheapIterations
    );

    runBenchmark!benchLongExtreme(
        "long full-range",
        cheapIterations
    );


    runBenchmark!benchFloatFast(
        "float ordinary",
        cheapIterations
    );


    runBenchmark!benchDoubleFast(
        "double filter fast",
        cheapIterations
    );

    runBenchmark!benchDoubleExpansionCollinear(
        "double expansion collinear",
        expansionIterations
    );

    runBenchmark!benchDoubleExpansionNear(
        "double expansion near",
        expansionIterations
    );

    runBenchmark!benchDoubleDyadicCollinear(
        "double dyadic collinear",
        dyadicIterations
    );

    runBenchmark!benchDoubleDyadicNear(
        "double dyadic near",
        dyadicIterations
    );

    runBenchmark!benchDoubleSubnormal(
        "double dyadic subnormal",
        dyadicIterations
    );


    writefln("");
    writefln("sink: %s", benchmarkSink);
}
