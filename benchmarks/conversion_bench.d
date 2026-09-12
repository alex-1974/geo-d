/*
 * Public-API benchmark for checked scalar conversion and explicit
 * quantisation.
 *
 * Covers representative public operations from geo.convert:
 *
 * - Point2 checked conversion:
 *     int    -> long
 *     long   -> int, success and failure
 *     long   -> double
 *     double -> int, success and fractional failure
 *     double -> float, success
 *
 * - Segment2 checked conversion as the composed four-coordinate path.
 *
 * - Point2!double quantisation:
 *     rounded
 *     floored
 *     ceiled
 *     truncated
 *
 * Local direct references implement the same relevant scalar rules and are
 * diagnostic comparisons only.
 *
 * All benchmark inputs are prepared before timing.
 */
module conversion_bench;

import geo.convert :
    ceiled,
    floored,
    rounded,
    truncated,
    tryConvert;

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

import std.math.rounding :
    ceil,
    floor;

import std.math.traits :
    isFinite;

import std.stdio :
    writefln,
    writeln;


alias PI = Point2!int;
alias PL = Point2!long;
alias PF = Point2!float;
alias PD = Point2!double;

alias SLD = Segment2!long;
alias SID = Segment2!int;
alias SDD = Segment2!double;


enum size_t repetitions = 7;

enum size_t conversionIterations = 4_000_000;
enum size_t quantisationIterations = 4_000_000;

__gshared ulong benchmarkSink;


__gshared PI[2] intPoints;
__gshared PL[2] longNarrowSuccess;
__gshared PL[2] longNarrowFailure;
__gshared PL[2] longToDoublePoints;

__gshared PD[2] doubleToIntSuccess;
__gshared PD[2] doubleToIntFailure;
__gshared PD[2] doubleToFloatSuccess;

__gshared SLD[2] segmentNarrowSuccess;
__gshared SDD[2] segmentDoubleToIntSuccess;

__gshared PD[2] quantisationPoints;


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


private ulong encodeIntPoint(
    bool success,
    PI value
)
    pure nothrow @safe @nogc
{
    return
        cast(ulong) cast(uint) value.x ^
        (
            cast(ulong) cast(uint) value.y
            << 32
        ) ^
        (
            success
                ? 0x9e37_79b9_7f4a_7c15UL
                : 0x243f_6a88_85a3_08d3UL
        );
}


private ulong encodeLongPoint(
    bool success,
    PL value
)
    pure nothrow @safe @nogc
{
    return
        cast(ulong) value.x ^
        (
            cast(ulong) value.y *
            0xbf58_476d_1ce4_e5b9UL
        ) ^
        (
            success
                ? 0x94d0_49bb_1331_11ebUL
                : 0x2545_f491_4f6c_dd1dUL
        );
}


private ulong encodeFloatPoint(
    bool success,
    PF value
)
    pure nothrow @safe @nogc
{
    return
        bits(cast(double) value.x) ^
        (
            bits(cast(double) value.y) *
            0xbf58_476d_1ce4_e5b9UL
        ) ^
        (
            success
                ? 0xd6e8_feb8_6659_fd93UL
                : 0xa409_3822_299f_31d0UL
        );
}


private ulong encodeDoublePoint(
    bool success,
    PD value
)
    pure nothrow @safe @nogc
{
    return
        bits(value.x) ^
        (
            bits(value.y) *
            0xbf58_476d_1ce4_e5b9UL
        ) ^
        (
            success
                ? 0x1319_8a2e_0370_7344UL
                : 0x082e_fa98_ec4e_6c89UL
        );
}


private ulong encodeIntSegment(
    bool success,
    SID value
)
    pure nothrow @safe @nogc
{
    return
        encodeIntPoint(
            success,
            value.a
        ) ^
        (
            encodeIntPoint(
                success,
                value.b
            ) *
            0x9e37_79b9_7f4a_7c15UL
        );
}


/*
 * Direct reference: int -> long.
 */
private bool directIntToLong(
    PI source,
    out PL result
)
    pure nothrow @safe @nogc
{
    result =
        PL(
            cast(long) source.x,
            cast(long) source.y
        );

    return true;
}


/*
 * Direct reference: checked long -> int.
 */
private bool directLongToInt(
    PL source,
    out PI result
)
    pure nothrow @safe @nogc
{
    if (
        source.x < int.min ||
        source.x > int.max ||
        source.y < int.min ||
        source.y > int.max
    )
    {
        result = PI.init;
        return false;
    }

    result =
        PI(
            cast(int) source.x,
            cast(int) source.y
        );

    return true;
}


/*
 * Direct reference: long -> double.
 *
 * The public contract permits precision loss and every long is inside the
 * exponent range of binary64.
 */
private bool directLongToDouble(
    PL source,
    out PD result
)
    pure nothrow @safe @nogc
{
    result =
        PD(
            cast(double) source.x,
            cast(double) source.y
        );

    return true;
}


/*
 * Truncation helper equivalent to the conversion implementation's
 * already-integral test.
 */
private double directTruncateTowardZero(double value)
    pure nothrow @safe @nogc
{
    if (value > 0.0)
        return floor(value);

    if (value < 0.0)
        return ceil(value);

    return value;
}


/*
 * Direct reference: checked double -> int.
 */
private bool directDoubleToInt(
    PD source,
    out PI result
)
    pure nothrow @safe @nogc
{
    enum double lower =
        -2147483648.0;

    enum double upperExclusive =
        2147483648.0;

    if (
        !isFinite(source.x) ||
        !isFinite(source.y) ||
        source.x != directTruncateTowardZero(source.x) ||
        source.y != directTruncateTowardZero(source.y) ||
        source.x < lower ||
        source.x >= upperExclusive ||
        source.y < lower ||
        source.y >= upperExclusive
    )
    {
        result = PI.init;
        return false;
    }

    result =
        PI(
            cast(int) source.x,
            cast(int) source.y
        );

    return true;
}


/*
 * Direct reference: checked double -> float.
 *
 * NaN and infinities are allowed, but these benchmark inputs are ordinary
 * finite values. A finite source becoming infinity is rejected.
 */
private bool directDoubleToFloat(
    PD source,
    out PF result
)
    pure nothrow @safe @nogc
{
    const float x =
        cast(float) source.x;

    const float y =
        cast(float) source.y;

    if (
        isFinite(source.x) &&
        !isFinite(x)
    )
    {
        result = PF.init;
        return false;
    }

    if (
        isFinite(source.y) &&
        !isFinite(y)
    )
    {
        result = PF.init;
        return false;
    }

    result =
        PF(
            x,
            y
        );

    return true;
}


/*
 * Direct reference for four-coordinate Segment2 long -> int conversion.
 */
private bool directSegmentLongToInt(
    SLD source,
    out SID result
)
    pure nothrow @safe @nogc
{
    PI a;
    PI b;

    if (!directLongToInt(source.a, a))
    {
        result = SID.init;
        return false;
    }

    if (!directLongToInt(source.b, b))
    {
        result = SID.init;
        return false;
    }

    result =
        SID(
            a,
            b
        );

    return true;
}


/*
 * Direct reference for four-coordinate Segment2 double -> int conversion.
 */
private bool directSegmentDoubleToInt(
    SDD source,
    out SID result
)
    pure nothrow @safe @nogc
{
    PI a;
    PI b;

    if (!directDoubleToInt(source.a, a))
    {
        result = SID.init;
        return false;
    }

    if (!directDoubleToInt(source.b, b))
    {
        result = SID.init;
        return false;
    }

    result =
        SID(
            a,
            b
        );

    return true;
}


private double directRoundAwayFromZero(double value)
    pure nothrow @safe @nogc
{
    if (!isFinite(value) || value == 0.0)
        return value;

    if (value > 0.0)
    {
        const double lower =
            floor(value);

        return
            value - lower < 0.5
                ? lower
                : lower + 1.0;
    }

    const double upper =
        ceil(value);

    return
        upper - value < 0.5
            ? upper
            : upper - 1.0;
}


private PD directRounded(PD value)
    pure nothrow @safe @nogc
{
    return
        PD(
            directRoundAwayFromZero(value.x),
            directRoundAwayFromZero(value.y)
        );
}


private PD directFloored(PD value)
    pure nothrow @safe @nogc
{
    return
        PD(
            floor(value.x),
            floor(value.y)
        );
}


private PD directCeiled(PD value)
    pure nothrow @safe @nogc
{
    return
        PD(
            ceil(value.x),
            ceil(value.y)
        );
}


private PD directTruncated(PD value)
    pure nothrow @safe @nogc
{
    return
        PD(
            directTruncateTowardZero(value.x),
            directTruncateTowardZero(value.y)
        );
}


private void prepareCases()
{
    intPoints[0] =
        PI(
            123456789,
            -987654321
        );

    intPoints[1] =
        PI(
            int.max - 17,
            int.min + 29
        );


    longNarrowSuccess[0] =
        PL(
            123456789,
            -987654321
        );

    longNarrowSuccess[1] =
        PL(
            int.max - 17L,
            int.min + 29L
        );


    longNarrowFailure[0] =
        PL(
            cast(long) int.max + 1L,
            0
        );

    longNarrowFailure[1] =
        PL(
            0,
            cast(long) int.min - 1L
        );


    longToDoublePoints[0] =
        PL(
            9_007_199_254_740_993L,
            -9_007_199_254_740_993L
        );

    longToDoublePoints[1] =
        PL(
            long.max,
            long.min
        );


    doubleToIntSuccess[0] =
        PD(
            123456789.0,
            -987654321.0
        );

    doubleToIntSuccess[1] =
        PD(
            2147483000.0,
            -2147483000.0
        );


    doubleToIntFailure[0] =
        PD(
            123456789.5,
            -987654321.0
        );

    doubleToIntFailure[1] =
        PD(
            42.0,
            -17.25
        );


    doubleToFloatSuccess[0] =
        PD(
            12345.125,
            -98765.5
        );

    doubleToFloatSuccess[1] =
        PD(
            0x1p100,
            -0x1p-100
        );


    segmentNarrowSuccess[0] =
        SLD(
            PL(
                123456789,
                -987654321
            ),
            PL(
                -111111111,
                222222222
            )
        );

    segmentNarrowSuccess[1] =
        SLD(
            PL(
                int.max - 7L,
                int.min + 11L
            ),
            PL(
                1,
                -1
            )
        );


    segmentDoubleToIntSuccess[0] =
        SDD(
            PD(
                100.0,
                -200.0
            ),
            PD(
                300.0,
                -400.0
            )
        );

    segmentDoubleToIntSuccess[1] =
        SDD(
            PD(
                1234567.0,
                -7654321.0
            ),
            PD(
                2147483000.0,
                -2147483000.0
            )
        );


    quantisationPoints[0] =
        PD(
            12345.375,
            -98765.625
        );

    quantisationPoints[1] =
        PD(
            -42.5,
            17.5
        );
}


private void verifyReferences()
{
    writeln("Reference verification:");

    {
        PL publicResult;
        PL directResult;

        assert(
            tryConvert!long(
                intPoints[0],
                publicResult
            )
        );

        assert(
            directIntToLong(
                intPoints[0],
                directResult
            )
        );

        assert(publicResult == directResult);
    }


    {
        PI publicResult;
        PI directResult;

        assert(
            tryConvert!int(
                longNarrowSuccess[0],
                publicResult
            )
        );

        assert(
            directLongToInt(
                longNarrowSuccess[0],
                directResult
            )
        );

        assert(publicResult == directResult);


        assert(
            !tryConvert!int(
                longNarrowFailure[0],
                publicResult
            )
        );

        assert(
            !directLongToInt(
                longNarrowFailure[0],
                directResult
            )
        );

        assert(publicResult == PI.init);
        assert(directResult == PI.init);
    }


    {
        PD publicResult;
        PD directResult;

        assert(
            tryConvert!double(
                longToDoublePoints[0],
                publicResult
            )
        );

        assert(
            directLongToDouble(
                longToDoublePoints[0],
                directResult
            )
        );

        assert(publicResult == directResult);
    }


    {
        PI publicResult;
        PI directResult;

        assert(
            tryConvert!int(
                doubleToIntSuccess[0],
                publicResult
            )
        );

        assert(
            directDoubleToInt(
                doubleToIntSuccess[0],
                directResult
            )
        );

        assert(publicResult == directResult);


        assert(
            !tryConvert!int(
                doubleToIntFailure[0],
                publicResult
            )
        );

        assert(
            !directDoubleToInt(
                doubleToIntFailure[0],
                directResult
            )
        );

        assert(publicResult == PI.init);
        assert(directResult == PI.init);
    }


    {
        PF publicResult;
        PF directResult;

        assert(
            tryConvert!float(
                doubleToFloatSuccess[0],
                publicResult
            )
        );

        assert(
            directDoubleToFloat(
                doubleToFloatSuccess[0],
                directResult
            )
        );

        assert(publicResult == directResult);
    }


    {
        SID publicResult;
        SID directResult;

        assert(
            tryConvert!int(
                segmentNarrowSuccess[0],
                publicResult
            )
        );

        assert(
            directSegmentLongToInt(
                segmentNarrowSuccess[0],
                directResult
            )
        );

        assert(publicResult == directResult);


        assert(
            tryConvert!int(
                segmentDoubleToIntSuccess[0],
                publicResult
            )
        );

        assert(
            directSegmentDoubleToInt(
                segmentDoubleToIntSuccess[0],
                directResult
            )
        );

        assert(publicResult == directResult);
    }


    {
        const PD value =
            quantisationPoints[0];

        assert(value.rounded == directRounded(value));
        assert(value.floored == directFloored(value));
        assert(value.ceiled == directCeiled(value));
        assert(value.truncated == directTruncated(value));
    }

    writeln("  PASS");
}


pragma(inline, false)
private ulong publicIntToLong(size_t i)
{
    PL result;

    const bool success =
        tryConvert!long(
            intPoints[i & 1],
            result
        );

    return
        encodeLongPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong directIntToLongBench(size_t i)
{
    PL result;

    const bool success =
        directIntToLong(
            intPoints[i & 1],
            result
        );

    return
        encodeLongPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong publicLongToIntSuccess(size_t i)
{
    PI result;

    const bool success =
        tryConvert!int(
            longNarrowSuccess[i & 1],
            result
        );

    return
        encodeIntPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong directLongToIntSuccess(size_t i)
{
    PI result;

    const bool success =
        directLongToInt(
            longNarrowSuccess[i & 1],
            result
        );

    return
        encodeIntPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong publicLongToIntFailure(size_t i)
{
    PI result;

    const bool success =
        tryConvert!int(
            longNarrowFailure[i & 1],
            result
        );

    return
        encodeIntPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong directLongToIntFailure(size_t i)
{
    PI result;

    const bool success =
        directLongToInt(
            longNarrowFailure[i & 1],
            result
        );

    return
        encodeIntPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong publicLongToDouble(size_t i)
{
    PD result;

    const bool success =
        tryConvert!double(
            longToDoublePoints[i & 1],
            result
        );

    return
        encodeDoublePoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong directLongToDoubleBench(size_t i)
{
    PD result;

    const bool success =
        directLongToDouble(
            longToDoublePoints[i & 1],
            result
        );

    return
        encodeDoublePoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong publicDoubleToIntSuccess(size_t i)
{
    PI result;

    const bool success =
        tryConvert!int(
            doubleToIntSuccess[i & 1],
            result
        );

    return
        encodeIntPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong directDoubleToIntSuccess(size_t i)
{
    PI result;

    const bool success =
        directDoubleToInt(
            doubleToIntSuccess[i & 1],
            result
        );

    return
        encodeIntPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong publicDoubleToIntFailure(size_t i)
{
    PI result;

    const bool success =
        tryConvert!int(
            doubleToIntFailure[i & 1],
            result
        );

    return
        encodeIntPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong directDoubleToIntFailure(size_t i)
{
    PI result;

    const bool success =
        directDoubleToInt(
            doubleToIntFailure[i & 1],
            result
        );

    return
        encodeIntPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong publicDoubleToFloat(size_t i)
{
    PF result;

    const bool success =
        tryConvert!float(
            doubleToFloatSuccess[i & 1],
            result
        );

    return
        encodeFloatPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong directDoubleToFloatBench(size_t i)
{
    PF result;

    const bool success =
        directDoubleToFloat(
            doubleToFloatSuccess[i & 1],
            result
        );

    return
        encodeFloatPoint(
            success,
            result
        );
}


pragma(inline, false)
private ulong publicSegmentLongToInt(size_t i)
{
    SID result;

    const bool success =
        tryConvert!int(
            segmentNarrowSuccess[i & 1],
            result
        );

    return
        encodeIntSegment(
            success,
            result
        );
}


pragma(inline, false)
private ulong directSegmentLongToIntBench(size_t i)
{
    SID result;

    const bool success =
        directSegmentLongToInt(
            segmentNarrowSuccess[i & 1],
            result
        );

    return
        encodeIntSegment(
            success,
            result
        );
}


pragma(inline, false)
private ulong publicSegmentDoubleToInt(size_t i)
{
    SID result;

    const bool success =
        tryConvert!int(
            segmentDoubleToIntSuccess[i & 1],
            result
        );

    return
        encodeIntSegment(
            success,
            result
        );
}


pragma(inline, false)
private ulong directSegmentDoubleToIntBench(size_t i)
{
    SID result;

    const bool success =
        directSegmentDoubleToInt(
            segmentDoubleToIntSuccess[i & 1],
            result
        );

    return
        encodeIntSegment(
            success,
            result
        );
}


pragma(inline, false)
private ulong publicRounded(size_t i)
{
    return
        encodeDoublePoint(
            true,
            quantisationPoints[i & 1].rounded
        );
}


pragma(inline, false)
private ulong directRoundedBench(size_t i)
{
    return
        encodeDoublePoint(
            true,
            directRounded(
                quantisationPoints[i & 1]
            )
        );
}


pragma(inline, false)
private ulong publicFloored(size_t i)
{
    return
        encodeDoublePoint(
            true,
            quantisationPoints[i & 1].floored
        );
}


pragma(inline, false)
private ulong directFlooredBench(size_t i)
{
    return
        encodeDoublePoint(
            true,
            directFloored(
                quantisationPoints[i & 1]
            )
        );
}


pragma(inline, false)
private ulong publicCeiled(size_t i)
{
    return
        encodeDoublePoint(
            true,
            quantisationPoints[i & 1].ceiled
        );
}


pragma(inline, false)
private ulong directCeiledBench(size_t i)
{
    return
        encodeDoublePoint(
            true,
            directCeiled(
                quantisationPoints[i & 1]
            )
        );
}


pragma(inline, false)
private ulong publicTruncated(size_t i)
{
    return
        encodeDoublePoint(
            true,
            quantisationPoints[i & 1].truncated
        );
}


pragma(inline, false)
private ulong directTruncatedBench(size_t i)
{
    return
        encodeDoublePoint(
            true,
            directTruncated(
                quantisationPoints[i & 1]
            )
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
        "%-42s %10.2f ns/op",
        name,
        nsPerOperation
    );
}


void main()
{
    prepareCases();
    verifyReferences();

    writeln();
    writeln("Checked Point2 conversion:");

    runBenchmark!publicIntToLong(
        "public int -> long",
        conversionIterations
    );

    runBenchmark!directIntToLongBench(
        "direct int -> long",
        conversionIterations
    );


    runBenchmark!publicLongToIntSuccess(
        "public long -> int success",
        conversionIterations
    );

    runBenchmark!directLongToIntSuccess(
        "direct long -> int success",
        conversionIterations
    );


    runBenchmark!publicLongToIntFailure(
        "public long -> int failure",
        conversionIterations
    );

    runBenchmark!directLongToIntFailure(
        "direct long -> int failure",
        conversionIterations
    );


    runBenchmark!publicLongToDouble(
        "public long -> double",
        conversionIterations
    );

    runBenchmark!directLongToDoubleBench(
        "direct long -> double",
        conversionIterations
    );


    runBenchmark!publicDoubleToIntSuccess(
        "public double -> int success",
        conversionIterations
    );

    runBenchmark!directDoubleToIntSuccess(
        "direct double -> int success",
        conversionIterations
    );


    runBenchmark!publicDoubleToIntFailure(
        "public double -> int fractional failure",
        conversionIterations
    );

    runBenchmark!directDoubleToIntFailure(
        "direct double -> int fractional failure",
        conversionIterations
    );


    runBenchmark!publicDoubleToFloat(
        "public double -> float",
        conversionIterations
    );

    runBenchmark!directDoubleToFloatBench(
        "direct double -> float",
        conversionIterations
    );


    writeln();
    writeln("Checked Segment2 conversion:");

    runBenchmark!publicSegmentLongToInt(
        "public segment long -> int",
        conversionIterations
    );

    runBenchmark!directSegmentLongToIntBench(
        "direct segment long -> int",
        conversionIterations
    );


    runBenchmark!publicSegmentDoubleToInt(
        "public segment double -> int",
        conversionIterations
    );

    runBenchmark!directSegmentDoubleToIntBench(
        "direct segment double -> int",
        conversionIterations
    );


    writeln();
    writeln("Point2!double quantisation:");

    runBenchmark!publicRounded(
        "public rounded",
        quantisationIterations
    );

    runBenchmark!directRoundedBench(
        "direct rounded",
        quantisationIterations
    );


    runBenchmark!publicFloored(
        "public floored",
        quantisationIterations
    );

    runBenchmark!directFlooredBench(
        "direct floored",
        quantisationIterations
    );


    runBenchmark!publicCeiled(
        "public ceiled",
        quantisationIterations
    );

    runBenchmark!directCeiledBench(
        "direct ceiled",
        quantisationIterations
    );


    runBenchmark!publicTruncated(
        "public truncated",
        quantisationIterations
    );

    runBenchmark!directTruncatedBench(
        "direct truncated",
        quantisationIterations
    );


    writeln();
    writefln(
        "sink=%s",
        benchmarkSink
    );
}
