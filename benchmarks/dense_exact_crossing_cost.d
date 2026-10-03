module geo.internal.dense_exact_crossing_cost_probe;

import core.memory : GC;
import core.volatile : volatileLoad;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind;
import geo.internal.intersection_exact :
    ExactProperIntersection,
    tryProperIntersectionExact;
import geo.internal.polygon_union_exact :
    ExactOverlayPoint;
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
    Segment2!T[] properEdges;
    ExactProperIntersection[][2] precomputed;
}

private Fixture!T denseFixture(T)(size_t teeth)
{
    alias P = Point2!T;
    alias S = Segment2!T;

    const int right = cast(int)(4 * teeth - 2);

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

        if (
            segmentContactKind(
                query,
                result.edges[i]
            ) == SegmentContactKind.properCrossing
        )
        {
            result.properEdges ~=
                result.edges[i];
        }
    }

    enforce(
        result.properEdges.length ==
        2 * teeth,
        "unexpected proper-crossing count"
    );

    foreach (direction; 0 .. 2)
    {
        result.precomputed[direction] =
            new ExactProperIntersection[
                result.properEdges.length
            ];

        foreach (i, edge; result.properEdges)
        {
            enforce(
                tryProperIntersectionExact(
                    result.queries[direction],
                    edge,
                    result.precomputed[direction][i]
                ),
                "exact-crossing preflight failed"
            );
        }
    }

    return result;
}

pragma(inline, false)
private ulong hashExact(
    ref const ExactProperIntersection exact
)
    nothrow @safe @nogc
{
    ulong result =
        cast(ulong)(
            exact.xNumerator.sign + 2
        );

    foreach (limb; exact.xNumerator.magnitude.limb)
        result = result * 1_000_003UL + limb;

    result =
        result * 1_000_003UL +
        cast(ulong)(
            exact.yNumerator.sign + 2
        );

    foreach (limb; exact.yNumerator.magnitude.limb)
        result = result * 1_000_003UL + limb;

    foreach (limb; exact.denominator.limb)
        result = result * 1_000_003UL + limb;

    return result;
}

pragma(inline, false)
private ulong exactConstructionReplay(T)(
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

        const bool found =
            tryProperIntersectionExact(
                query,
                edge,
                exact
            );

        result =
            result * 1_000_003UL +
            cast(ulong) found;

        result =
            result * 1_000_003UL +
            hashExact(exact);
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

    foreach (ref exact; fixture.precomputed[direction])
    {
        result =
            result * 1_000_003UL +
            hashExact(exact);
    }

    return result;
}

pragma(inline, false)
private ulong contactClassificationReplay(T)(
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

    foreach (edge; fixture.edges)
    {
        result =
            result * 1_000_003UL +
            cast(ulong)
                segmentContactKind(
                    query,
                    edge
                );
    }

    return result;
}

private void measure(alias operation, T)(
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

    const double perProper =
        fixture.properEdges.length == 0
            ? 0.0
            : median /
                fixture.properEdges.length;

    writefln(
        "summary,%s,%s,%s,%.3f,%.3f,%s,%s",
        T.stringof,
        fixture.name,
        operationName,
        median,
        perProper,
        fixture.edges.length,
        fixture.properEdges.length
    );

    benchmarkSink = sink;
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

        measure!(
            carrierReadReplay
        )(
            fixture,
            "carrier-read",
            rounds,
            targetMilliseconds
        );

        measure!(
            exactConstructionReplay
        )(
            fixture,
            "exact-construction",
            rounds,
            targetMilliseconds
        );

        measure!(
            contactClassificationReplay
        )(
            fixture,
            "contact-classification",
            rounds,
            targetMilliseconds
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: dense_exact_crossing_cost <rounds> <target-ms>"
    );

    const size_t rounds =
        args[1].to!size_t;

    const long targetMilliseconds =
        args[2].to!long;

    writefln(
        "sizeof,ExactProperIntersection,%s",
        ExactProperIntersection.sizeof
    );

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
