module geo.internal.lazy_segment_parameter_probe;

import core.memory : GC;
import core.volatile : volatileLoad;

import geo.internal.dyadic :
    DyadicProductMagnitude;
import geo.internal.fixed_uint :
    compareUnsigned,
    multiplyUnsigned;
import geo.internal.intersection_exact :
    ExactProperIntersection,
    PreparedExactSegment,
    compareProperIntersectionsAlongSegment,
    prepareExactSegment,
    properIntersectionExactKnownCrossingPreparedFirst;
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

private struct ExactSegmentParameter
{
    /*
     * For a strict crossing on source A -> B:
     *
     *     P = (weightA * A + weightB * B) / (weightA + weightB)
     *     t = weightB / (weightA + weightB)
     *
     * Both weights are positive exact determinant magnitudes.
     */
    DyadicProductMagnitude weightA;
    DyadicProductMagnitude weightB;
}

private struct CurrentEvent
{
    ExactProperIntersection exact;
    size_t id;
}

private struct ParameterEvent
{
    ExactSegmentParameter parameter;
    size_t id;
}

private struct Fixture(T)
{
    string name;
    Segment2!T query;
    Segment2!T[] edges;
    CurrentEvent[] currentTemplate;
    ParameterEvent[] parameterTemplate;
    PreparedExactSegment preparedQuery;
}

private int compareParameter(
    ref const ExactSegmentParameter lhs,
    ref const ExactSegmentParameter rhs
)
    pure nothrow @safe @nogc
{
    /*
     * For positive a/b weights:
     *
     *   b1 / (a1 + b1) < b2 / (a2 + b2)
     *
     * iff
     *
     *   b1 * a2 < b2 * a1
     *
     * The common b1*b2 term cancels, so no denominator materialization is
     * required.
     */
    const auto left =
        multiplyUnsigned(
            lhs.weightB,
            rhs.weightA
        );

    const auto right =
        multiplyUnsigned(
            rhs.weightB,
            lhs.weightA
        );

    return compareUnsigned(left, right);
}

private ExactSegmentParameter buildParameter(T)(
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

    return
        ExactSegmentParameter(
            dB.magnitude,
            dA.magnitude
        );
}

private size_t strideFor(size_t count)
{
    final switch (count)
    {
        case 4:
            return 3;
        case 16:
            return 5;
        case 64:
            return 37;
    }
}

private Fixture!T makeFixture(T)(size_t count)
{
    alias P = Point2!T;
    alias S = Segment2!T;

    Fixture!T result;
    result.name = "dense-" ~ count.to!string;

    result.query =
        S(
            P(cast(T) 0, cast(T) 0),
            P(cast(T)(count + 1), cast(T) 0)
        );

    result.preparedQuery =
        prepareExactSegment(result.query);

    result.edges =
        new S[count];

    result.currentTemplate =
        new CurrentEvent[count];

    result.parameterTemplate =
        new ParameterEvent[count];

    const size_t stride =
        strideFor(count);

    foreach (i; 0 .. count)
    {
        const size_t slot =
            (i * stride) % count;

        const T x =
            cast(T)(slot + 1);

        result.edges[i] =
            S(
                P(x, cast(T)-1),
                P(x, cast(T) 1)
            );

        properIntersectionExactKnownCrossingPreparedFirst(
            result.preparedQuery,
            result.edges[i],
            result.currentTemplate[i].exact
        );

        result.currentTemplate[i].id = slot;

        result.parameterTemplate[i].parameter =
            buildParameter(
                result.preparedQuery,
                result.edges[i]
            );

        result.parameterTemplate[i].id = slot;
    }

    /*
     * Strong preflight: every pair must compare identically under the current
     * exact Cartesian ordering and the parameter ordering.
     */
    foreach (i; 0 .. count)
    {
        foreach (j; 0 .. count)
        {
            const int current =
                compareProperIntersectionsAlongSegment(
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
                "parameter ordering mismatch"
            );
        }
    }

    return result;
}

private void siftDownCurrent(T)(
    Segment2!T query,
    scope CurrentEvent[] events,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
{
    while (true)
    {
        const size_t left =
            root * 2 + 1;

        if (left >= end)
            return;

        size_t largest = root;

        if (
            compareProperIntersectionsAlongSegment(
                query,
                events[largest].exact,
                events[left].exact
            ) < 0
        )
        {
            largest = left;
        }

        const size_t right =
            left + 1;

        if (
            right < end &&
            compareProperIntersectionsAlongSegment(
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

        const auto temporary =
            events[root];

        events[root] =
            events[largest];

        events[largest] =
            temporary;

        root = largest;
    }
}

private void sortCurrent(T)(
    Segment2!T query,
    scope CurrentEvent[] events
)
    pure nothrow @safe @nogc
{
    if (events.length < 2)
        return;

    size_t start =
        events.length / 2;

    while (start > 0)
    {
        --start;
        siftDownCurrent(
            query,
            events,
            start,
            events.length
        );
    }

    size_t end =
        events.length;

    while (end > 1)
    {
        --end;

        const auto temporary =
            events[0];

        events[0] =
            events[end];

        events[end] =
            temporary;

        siftDownCurrent(
            query,
            events,
            0,
            end
        );
    }
}

private void siftDownParameter(
    scope ParameterEvent[] events,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
{
    while (true)
    {
        const size_t left =
            root * 2 + 1;

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

        const size_t right =
            left + 1;

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

        const auto temporary =
            events[root];

        events[root] =
            events[largest];

        events[largest] =
            temporary;

        root = largest;
    }
}

private void sortParameter(
    scope ParameterEvent[] events
)
    pure nothrow @safe @nogc
{
    if (events.length < 2)
        return;

    size_t start =
        events.length / 2;

    while (start > 0)
    {
        --start;
        siftDownParameter(
            events,
            start,
            events.length
        );
    }

    size_t end =
        events.length;

    while (end > 1)
    {
        --end;

        const auto temporary =
            events[0];

        events[0] =
            events[end];

        events[end] =
            temporary;

        siftDownParameter(
            events,
            0,
            end
        );
    }
}

private ulong hashCurrent(scope const(CurrentEvent)[] events)
    pure nothrow @safe @nogc
{
    ulong result = 1;

    foreach (event; events)
    {
        result =
            result * 1_000_003UL +
            event.id;

        result +=
            event.exact.denominator.limb[0];
    }

    return result;
}

private ulong hashParameter(scope const(ParameterEvent)[] events)
    pure nothrow @safe @nogc
{
    ulong result = 1;

    foreach (event; events)
    {
        result =
            result * 1_000_003UL +
            event.id;

        result +=
            event.parameter.weightA.limb[0] +
            event.parameter.weightB.limb[0];
    }

    return result;
}

pragma(inline, false)
private ulong currentBuildReplay(T)(
    ref Fixture!T fixture,
    scope CurrentEvent[] buffer,
    size_t iteration
)
    @nogc
{
    foreach (i, edge; fixture.edges)
    {
        properIntersectionExactKnownCrossingPreparedFirst(
            fixture.preparedQuery,
            edge,
            buffer[i].exact
        );

        buffer[i].id =
            fixture.currentTemplate[i].id;
    }

    return
        hashCurrent(buffer) +
        volatileLoad(&iteration);
}

pragma(inline, false)
private ulong parameterBuildReplay(T)(
    ref Fixture!T fixture,
    scope ParameterEvent[] buffer,
    size_t iteration
)
    @nogc
{
    foreach (i, edge; fixture.edges)
    {
        buffer[i].parameter =
            buildParameter(
                fixture.preparedQuery,
                edge
            );

        buffer[i].id =
            fixture.parameterTemplate[i].id;
    }

    return
        hashParameter(buffer) +
        volatileLoad(&iteration);
}

pragma(inline, false)
private ulong currentBuildSortReplay(T)(
    ref Fixture!T fixture,
    scope CurrentEvent[] buffer,
    size_t iteration
)
    @nogc
{
    currentBuildReplay(
        fixture,
        buffer,
        iteration
    );

    sortCurrent(
        fixture.query,
        buffer
    );

    return
        hashCurrent(buffer) +
        volatileLoad(&iteration);
}

pragma(inline, false)
private ulong parameterBuildSortReplay(T)(
    ref Fixture!T fixture,
    scope ParameterEvent[] buffer,
    size_t iteration
)
    @nogc
{
    parameterBuildReplay(
        fixture,
        buffer,
        iteration
    );

    sortParameter(buffer);

    return
        hashParameter(buffer) +
        volatileLoad(&iteration);
}

private double measureCurrent(alias operation, T)(
    ref Fixture!T fixture,
    string operationName,
    size_t rounds,
    long targetMilliseconds
)
{
    auto buffer =
        new CurrentEvent[
            fixture.edges.length
        ];

    size_t iterations = 1;
    ulong sink = 1;

    while (true)
    {
        StopWatch calibration;
        calibration.start();

        foreach (i; 0 .. iterations)
        {
            sink ^=
                operation(
                    fixture,
                    buffer[],
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

    double[] timings =
        new double[rounds];

    foreach (round; 0 .. rounds)
    {
        GC.collect();

        StopWatch watch;
        watch.start();

        foreach (i; 0 .. iterations)
        {
            sink ^=
                operation(
                    fixture,
                    buffer[],
                    i
                );
        }

        watch.stop();

        timings[round] =
            cast(double)
                watch.peek.total!"nsecs" /
            iterations;
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

    benchmarkSink ^= sink;
    return median;
}

private double measureParameter(alias operation, T)(
    ref Fixture!T fixture,
    string operationName,
    size_t rounds,
    long targetMilliseconds
)
{
    auto buffer =
        new ParameterEvent[
            fixture.edges.length
        ];

    size_t iterations = 1;
    ulong sink = 1;

    while (true)
    {
        StopWatch calibration;
        calibration.start();

        foreach (i; 0 .. iterations)
        {
            sink ^=
                operation(
                    fixture,
                    buffer[],
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

    double[] timings =
        new double[rounds];

    foreach (round; 0 .. rounds)
    {
        GC.collect();

        StopWatch watch;
        watch.start();

        foreach (i; 0 .. iterations)
        {
            sink ^=
                operation(
                    fixture,
                    buffer[],
                    i
                );
        }

        watch.stop();

        timings[round] =
            cast(double)
                watch.peek.total!"nsecs" /
            iterations;
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

    benchmarkSink ^= sink;
    return median;
}

private void runFixture(T)(
    ref Fixture!T fixture,
    size_t rounds,
    long targetMilliseconds
)
{
    const double currentBuild =
        measureCurrent!currentBuildReplay(
            fixture,
            "current-build",
            rounds,
            targetMilliseconds
        );

    const double parameterBuild =
        measureParameter!parameterBuildReplay(
            fixture,
            "parameter-build",
            rounds,
            targetMilliseconds
        );

    const double currentBuildSort =
        measureCurrent!currentBuildSortReplay(
            fixture,
            "current-build-sort",
            rounds,
            targetMilliseconds
        );

    const double parameterBuildSort =
        measureParameter!parameterBuildSortReplay(
            fixture,
            "parameter-build-sort",
            rounds,
            targetMilliseconds
        );

    writefln(
        "derived,%s,%s,%.3f,%.3f,%.3f,%.3f,%.6f,%.6f",
        T.stringof,
        fixture.name,
        currentBuild,
        parameterBuild,
        currentBuildSort,
        parameterBuildSort,
        currentBuild / parameterBuild,
        currentBuildSort / parameterBuildSort
    );
}

private void runType(T)(
    size_t rounds,
    long targetMilliseconds
)
{
    foreach (count; [4UL, 16UL, 64UL])
    {
        auto fixture =
            makeFixture!T(count);

        runFixture(
            fixture,
            rounds,
            targetMilliseconds
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: lazy_segment_parameter_probe <rounds> <target-ms>"
    );

    const size_t rounds =
        args[1].to!size_t;

    const long targetMilliseconds =
        args[2].to!long;

    writefln(
        "layout,ExactProperIntersection,%s",
        ExactProperIntersection.sizeof
    );

    writefln(
        "layout,ExactSegmentParameter,%s",
        ExactSegmentParameter.sizeof
    );

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
