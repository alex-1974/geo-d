module geo.internal.intersection_bench_adapter;

import geo.internal.intersection_exact :
    ExactProperIntersection,
    PreparedExactSegment,
    prepareExactSegment,
    properIntersectionExactKnownCrossingPreparedFirst;

import geo.point : Point2;
import geo.segment : Segment2;

struct PreparedIntersectionBenchInput
{
    PreparedExactSegment first;
    Segment2!double second;
}

PreparedIntersectionBenchInput prepareIntersectionBenchInput(
    Segment2!double first
)
    pure nothrow @safe @nogc
{
    return PreparedIntersectionBenchInput(
        prepareExactSegment(first),
        Segment2!double(
            Point2!double(0.0, 10.0),
            Point2!double(10.0, 0.0)
        )
    );
}

void runPreparedIntersectionBench(
    ref const PreparedIntersectionBenchInput input,
    out ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    properIntersectionExactKnownCrossingPreparedFirst(
        input.first,
        input.second,
        result
    );
}
