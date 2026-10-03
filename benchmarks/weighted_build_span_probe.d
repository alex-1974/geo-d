module geo.internal.weighted_build_span_probe;

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
        return first < end
            ? end - first
            : 0;
    }
}

private struct PreparedQuerySpans
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
    Segment2!T[2] queries;
    Segment2!T[] properEdges;
    PreparedExactSegment[2] preparedQueries;
    PreparedQuerySpans[2] querySpans;
    DeterminantPair[][2] determinants;
    ExactProperIntersection[][2] expected;
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

private PreparedQuerySpans querySpans(
    ref const PreparedExactSegment query
)
    pure nothrow @safe @nogc
{
    return
        PreparedQuerySpans(
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

private SignedExactCoordinateNumerator combineWeightedProducts(
    int signA,
    ref const ExactCoordinateNumeratorMagnitude magnitudeA,
    int signB,
    ref const ExactCoordinateNumeratorMagnitude magnitudeB
)
    pure nothrow @safe @nogc
{
    SignedExactCoordinateNumerator result;

    if (signA == 0)
    {
        if (signB == 0)
            return result;

        result.sign = signB;
        result.magnitude = magnitudeB;
        return result;
    }

    if (signB == 0)
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
    SignedExactCoordinateNumerator result;

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

    const bool zeroA =
        a.sign == 0 ||
        magnitudeA.isZero;

    const bool zeroB =
        b.sign == 0 ||
        magnitudeB.isZero;

    if (zeroA)
    {
        if (zeroB)
            return result;

        result.sign = b.sign;
        result.magnitude = magnitudeB;
        return result;
    }

    if (zeroB)
    {
        result.sign = a.sign;
        result.magnitude = magnitudeA;
        return result;
    }

    return
        combineWeightedProducts(
            a.sign,
            magnitudeA,
            b.sign,
            magnitudeB
        );
}

private SignedExactCoordinateNumerator weightedNonZeroInvariant(
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
        combineWeightedProducts(
            a.sign,
            magnitudeA,
            b.sign,
            magnitudeB
        );
}

private SignedExactCoordinateNumerator weightedQuerySpan(
    ref const DyadicProductMagnitude weightA,
    ref const SignedDyadicCoordinate a,
    LimbSpan aSpan,
    ref const DyadicProductMagnitude weightB,
    ref const SignedDyadicCoordinate b,
    LimbSpan bSpan
)
    pure nothrow @safe @nogc
{
    const LimbSpan weightASpan =
        activeSpan(weightA);

    const LimbSpan weightBSpan =
        activeSpan(weightB);

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
        combineWeightedProducts(
            a.sign,
            magnitudeA,
            b.sign,
            magnitudeB
        );
}

private SignedExactCoordinateNumerator weightedWeightSpan(
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
        combineWeightedProducts(
            a.sign,
            magnitudeA,
            b.sign,
            magnitudeB
        );
}

private SignedExactCoordinateNumerator weightedAllSpan(
    ref const DyadicProductMagnitude weightA,
    LimbSpan weightASpan,
    ref const SignedDyadicCoordinate a,
    LimbSpan aSpan,
    ref const DyadicProductMagnitude weightB,
    LimbSpan weightBSpan,
    ref const SignedDyadicCoordinate b,
    LimbSpan bSpan
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
        combineWeightedProducts(
            a.sign,
            magnitudeA,
            b.sign,
            magnitudeB
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

private void buildNonZeroInvariant(
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
        weightedNonZeroInvariant(
            weightA,
            first.aX,
            weightB,
            first.bX
        );

    result.yNumerator =
        weightedNonZeroInvariant(
            weightA,
            first.aY,
            weightB,
            first.bY
        );
}

private void buildQuerySpan(
    ref const PreparedExactSegment first,
    ref const PreparedQuerySpans spans,
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
        weightedQuerySpan(
            weightA,
            first.aX,
            spans.aX,
            weightB,
            first.bX,
            spans.bX
        );

    result.yNumerator =
        weightedQuerySpan(
            weightA,
            first.aY,
            spans.aY,
            weightB,
            first.bY,
            spans.bY
        );
}

private void buildWeightSpan(
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
        weightedWeightSpan(
            weightA,
            weightASpan,
            first.aX,
            weightB,
            weightBSpan,
            first.bX
        );

    result.yNumerator =
        weightedWeightSpan(
            weightA,
            weightASpan,
            first.aY,
            weightB,
            weightBSpan,
            first.bY
        );
}

private void buildAllSpan(
    ref const PreparedExactSegment first,
    ref const PreparedQuerySpans spans,
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
        weightedAllSpan(
            weightA,
            weightASpan,
            first.aX,
            spans.aX,
            weightB,
            weightBSpan,
            first.bX,
            spans.bX
        );

    result.yNumerator =
        weightedAllSpan(
            weightA,
            weightASpan,
            first.aY,
            spans.aY,
            weightB,
            weightBSpan,
            first.bY,
            spans.bY
        );
}

private DeterminantPair determinantsFromPrepared(
    ref const PreparedExactSegment first,
    ref const PreparedExactSegment second
)
    pure nothrow @safe @nogc
{
    DeterminantPair result;

    result.dA =
        orientationDeterminantDyadicDecoded(
            second.aX,
            second.aY,
            second.bX,
            second.bY,
            first.aX,
            first.aY
        );

    result.dB =
        orientationDeterminantDyadicDecoded(
            second.aX,
            second.aY,
            second.bX,
            second.bY,
            first.bX,
            first.bY
        );

    assert(result.dA.sign != 0);
    assert(result.dB.sign != 0);
    assert(result.dA.sign != result.dB.sign);

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

private Fixture!T denseFixture(T)(size_t teeth)
{
    alias P = Point2!T;
    alias S = Segment2!T;

    const int right =
        cast(int)(4 * teeth - 2);

    P[] ring = [
        P(0, 0),
        P(cast(T) right, 0),
        P(cast(T) right, 4),
    ];

    foreach_reverse (j; 1 .. teeth)
    {
        ring ~= [
            P(cast(T)(4 * j), 4),
            P(cast(T)(4 * j), 1),
            P(cast(T)(4 * j - 2), 1),
            P(cast(T)(4 * j - 2), 4),
        ];
    }

    ring ~= P(0, 4);

    Fixture!T result;
    result.name = "dense-" ~ teeth.to!string;

    const S query =
        S(
            P(-1, 2),
            P(cast(T)(right + 1), 2)
        );

    result.queries = [
        query,
        S(query.b, query.a),
    ];

    foreach (i; 0 .. ring.length)
    {
        const S edge =
            S(
                ring[i],
                ring[(i + 1) % ring.length]
            );

        if (
            segmentContactKind(
                query,
                edge
            ) == SegmentContactKind.properCrossing
        )
        {
            result.properEdges ~= edge;
        }
    }

    enforce(
        result.properEdges.length == 2 * teeth,
        "unexpected proper-crossing count"
    );

    foreach (direction; 0 .. 2)
    {
        const currentQuery =
            result.queries[direction];

        result.preparedQueries[direction] =
            prepareExactSegment(
                currentQuery
            );

        result.querySpans[direction] =
            querySpans(
                result.preparedQueries[direction]
            );

        result.determinants[direction] =
            new DeterminantPair[
                result.properEdges.length
            ];

        result.expected[direction] =
            new ExactProperIntersection[
                result.properEdges.length
            ];

        foreach (i, edge; result.properEdges)
        {
            const auto preparedEdge =
                prepareExactSegment(
                    edge
                );

            result.determinants[direction][i] =
                determinantsFromPrepared(
                    result.preparedQueries[direction],
                    preparedEdge
                );

            ExactProperIntersection production;

            properIntersectionExactKnownCrossingPreparedFirst(
                result.preparedQueries[direction],
                edge,
                production
            );

            ExactProperIntersection current;
            ExactProperIntersection nonZero;
            ExactProperIntersection queryBounded;
            ExactProperIntersection weightBounded;
            ExactProperIntersection allBounded;

            buildCurrent(
                result.preparedQueries[direction],
                result.determinants[direction][i],
                current
            );

            buildNonZeroInvariant(
                result.preparedQueries[direction],
                result.determinants[direction][i],
                nonZero
            );

            buildQuerySpan(
                result.preparedQueries[direction],
                result.querySpans[direction],
                result.determinants[direction][i],
                queryBounded
            );

            buildWeightSpan(
                result.preparedQueries[direction],
                result.determinants[direction][i],
                weightBounded
            );

            buildAllSpan(
                result.preparedQueries[direction],
                result.querySpans[direction],
                result.determinants[direction][i],
                allBounded
            );

            enforce(exactEqual(production, current), "current mismatch");
            enforce(exactEqual(production, nonZero), "nonzero mismatch");
            enforce(exactEqual(production, queryBounded), "query-span mismatch");
            enforce(exactEqual(production, weightBounded), "weight-span mismatch");
            enforce(exactEqual(production, allBounded), "all-span mismatch");

            result.expected[direction][i] =
                production;
        }
    }

    return result;
}

private void emitSpanSummary(T)(
    ref Fixture!T fixture
)
{
    size_t queryFirstMin = size_t.max;
    size_t queryFirstMax;
    size_t queryEndMin = size_t.max;
    size_t queryEndMax;
    size_t queryWidthTotal;
    size_t queryCount;

    foreach (direction; 0 .. 2)
    {
        const auto spans =
            fixture.querySpans[direction];

        foreach (
            span;
            [
                spans.aX,
                spans.aY,
                spans.bX,
                spans.bY,
            ]
        )
        {
            queryFirstMin =
                span.first < queryFirstMin
                    ? span.first
                    : queryFirstMin;

            queryFirstMax =
                span.first > queryFirstMax
                    ? span.first
                    : queryFirstMax;

            queryEndMin =
                span.end < queryEndMin
                    ? span.end
                    : queryEndMin;

            queryEndMax =
                span.end > queryEndMax
                    ? span.end
                    : queryEndMax;

            queryWidthTotal += span.width;
            ++queryCount;
        }
    }

    size_t weightFirstMin = size_t.max;
    size_t weightFirstMax;
    size_t weightEndMin = size_t.max;
    size_t weightEndMax;
    size_t weightWidthTotal;
    size_t weightCount;

    foreach (direction; 0 .. 2)
    {
        foreach (ref pair; fixture.determinants[direction])
        {
            foreach (
                ref weight;
                [
                    pair.dA.magnitude,
                    pair.dB.magnitude,
                ]
            )
            {
                const auto span =
                    activeSpan(weight);

                weightFirstMin =
                    span.first < weightFirstMin
                        ? span.first
                        : weightFirstMin;

                weightFirstMax =
                    span.first > weightFirstMax
                        ? span.first
                        : weightFirstMax;

                weightEndMin =
                    span.end < weightEndMin
                        ? span.end
                        : weightEndMin;

                weightEndMax =
                    span.end > weightEndMax
                        ? span.end
                        : weightEndMax;

                weightWidthTotal += span.width;
                ++weightCount;
            }
        }
    }

    writefln(
        "span,%s,%s,query,%s,%s,%s,%s,%.6f",
        T.stringof,
        fixture.name,
        queryFirstMin,
        queryFirstMax,
        queryEndMin,
        queryEndMax,
        cast(double) queryWidthTotal / queryCount
    );

    writefln(
        "span,%s,%s,weight,%s,%s,%s,%s,%.6f",
        T.stringof,
        fixture.name,
        weightFirstMin,
        weightFirstMax,
        weightEndMin,
        weightEndMax,
        cast(double) weightWidthTotal / weightCount
    );
}

pragma(inline, false)
private ulong carrierReadReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (ref exact; fixture.expected[direction])
    {
        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong currentReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (ref pair; fixture.determinants[direction])
    {
        ExactProperIntersection exact;

        buildCurrent(
            fixture.preparedQueries[direction],
            pair,
            exact
        );

        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong nonZeroReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (ref pair; fixture.determinants[direction])
    {
        ExactProperIntersection exact;

        buildNonZeroInvariant(
            fixture.preparedQueries[direction],
            pair,
            exact
        );

        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong querySpanReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (ref pair; fixture.determinants[direction])
    {
        ExactProperIntersection exact;

        buildQuerySpan(
            fixture.preparedQueries[direction],
            fixture.querySpans[direction],
            pair,
            exact
        );

        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong weightSpanReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (ref pair; fixture.determinants[direction])
    {
        ExactProperIntersection exact;

        buildWeightSpan(
            fixture.preparedQueries[direction],
            pair,
            exact
        );

        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong allSpanReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (ref pair; fixture.determinants[direction])
    {
        ExactProperIntersection exact;

        buildAllSpan(
            fixture.preparedQueries[direction],
            fixture.querySpans[direction],
            pair,
            exact
        );

        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
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
            iterations >= 65_536
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
        "summary,%s,%s,%s,%.3f,%s",
        T.stringof,
        fixture.name,
        operationName,
        median,
        fixture.properEdges.length
    );

    benchmarkSink = sink;

    return median;
}

private void runType(T)(
    size_t rounds,
    long targetMilliseconds
)
{
    foreach (teeth; [4, 16, 64])
    {
        auto fixture =
            denseFixture!T(teeth);

        emitSpanSummary(fixture);

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

        const double nonZero =
            measure!nonZeroReplay(
                fixture,
                "nonzero-invariant",
                rounds,
                targetMilliseconds
            );

        const double querySpan =
            measure!querySpanReplay(
                fixture,
                "query-span",
                rounds,
                targetMilliseconds
            );

        const double weightSpan =
            measure!weightSpanReplay(
                fixture,
                "weight-span",
                rounds,
                targetMilliseconds
            );

        const double allSpan =
            measure!allSpanReplay(
                fixture,
                "all-span",
                rounds,
                targetMilliseconds
            );

        const double currentNet =
            current - carrierRead;

        const double nonZeroNet =
            nonZero - carrierRead;

        const double querySpanNet =
            querySpan - carrierRead;

        const double weightSpanNet =
            weightSpan - carrierRead;

        const double allSpanNet =
            allSpan - carrierRead;

        writefln(
            "derived,%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.6f,%.6f,%.6f,%.6f",
            T.stringof,
            fixture.name,
            currentNet,
            nonZeroNet,
            querySpanNet,
            weightSpanNet,
            allSpanNet,
            currentNet / nonZeroNet,
            nonZeroNet / querySpanNet,
            nonZeroNet / weightSpanNet,
            nonZeroNet / allSpanNet
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: weighted_build_span_probe <rounds> <target-ms>"
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
