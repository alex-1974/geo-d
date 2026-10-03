module geo.internal.dense_event_provenance_cost_probe;

import core.memory : GC;
import core.volatile : volatileLoad;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind;
import geo.internal.intersection_exact :
    ExactProperIntersection,
    tryProperIntersectionExact;
import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    appendSegmentPairNodingEvents,
    compareExactOverlayPointsAlongSegmentEqualPreferred,
    exactOverlayPoint,
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
    ExactOverlayPoint[][2] sortedEvents;
    ExactOverlayPoint[][2] properTargets;
    size_t[][2] directIndices;
}

private ulong eventFingerprint(
    ref const ExactOverlayPoint event
)
    pure nothrow @safe @nogc
{
    enum size_t xLast =
        event.xNumerator.magnitude.limb.length - 1;

    enum size_t yLast =
        event.yNumerator.magnitude.limb.length - 1;

    enum size_t dLast =
        event.denominator.limb.length - 1;

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

    return
        result;
}

private size_t findEvent(T)(
    Segment2!T query,
    scope const(ExactOverlayPoint)[] events,
    ref const ExactOverlayPoint target
)
    pure nothrow @safe @nogc
{
    size_t lower = 0;
    size_t upper =
        events.length;

    while (lower < upper)
    {
        const size_t middle =
            lower + (upper - lower) / 2;

        const int comparison =
            compareExactOverlayPointsAlongSegmentEqualPreferred(
                query,
                events[middle],
                target
            );

        if (comparison < 0)
            lower = middle + 1;
        else
            upper = middle;
    }

    if (
        lower < events.length &&
        exactOverlayPointsEqual(
            events[lower],
            target
        )
    )
    {
        return
            lower;
    }

    return
        size_t.max;
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

    foreach (direction; 0 .. 2)
    {
        auto events =
            new ExactOverlayPoint[
                2 + 2 * result.edges.length
            ];

        size_t eventCount;

        enforce(
            seedExactEdgeEvents(
                result.queries[direction],
                events[],
                eventCount
            ),
            "seedExactEdgeEvents failed"
        );

        ExactOverlayPoint[] targets;

        foreach (edge; result.edges)
        {
            ExactOverlayPoint[2] ignored;
            size_t ignoredCount;

            enforce(
                appendSegmentPairNodingEvents(
                    result.queries[direction],
                    edge,
                    events[],
                    eventCount,
                    ignored[],
                    ignoredCount
                ),
                "appendSegmentPairNodingEvents failed"
            );

            if (
                segmentContactKind(
                    result.queries[direction],
                    edge
                ) ==
                SegmentContactKind.properCrossing
            )
            {
                ExactProperIntersection exact;

                enforce(
                    tryProperIntersectionExact(
                        result.queries[direction],
                        edge,
                        exact
                    ),
                    "proper crossing preflight failed"
                );

                targets ~=
                    exactOverlayPoint(
                        exact
                    );
            }
        }

        events.length =
            eventCount;

        const size_t uniqueCount =
            sortUniqueExactEdgeEventsEqualPreferred(
                result.queries[direction],
                events[]
            );

        events.length =
            uniqueCount;

        result.sortedEvents[direction] =
            events;

        result.properTargets[direction] =
            targets;

        auto indices =
            new size_t[
                targets.length
            ];

        foreach (i, ref target; targets)
        {
            const size_t index =
                findEvent(
                    result.queries[direction],
                    events[],
                    target
                );

            enforce(
                index != size_t.max,
                "proper target not found"
            );

            indices[i] =
                index;
        }

        result.directIndices[direction] =
            indices;
    }

    enforce(
        result.properTargets[0].length ==
            2 * teeth,
        "unexpected proper-crossing count"
    );

    return
        result;
}

pragma(inline, false)
private ulong lookupReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const query =
        fixture.queries[direction];

    const events =
        fixture.sortedEvents[direction];

    const targets =
        fixture.properTargets[direction];

    ulong result = 1;

    foreach (ref target; targets)
    {
        const size_t index =
            findEvent(
                query,
                events,
                target
            );

        result =
            result * 1_000_003UL +
            index;

        result =
            result * 1_000_003UL +
            eventFingerprint(
                events[index]
            );
    }

    return
        result;
}

pragma(inline, false)
private ulong directIndexReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const events =
        fixture.sortedEvents[direction];

    const indices =
        fixture.directIndices[direction];

    ulong result = 1;

    foreach (index; indices)
    {
        result =
            result * 1_000_003UL +
            index;

        result =
            result * 1_000_003UL +
            eventFingerprint(
                events[index]
            );
    }

    return
        result;
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
        "summary,%s,%s,%s,%.3f,%s,%s",
        T.stringof,
        fixture.name,
        operationName,
        median,
        fixture.sortedEvents[0].length,
        fixture.properTargets[0].length
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

        const double directMedian =
            measure!(
                directIndexReplay
            )(
                fixture,
                "direct-index",
                rounds,
                targetMilliseconds
            );

        const double lookupMedian =
            measure!(
                lookupReplay
            )(
                fixture,
                "binary-lookup",
                rounds,
                targetMilliseconds
            );

        const double net =
            lookupMedian -
            directMedian;

        writefln(
            "derived,%s,%s,%.3f,%.3f,%.3f,%.3f",
            T.stringof,
            fixture.name,
            lookupMedian,
            directMedian,
            net,
            net /
                fixture.properTargets[0].length
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: dense_event_provenance_cost_probe <rounds> <target-ms>"
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
