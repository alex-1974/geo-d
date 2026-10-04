module geo.internal.weight_span_only_probe;

import core.memory : GC;
import core.volatile : volatileLoad;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    SignedDyadicCoordinate,
    SignedDyadicProduct;
import geo.internal.exact_coordinate :
    ExactCoordinateNumeratorMagnitude,
    SignedExactCoordinateNumerator;
import geo.internal.fixed_uint :
    UIntFixed,
    addUnsigned,
    compareUnsigned,
    multiplyUnsigned,
    subtractUnsigned;
import geo.internal.intersection_exact :
    ExactProperIntersection,
    PreparedExactSegment,
    prepareExactSegment,
    properIntersectionExactKnownCrossingPreparedFirst;
import geo.internal.orientation_dyadic :
    orientationDeterminantDyadicDecoded;
import geo.intersection :
    SegmentContactKind,
    segmentContactKind;
import geo.point : Point2;
import geo.segment : Segment2;

import std.algorithm.sorting : sort;
import std.conv : to;
import std.datetime.stopwatch : StopWatch;
import std.exception : enforce;
import std.stdio : writefln;

__gshared ulong benchmarkSink;

private struct LimbSpan
{
    size_t first;
    size_t end;

    @property size_t width() const
        pure nothrow @safe @nogc
    {
        return first < end ? end - first : 0;
    }
}

private struct QuerySpans
{
    LimbSpan aX;
    LimbSpan aY;
    LimbSpan bX;
    LimbSpan bY;
}

private struct DeterminantPair
{
    SignedDyadicProduct dA;
    SignedDyadicProduct dB;
}

private struct Fixture(T)
{
    string name;
    Segment2!T query;
    Segment2!T edge;
    PreparedExactSegment preparedQuery;
    QuerySpans querySpans;
    DeterminantPair determinants;
    ExactProperIntersection expected;
    LimbSpan weightA;
    LimbSpan weightB;
}

private LimbSpan activeSpan(size_t Limbs)(
    ref const UIntFixed!Limbs value
)
    pure nothrow @safe @nogc
{
    size_t first = Limbs;

    foreach (i; 0 .. Limbs)
    {
        if (value.limb[i] != 0)
        {
            first = i;
            break;
        }
    }

    if (first == Limbs)
        return LimbSpan(Limbs, 0);

    size_t end = Limbs;

    while (end != 0)
    {
        if (value.limb[end - 1] != 0)
            break;

        --end;
    }

    assert(first < end);

    return LimbSpan(first, end);
}

private QuerySpans spansForQuery(
    ref const PreparedExactSegment query
)
    pure nothrow @safe @nogc
{
    return
        QuerySpans(
            activeSpan(query.aX.magnitude),
            activeSpan(query.aY.magnitude),
            activeSpan(query.bX.magnitude),
            activeSpan(query.bY.magnitude)
        );
}

private UIntFixed!(LhsLimbs + RhsLimbs)
multiplyUnsignedSpanned(
    size_t LhsLimbs,
    size_t RhsLimbs
)(
    ref const UIntFixed!LhsLimbs lhs,
    LimbSpan lhsSpan,
    ref const UIntFixed!RhsLimbs rhs,
    LimbSpan rhsSpan
)
    pure nothrow @safe @nogc
{
    UIntFixed!(LhsLimbs + RhsLimbs) result;

    if (
        lhsSpan.width == 0 ||
        rhsSpan.width == 0
    )
    {
        return result;
    }

    assert(lhsSpan.first < lhsSpan.end);
    assert(lhsSpan.end <= LhsLimbs);
    assert(rhsSpan.first < rhsSpan.end);
    assert(rhsSpan.end <= RhsLimbs);

    foreach (i; lhsSpan.first .. lhsSpan.end)
    {
        const uint lhsWord =
            lhs.limb[i];

        if (lhsWord == 0)
            continue;

        ulong carry = 0;

        foreach (j; rhsSpan.first .. rhsSpan.end)
        {
            const size_t index =
                i + j;

            const ulong accumulated =
                cast(ulong) lhsWord *
                    cast(ulong) rhs.limb[j]
                + cast(ulong) result.limb[index]
                + carry;

            result.limb[index] =
                cast(uint) accumulated;

            carry =
                accumulated >> 32;
        }

        const size_t carryIndex =
            i + rhsSpan.end;

        assert(
            carryIndex <
            LhsLimbs + RhsLimbs
        );

        assert(result.limb[carryIndex] == 0);

        result.limb[carryIndex] =
            cast(uint) carry;
    }

    return result;
}

private SignedExactCoordinateNumerator combineProducts(
    int signA,
    ref const ExactCoordinateNumeratorMagnitude magnitudeA,
    int signB,
    ref const ExactCoordinateNumeratorMagnitude magnitudeB,
    bool useProductZeroScan
)
    pure nothrow @safe @nogc
{
    SignedExactCoordinateNumerator result;

    const bool zeroA =
        signA == 0 ||
        (
            useProductZeroScan &&
            magnitudeA.isZero
        );

    const bool zeroB =
        signB == 0 ||
        (
            useProductZeroScan &&
            magnitudeB.isZero
        );

    if (zeroA)
    {
        if (zeroB)
            return result;

        result.sign = signB;
        result.magnitude = magnitudeB;
        return result;
    }

    if (zeroB)
    {
        result.sign = signA;
        result.magnitude = magnitudeA;
        return result;
    }

    if (signA == signB)
    {
        result.sign = signA;

        result.magnitude =
            addUnsigned(
                magnitudeA,
                magnitudeB
            );

        return result;
    }

    const int comparison =
        compareUnsigned(
            magnitudeA,
            magnitudeB
        );

    if (comparison == 0)
        return result;

    if (comparison > 0)
    {
        result.sign = signA;

        result.magnitude =
            subtractUnsigned(
                magnitudeA,
                magnitudeB
            );
    }
    else
    {
        result.sign = signB;

        result.magnitude =
            subtractUnsigned(
                magnitudeB,
                magnitudeA
            );
    }

    return result;
}

private SignedExactCoordinateNumerator weightedCurrent(
    ref const DyadicProductMagnitude weightA,
    ref const SignedDyadicCoordinate a,
    ref const DyadicProductMagnitude weightB,
    ref const SignedDyadicCoordinate b
)
    pure nothrow @safe @nogc
{
    const auto magnitudeA =
        multiplyUnsigned(
            weightA,
            a.magnitude
        );

    const auto magnitudeB =
        multiplyUnsigned(
            weightB,
            b.magnitude
        );

    return
        combineProducts(
            a.sign,
            magnitudeA,
            b.sign,
            magnitudeB,
            true
        );
}

private SignedExactCoordinateNumerator weightedWeightSpanned(
    ref const DyadicProductMagnitude weightA,
    LimbSpan weightASpan,
    ref const SignedDyadicCoordinate a,
    ref const DyadicProductMagnitude weightB,
    LimbSpan weightBSpan,
    ref const SignedDyadicCoordinate b
)
    pure nothrow @safe @nogc
{
    const LimbSpan aSpan =
        activeSpan(a.magnitude);

    const LimbSpan bSpan =
        activeSpan(b.magnitude);

    const auto magnitudeA =
        multiplyUnsignedSpanned(
            weightA,
            weightASpan,
            a.magnitude,
            aSpan
        );

    const auto magnitudeB =
        multiplyUnsignedSpanned(
            weightB,
            weightBSpan,
            b.magnitude,
            bSpan
        );

    return
        combineProducts(
            a.sign,
            magnitudeA,
            b.sign,
            magnitudeB,
            true
        );
}


private SignedExactCoordinateNumerator weightedSpanned(
    ref const DyadicProductMagnitude weightA,
    LimbSpan weightASpan,
    ref const SignedDyadicCoordinate a,
    LimbSpan aSpan,
    ref const DyadicProductMagnitude weightB,
    LimbSpan weightBSpan,
    ref const SignedDyadicCoordinate b,
    LimbSpan bSpan,
    bool useProductZeroScan
)
    pure nothrow @safe @nogc
{
    const auto magnitudeA =
        multiplyUnsignedSpanned(
            weightA,
            weightASpan,
            a.magnitude,
            aSpan
        );

    const auto magnitudeB =
        multiplyUnsignedSpanned(
            weightB,
            weightBSpan,
            b.magnitude,
            bSpan
        );

    return
        combineProducts(
            a.sign,
            magnitudeA,
            b.sign,
            magnitudeB,
            useProductZeroScan
        );
}

private void buildCurrent(
    ref const PreparedExactSegment first,
    ref const DeterminantPair pair,
    ref ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    const DyadicProductMagnitude weightA =
        pair.dB.magnitude;

    const DyadicProductMagnitude weightB =
        pair.dA.magnitude;

    result.denominator =
        addUnsigned(
            weightA,
            weightB
        );

    result.xNumerator =
        weightedCurrent(
            weightA,
            first.aX,
            weightB,
            first.bX
        );

    result.yNumerator =
        weightedCurrent(
            weightA,
            first.aY,
            weightB,
            first.bY
        );
}

private void buildWeightOnly(
    ref const PreparedExactSegment first,
    ref const DeterminantPair pair,
    ref ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    const DyadicProductMagnitude weightA =
        pair.dB.magnitude;

    const DyadicProductMagnitude weightB =
        pair.dA.magnitude;

    const LimbSpan weightASpan =
        activeSpan(weightA);

    const LimbSpan weightBSpan =
        activeSpan(weightB);

    result.denominator =
        addUnsigned(
            weightA,
            weightB
        );

    result.xNumerator =
        weightedWeightSpanned(
            weightA,
            weightASpan,
            first.aX,
            weightB,
            weightBSpan,
            first.bX
        );

    result.yNumerator =
        weightedWeightSpanned(
            weightA,
            weightASpan,
            first.aY,
            weightB,
            weightBSpan,
            first.bY
        );
}


private void buildSpanOnly(
    ref const PreparedExactSegment first,
    ref const QuerySpans querySpans,
    ref const DeterminantPair pair,
    ref ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    const DyadicProductMagnitude weightA =
        pair.dB.magnitude;

    const DyadicProductMagnitude weightB =
        pair.dA.magnitude;

    const LimbSpan weightASpan =
        activeSpan(weightA);

    const LimbSpan weightBSpan =
        activeSpan(weightB);

    result.denominator =
        addUnsigned(
            weightA,
            weightB
        );

    result.xNumerator =
        weightedSpanned(
            weightA,
            weightASpan,
            first.aX,
            querySpans.aX,
            weightB,
            weightBSpan,
            first.bX,
            querySpans.bX,
            true
        );

    result.yNumerator =
        weightedSpanned(
            weightA,
            weightASpan,
            first.aY,
            querySpans.aY,
            weightB,
            weightBSpan,
            first.bY,
            querySpans.bY,
            true
        );
}

private void buildSpanNonZero(
    ref const PreparedExactSegment first,
    ref const QuerySpans querySpans,
    ref const DeterminantPair pair,
    ref ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    const DyadicProductMagnitude weightA =
        pair.dB.magnitude;

    const DyadicProductMagnitude weightB =
        pair.dA.magnitude;

    const LimbSpan weightASpan =
        activeSpan(weightA);

    const LimbSpan weightBSpan =
        activeSpan(weightB);

    result.denominator =
        addUnsigned(
            weightA,
            weightB
        );

    result.xNumerator =
        weightedSpanned(
            weightA,
            weightASpan,
            first.aX,
            querySpans.aX,
            weightB,
            weightBSpan,
            first.bX,
            querySpans.bX,
            false
        );

    result.yNumerator =
        weightedSpanned(
            weightA,
            weightASpan,
            first.aY,
            querySpans.aY,
            weightB,
            weightBSpan,
            first.bY,
            querySpans.bY,
            false
        );
}

private DeterminantPair determinantPair(
    ref const PreparedExactSegment first,
    Segment2!double second
)
    pure nothrow @safe @nogc
{
    const auto preparedSecond =
        prepareExactSegment(
            second
        );

    DeterminantPair result;

    result.dA =
        orientationDeterminantDyadicDecoded(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.aX,
            first.aY
        );

    result.dB =
        orientationDeterminantDyadicDecoded(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.bX,
            first.bY
        );

    return result;
}

private DeterminantPair determinantPair(T)(
    ref const PreparedExactSegment first,
    Segment2!T second
)
    pure nothrow @safe @nogc
if (!is(T == double))
{
    const auto preparedSecond =
        prepareExactSegment(
            second
        );

    DeterminantPair result;

    result.dA =
        orientationDeterminantDyadicDecoded(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.aX,
            first.aY
        );

    result.dB =
        orientationDeterminantDyadicDecoded(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.bX,
            first.bY
        );

    return result;
}

private bool exactEqual(
    ref const ExactProperIntersection lhs,
    ref const ExactProperIntersection rhs
)
    pure nothrow @safe @nogc
{
    return
        lhs.xNumerator.sign ==
            rhs.xNumerator.sign &&
        lhs.xNumerator.magnitude.limb ==
            rhs.xNumerator.magnitude.limb &&
        lhs.yNumerator.sign ==
            rhs.yNumerator.sign &&
        lhs.yNumerator.magnitude.limb ==
            rhs.yNumerator.magnitude.limb &&
        lhs.denominator.limb ==
            rhs.denominator.limb;
}

private Fixture!T makeFixture(T)(
    string name,
    T xNegativeMagnitude,
    T xPositive,
    T edgeNegativeMagnitude,
    T edgePositive
)
{
    alias P = Point2!T;
    alias S = Segment2!T;

    const T queryY =
        cast(T) 1;

    Fixture!T result;
    result.name = name;

    result.query =
        S(
            P(
                -xNegativeMagnitude,
                queryY
            ),
            P(
                xPositive,
                queryY
            )
        );

    result.edge =
        S(
            P(
                cast(T) 0,
                -edgeNegativeMagnitude
            ),
            P(
                cast(T) 0,
                edgePositive
            )
        );

    enforce(
        segmentContactKind(
            result.query,
            result.edge
        ) ==
            SegmentContactKind.properCrossing,
        "fixture is not a strict proper crossing: " ~
            name
    );

    result.preparedQuery =
        prepareExactSegment(
            result.query
        );

    result.querySpans =
        spansForQuery(
            result.preparedQuery
        );

    result.determinants =
        determinantPair(
            result.preparedQuery,
            result.edge
        );

    enforce(
        result.determinants.dA.sign != 0 &&
        result.determinants.dB.sign != 0 &&
        result.determinants.dA.sign !=
            result.determinants.dB.sign,
        "unexpected determinant signs: " ~
            name
    );

    result.weightA =
        activeSpan(
            result.determinants.dB.magnitude
        );

    result.weightB =
        activeSpan(
            result.determinants.dA.magnitude
        );

    properIntersectionExactKnownCrossingPreparedFirst(
        result.preparedQuery,
        result.edge,
        result.expected
    );

    ExactProperIntersection current;
    ExactProperIntersection weightOnly;
    ExactProperIntersection spanOnly;
    ExactProperIntersection spanNonZero;

    buildCurrent(
        result.preparedQuery,
        result.determinants,
        current
    );

    buildWeightOnly(
        result.preparedQuery,
        result.determinants,
        weightOnly
    );

    buildSpanOnly(
        result.preparedQuery,
        result.querySpans,
        result.determinants,
        spanOnly
    );

    buildSpanNonZero(
        result.preparedQuery,
        result.querySpans,
        result.determinants,
        spanNonZero
    );

    enforce(
        exactEqual(
            result.expected,
            current
        ),
        "current mismatch: " ~ name
    );

    enforce(
        exactEqual(
            result.expected,
            weightOnly
        ),
        "weight-only mismatch: " ~ name
    );

    enforce(
        exactEqual(
            result.expected,
            spanOnly
        ),
        "span-only mismatch: " ~ name
    );

    enforce(
        exactEqual(
            result.expected,
            spanNonZero
        ),
        "span+nonzero mismatch: " ~ name
    );

    return result;
}

private Fixture!T[] fixtures(T)()
{
    Fixture!T[] result;

    static if (is(T == int))
    {
        result ~=
            makeFixture!T(
                "compact",
                16,
                16,
                8,
                8
            );

        result ~=
            makeFixture!T(
                "wide",
                cast(T)(1 << 30),
                1,
                1,
                cast(T)(1 << 30)
            );
    }
    else static if (is(T == long))
    {
        result ~=
            makeFixture!T(
                "compact",
                16,
                16,
                8,
                8
            );

        result ~=
            makeFixture!T(
                "wide",
                cast(T)(1L << 60),
                1,
                1,
                cast(T)(1L << 60)
            );
    }
    else static if (is(T == float))
    {
        result ~=
            makeFixture!T(
                "compact",
                cast(T) 16.0,
                cast(T) 16.0,
                cast(T) 8.0,
                cast(T) 8.0
            );

        result ~=
            makeFixture!T(
                "medium",
                cast(T) 0x1p+60,
                cast(T) 0x1p-40,
                cast(T) 0x1p-40,
                cast(T) 0x1p+60
            );

        result ~=
            makeFixture!T(
                "wide",
                cast(T) 0x1p+120,
                cast(T) 0x1p-120,
                cast(T) 0x1p-120,
                cast(T) 0x1p+120
            );
    }
    else static if (is(T == double))
    {
        result ~=
            makeFixture!T(
                "compact",
                16.0,
                16.0,
                8.0,
                8.0
            );

        result ~=
            makeFixture!T(
                "medium",
                0x1p+256,
                0x1p-64,
                0x1p-64,
                0x1p+256
            );

        result ~=
            makeFixture!T(
                "wide",
                0x1p+600,
                0x1p-500,
                0x1p-500,
                0x1p+600
            );

        result ~=
            makeFixture!T(
                "extreme",
                0x1p+900,
                0x1p-900,
                0x1p-900,
                0x1p+900
            );
    }

    return result;
}

private ulong hashExact(
    ref const ExactProperIntersection exact
)
    pure nothrow @safe @nogc
{
    ulong result =
        cast(ulong)(exact.xNumerator.sign + 2);

    foreach (limb; exact.xNumerator.magnitude.limb)
        result = result * 1_000_003UL + limb;

    result =
        result * 1_000_003UL +
        cast(ulong)(exact.yNumerator.sign + 2);

    foreach (limb; exact.yNumerator.magnitude.limb)
        result = result * 1_000_003UL + limb;

    foreach (limb; exact.denominator.limb)
        result = result * 1_000_003UL + limb;

    return result;
}

pragma(inline, false)
private ulong carrierReadReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t probe =
        volatileLoad(&iteration);

    return
        hashExact(
            fixture.expected
        ) +
        probe;
}

pragma(inline, false)
private ulong currentReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    ExactProperIntersection exact;

    buildCurrent(
        fixture.preparedQuery,
        fixture.determinants,
        exact
    );

    return
        hashExact(exact) +
        volatileLoad(&iteration);
}

pragma(inline, false)
private ulong weightOnlyReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    ExactProperIntersection exact;

    buildWeightOnly(
        fixture.preparedQuery,
        fixture.determinants,
        exact
    );

    return
        hashExact(exact) +
        volatileLoad(&iteration);
}


pragma(inline, false)
private ulong spanOnlyReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    ExactProperIntersection exact;

    buildSpanOnly(
        fixture.preparedQuery,
        fixture.querySpans,
        fixture.determinants,
        exact
    );

    return
        hashExact(exact) +
        volatileLoad(&iteration);
}

pragma(inline, false)
private ulong spanNonZeroReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    ExactProperIntersection exact;

    buildSpanNonZero(
        fixture.preparedQuery,
        fixture.querySpans,
        fixture.determinants,
        exact
    );

    return
        hashExact(exact) +
        volatileLoad(&iteration);
}

private double measure(alias operation, T)(
    ref Fixture!T fixture,
    string operationName,
    size_t rounds,
    long targetMilliseconds
)
{
    size_t iterations = 1;
    ulong sink = 1;

    while (true)
    {
        StopWatch calibration;
        calibration.start();

        foreach (i; 0 .. iterations)
        {
            sink =
                sink * 1_000_003UL +
                operation(
                    fixture,
                    i
                );
        }

        calibration.stop();

        if (
            calibration.peek.total!"msecs" >=
                targetMilliseconds ||
            iterations >= 1_048_576
        )
        {
            break;
        }

        iterations *= 2;
    }

    const size_t warmup =
        iterations / 10 + 1;

    foreach (i; 0 .. warmup)
    {
        sink =
            sink * 1_000_003UL +
            operation(
                fixture,
                i
            );
    }

    double[] timings =
        new double[rounds];

    foreach (round; 0 .. rounds)
    {
        GC.collect();

        StopWatch watch;
        watch.start();

        foreach (i; 0 .. iterations)
        {
            sink =
                sink * 1_000_003UL +
                operation(
                    fixture,
                    i
                );
        }

        watch.stop();

        timings[round] =
            cast(double)
                watch.peek.total!"nsecs" /
            iterations;

        writefln(
            "sample,%s,%s,%s,%.3f,%s,%s",
            T.stringof,
            fixture.name,
            operationName,
            timings[round],
            iterations,
            round
        );
    }

    timings.sort;

    const double median =
        timings[timings.length / 2];

    writefln(
        "summary,%s,%s,%s,%.3f",
        T.stringof,
        fixture.name,
        operationName,
        median
    );

    benchmarkSink = sink;

    return median;
}

private void emitSpans(T)(
    ref Fixture!T fixture
)
{
    size_t queryMin = size_t.max;
    size_t queryMax;
    size_t queryTotal;
    size_t queryCount;

    foreach (
        span;
        [
            fixture.querySpans.aX,
            fixture.querySpans.aY,
            fixture.querySpans.bX,
            fixture.querySpans.bY,
        ]
    )
    {
        queryMin =
            span.width < queryMin
                ? span.width
                : queryMin;

        queryMax =
            span.width > queryMax
                ? span.width
                : queryMax;

        queryTotal += span.width;
        ++queryCount;
    }

    const size_t weightMin =
        fixture.weightA.width <
            fixture.weightB.width
            ? fixture.weightA.width
            : fixture.weightB.width;

    const size_t weightMax =
        fixture.weightA.width >
            fixture.weightB.width
            ? fixture.weightA.width
            : fixture.weightB.width;

    const double weightAverage =
        cast(double)(
            fixture.weightA.width +
            fixture.weightB.width
        ) / 2.0;

    writefln(
        "span,%s,%s,query,%s,%s,%.6f",
        T.stringof,
        fixture.name,
        queryMin,
        queryMax,
        cast(double) queryTotal /
            queryCount
    );

    writefln(
        "span,%s,%s,weight,%s,%s,%.6f",
        T.stringof,
        fixture.name,
        weightMin,
        weightMax,
        weightAverage
    );
}

private void runType(T)(
    size_t rounds,
    long targetMilliseconds
)
{
    auto allFixtures =
        fixtures!T();

    foreach (ref fixture; allFixtures)
    {
        emitSpans(fixture);

        const double carrierRead =
            measure!carrierReadReplay(
                fixture,
                "carrier-read",
                rounds,
                targetMilliseconds
            );

        const double current =
            measure!currentReplay(
                fixture,
                "current",
                rounds,
                targetMilliseconds
            );

        const double weightOnly =
            measure!weightOnlyReplay(
                fixture,
                "weight-only",
                rounds,
                targetMilliseconds
            );

        const double spanOnly =
            measure!spanOnlyReplay(
                fixture,
                "span-only",
                rounds,
                targetMilliseconds
            );

        const double spanNonZero =
            measure!spanNonZeroReplay(
                fixture,
                "span-nonzero",
                rounds,
                targetMilliseconds
            );

        const double currentNet =
            current - carrierRead;

        const double weightOnlyNet =
            weightOnly - carrierRead;

        const double spanOnlyNet =
            spanOnly - carrierRead;

        const double spanNonZeroNet =
            spanNonZero - carrierRead;

        writefln(
            "derived,%s,%s,%.3f,%.3f,%.3f,%.3f,%.6f,%.6f,%.6f",
            T.stringof,
            fixture.name,
            currentNet,
            weightOnlyNet,
            spanOnlyNet,
            spanNonZeroNet,
            currentNet / weightOnlyNet,
            currentNet / spanOnlyNet,
            currentNet / spanNonZeroNet
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: weight_span_only_probe <rounds> <target-ms>"
    );

    const size_t rounds =
        args[1].to!size_t;

    const long targetMilliseconds =
        args[2].to!long;

    runType!int(rounds, targetMilliseconds);
    runType!long(rounds, targetMilliseconds);
    runType!float(rounds, targetMilliseconds);
    runType!double(rounds, targetMilliseconds);

    writefln("sink,%s", benchmarkSink);
}
