module geo.internal.mixed_segment_parameter_probe;

import core.memory : GC;
import core.volatile : volatileLoad;

import geo.internal.dyadic :
    DyadicCoordinateMagnitude,
    DyadicProductMagnitude,
    decodeDyadicCoordinate,
    subtractDyadicCoordinates;
import geo.internal.fixed_uint :
    addUnsigned,
    compareUnsigned,
    multiplyUnsigned;
import geo.internal.intersection_exact :
    ExactProperIntersection,
    PreparedExactSegment,
    prepareExactSegment,
    properIntersectionExactKnownCrossingPreparedFirst;
import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    compareExactOverlayPointsAlongSegment,
    exactOverlayPoint;
import geo.internal.orientation_dyadic :
    orientationDeterminantDyadicDecoded;
import geo.point : Point2;
import geo.segment : Segment2;

import std.algorithm.sorting : sort;
import std.conv : to;
import std.datetime.stopwatch : StopWatch;
import std.exception : enforce;
import std.stdio : writefln;

__gshared ulong benchmarkSink;

private struct ExactSourceParameter
{
    DyadicProductMagnitude numerator;
    DyadicProductMagnitude denominator;
}

private struct CurrentEvent
{
    ExactOverlayPoint exact;
    size_t positionId;
}

private struct ParameterEvent
{
    ExactSourceParameter parameter;
    size_t positionId;
}

private enum EventKind : ubyte
{
    represented,
    properCrossing,
}

private struct EventSpec(T)
{
    EventKind kind;
    T x;
    size_t positionId;
}

private struct Fixture(T)
{
    string name;
    Segment2!T query;
    PreparedExactSegment preparedQuery;
    EventSpec!T[] specs;
    CurrentEvent[] currentTemplate;
    ParameterEvent[] parameterTemplate;
}

private void embedCoordinateMagnitude(
    ref DyadicProductMagnitude destination,
    ref const DyadicCoordinateMagnitude source
)
    pure nothrow @safe @nogc
{
    foreach (i, limb; source.limb)
        destination.limb[i] = limb;
}

private ExactSourceParameter parameterForPoint(T)(
    Segment2!T source,
    Point2!T point
)
    pure nothrow @safe @nogc
{
    T sourceA;
    T sourceB;
    T pointValue;

    if (source.a.x != source.b.x)
    {
        sourceA = source.a.x;
        sourceB = source.b.x;
        pointValue = point.x;
    }
    else
    {
        sourceA = source.a.y;
        sourceB = source.b.y;
        pointValue = point.y;
    }

    const auto a =
        decodeDyadicCoordinate(sourceA);

    const auto b =
        decodeDyadicCoordinate(sourceB);

    const auto p =
        decodeDyadicCoordinate(pointValue);

    const auto total =
        subtractDyadicCoordinates(
            b,
            a
        );

    const auto part =
        subtractDyadicCoordinates(
            p,
            a
        );

    assert(total.sign != 0);
    assert(part.sign == 0 || part.sign == total.sign);

    ExactSourceParameter result;

    embedCoordinateMagnitude(
        result.denominator,
        total.magnitude
    );

    if (part.sign != 0)
    {
        embedCoordinateMagnitude(
            result.numerator,
            part.magnitude
        );
    }

    return result;
}

private ExactSourceParameter parameterForCrossing(T)(
    ref const PreparedExactSegment first,
    Segment2!T second
)
    pure nothrow @safe @nogc
{
    const auto preparedSecond =
        prepareExactSegment(second);

    const auto dA =
        orientationDeterminantDyadicDecoded(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.aX,
            first.aY
        );

    const auto dB =
        orientationDeterminantDyadicDecoded(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.bX,
            first.bY
        );

    assert(dA.sign != 0);
    assert(dB.sign != 0);
    assert(dA.sign != dB.sign);

    ExactSourceParameter result;

    result.numerator =
        dA.magnitude;

    result.denominator =
        addUnsigned(
            dB.magnitude,
            dA.magnitude
        );

    return result;
}

private int compareParameter(
    ref const ExactSourceParameter lhs,
    ref const ExactSourceParameter rhs
)
    pure nothrow @safe @nogc
{
    const auto left =
        multiplyUnsigned(
            lhs.numerator,
            rhs.denominator
        );

    const auto right =
        multiplyUnsigned(
            rhs.numerator,
            lhs.denominator
        );

    return compareUnsigned(left, right);
}

private size_t strideFor(size_t count)
{
    return count == 16 ? 5 : 37;
}

private Fixture!T makeFixture(T)(size_t count)
{
    alias P = Point2!T;
    alias S = Segment2!T;

    Fixture!T result;
    result.name = "mixed-" ~ count.to!string;

    result.query =
        S(
            P(cast(T) 0, cast(T) 0),
            P(cast(T)(count + 1), cast(T) 0)
        );

    result.preparedQuery =
        prepareExactSegment(
            result.query
        );

    result.specs =
        new EventSpec!T[count];

    result.currentTemplate =
        new CurrentEvent[count];

    result.parameterTemplate =
        new ParameterEvent[count];

    result.specs[0] =
        EventSpec!T(
            EventKind.represented,
            cast(T) 0,
            0
        );

    result.specs[1] =
        EventSpec!T(
            EventKind.represented,
            cast(T)(count + 1),
            count + 1
        );

    const size_t stride =
        strideFor(count);

    foreach (i; 2 .. count)
    {
        size_t slot =
            ((i - 2) * stride) % (count - 2) + 1;

        /*
         * Deliberate duplicates exercise equality/dedup across representation
         * kinds. A duplicated position may be represented in one event and a
         * proper crossing in another.
         */
        if (i >= 4 && i % 7 == 0)
        {
            slot =
                result.specs[i - 1].positionId;
        }

        result.specs[i] =
            EventSpec!T(
                i % 4 == 0
                    ? EventKind.represented
                    : EventKind.properCrossing,
                cast(T) slot,
                slot
            );
    }

    foreach (i, spec; result.specs)
    {
        final switch (spec.kind)
        {
            case EventKind.represented:
            {
                const point =
                    P(
                        spec.x,
                        cast(T) 0
                    );

                result.currentTemplate[i] =
                    CurrentEvent(
                        exactOverlayPoint(point),
                        spec.positionId
                    );

                result.parameterTemplate[i] =
                    ParameterEvent(
                        parameterForPoint(
                            result.query,
                            point
                        ),
                        spec.positionId
                    );

                break;
            }

            case EventKind.properCrossing:
            {
                const edge =
                    S(
                        P(spec.x, cast(T)-1),
                        P(spec.x, cast(T) 1)
                    );

                ExactProperIntersection exact;

                properIntersectionExactKnownCrossingPreparedFirst(
                    result.preparedQuery,
                    edge,
                    exact
                );

                result.currentTemplate[i] =
                    CurrentEvent(
                        exactOverlayPoint(exact),
                        spec.positionId
                    );

                result.parameterTemplate[i] =
                    ParameterEvent(
                        parameterForCrossing(
                            result.preparedQuery,
                            edge
                        ),
                        spec.positionId
                    );

                break;
            }
        }
    }

    foreach (i; 0 .. count)
    {
        foreach (j; 0 .. count)
        {
            const int current =
                compareExactOverlayPointsAlongSegment(
                    result.query,
                    result.currentTemplate[i].exact,
                    result.currentTemplate[j].exact
                );

            const int parameter =
                compareParameter(
                    result.parameterTemplate[i].parameter,
                    result.parameterTemplate[j].parameter
                );

            enforce(
                (current < 0) == (parameter < 0) &&
                (current == 0) == (parameter == 0) &&
                (current > 0) == (parameter > 0),
                "mixed parameter ordering mismatch"
            );
        }
    }

    return result;
}

private void siftCurrent(T)(
    Segment2!T query,
    scope CurrentEvent[] events,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
{
    while (true)
    {
        const size_t left = root * 2 + 1;

        if (left >= end)
            return;

        size_t largest = root;

        if (
            compareExactOverlayPointsAlongSegment(
                query,
                events[largest].exact,
                events[left].exact
            ) < 0
        )
        {
            largest = left;
        }

        const size_t right = left + 1;

        if (
            right < end &&
            compareExactOverlayPointsAlongSegment(
                query,
                events[largest].exact,
                events[right].exact
            ) < 0
        )
        {
            largest = right;
        }

        if (largest == root)
            return;

        const auto temporary = events[root];
        events[root] = events[largest];
        events[largest] = temporary;
        root = largest;
    }
}

private void siftParameter(
    scope ParameterEvent[] events,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
{
    while (true)
    {
        const size_t left = root * 2 + 1;

        if (left >= end)
            return;

        size_t largest = root;

        if (
            compareParameter(
                events[largest].parameter,
                events[left].parameter
            ) < 0
        )
        {
            largest = left;
        }

        const size_t right = left + 1;

        if (
            right < end &&
            compareParameter(
                events[largest].parameter,
                events[right].parameter
            ) < 0
        )
        {
            largest = right;
        }

        if (largest == root)
            return;

        const auto temporary = events[root];
        events[root] = events[largest];
        events[largest] = temporary;
        root = largest;
    }
}

private void heapSortCurrent(T)(
    Segment2!T query,
    scope CurrentEvent[] events
)
    pure nothrow @safe @nogc
{
    size_t start = events.length / 2;

    while (start > 0)
    {
        --start;
        siftCurrent(
            query,
            events,
            start,
            events.length
        );
    }

    size_t end = events.length;

    while (end > 1)
    {
        --end;
        const auto temporary = events[0];
        events[0] = events[end];
        events[end] = temporary;
        siftCurrent(query, events, 0, end);
    }
}

private void heapSortParameter(
    scope ParameterEvent[] events
)
    pure nothrow @safe @nogc
{
    size_t start = events.length / 2;

    while (start > 0)
    {
        --start;
        siftParameter(
            events,
            start,
            events.length
        );
    }

    size_t end = events.length;

    while (end > 1)
    {
        --end;
        const auto temporary = events[0];
        events[0] = events[end];
        events[end] = temporary;
        siftParameter(events, 0, end);
    }
}

private size_t dedupCurrent(T)(
    Segment2!T query,
    scope CurrentEvent[] events
)
    pure nothrow @safe @nogc
{
    if (events.length == 0)
        return 0;

    size_t write = 1;

    foreach (read; 1 .. events.length)
    {
        if (
            compareExactOverlayPointsAlongSegment(
                query,
                events[write - 1].exact,
                events[read].exact
            ) != 0
        )
        {
            events[write++] = events[read];
        }
    }

    return write;
}

private size_t dedupParameter(
    scope ParameterEvent[] events
)
    pure nothrow @safe @nogc
{
    if (events.length == 0)
        return 0;

    size_t write = 1;

    foreach (read; 1 .. events.length)
    {
        if (
            compareParameter(
                events[write - 1].parameter,
                events[read].parameter
            ) != 0
        )
        {
            events[write++] = events[read];
        }
    }

    return write;
}

private ulong hashIds(T)(
    ref Fixture!T fixture,
    scope CurrentEvent[] current,
    scope ParameterEvent[] parameter
)
{
    heapSortCurrent(
        fixture.query,
        current
    );

    heapSortParameter(parameter);

    const size_t currentCount =
        dedupCurrent(
            fixture.query,
            current
        );

    const size_t parameterCount =
        dedupParameter(parameter);

    enforce(
        currentCount == parameterCount,
        "mixed unique count mismatch"
    );

    ulong result = currentCount;

    foreach (i; 0 .. currentCount)
    {
        enforce(
            current[i].positionId ==
                parameter[i].positionId,
            "mixed unique order mismatch"
        );

        result =
            result * 1_000_003UL +
            current[i].positionId;
    }

    return result;
}

pragma(inline, false)
private ulong currentReplay(T)(
    ref Fixture!T fixture,
    scope CurrentEvent[] buffer,
    size_t iteration
)
    @nogc
{
    buffer[] =
        fixture.currentTemplate[];

    heapSortCurrent(
        fixture.query,
        buffer
    );

    const size_t count =
        dedupCurrent(
            fixture.query,
            buffer
        );

    ulong result = count;

    foreach (i; 0 .. count)
    {
        result =
            result * 1_000_003UL +
            buffer[i].positionId;
    }

    return
        result +
        volatileLoad(&iteration);
}

pragma(inline, false)
private ulong parameterReplay(T)(
    ref Fixture!T fixture,
    scope ParameterEvent[] buffer,
    size_t iteration
)
    @nogc
{
    buffer[] =
        fixture.parameterTemplate[];

    heapSortParameter(buffer);

    const size_t count =
        dedupParameter(buffer);

    ulong result = count;

    foreach (i; 0 .. count)
    {
        result =
            result * 1_000_003UL +
            buffer[i].positionId;
    }

    return
        result +
        volatileLoad(&iteration);
}

private double measureCurrent(T)(
    ref Fixture!T fixture,
    size_t rounds,
    long targetMilliseconds
)
{
    auto buffer =
        new CurrentEvent[
            fixture.currentTemplate.length
        ];

    size_t iterations = 1;
    ulong sink;

    while (true)
    {
        StopWatch watch;
        watch.start();

        foreach (i; 0 .. iterations)
            sink ^= currentReplay(fixture, buffer[], i);

        watch.stop();

        if (
            watch.peek.total!"msecs" >=
                targetMilliseconds ||
            iterations >= 1_048_576
        )
        {
            break;
        }

        iterations *= 2;
    }

    double[] samples =
        new double[rounds];

    foreach (round; 0 .. rounds)
    {
        GC.collect();

        StopWatch watch;
        watch.start();

        foreach (i; 0 .. iterations)
            sink ^= currentReplay(fixture, buffer[], i);

        watch.stop();

        samples[round] =
            cast(double)
                watch.peek.total!"nsecs" /
            iterations;
    }

    samples.sort;
    benchmarkSink ^= sink;
    return samples[samples.length / 2];
}

private double measureParameter(T)(
    ref Fixture!T fixture,
    size_t rounds,
    long targetMilliseconds
)
{
    auto buffer =
        new ParameterEvent[
            fixture.parameterTemplate.length
        ];

    size_t iterations = 1;
    ulong sink;

    while (true)
    {
        StopWatch watch;
        watch.start();

        foreach (i; 0 .. iterations)
            sink ^= parameterReplay(fixture, buffer[], i);

        watch.stop();

        if (
            watch.peek.total!"msecs" >=
                targetMilliseconds ||
            iterations >= 1_048_576
        )
        {
            break;
        }

        iterations *= 2;
    }

    double[] samples =
        new double[rounds];

    foreach (round; 0 .. rounds)
    {
        GC.collect();

        StopWatch watch;
        watch.start();

        foreach (i; 0 .. iterations)
            sink ^= parameterReplay(fixture, buffer[], i);

        watch.stop();

        samples[round] =
            cast(double)
                watch.peek.total!"nsecs" /
            iterations;
    }

    samples.sort;
    benchmarkSink ^= sink;
    return samples[samples.length / 2];
}

private void runType(T)(
    size_t rounds,
    long targetMilliseconds
)
{
    foreach (count; [16UL, 64UL])
    {
        auto fixture =
            makeFixture!T(count);

        auto currentCheck =
            fixture.currentTemplate.dup;

        auto parameterCheck =
            fixture.parameterTemplate.dup;

        const ulong check =
            hashIds(
                fixture,
                currentCheck[],
                parameterCheck[]
            );

        const double current =
            measureCurrent(
                fixture,
                rounds,
                targetMilliseconds
            );

        const double parameter =
            measureParameter(
                fixture,
                rounds,
                targetMilliseconds
            );

        writefln(
            "summary,%s,%s,current,%.3f",
            T.stringof,
            fixture.name,
            current
        );

        writefln(
            "summary,%s,%s,parameter,%.3f",
            T.stringof,
            fixture.name,
            parameter
        );

        writefln(
            "derived,%s,%s,%.3f,%.3f,%.6f,%s",
            T.stringof,
            fixture.name,
            current,
            parameter,
            current / parameter,
            check
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: mixed_segment_parameter_probe <rounds> <target-ms>"
    );

    const size_t rounds =
        args[1].to!size_t;

    const long targetMilliseconds =
        args[2].to!long;

    writefln(
        "layout,CurrentEvent,%s",
        CurrentEvent.sizeof
    );

    writefln(
        "layout,ParameterEvent,%s",
        ParameterEvent.sizeof
    );

    runType!int(rounds, targetMilliseconds);
    runType!long(rounds, targetMilliseconds);
    runType!float(rounds, targetMilliseconds);
    runType!double(rounds, targetMilliseconds);

    writefln("sink,%s", benchmarkSink);
}
