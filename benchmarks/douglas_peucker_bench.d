module douglas_peucker_bench;

import geo;

import std.algorithm.sorting : sort;
import std.datetime.stopwatch : StopWatch;
import std.format : format;
import std.math : sin;
import std.stdio : stderr, writefln, writeln;


enum sampleCount = 7;

__gshared size_t benchmarkSink;


struct OwnedPolyline(T)
{
    Point2!T[] points;
    PolylineView!T view;
}


OwnedPolyline!T ownedPolyline(T)(Point2!T[] points)
{
    OwnedPolyline!T result;

    result.points = points;
    result.view = PolylineView!T(
        result.points[]
    );

    return result;
}


OwnedPolyline!double makeStraight(
    size_t pointCount,
    double shift
)
{
    auto points =
        new Point2!double[pointCount];

    foreach (i; 0 .. pointCount)
    {
        points[i] =
            Point2!double(
                cast(double) i + shift,
                shift
            );
    }

    return ownedPolyline(points);
}


OwnedPolyline!double makeSine(
    size_t pointCount,
    double shift
)
{
    auto points =
        new Point2!double[pointCount];

    foreach (i; 0 .. pointCount)
    {
        const double x =
            cast(double) i;

        points[i] =
            Point2!double(
                x + shift,
                sin(x * 0.15) + shift
            );
    }

    return ownedPolyline(points);
}


OwnedPolyline!double makeParabola(
    size_t pointCount,
    double shift
)
{
    auto points =
        new Point2!double[pointCount];

    foreach (i; 0 .. pointCount)
    {
        const double x =
            cast(double) i;

        points[i] =
            Point2!double(
                x + shift,
                x * x + shift
            );
    }

    return ownedPolyline(points);
}


OwnedPolyline!double makeZigzag(
    size_t pointCount,
    double shift
)
{
    auto points =
        new Point2!double[pointCount];

    foreach (i; 0 .. pointCount)
    {
        const double y =
            (i & 1) == 0
                ? -1.0
                : 1.0;

        points[i] =
            Point2!double(
                cast(double) i + shift,
                y + shift
            );
    }

    return ownedPolyline(points);
}


OwnedPolyline!long makeLongZigzag(
    size_t pointCount,
    long shift
)
{
    auto points =
        new Point2!long[pointCount];

    foreach (i; 0 .. pointCount)
    {
        const long y =
            (i & 1) == 0
                ? -1L
                : 1L;

        points[i] =
            Point2!long(
                cast(long) i + shift,
                y + shift
            );
    }

    return ownedPolyline(points);
}


double median(double[sampleCount] samples)
{
    sort(samples[]);

    return samples[sampleCount / 2];
}


bool verifyCase(T)(
    ref OwnedPolyline!T first,
    ref OwnedPolyline!T second,
    MetricScalar!T tolerance,
    size_t expectedWritten,
    bool requireIntermediateRetention,
    out size_t retained
)
{
    const size_t pointCount =
        first.points.length;

    if (second.points.length != pointCount)
        return false;

    auto destination =
        new Point2!T[pointCount];

    auto workspace =
        new size_t[
            douglasPeuckerWorkspaceSize(
                pointCount
            )
        ];

    size_t firstWritten;

    if (
        !trySimplifyDouglasPeuckerInto(
            first.view,
            tolerance,
            destination[],
            workspace[],
            firstWritten
        )
    )
    {
        return false;
    }

    size_t secondWritten;

    if (
        !trySimplifyDouglasPeuckerInto(
            second.view,
            tolerance,
            destination[],
            workspace[],
            secondWritten
        )
    )
    {
        return false;
    }

    if (firstWritten != secondWritten)
        return false;

    if (
        expectedWritten != 0 &&
        firstWritten != expectedWritten
    )
    {
        return false;
    }

    if (
        requireIntermediateRetention &&
        (
            firstWritten <= 2 ||
            firstWritten >= pointCount
        )
    )
    {
        return false;
    }

    retained = firstWritten;

    return true;
}


double benchmarkCase(T)(
    string label,
    ref OwnedPolyline!T first,
    ref OwnedPolyline!T second,
    MetricScalar!T tolerance,
    size_t iterations,
    size_t expectedWritten,
    bool requireIntermediateRetention
)
{
    const size_t pointCount =
        first.points.length;

    size_t retained;

    if (
        !verifyCase!T(
            first,
            second,
            tolerance,
            expectedWritten,
            requireIntermediateRetention,
            retained
        )
    )
    {
        stderr.writefln(
            "verification failed: %s",
            label
        );

        return double.nan;
    }

    auto destination =
        new Point2!T[pointCount];

    auto workspace =
        new size_t[
            douglasPeuckerWorkspaceSize(
                pointCount
            )
        ];

    double[sampleCount] samples;

    foreach (sample; 0 .. sampleCount)
    {
        size_t localSink = 0;

        StopWatch stopwatch;
        stopwatch.start();

        foreach (iteration; 0 .. iterations)
        {
            size_t written;
            bool success;

            if ((iteration & 1) == 0)
            {
                success =
                    trySimplifyDouglasPeuckerInto(
                        first.view,
                        tolerance,
                        destination[],
                        workspace[],
                        written
                    );

                if (
                    success &&
                    written != 0
                )
                {
                    localSink ^=
                        written * 33 +
                        cast(size_t)(
                            destination[written - 1] ==
                            first.points[$ - 1]
                        );
                }
            }
            else
            {
                success =
                    trySimplifyDouglasPeuckerInto(
                        second.view,
                        tolerance,
                        destination[],
                        workspace[],
                        written
                    );

                if (
                    success &&
                    written != 0
                )
                {
                    localSink ^=
                        written * 33 +
                        cast(size_t)(
                            destination[written - 1] ==
                            second.points[$ - 1]
                        );
                }
            }

            if (!success)
            {
                stderr.writefln(
                    "timed call failed: %s",
                    label
                );

                return double.nan;
            }
        }

        stopwatch.stop();

        benchmarkSink ^=
            localSink;

        samples[sample] =
            cast(double)
                stopwatch.peek.total!"nsecs" /
            cast(double)
                iterations;
    }

    const double nsPerOperation =
        median(samples);

    writefln(
        "%-36s %12.2f ns/op  %8.3f ns/input-point  retained=%s/%s",
        label,
        nsPerOperation,
        nsPerOperation /
            cast(double) pointCount,
        retained,
        pointCount
    );

    return nsPerOperation;
}


size_t straightIterations(size_t pointCount)
{
    final switch (pointCount)
    {
        case 64:
            return 100_000;

        case 256:
            return 30_000;

        case 1024:
            return 8_000;
    }
}


size_t sineIterations(size_t pointCount)
{
    final switch (pointCount)
    {
        case 64:
            return 30_000;

        case 256:
            return 4_000;

        case 1024:
            return 300;
    }
}


size_t parabolaIterations(size_t pointCount)
{
    final switch (pointCount)
    {
        case 64:
            return 30_000;

        case 256:
            return 4_000;

        case 1024:
            return 500;
    }
}


size_t zigzagIterations(size_t pointCount)
{
    final switch (pointCount)
    {
        case 64:
            return 8_000;

        case 256:
            return 300;

        case 1024:
            return 12;
    }
}


void main()
{
    const size_t[] sizes = [
        64,
        256,
        1024
    ];

    writeln(
        "Case verification is performed before each timed workload."
    );

    writeln;
    writeln(
        "Straight polyline: complete reduction to endpoints"
    );

    foreach (pointCount; sizes)
    {
        auto first =
            makeStraight(
                pointCount,
                0.0
            );

        auto second =
            makeStraight(
                pointCount,
                0.125
            );

        benchmarkCase!double(
            format(
                "straight n=%s",
                pointCount
            ),
            first,
            second,
            0.0,
            straightIterations(pointCount),
            2,
            false
        );
    }


    writeln;
    writeln(
        "Sine polyline: intermediate retained-point ratio"
    );

    foreach (pointCount; sizes)
    {
        auto first =
            makeSine(
                pointCount,
                0.0
            );

        auto second =
            makeSine(
                pointCount,
                0.125
            );

        benchmarkCase!double(
            format(
                "sine n=%s tol=0.1",
                pointCount
            ),
            first,
            second,
            0.1,
            sineIterations(pointCount),
            0,
            true
        );
    }


    writeln;
    writeln(
        "Parabola: all points retained, comparatively balanced splits"
    );

    foreach (pointCount; sizes)
    {
        auto first =
            makeParabola(
                pointCount,
                0.0
            );

        auto second =
            makeParabola(
                pointCount,
                0.125
            );

        benchmarkCase!double(
            format(
                "parabola n=%s tol=0",
                pointCount
            ),
            first,
            second,
            0.0,
            parabolaIterations(pointCount),
            pointCount,
            false
        );
    }


    writeln;
    writeln(
        "Zigzag: all points retained, adversarial split-balance candidate"
    );

    foreach (pointCount; sizes)
    {
        auto first =
            makeZigzag(
                pointCount,
                0.0
            );

        auto second =
            makeZigzag(
                pointCount,
                0.125
            );

        benchmarkCase!double(
            format(
                "zigzag n=%s tol=0",
                pointCount
            ),
            first,
            second,
            0.0,
            zigzagIterations(pointCount),
            pointCount,
            false
        );
    }


    writeln;
    writeln(
        "Integral scalar-domain control"
    );

    {
        enum pointCount = 256;

        auto first =
            makeLongZigzag(
                pointCount,
                0
            );

        auto second =
            makeLongZigzag(
                pointCount,
                7
            );

        benchmarkCase!long(
            "long zigzag n=256 tol=0",
            first,
            second,
            cast(MetricScalar!long) 0,
            300,
            pointCount,
            false
        );
    }


    writeln;

    writefln(
        "benchmarkSink=%s",
        benchmarkSink
    );
}
