module geo.internal.exact_construction_transport_probe;

import core.memory : GC;
import core.volatile : volatileLoad;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    SignedDyadicCoordinate,
    SignedDyadicProduct,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;
import geo.internal.exact_coordinate :
    SignedExactCoordinateNumerator;
import geo.internal.fixed_uint :
    addUnsigned,
    compareUnsigned,
    multiplyUnsigned,
    subtractUnsigned;
import geo.internal.intersection_exact :
    ExactProperIntersection,
    properIntersectionExactKnownCrossing;
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

private struct DecodedSegment
{
    SignedDyadicCoordinate ax;
    SignedDyadicCoordinate ay;
    SignedDyadicCoordinate bx;
    SignedDyadicCoordinate by;
}

private struct Fixture(T)
{
    string name;
    Segment2!T[2] queries;
    Segment2!T[] properEdges;
    ExactProperIntersection[][2] expected;
}

private DecodedSegment decodeSegment(T)(Segment2!T segment)
    pure nothrow @safe @nogc
{
    DecodedSegment result;

    result.ax = decodeDyadicCoordinate(segment.a.x);
    result.ay = decodeDyadicCoordinate(segment.a.y);
    result.bx = decodeDyadicCoordinate(segment.b.x);
    result.by = decodeDyadicCoordinate(segment.b.y);

    return result;
}

private SignedDyadicProduct orientationDeterminantDecoded(
    ref const DecodedSegment line,
    ref const SignedDyadicCoordinate px,
    ref const SignedDyadicCoordinate py
)
    pure nothrow @safe @nogc
{
    const auto bAx =
        subtractDyadicCoordinates(
            line.bx,
            line.ax
        );

    const auto bAy =
        subtractDyadicCoordinates(
            line.by,
            line.ay
        );

    const auto pAx =
        subtractDyadicCoordinates(
            px,
            line.ax
        );

    const auto pAy =
        subtractDyadicCoordinates(
            py,
            line.ay
        );

    const auto p =
        multiplyDyadicDifferences(
            bAx,
            pAy
        );

    const auto q =
        multiplyDyadicDifferences(
            bAy,
            pAx
        );

    return
        subtractDyadicProducts(
            p,
            q
        );
}

private SignedExactCoordinateNumerator weightedCoordinateValue(
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

private void buildPreparedValue(
    ref const DecodedSegment first,
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

    result.xNumerator =
        weightedCoordinateValue(
            weightA,
            first.ax,
            weightB,
            first.bx
        );

    result.yNumerator =
        weightedCoordinateValue(
            weightA,
            first.ay,
            weightB,
            first.by
        );
}

private size_t firstNonZero(
    scope const(uint)[] value
)
    pure nothrow @safe @nogc
{
    foreach (i, limb; value)
    {
        if (limb != 0)
            return i;
    }

    return value.length;
}

private size_t pastLastNonZero(
    scope const(uint)[] value
)
    pure nothrow @safe @nogc
{
    size_t i = value.length;

    while (i != 0)
    {
        if (value[i - 1] != 0)
            return i;

        --i;
    }

    return 0;
}

private void multiplyUnsignedInto(
    scope const(uint)[] lhs,
    scope const(uint)[] rhs,
    scope uint[] result
)
    pure nothrow @safe @nogc
{
    assert(result.length == lhs.length + rhs.length);

    result[] = 0;

    const size_t lhsFirst = firstNonZero(lhs);

    if (lhsFirst == lhs.length)
        return;

    const size_t rhsFirst = firstNonZero(rhs);

    if (rhsFirst == rhs.length)
        return;

    const size_t lhsEnd = pastLastNonZero(lhs);
    const size_t rhsEnd = pastLastNonZero(rhs);

    foreach (i; lhsFirst .. lhsEnd)
    {
        const uint lhsWord = lhs[i];

        if (lhsWord == 0)
            continue;

        ulong carry = 0;

        foreach (j; rhsFirst .. rhsEnd)
        {
            const size_t index = i + j;

            const ulong accumulated =
                cast(ulong) lhsWord *
                    cast(ulong) rhs[j]
                + cast(ulong) result[index]
                + carry;

            result[index] =
                cast(uint) accumulated;

            carry =
                accumulated >> 32;
        }

        const size_t carryIndex =
            i + rhsEnd;

        assert(carryIndex < result.length);
        assert(result[carryIndex] == 0);

        result[carryIndex] =
            cast(uint) carry;
    }
}

private void addUnsignedInto(
    scope const(uint)[] lhs,
    scope const(uint)[] rhs,
    scope uint[] result
)
    pure nothrow @safe @nogc
{
    assert(lhs.length == rhs.length);
    assert(result.length == lhs.length);

    result[] = lhs[];

    const size_t rhsFirst = firstNonZero(rhs);

    if (rhsFirst == rhs.length)
        return;

    const size_t rhsEnd = pastLastNonZero(rhs);

    ulong carry = 0;

    foreach (index; rhsFirst .. rhsEnd)
    {
        const ulong sum =
            cast(ulong) result[index] +
            cast(ulong) rhs[index] +
            carry;

        result[index] =
            cast(uint) sum;

        carry =
            sum >> 32;
    }

    size_t index = rhsEnd;

    while (carry != 0)
    {
        assert(index < result.length);

        const ulong sum =
            cast(ulong) result[index] +
            carry;

        result[index] =
            cast(uint) sum;

        carry =
            sum >> 32;

        ++index;
    }
}

private int compareUnsignedSlices(
    scope const(uint)[] lhs,
    scope const(uint)[] rhs
)
    pure nothrow @safe @nogc
{
    assert(lhs.length == rhs.length);

    size_t index = lhs.length;

    while (index != 0)
    {
        --index;

        if (lhs[index] < rhs[index])
            return -1;

        if (lhs[index] > rhs[index])
            return 1;
    }

    return 0;
}

private void subtractUnsignedInto(
    scope const(uint)[] lhs,
    scope const(uint)[] rhs,
    scope uint[] result
)
    pure nothrow @safe @nogc
{
    assert(lhs.length == rhs.length);
    assert(result.length == lhs.length);
    assert(compareUnsignedSlices(lhs, rhs) >= 0);

    result[] = lhs[];

    const size_t rhsFirst = firstNonZero(rhs);

    if (rhsFirst == rhs.length)
        return;

    const size_t rhsEnd = pastLastNonZero(rhs);

    ulong borrow = 0;

    foreach (index; rhsFirst .. rhsEnd)
    {
        const ulong lhsValue =
            cast(ulong) result[index];

        const ulong rhsValue =
            cast(ulong) rhs[index] +
            borrow;

        if (lhsValue >= rhsValue)
        {
            result[index] =
                cast(uint)(
                    lhsValue - rhsValue
                );

            borrow = 0;
        }
        else
        {
            result[index] =
                cast(uint)(
                    0x1_0000_0000UL +
                    lhsValue -
                    rhsValue
                );

            borrow = 1;
        }
    }

    size_t index = rhsEnd;

    while (borrow != 0)
    {
        assert(index < result.length);

        if (result[index] != 0)
        {
            --result[index];
            borrow = 0;
        }
        else
        {
            result[index] = uint.max;
            ++index;
        }
    }
}

private bool isZeroSlice(
    scope const(uint)[] value
)
    pure nothrow @safe @nogc
{
    foreach (limb; value)
    {
        if (limb != 0)
            return false;
    }

    return true;
}

private void weightedCoordinateInto(
    ref const DyadicProductMagnitude weightA,
    ref const SignedDyadicCoordinate a,
    ref const DyadicProductMagnitude weightB,
    ref const SignedDyadicCoordinate b,
    ref SignedExactCoordinateNumerator result
)
    pure nothrow @safe @nogc
{
    SignedExactCoordinateNumerator magnitudeAHolder;
    SignedExactCoordinateNumerator magnitudeBHolder;

    multiplyUnsignedInto(
        weightA.limb[],
        a.magnitude.limb[],
        magnitudeAHolder.magnitude.limb[]
    );

    multiplyUnsignedInto(
        weightB.limb[],
        b.magnitude.limb[],
        magnitudeBHolder.magnitude.limb[]
    );

    const bool zeroA =
        a.sign == 0 ||
        isZeroSlice(
            magnitudeAHolder.magnitude.limb[]
        );

    const bool zeroB =
        b.sign == 0 ||
        isZeroSlice(
            magnitudeBHolder.magnitude.limb[]
        );

    result =
        SignedExactCoordinateNumerator.init;

    if (zeroA)
    {
        if (zeroB)
            return;

        result.sign = b.sign;
        result.magnitude =
            magnitudeBHolder.magnitude;
        return;
    }

    if (zeroB)
    {
        result.sign = a.sign;
        result.magnitude =
            magnitudeAHolder.magnitude;
        return;
    }

    if (a.sign == b.sign)
    {
        result.sign = a.sign;

        addUnsignedInto(
            magnitudeAHolder.magnitude.limb[],
            magnitudeBHolder.magnitude.limb[],
            result.magnitude.limb[]
        );

        return;
    }

    const int comparison =
        compareUnsignedSlices(
            magnitudeAHolder.magnitude.limb[],
            magnitudeBHolder.magnitude.limb[]
        );

    if (comparison == 0)
        return;

    if (comparison > 0)
    {
        result.sign = a.sign;

        subtractUnsignedInto(
            magnitudeAHolder.magnitude.limb[],
            magnitudeBHolder.magnitude.limb[],
            result.magnitude.limb[]
        );
    }
    else
    {
        result.sign = b.sign;

        subtractUnsignedInto(
            magnitudeBHolder.magnitude.limb[],
            magnitudeAHolder.magnitude.limb[],
            result.magnitude.limb[]
        );
    }
}

private void buildPreparedInPlace(
    ref const DecodedSegment first,
    ref const SignedDyadicProduct dA,
    ref const SignedDyadicProduct dB,
    ref ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    assert(dA.sign != 0);
    assert(dB.sign != 0);
    assert(dA.sign != dB.sign);

    result =
        ExactProperIntersection.init;

    addUnsignedInto(
        dB.magnitude.limb[],
        dA.magnitude.limb[],
        result.denominator.limb[]
    );

    weightedCoordinateInto(
        dB.magnitude,
        first.ax,
        dA.magnitude,
        first.bx,
        result.xNumerator
    );

    weightedCoordinateInto(
        dB.magnitude,
        first.ay,
        dA.magnitude,
        first.by,
        result.yNumerator
    );
}

private void preparedValueKnownCrossing(T)(
    ref const DecodedSegment first,
    Segment2!T second,
    ref ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    const DecodedSegment decodedSecond =
        decodeSegment(second);

    const auto dA =
        orientationDeterminantDecoded(
            decodedSecond,
            first.ax,
            first.ay
        );

    const auto dB =
        orientationDeterminantDecoded(
            decodedSecond,
            first.bx,
            first.by
        );

    assert(dA.sign != 0);
    assert(dB.sign != 0);
    assert(dA.sign != dB.sign);

    buildPreparedValue(
        first,
        dA,
        dB,
        result
    );
}

private void preparedInPlaceKnownCrossing(T)(
    ref const DecodedSegment first,
    Segment2!T second,
    ref ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    const DecodedSegment decodedSecond =
        decodeSegment(second);

    const auto dA =
        orientationDeterminantDecoded(
            decodedSecond,
            first.ax,
            first.ay
        );

    const auto dB =
        orientationDeterminantDecoded(
            decodedSecond,
            first.bx,
            first.by
        );

    assert(dA.sign != 0);
    assert(dB.sign != 0);
    assert(dA.sign != dB.sign);

    buildPreparedInPlace(
        first,
        dA,
        dB,
        result
    );
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
        result.expected[direction] =
            new ExactProperIntersection[
                result.properEdges.length
            ];

        const currentQuery =
            result.queries[direction];

        const decodedQuery =
            decodeSegment(currentQuery);

        foreach (i, edge; result.properEdges)
        {
            ExactProperIntersection production;
            ExactProperIntersection preparedValue;
            ExactProperIntersection preparedInPlace;

            properIntersectionExactKnownCrossing(
                currentQuery,
                edge,
                production
            );

            preparedValueKnownCrossing(
                decodedQuery,
                edge,
                preparedValue
            );

            preparedInPlaceKnownCrossing(
                decodedQuery,
                edge,
                preparedInPlace
            );

            enforce(
                exactEqual(
                    production,
                    preparedValue
                ),
                "prepared-value mismatch"
            );

            enforce(
                exactEqual(
                    production,
                    preparedInPlace
                ),
                "prepared-inplace mismatch"
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
private ulong productionReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const query =
        fixture.queries[direction];

    ulong result = 1;

    foreach (edge; fixture.properEdges)
    {
        ExactProperIntersection exact;

        properIntersectionExactKnownCrossing(
            query,
            edge,
            exact
        );

        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong preparedValueReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const decodedQuery =
        decodeSegment(
            fixture.queries[direction]
        );

    ulong result = 1;

    foreach (edge; fixture.properEdges)
    {
        ExactProperIntersection exact;

        preparedValueKnownCrossing(
            decodedQuery,
            edge,
            exact
        );

        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong preparedInPlaceReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const decodedQuery =
        decodeSegment(
            fixture.queries[direction]
        );

    ulong result = 1;

    foreach (edge; fixture.properEdges)
    {
        ExactProperIntersection exact;

        preparedInPlaceKnownCrossing(
            decodedQuery,
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

        const double production =
            measure!productionReplay(
                fixture,
                "production",
                rounds,
                targetMilliseconds
            );

        const double preparedValue =
            measure!preparedValueReplay(
                fixture,
                "prepared-value",
                rounds,
                targetMilliseconds
            );

        const double preparedInPlace =
            measure!preparedInPlaceReplay(
                fixture,
                "prepared-inplace",
                rounds,
                targetMilliseconds
            );

        const double productionNet =
            production - carrierRead;

        const double preparedValueNet =
            preparedValue - carrierRead;

        const double preparedInPlaceNet =
            preparedInPlace - carrierRead;

        writefln(
            "derived,%s,%s,%.3f,%.3f,%.3f,%.6f,%.6f",
            T.stringof,
            fixture.name,
            productionNet,
            preparedValueNet,
            preparedInPlaceNet,
            productionNet / preparedValueNet,
            preparedValueNet / preparedInPlaceNet
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: exact_construction_transport_probe <rounds> <target-ms>"
    );

    const size_t rounds =
        args[1].to!size_t;

    const long targetMilliseconds =
        args[2].to!long;

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
