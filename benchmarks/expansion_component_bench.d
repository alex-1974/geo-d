module expansion_component_bench;

import geo.internal.expansion :
    ExpansionBuffer,
    TwoComponent,
    fastExpansionSumZeroElim,
    fastTwoSum,
    scaleExpansionZeroElim,
    twoDiff,
    twoProduct,
    twoSum;

import geo.internal.orientation_exact :
    tryOrientationExactExpansion;

import std.algorithm.sorting : sort;
import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;

enum size_t repetitions = 7;
enum size_t warmupIterations = 500_000;

enum size_t eftIterations = 20_000_000;
enum size_t expansionIterations = 5_000_000;
enum size_t orientationIterations = 1_000_000;

__gshared ulong benchmarkSink;

struct Pair
{
    double a;
    double b;
}

__gshared Pair[2] sumCases;
__gshared Pair[2] diffCases;
__gshared Pair[2] productCases;
__gshared Pair[2] fastSumCases;

__gshared ExpansionBuffer!2[2] scaleInputs;
__gshared double[2] scaleScalars;

__gshared ExpansionBuffer!4[2] sumLeft;
__gshared ExpansionBuffer!4[2] sumRight;

struct OrientationCase
{
    double ax;
    double ay;
    double bx;
    double by;
    double cx;
    double cy;
}

__gshared OrientationCase[2] orientationCollinearCases;
__gshared OrientationCase[2] orientationNearCases;


private ulong encode(TwoComponent value)
    pure nothrow @safe @nogc
{
    return
        cast(ulong)(value.high != 0.0) +
        3UL * cast(ulong)(value.low != 0.0) +
        cast(ulong)(value.high < 0.0);
}


private void prepareCases()
{
    sumCases[0] = Pair(1.0, 0x1p-53);
    sumCases[1] = Pair(-2.0, 0x1p-52);

    diffCases[0] = Pair(1.0, 0x1p-53);
    diffCases[1] = Pair(-2.0, -0x1p-52);

    productCases[0] = Pair(1.0 + 0x1p-27, 1.0 - 0x1p-27);
    productCases[1] = Pair(-3.0 + 0x1p-25, 0.5 + 0x1p-28);

    /*
     * FastTwoSum requires |a| >= |b|.
     */
    fastSumCases[0] = Pair(1.0, 0x1p-53);
    fastSumCases[1] = Pair(-2.0, 0x1p-52);

    foreach (index; 0 .. 2)
    {
        scaleInputs[index].clear();
    }

    scaleInputs[0].append(0x1p-104);
    scaleInputs[0].append(1.0);
    scaleScalars[0] = 1.0 + 0x1p-27;

    scaleInputs[1].append(-0x1p-103);
    scaleInputs[1].append(2.0);
    scaleScalars[1] = -0.5 + 0x1p-28;

    foreach (index; 0 .. 2)
    {
        sumLeft[index].clear();
        sumRight[index].clear();
    }

    /*
     * Valid non-overlapping, increasing-magnitude expansions.
     */
    sumLeft[0].append(0x1p-156);
    sumLeft[0].append(-0x1p-104);
    sumLeft[0].append(0x1p-52);
    sumLeft[0].append(1.0);

    sumRight[0].append(-0x1p-155);
    sumRight[0].append(0x1p-103);
    sumRight[0].append(-0x1p-51);
    sumRight[0].append(2.0);

    sumLeft[1].append(-0x1p-158);
    sumLeft[1].append(0x1p-106);
    sumLeft[1].append(-0x1p-54);
    sumLeft[1].append(-1.5);

    sumRight[1].append(0x1p-157);
    sumRight[1].append(-0x1p-105);
    sumRight[1].append(0x1p-53);
    sumRight[1].append(-2.5);

    orientationCollinearCases[0] =
        OrientationCase(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 5.0
        );

    orientationCollinearCases[1] =
        OrientationCase(
            1.0, 1.0,
            11.0, 11.0,
            6.0, 6.0
        );

    orientationNearCases[0] =
        OrientationCase(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 0x1.4000000000001p+2
        );

    orientationNearCases[1] =
        OrientationCase(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 0x1.3ffffffffffffp+2
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

    const double median =
        cast(double) samples[repetitions / 2] /
        cast(double) iterations;

    const double minimum =
        cast(double) samples[0] /
        cast(double) iterations;

    const double maximum =
        cast(double) samples[$ - 1] /
        cast(double) iterations;

    writefln(
        "%-31s %10.2f ns/op   min=%8.2f   max=%8.2f   n=%s",
        name,
        median,
        minimum,
        maximum,
        iterations
    );
}


pragma(inline, false)
private ulong benchTwoSum(size_t i)
{
    const auto value = sumCases[i & 1];
    return encode(twoSum(value.a, value.b));
}


pragma(inline, false)
private ulong benchTwoDiff(size_t i)
{
    const auto value = diffCases[i & 1];
    return encode(twoDiff(value.a, value.b));
}


pragma(inline, false)
private ulong benchFastTwoSum(size_t i)
{
    const auto value = fastSumCases[i & 1];
    return encode(fastTwoSum(value.a, value.b));
}


pragma(inline, false)
private ulong benchTwoProduct(size_t i)
{
    const auto value = productCases[i & 1];
    return encode(twoProduct(value.a, value.b));
}


pragma(inline, false)
private ulong benchScale2(size_t i)
{
    const size_t index = i & 1;

    ExpansionBuffer!4 result;

    scaleExpansionZeroElim(
        scaleInputs[index],
        scaleScalars[index],
        result
    );

    return
        cast(ulong) result.length +
        7UL * cast(ulong)(
            result[result.length - 1] != 0.0
        );
}


pragma(inline, false)
private ulong benchSum4x4(size_t i)
{
    const size_t index = i & 1;

    ExpansionBuffer!8 result;

    fastExpansionSumZeroElim(
        sumLeft[index],
        sumRight[index],
        result
    );

    return
        cast(ulong) result.length +
        7UL * cast(ulong)(
            result[result.length - 1] != 0.0
        );
}


pragma(inline, false)
private ulong benchOrientationCollinear(size_t i)
{
    const auto value =
        orientationCollinearCases[i & 1];

    int sign;

    const bool success =
        tryOrientationExactExpansion(
            value.ax, value.ay,
            value.bx, value.by,
            value.cx, value.cy,
            sign
        );

    return
        cast(ulong) success +
        cast(ulong)(sign + 1) * 3UL;
}


pragma(inline, false)
private ulong benchOrientationNear(size_t i)
{
    const auto value =
        orientationNearCases[i & 1];

    int sign;

    const bool success =
        tryOrientationExactExpansion(
            value.ax, value.ay,
            value.bx, value.by,
            value.cx, value.cy,
            sign
        );

    return
        cast(ulong) success +
        cast(ulong)(sign + 1) * 3UL;
}


void main()
{
    prepareCases();

    writelnHeader();

    runBenchmark!benchTwoSum(
        "twoSum",
        eftIterations
    );

    runBenchmark!benchTwoDiff(
        "twoDiff",
        eftIterations
    );

    runBenchmark!benchFastTwoSum(
        "fastTwoSum",
        eftIterations
    );

    runBenchmark!benchTwoProduct(
        "twoProduct",
        eftIterations
    );

    runBenchmark!benchScale2(
        "scaleExpansion 2->4",
        expansionIterations
    );

    runBenchmark!benchSum4x4(
        "fastExpansionSum 4+4",
        expansionIterations
    );

    runBenchmark!benchOrientationCollinear(
        "orientation exact collinear",
        orientationIterations
    );

    runBenchmark!benchOrientationNear(
        "orientation exact near",
        orientationIterations
    );

    writefln("\nsink: %s", benchmarkSink);
}


private void writelnHeader()
{
    import std.stdio : writeln;

    writeln(
        "D/LDC expansion component benchmark\n",
        "median of 7 measured runs"
    );
}
