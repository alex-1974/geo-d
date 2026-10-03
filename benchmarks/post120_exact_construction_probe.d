module geo.internal.post120_exact_construction_probe;

import core.memory : GC;
import core.volatile : volatileLoad;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    SignedDyadicCoordinate,
    SignedDyadicProduct;
import geo.internal.exact_coordinate :
    SignedExactCoordinateNumerator;
import geo.internal.fixed_uint :
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
    PreparedExactSegment[][2] preparedEdges;
    DeterminantPair[][2] determinants;
    ExactProperIntersection[][2] expected;
}

private SignedExactCoordinateNumerator weightedCoordinateProbe(
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

    if (a.sign == b.sign)
    {
        result.sign = a.sign;

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
        result.sign = a.sign;

        result.magnitude =
            subtractUnsigned(
                magnitudeA,
                magnitudeB
            );
    }
    else
    {
        result.sign = b.sign;

        result.magnitude =
            subtractUnsigned(
                magnitudeB,
                magnitudeA
            );
    }

    return result;
}

private void buildFromPrepared(
    ref const PreparedExactSegment first,
    ref const SignedDyadicProduct dA,
    ref const SignedDyadicProduct dB,
    ref ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    assert(dA.sign != 0);
    assert(dB.sign != 0);
    assert(dA.sign != dB.sign);

    const DyadicProductMagnitude weightA =
        dB.magnitude;

    const DyadicProductMagnitude weightB =
        dA.magnitude;

    result.denominator =
        addUnsigned(
            weightA,
            weightB
        );

    assert(!result.denominator.isZero);

    result.xNumerator =
        weightedCoordinateProbe(
            weightA,
            first.aX,
            weightB,
            first.bX
        );

    result.yNumerator =
        weightedCoordinateProbe(
            weightA,
            first.aY,
            weightB,
            first.bY
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

private ulong hashCoordinate(
    ref const SignedDyadicCoordinate value
)
    pure nothrow @safe @nogc
{
    ulong result =
        cast(ulong)(value.sign + 2);

    foreach (limb; value.magnitude.limb)
        result = result * 1_000_003UL + limb;

    return result;
}

private ulong hashPrepared(
    ref const PreparedExactSegment value
)
    pure nothrow @safe @nogc
{
    ulong result = 1;

    result =
        result * 1_000_003UL +
        hashCoordinate(value.aX);

    result =
        result * 1_000_003UL +
        hashCoordinate(value.aY);

    result =
        result * 1_000_003UL +
        hashCoordinate(value.bX);

    result =
        result * 1_000_003UL +
        hashCoordinate(value.bY);

    return result;
}

private ulong hashProduct(
    ref const SignedDyadicProduct value
)
    pure nothrow @safe @nogc
{
    ulong result =
        cast(ulong)(value.sign + 2);

    foreach (limb; value.magnitude.limb)
        result = result * 1_000_003UL + limb;

    return result;
}

private ulong hashPair(
    ref const DeterminantPair pair
)
    pure nothrow @safe @nogc
{
    return
        hashProduct(pair.dA) *
            1_000_003UL +
        hashProduct(pair.dB);
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

        result.preparedEdges[direction] =
            new PreparedExactSegment[
                result.properEdges.length
            ];

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
            result.preparedEdges[direction][i] =
                prepareExactSegment(
                    edge
                );

            result.determinants[direction][i] =
                determinantsFromPrepared(
                    result.preparedQueries[direction],
                    result.preparedEdges[direction][i]
                );

            ExactProperIntersection production;

            properIntersectionExactKnownCrossingPreparedFirst(
                result.preparedQueries[direction],
                edge,
                production
            );

            ExactProperIntersection reconstructed;

            buildFromPrepared(
                result.preparedQueries[direction],
                result.determinants[direction][i].dA,
                result.determinants[direction][i].dB,
                reconstructed
            );

            enforce(
                exactEqual(
                    production,
                    reconstructed
                ),
                "research decomposition mismatch"
            );

            result.expected[direction][i] =
                production;
        }
    }

    return result;
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
private ulong preparedEdgeReadReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (ref edge; fixture.preparedEdges[direction])
    {
        result =
            result * 1_000_003UL +
            hashPrepared(edge);
    }

    return result;
}

pragma(inline, false)
private ulong edgeDecodeReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (edge; fixture.properEdges)
    {
        const auto prepared =
            prepareExactSegment(
                edge
            );

        result =
            result * 1_000_003UL +
            hashPrepared(prepared);
    }

    return result;
}

pragma(inline, false)
private ulong determinantReadReplay(T)(
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
        result =
            result * 1_000_003UL +
            hashPair(pair);
    }

    return result;
}

pragma(inline, false)
private ulong determinantComputeReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (ref second; fixture.preparedEdges[direction])
    {
        const auto pair =
            determinantsFromPrepared(
                fixture.preparedQueries[direction],
                second
            );

        result =
            result * 1_000_003UL +
            hashPair(pair);
    }

    return result;
}

pragma(inline, false)
private ulong buildReplay(T)(
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

        buildFromPrepared(
            fixture.preparedQueries[direction],
            pair.dA,
            pair.dB,
            exact
        );

        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong fullPreparedBothReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (ref second; fixture.preparedEdges[direction])
    {
        const auto pair =
            determinantsFromPrepared(
                fixture.preparedQueries[direction],
                second
            );

        ExactProperIntersection exact;

        buildFromPrepared(
            fixture.preparedQueries[direction],
            pair.dA,
            pair.dB,
            exact
        );

        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong fullProductionReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    ulong result = 1;

    foreach (edge; fixture.properEdges)
    {
        ExactProperIntersection exact;

        properIntersectionExactKnownCrossingPreparedFirst(
            fixture.preparedQueries[direction],
            edge,
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

        const double carrierRead =
            measure!carrierReadReplay(
                fixture,
                "carrier-read",
                rounds,
                targetMilliseconds
            );

        const double preparedEdgeRead =
            measure!preparedEdgeReadReplay(
                fixture,
                "prepared-edge-read",
                rounds,
                targetMilliseconds
            );

        const double edgeDecode =
            measure!edgeDecodeReplay(
                fixture,
                "edge-decode",
                rounds,
                targetMilliseconds
            );

        const double determinantRead =
            measure!determinantReadReplay(
                fixture,
                "determinant-read",
                rounds,
                targetMilliseconds
            );

        const double determinantCompute =
            measure!determinantComputeReplay(
                fixture,
                "determinant-compute",
                rounds,
                targetMilliseconds
            );

        const double build =
            measure!buildReplay(
                fixture,
                "weighted-build",
                rounds,
                targetMilliseconds
            );

        const double fullPreparedBoth =
            measure!fullPreparedBothReplay(
                fixture,
                "full-prepared-both",
                rounds,
                targetMilliseconds
            );

        const double fullProduction =
            measure!fullProductionReplay(
                fixture,
                "full-prepared-first",
                rounds,
                targetMilliseconds
            );

        const double edgeDecodeNet =
            edgeDecode -
            preparedEdgeRead;

        const double determinantNet =
            determinantCompute -
            determinantRead;

        const double buildNet =
            build -
            carrierRead;

        const double fullPreparedBothNet =
            fullPreparedBoth -
            carrierRead;

        const double fullProductionNet =
            fullProduction -
            carrierRead;

        const double fullDecodeDelta =
            fullProductionNet -
            fullPreparedBothNet;

        const double componentSum =
            edgeDecodeNet +
            determinantNet +
            buildNet;

        writefln(
            "derived,%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.6f,%.6f,%.6f",
            T.stringof,
            fixture.name,
            edgeDecodeNet,
            determinantNet,
            buildNet,
            fullPreparedBothNet,
            fullProductionNet,
            fullDecodeDelta,
            componentSum,
            fullProductionNet /
                fixture.properEdges.length,
            determinantNet /
                fixture.properEdges.length,
            buildNet /
                fixture.properEdges.length
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: post120_exact_construction_probe <rounds> <target-ms>"
    );

    const size_t rounds =
        args[1].to!size_t;

    const long targetMilliseconds =
        args[2].to!long;

    writefln(
        "sizeof,PreparedExactSegment,%s",
        PreparedExactSegment.sizeof
    );

    writefln(
        "sizeof,SignedDyadicProduct,%s",
        SignedDyadicProduct.sizeof
    );

    writefln(
        "sizeof,ExactProperIntersection,%s",
        ExactProperIntersection.sizeof
    );

    runType!int(rounds, targetMilliseconds);
    runType!long(rounds, targetMilliseconds);
    runType!float(rounds, targetMilliseconds);
    runType!double(rounds, targetMilliseconds);

    writefln("sink,%s", benchmarkSink);
}
