module geo.internal.dense_event_index_sort_probe;

import core.memory : GC;
import core.volatile : volatileLoad;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    appendSegmentPairNodingEvents,
    compareExactOverlayPointsAlongSegmentEqualPreferred,
    exactOverlayPointsEqual,
    seedExactEdgeEvents,
    sortUniqueExactEdgeEventsEqualPreferred;
import geo.point : Point2;
import geo.segment : Segment2;

import std.algorithm.sorting : sort;
import std.conv : to;
import std.datetime.stopwatch : StopWatch;
import std.exception : enforce;
import std.stdio : writefln;

__gshared ulong benchmarkSink;

private struct Fixture(T)
{
    string name;
    Segment2!T[2] queries;
    Segment2!T[] edges;
    ExactOverlayPoint[][2] rawEvents;
    ExactOverlayPoint[] workEvents;
    size_t[] indices;
    size_t uniqueCount;
}

private ulong eventFingerprint(
    ref const ExactOverlayPoint event
)
    pure nothrow @safe @nogc
{
    enum size_t xLast = event.xNumerator.magnitude.limb.length - 1;
    enum size_t yLast = event.yNumerator.magnitude.limb.length - 1;
    enum size_t dLast = event.denominator.limb.length - 1;

    ulong result =
        cast(ulong)(event.xNumerator.sign + 2);

    result =
        result * 1_000_003UL +
        event.xNumerator.magnitude.limb[0];

    result =
        result * 1_000_003UL +
        event.xNumerator.magnitude.limb[xLast];

    result =
        result * 1_000_003UL +
        cast(ulong)(event.yNumerator.sign + 2);

    result =
        result * 1_000_003UL +
        event.yNumerator.magnitude.limb[0];

    result =
        result * 1_000_003UL +
        event.yNumerator.magnitude.limb[yLast];

    result =
        result * 1_000_003UL +
        event.denominator.limb[0];

    result =
        result * 1_000_003UL +
        event.denominator.limb[dLast];

    return result;
}

private ulong eventsFingerprint(
    scope const(ExactOverlayPoint)[] events
)
    pure nothrow @safe @nogc
{
    if (events.length == 0)
        return 0;

    ulong result =
        cast(ulong) events.length;

    const size_t middle =
        events.length / 2;

    result =
        result * 1_000_003UL +
        eventFingerprint(events[0]);

    result =
        result * 1_000_003UL +
        eventFingerprint(events[middle]);

    result =
        result * 1_000_003UL +
        eventFingerprint(events[$ - 1]);

    return result;
}

private void siftDownIndicesEqualPreferred(T)(
    Segment2!T source,
    scope const(ExactOverlayPoint)[] events,
    scope size_t[] indices,
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

        size_t largest =
            root;

        if (
            compareExactOverlayPointsAlongSegmentEqualPreferred(
                source,
                events[indices[largest]],
                events[indices[left]]
            ) < 0
        )
        {
            largest =
                left;
        }

        const size_t right =
            left + 1;

        if (
            right < end &&
            compareExactOverlayPointsAlongSegmentEqualPreferred(
                source,
                events[indices[largest]],
                events[indices[right]]
            ) < 0
        )
        {
            largest =
                right;
        }

        if (largest == root)
            return;

        const size_t temporary =
            indices[root];

        indices[root] =
            indices[largest];

        indices[largest] =
            temporary;

        root =
            largest;
    }
}

private size_t sortUniqueByIndex(T)(
    Segment2!T source,
    scope const(ExactOverlayPoint)[] input,
    scope size_t[] indices,
    scope ExactOverlayPoint[] output
)
    pure nothrow @safe @nogc
{
    assert(indices.length >= input.length);
    assert(output.length >= input.length);

    foreach (i; 0 .. input.length)
        indices[i] = i;

    auto order =
        indices[0 .. input.length];

    size_t start =
        order.length / 2;

    while (start > 0)
    {
        --start;

        siftDownIndicesEqualPreferred(
            source,
            input,
            order,
            start,
            order.length
        );
    }

    size_t end =
        order.length;

    while (end > 1)
    {
        --end;

        const size_t temporary =
            order[0];

        order[0] =
            order[end];

        order[end] =
            temporary;

        siftDownIndicesEqualPreferred(
            source,
            input,
            order,
            0,
            end
        );
    }

    if (order.length == 0)
        return 0;

    size_t write = 0;
    size_t previousInputIndex = size_t.max;

    foreach (inputIndex; order)
    {
        if (
            previousInputIndex == size_t.max ||
            !exactOverlayPointsEqual(
                input[previousInputIndex],
                input[inputIndex]
            )
        )
        {
            output[write] =
                input[inputIndex];

            ++write;

            previousInputIndex =
                inputIndex;
        }
    }

    return write;
}

private Fixture!T denseFixture(T)(
    size_t teeth
)
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

    ring ~=
        P(0, 4);

    Fixture!T result;
    result.name =
        "dense-" ~ teeth.to!string;

    const S query =
        S(
            P(-1, 2),
            P(cast(T)(right + 1), 2)
        );

    result.queries = [
        query,
        S(query.b, query.a),
    ];

    result.edges =
        new S[
            ring.length
        ];

    foreach (i; 0 .. ring.length)
    {
        result.edges[i] =
            S(
                ring[i],
                ring[(i + 1) % ring.length]
            );
    }

    size_t maximumRawCount;

    foreach (direction; 0 .. 2)
    {
        auto raw =
            new ExactOverlayPoint[
                2 + 2 * result.edges.length
            ];

        size_t count;

        enforce(
            seedExactEdgeEvents(
                result.queries[direction],
                raw[],
                count
            ),
            "seedExactEdgeEvents failed"
        );

        foreach (edge; result.edges)
        {
            ExactOverlayPoint[2] ignored;
            size_t ignoredCount;

            enforce(
                appendSegmentPairNodingEvents(
                    result.queries[direction],
                    edge,
                    raw[],
                    count,
                    ignored[],
                    ignoredCount
                ),
                "appendSegmentPairNodingEvents failed"
            );
        }

        raw.length =
            count;

        result.rawEvents[direction] =
            raw;

        if (count > maximumRawCount)
            maximumRawCount = count;
    }

    result.workEvents =
        new ExactOverlayPoint[
            maximumRawCount
        ];

    result.indices =
        new size_t[
            maximumRawCount
        ];

    auto expected =
        result.rawEvents[0].dup;

    const size_t expectedCount =
        sortUniqueExactEdgeEventsEqualPreferred(
            result.queries[0],
            expected[]
        );

    const size_t indexCount =
        sortUniqueByIndex(
            result.queries[0],
            result.rawEvents[0],
            result.indices[],
            result.workEvents[]
        );

    enforce(
        indexCount == expectedCount,
        "index-sort unique count mismatch"
    );

    foreach (i; 0 .. expectedCount)
    {
        enforce(
            exactOverlayPointsEqual(
                expected[i],
                result.workEvents[i]
            ),
            "index-sort event mismatch"
        );
    }

    result.uniqueCount =
        expectedCount;

    return result;
}

pragma(inline, false)
private ulong copyReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const raw =
        fixture.rawEvents[direction];

    fixture.workEvents[0 .. raw.length] =
        raw[];

    return
        eventsFingerprint(
            fixture.workEvents[0 .. raw.length]
        );
}

pragma(inline, false)
private ulong carrierSortReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const raw =
        fixture.rawEvents[direction];

    fixture.workEvents[0 .. raw.length] =
        raw[];

    const size_t count =
        sortUniqueExactEdgeEventsEqualPreferred(
            fixture.queries[direction],
            fixture.workEvents[0 .. raw.length]
        );

    return
        eventsFingerprint(
            fixture.workEvents[0 .. count]
        );
}

pragma(inline, false)
private ulong indexSortReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const raw =
        fixture.rawEvents[direction];

    const size_t count =
        sortUniqueByIndex(
            fixture.queries[direction],
            raw,
            fixture.indices[],
            fixture.workEvents[]
        );

    return
        eventsFingerprint(
            fixture.workEvents[0 .. count]
        );
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
        new double[
            rounds
        ];

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
        timings[
            timings.length / 2
        ];

    writefln(
        "summary,%s,%s,%s,%.3f,%s,%s,%s",
        T.stringof,
        fixture.name,
        operationName,
        median,
        fixture.rawEvents[0].length,
        fixture.uniqueCount,
        ExactOverlayPoint.sizeof
    );

    benchmarkSink =
        sink;

    return
        median;
}

private void runType(T)(
    size_t rounds,
    long targetMilliseconds
)
{
    foreach (teeth; [4, 16, 64])
    {
        auto fixture =
            denseFixture!T(
                teeth
            );

        const double copyMedian =
            measure!(
                copyReplay
            )(
                fixture,
                "copy",
                rounds,
                targetMilliseconds
            );

        const double carrierMedian =
            measure!(
                carrierSortReplay
            )(
                fixture,
                "carrier-sort",
                rounds,
                targetMilliseconds
            );

        const double indexMedian =
            measure!(
                indexSortReplay
            )(
                fixture,
                "index-sort",
                rounds,
                targetMilliseconds
            );

        writefln(
            "derived,%s,%s,%.3f,%.3f,%.3f,%.6f",
            T.stringof,
            fixture.name,
            carrierMedian - copyMedian,
            indexMedian - copyMedian,
            carrierMedian - indexMedian,
            carrierMedian / indexMedian
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: dense_event_index_sort_probe <rounds> <target-ms>"
    );

    const size_t rounds =
        args[1].to!size_t;

    const long targetMilliseconds =
        args[2].to!long;

    writefln(
        "sizeof,ExactOverlayPoint,%s",
        ExactOverlayPoint.sizeof
    );

    runType!int(
        rounds,
        targetMilliseconds
    );

    runType!long(
        rounds,
        targetMilliseconds
    );

    runType!float(
        rounds,
        targetMilliseconds
    );

    runType!double(
        rounds,
        targetMilliseconds
    );

    writefln(
        "sink,%s",
        benchmarkSink
    );
}
