module geo.internal.exact_event_active_span_probe;

import core.memory : GC;
import core.volatile : volatileLoad;

import geo.internal.intersection_exact :
    ExactProperIntersection,
    properIntersectionExactKnownCrossing;
import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    compareExactOverlayPointsAlongSegmentEqualPreferred,
    exactOverlayPoint,
    exactOverlayPointsEqual;
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

private struct EventMeta
{
    ushort xEnd;
    ushort yEnd;
    ushort dEnd;
}

private struct Fixture(T)
{
    string name;
    Segment2!T[2] queries;
    Segment2!T[] edges;
    Segment2!T[] properEdges;
    ExactProperIntersection[][2] precomputed;
    ExactOverlayPoint[][2] events;
    EventMeta[][2] metadata;
    size_t[] indices;
}

private size_t firstNonZero(scope const(uint)[] limbs)
    pure nothrow @safe @nogc
{
    foreach (i, value; limbs)
    {
        if (value != 0)
            return i;
    }

    return limbs.length;
}

private size_t pastLastNonZero(scope const(uint)[] limbs)
    pure nothrow @safe @nogc
{
    size_t i = limbs.length;

    while (i != 0)
    {
        if (limbs[i - 1] != 0)
            return i;

        --i;
    }

    return 0;
}

private EventMeta eventMeta(ref const ExactOverlayPoint event)
    pure nothrow @safe @nogc
{
    const size_t xEnd =
        pastLastNonZero(event.xNumerator.magnitude.limb[]);

    const size_t yEnd =
        pastLastNonZero(event.yNumerator.magnitude.limb[]);

    const size_t dEnd =
        pastLastNonZero(event.denominator.limb[]);

    assert(xEnd <= ushort.max);
    assert(yEnd <= ushort.max);
    assert(dEnd <= ushort.max);

    return EventMeta(
        cast(ushort) xEnd,
        cast(ushort) yEnd,
        cast(ushort) dEnd
    );
}

private bool equalUnsignedBounded(
    scope const(uint)[] lhs,
    size_t lhsEnd,
    scope const(uint)[] rhs,
    size_t rhsEnd
)
    pure nothrow @safe @nogc
{
    if (lhsEnd != rhsEnd)
        return false;

    foreach (i; 0 .. lhsEnd)
    {
        if (lhs[i] != rhs[i])
            return false;
    }

    return true;
}

private int compareUnsignedBounded(
    scope const(uint)[] lhs,
    size_t lhsEnd,
    scope const(uint)[] rhs,
    size_t rhsEnd
)
    pure nothrow @safe @nogc
{
    if (lhsEnd < rhsEnd)
        return -1;

    if (lhsEnd > rhsEnd)
        return 1;

    size_t i = lhsEnd;

    while (i != 0)
    {
        --i;

        if (lhs[i] < rhs[i])
            return -1;

        if (lhs[i] > rhs[i])
            return 1;
    }

    return 0;
}

private int compareCanonicalEqualDenominatorBounded(
    ref const ExactOverlayPoint lhs,
    EventMeta lhsMeta,
    ref const ExactOverlayPoint rhs,
    EventMeta rhsMeta,
    bool useX
)
    pure nothrow @safe @nogc
{
    const bool equalDenominator =
        equalUnsignedBounded(
            lhs.denominator.limb[],
            lhsMeta.dEnd,
            rhs.denominator.limb[],
            rhsMeta.dEnd
        );

    if (!equalDenominator)
        return 2;

    const int lhsSign =
        useX
            ? lhs.xNumerator.sign
            : lhs.yNumerator.sign;

    const int rhsSign =
        useX
            ? rhs.xNumerator.sign
            : rhs.yNumerator.sign;

    if (lhsSign < rhsSign)
        return -1;

    if (lhsSign > rhsSign)
        return 1;

    if (lhsSign == 0)
        return 0;

    const auto lhsLimbs =
        useX
            ? lhs.xNumerator.magnitude.limb[]
            : lhs.yNumerator.magnitude.limb[];

    const auto rhsLimbs =
        useX
            ? rhs.xNumerator.magnitude.limb[]
            : rhs.yNumerator.magnitude.limb[];

    const size_t lhsEnd =
        useX
            ? lhsMeta.xEnd
            : lhsMeta.yEnd;

    const size_t rhsEnd =
        useX
            ? rhsMeta.xEnd
            : rhsMeta.yEnd;

    const int magnitudeComparison =
        compareUnsignedBounded(
            lhsLimbs,
            lhsEnd,
            rhsLimbs,
            rhsEnd
        );

    return
        lhsSign > 0
            ? magnitudeComparison
            : -magnitudeComparison;
}

private int compareBounded(T)(
    Segment2!T source,
    ref const ExactOverlayPoint lhs,
    EventMeta lhsMeta,
    ref const ExactOverlayPoint rhs,
    EventMeta rhsMeta
)
    pure nothrow @safe @nogc
{
    const bool useX =
        source.a.x != source.b.x;

    const int bounded =
        compareCanonicalEqualDenominatorBounded(
            lhs,
            lhsMeta,
            rhs,
            rhsMeta,
            useX
        );

    if (bounded == 2)
    {
        return
            compareExactOverlayPointsAlongSegmentEqualPreferred(
                source,
                lhs,
                rhs
            );
    }

    if (useX)
    {
        return
            source.a.x < source.b.x
                ? bounded
                : -bounded;
    }

    return
        source.a.y < source.b.y
            ? bounded
            : -bounded;
}

private void siftDownCurrent(T)(
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
        const size_t left = root * 2 + 1;

        if (left >= end)
            return;

        size_t largest = root;

        if (
            compareExactOverlayPointsAlongSegmentEqualPreferred(
                source,
                events[indices[largest]],
                events[indices[left]]
            ) < 0
        )
        {
            largest = left;
        }

        const size_t right = left + 1;

        if (
            right < end &&
            compareExactOverlayPointsAlongSegmentEqualPreferred(
                source,
                events[indices[largest]],
                events[indices[right]]
            ) < 0
        )
        {
            largest = right;
        }

        if (largest == root)
            return;

        const size_t temporary = indices[root];
        indices[root] = indices[largest];
        indices[largest] = temporary;
        root = largest;
    }
}

private void siftDownBounded(T)(
    Segment2!T source,
    scope const(ExactOverlayPoint)[] events,
    scope const(EventMeta)[] metadata,
    scope size_t[] indices,
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
            compareBounded(
                source,
                events[indices[largest]],
                metadata[indices[largest]],
                events[indices[left]],
                metadata[indices[left]]
            ) < 0
        )
        {
            largest = left;
        }

        const size_t right = left + 1;

        if (
            right < end &&
            compareBounded(
                source,
                events[indices[largest]],
                metadata[indices[largest]],
                events[indices[right]],
                metadata[indices[right]]
            ) < 0
        )
        {
            largest = right;
        }

        if (largest == root)
            return;

        const size_t temporary = indices[root];
        indices[root] = indices[largest];
        indices[largest] = temporary;
        root = largest;
    }
}

private void sortCurrent(T)(
    Segment2!T source,
    scope const(ExactOverlayPoint)[] events,
    scope size_t[] indices
)
    pure nothrow @safe @nogc
{
    assert(indices.length >= events.length);

    auto order = indices[0 .. events.length];

    foreach (i; 0 .. order.length)
        order[i] = i;

    size_t start = order.length / 2;

    while (start > 0)
    {
        --start;
        siftDownCurrent(
            source,
            events,
            order,
            start,
            order.length
        );
    }

    size_t end = order.length;

    while (end > 1)
    {
        --end;

        const size_t temporary = order[0];
        order[0] = order[end];
        order[end] = temporary;

        siftDownCurrent(
            source,
            events,
            order,
            0,
            end
        );
    }
}

private void sortBounded(T)(
    Segment2!T source,
    scope const(ExactOverlayPoint)[] events,
    scope const(EventMeta)[] metadata,
    scope size_t[] indices
)
    pure nothrow @safe @nogc
{
    assert(indices.length >= events.length);
    assert(metadata.length >= events.length);

    auto order = indices[0 .. events.length];

    foreach (i; 0 .. order.length)
        order[i] = i;

    size_t start = order.length / 2;

    while (start > 0)
    {
        --start;
        siftDownBounded(
            source,
            events,
            metadata,
            order,
            start,
            order.length
        );
    }

    size_t end = order.length;

    while (end > 1)
    {
        --end;

        const size_t temporary = order[0];
        order[0] = order[end];
        order[end] = temporary;

        siftDownBounded(
            source,
            events,
            metadata,
            order,
            0,
            end
        );
    }
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

private ulong hashOrder(
    scope const(size_t)[] indices
)
    pure nothrow @safe @nogc
{
    ulong result = indices.length;

    foreach (index; indices)
        result = result * 1_000_003UL + index;

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

    result.edges =
        new S[ring.length];

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
            result.properEdges ~= result.edges[i];
        }
    }

    enforce(
        result.properEdges.length == 2 * teeth,
        "unexpected proper-crossing count"
    );

    size_t maximumEvents;

    foreach (direction; 0 .. 2)
    {
        const currentQuery =
            result.queries[direction];

        result.precomputed[direction] =
            new ExactProperIntersection[
                result.properEdges.length
            ];

        auto events =
            new ExactOverlayPoint[
                result.properEdges.length + 2
            ];

        events[0] =
            exactOverlayPoint(
                currentQuery.a
            );

        events[1] =
            exactOverlayPoint(
                currentQuery.b
            );

        foreach (i, edge; result.properEdges)
        {
            properIntersectionExactKnownCrossing(
                currentQuery,
                edge,
                result.precomputed[direction][i]
            );

            events[i + 2] =
                exactOverlayPoint(
                    result.precomputed[direction][i]
                );
        }

        result.events[direction] =
            events;

        auto metadata =
            new EventMeta[
                events.length
            ];

        foreach (i, ref event; events)
            metadata[i] = eventMeta(event);

        result.metadata[direction] =
            metadata;

        if (events.length > maximumEvents)
            maximumEvents = events.length;
    }

    result.indices =
        new size_t[maximumEvents];

    foreach (direction; 0 .. 2)
    {
        auto currentOrder =
            new size_t[
                result.events[direction].length
            ];

        auto boundedOrder =
            new size_t[
                result.events[direction].length
            ];

        sortCurrent(
            result.queries[direction],
            result.events[direction],
            currentOrder[]
        );

        sortBounded(
            result.queries[direction],
            result.events[direction],
            result.metadata[direction],
            boundedOrder[]
        );

        enforce(
            currentOrder == boundedOrder,
            "bounded comparator order mismatch"
        );

        foreach (i; 1 .. currentOrder.length)
        {
            const auto previous =
                result.events[direction][
                    currentOrder[i - 1]
                ];

            const auto current =
                result.events[direction][
                    currentOrder[i]
                ];

            enforce(
                !exactOverlayPointsEqual(
                    previous,
                    current
                ),
                "unexpected duplicate dense event"
            );
        }
    }

    return result;
}

private void printSpanClass(
    T
)(
    string name,
    string kind,
    scope const(ExactOverlayPoint)[] events
)
{
    enforce(events.length != 0, "empty span class");

    size_t xFirstMin = size_t.max;
    size_t xEndMax;
    size_t yFirstMin = size_t.max;
    size_t yEndMax;
    size_t dFirstMin = size_t.max;
    size_t dEndMax;

    ulong xWidthSum;
    ulong yWidthSum;
    ulong dWidthSum;

    foreach (ref event; events)
    {
        const size_t xFirst =
            firstNonZero(
                event.xNumerator.magnitude.limb[]
            );

        const size_t xEnd =
            pastLastNonZero(
                event.xNumerator.magnitude.limb[]
            );

        const size_t yFirst =
            firstNonZero(
                event.yNumerator.magnitude.limb[]
            );

        const size_t yEnd =
            pastLastNonZero(
                event.yNumerator.magnitude.limb[]
            );

        const size_t dFirst =
            firstNonZero(
                event.denominator.limb[]
            );

        const size_t dEnd =
            pastLastNonZero(
                event.denominator.limb[]
            );

        if (xEnd != 0)
        {
            xFirstMin = xFirst < xFirstMin ? xFirst : xFirstMin;
            xEndMax = xEnd > xEndMax ? xEnd : xEndMax;
            xWidthSum += xEnd - xFirst;
        }

        if (yEnd != 0)
        {
            yFirstMin = yFirst < yFirstMin ? yFirst : yFirstMin;
            yEndMax = yEnd > yEndMax ? yEnd : yEndMax;
            yWidthSum += yEnd - yFirst;
        }

        enforce(dEnd != 0, "zero denominator");

        dFirstMin = dFirst < dFirstMin ? dFirst : dFirstMin;
        dEndMax = dEnd > dEndMax ? dEnd : dEndMax;
        dWidthSum += dEnd - dFirst;
    }

    if (xFirstMin == size_t.max)
        xFirstMin = 0;

    if (yFirstMin == size_t.max)
        yFirstMin = 0;

    writefln(
        "span,%s,%s,%s,%s,%s,%s,%.3f,%s,%s,%.3f,%s,%s,%.3f",
        T.stringof,
        name,
        kind,
        events.length,
        xFirstMin,
        xEndMax,
        cast(double) xWidthSum / events.length,
        yFirstMin,
        yEndMax,
        cast(double) yWidthSum / events.length,
        dFirstMin,
        dEndMax,
        cast(double) dWidthSum / events.length
    );
}

private void printSpans(T)(
    ref Fixture!T fixture
)
{
    foreach (direction; 0 .. 2)
    {
        const events =
            fixture.events[direction];

        printSpanClass!T(
            fixture.name,
            direction == 0
                ? "all-forward"
                : "all-reverse",
            events
        );

        printSpanClass!T(
            fixture.name,
            direction == 0
                ? "constructed-forward"
                : "constructed-reverse",
            events[2 .. $]
        );
    }
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
private ulong knownConstructionReplay(T)(
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
private ulong currentSortReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const events =
        fixture.events[direction];

    sortCurrent(
        fixture.queries[direction],
        events,
        fixture.indices[]
    );

    return
        hashOrder(
            fixture.indices[
                0 .. events.length
            ]
        );
}

pragma(inline, false)
private ulong boundedSortReplay(T)(
    ref Fixture!T fixture,
    size_t iteration
)
    @nogc
{
    const size_t direction =
        volatileLoad(&iteration) & 1;

    const events =
        fixture.events[direction];

    sortBounded(
        fixture.queries[direction],
        events,
        fixture.metadata[direction],
        fixture.indices[]
    );

    return
        hashOrder(
            fixture.indices[
                0 .. events.length
            ]
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
        "summary,%s,%s,%s,%.3f,%s,%s",
        T.stringof,
        fixture.name,
        operationName,
        median,
        fixture.events[0].length,
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

        printSpans(fixture);

        const double carrierRead =
            measure!carrierReadReplay(
                fixture,
                "carrier-read",
                rounds,
                targetMilliseconds
            );

        const double construction =
            measure!knownConstructionReplay(
                fixture,
                "known-construction",
                rounds,
                targetMilliseconds
            );

        const double currentSort =
            measure!currentSortReplay(
                fixture,
                "current-index-sort",
                rounds,
                targetMilliseconds
            );

        const double boundedSort =
            measure!boundedSortReplay(
                fixture,
                "bounded-index-sort",
                rounds,
                targetMilliseconds
            );

        writefln(
            "derived,%s,%s,%.3f,%.3f,%.3f,%.3f,%.6f",
            T.stringof,
            fixture.name,
            construction - carrierRead,
            (construction - carrierRead) /
                fixture.properEdges.length,
            currentSort,
            boundedSort,
            currentSort / boundedSort
        );
    }
}

void main(string[] args)
{
    enforce(
        args.length == 3,
        "usage: exact_event_active_span_probe <rounds> <target-ms>"
    );

    const size_t rounds =
        args[1].to!size_t;

    const long targetMilliseconds =
        args[2].to!long;

    writefln(
        "sizeof,ExactOverlayPoint,%s",
        ExactOverlayPoint.sizeof
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
