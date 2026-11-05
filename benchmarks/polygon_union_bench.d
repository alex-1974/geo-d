/*
 * Public-API benchmark for correctness-first polygon-union P1.
 *
 * The benchmark covers:
 *
 * - simple disjoint, overlapping, adjacent, and point-contact rectangles;
 * - a polygon-with-hole plus an island inside that hole;
 * - both integral and binary64 public input domains;
 * - increasing convex binary64 input sizes.
 *
 * Input geometry construction occurs before timing.
 *
 * polygonUnion() necessarily allocates exact-overlay workspace and immutable
 * result storage. Those allocations remain inside the timed public operation
 * and are therefore part of this P1 baseline.
 */
module polygon_union_bench;

import geo;

import std.algorithm.sorting :
    sort;

import std.datetime.stopwatch :
    StopWatch;

import std.math :
    PI,
    cos,
    sin;

import std.stdio :
    writefln,
    writeln;


enum size_t repetitions = 7;

__gshared ulong benchmarkSink;


private struct OwnedPolygon(T)
{
    Point2!T[][] points;
    LinearRing2View!T[] rings;
    Polygon2View!T view;
}


private struct UnionCase(T)
{
    OwnedPolygon!T first;
    OwnedPolygon!T second;

    size_t expectedComponents;
    size_t expectedHoles;
}


__gshared UnionCase!int[2] disjointIntCases;
__gshared UnionCase!int[2] overlapIntCases;
__gshared UnionCase!int[2] adjacentIntCases;
__gshared UnionCase!int[2] pointTouchIntCases;
__gshared UnionCase!int[2] donutIslandIntCases;

__gshared UnionCase!double[2] overlapDoubleCases;
__gshared UnionCase!double[2] convex16DoubleCases;
__gshared UnionCase!double[2] convex64DoubleCases;
__gshared UnionCase!double[2] convex128DoubleCases;


private Point2!T[] rectangle(T)(
    T minX,
    T minY,
    T maxX,
    T maxY
)
{
    alias P = Point2!T;

    return [
        P(minX, minY),
        P(maxX, minY),
        P(maxX, maxY),
        P(minX, maxY),
    ];
}


private Point2!double[] regularRing(
    size_t count,
    double centerX,
    double centerY,
    double radius,
    double phase
)
{
    auto result =
        new Point2!double[count];

    foreach (i; 0 .. count)
    {
        const double angle =
            phase +
            2.0 * cast(double) PI *
            cast(double) i /
            cast(double) count;

        result[i] =
            Point2!double(
                centerX +
                    radius * cos(angle),
                centerY +
                    radius * sin(angle)
            );
    }

    return result;
}


private OwnedPolygon!T fromPointArrays(T)(
    Point2!T[][] points
)
{
    OwnedPolygon!T result;

    result.points =
        points;

    result.rings =
        new LinearRing2View!T[
            result.points.length
        ];

    foreach (i; 0 .. result.points.length)
    {
        result.rings[i] =
            LinearRing2View!T(
                result.points[i]
            );
    }

    result.view =
        Polygon2View!T(
            result.rings
        );

    return result;
}


private UnionCase!int makeDisjointInt(
    int shift
)
{
    UnionCase!int result;

    result.first =
        fromPointArrays!int([
            rectangle!int(
                shift,
                shift,
                shift + 20,
                shift + 20
            )
        ]);

    result.second =
        fromPointArrays!int([
            rectangle!int(
                shift + 40,
                shift,
                shift + 60,
                shift + 20
            )
        ]);

    result.expectedComponents = 2;
    result.expectedHoles = 0;

    return result;
}


private UnionCase!int makeOverlapInt(
    int shift
)
{
    UnionCase!int result;

    result.first =
        fromPointArrays!int([
            rectangle!int(
                shift,
                shift,
                shift + 30,
                shift + 30
            )
        ]);

    result.second =
        fromPointArrays!int([
            rectangle!int(
                shift + 15,
                shift - 5,
                shift + 45,
                shift + 25
            )
        ]);

    result.expectedComponents = 1;
    result.expectedHoles = 0;

    return result;
}


private UnionCase!int makeAdjacentInt(
    int shift
)
{
    UnionCase!int result;

    result.first =
        fromPointArrays!int([
            rectangle!int(
                shift,
                shift,
                shift + 20,
                shift + 20
            )
        ]);

    result.second =
        fromPointArrays!int([
            rectangle!int(
                shift + 20,
                shift,
                shift + 40,
                shift + 20
            )
        ]);

    result.expectedComponents = 1;
    result.expectedHoles = 0;

    return result;
}


private UnionCase!int makePointTouchInt(
    int shift
)
{
    UnionCase!int result;

    result.first =
        fromPointArrays!int([
            rectangle!int(
                shift,
                shift,
                shift + 20,
                shift + 20
            )
        ]);

    result.second =
        fromPointArrays!int([
            rectangle!int(
                shift + 20,
                shift + 20,
                shift + 40,
                shift + 40
            )
        ]);

    result.expectedComponents = 2;
    result.expectedHoles = 0;

    return result;
}


private UnionCase!int makeDonutIslandInt(
    int shift
)
{
    UnionCase!int result;

    result.first =
        fromPointArrays!int([
            rectangle!int(
                shift,
                shift,
                shift + 100,
                shift + 100
            ),
            /*
             * Ring roles are structural. This clockwise order simply mirrors
             * an ordinary hole presentation.
             */
            [
                Point2!int(
                    shift + 20,
                    shift + 20
                ),
                Point2!int(
                    shift + 20,
                    shift + 80
                ),
                Point2!int(
                    shift + 80,
                    shift + 80
                ),
                Point2!int(
                    shift + 80,
                    shift + 20
                ),
            ],
        ]);

    result.second =
        fromPointArrays!int([
            rectangle!int(
                shift + 40,
                shift + 40,
                shift + 60,
                shift + 60
            )
        ]);

    result.expectedComponents = 2;
    result.expectedHoles = 1;

    return result;
}


private UnionCase!double makeOverlapDouble(
    double shift
)
{
    UnionCase!double result;

    result.first =
        fromPointArrays!double([
            rectangle!double(
                shift,
                shift,
                shift + 30.0,
                shift + 30.0
            )
        ]);

    result.second =
        fromPointArrays!double([
            rectangle!double(
                shift + 15.25,
                shift - 5.5,
                shift + 45.25,
                shift + 24.5
            )
        ]);

    result.expectedComponents = 1;
    result.expectedHoles = 0;

    return result;
}


private UnionCase!double makeConvexDouble(
    size_t vertexCount,
    double shift
)
{
    UnionCase!double result;

    result.first =
        fromPointArrays!double([
            regularRing(
                vertexCount,
                shift,
                shift,
                100.0,
                0.0
            )
        ]);

    result.second =
        fromPointArrays!double([
            regularRing(
                vertexCount,
                shift + 35.0,
                shift + 5.0,
                100.0,
                cast(double) PI /
                    cast(double) vertexCount
            )
        ]);

    result.expectedComponents = 1;
    result.expectedHoles = 0;

    return result;
}


private size_t holeCount(
    ref const PolygonUnionResult result
)
{
    size_t count = 0;

    foreach (i; 0 .. result.length)
    {
        count +=
            result[i].holeCount;
    }

    return count;
}


private ulong consume(
    ref const PolygonUnionResult result
)
{
    assert(result.succeeded);

    ulong value =
        cast(ulong) result.length + 1;

    foreach (i; 0 .. result.length)
    {
        const component =
            result[i];

        value =
            value * 1_000_003UL +
            cast(ulong) component.length;

        value =
            value * 1_000_033UL +
            cast(ulong) component.exterior.length;

        value =
            value * 1_000_037UL +
            cast(ulong) component.holeCount;

        foreach (
            holeIndex;
            0 ..
            component.holeCount
        )
        {
            value =
                value * 1_000_081UL +
                cast(ulong)
                    component.hole(
                        holeIndex
                    ).length;
        }
    }

    return value;
}


private ulong evaluateCase(T)(
    ref UnionCase!T benchmarkCase
)
{
    const result =
        polygonUnion(
            benchmarkCase.first.view,
            benchmarkCase.second.view
        );

    assert(result.succeeded);

    return consume(result);
}


private void verifyCase(T)(
    ref UnionCase!T benchmarkCase
)
{
    const result =
        polygonUnion(
            benchmarkCase.first.view,
            benchmarkCase.second.view
        );

    assert(result.succeeded);

    assert(
        result.status ==
        PolygonUnionStatus.success
    );

    assert(
        result.length ==
        benchmarkCase.expectedComponents
    );

    assert(
        holeCount(result) ==
        benchmarkCase.expectedHoles
    );

    benchmarkSink ^=
        consume(result);
}


private void prepareCases()
{
    disjointIntCases[0] =
        makeDisjointInt(0);

    disjointIntCases[1] =
        makeDisjointInt(1_000);

    overlapIntCases[0] =
        makeOverlapInt(0);

    overlapIntCases[1] =
        makeOverlapInt(1_000);

    adjacentIntCases[0] =
        makeAdjacentInt(0);

    adjacentIntCases[1] =
        makeAdjacentInt(1_000);

    pointTouchIntCases[0] =
        makePointTouchInt(0);

    pointTouchIntCases[1] =
        makePointTouchInt(1_000);

    donutIslandIntCases[0] =
        makeDonutIslandInt(0);

    donutIslandIntCases[1] =
        makeDonutIslandInt(1_000);

    overlapDoubleCases[0] =
        makeOverlapDouble(0.0);

    overlapDoubleCases[1] =
        makeOverlapDouble(1_000.0);

    convex16DoubleCases[0] =
        makeConvexDouble(
            16,
            0.0
        );

    convex16DoubleCases[1] =
        makeConvexDouble(
            16,
            1_000.0
        );

    convex64DoubleCases[0] =
        makeConvexDouble(
            64,
            0.0
        );

    convex64DoubleCases[1] =
        makeConvexDouble(
            64,
            1_000.0
        );

    convex128DoubleCases[0] =
        makeConvexDouble(
            128,
            0.0
        );

    convex128DoubleCases[1] =
        makeConvexDouble(
            128,
            1_000.0
        );
}


private void verifyCases()
{
    foreach (i; 0 .. 2)
    {
        verifyCase(
            disjointIntCases[i]
        );

        verifyCase(
            overlapIntCases[i]
        );

        verifyCase(
            adjacentIntCases[i]
        );

        verifyCase(
            pointTouchIntCases[i]
        );

        verifyCase(
            donutIslandIntCases[i]
        );

        verifyCase(
            overlapDoubleCases[i]
        );

        verifyCase(
            convex16DoubleCases[i]
        );

        verifyCase(
            convex64DoubleCases[i]
        );

        verifyCase(
            convex128DoubleCases[i]
        );
    }
}


pragma(inline, false)
private ulong benchDisjointInt(size_t i)
{
    return evaluateCase(
        disjointIntCases[i & 1]
    );
}


pragma(inline, false)
private ulong benchOverlapInt(size_t i)
{
    return evaluateCase(
        overlapIntCases[i & 1]
    );
}


pragma(inline, false)
private ulong benchAdjacentInt(size_t i)
{
    return evaluateCase(
        adjacentIntCases[i & 1]
    );
}


pragma(inline, false)
private ulong benchPointTouchInt(size_t i)
{
    return evaluateCase(
        pointTouchIntCases[i & 1]
    );
}


pragma(inline, false)
private ulong benchDonutIslandInt(size_t i)
{
    return evaluateCase(
        donutIslandIntCases[i & 1]
    );
}


pragma(inline, false)
private ulong benchOverlapDouble(size_t i)
{
    return evaluateCase(
        overlapDoubleCases[i & 1]
    );
}


pragma(inline, false)
private ulong benchConvex16Double(size_t i)
{
    return evaluateCase(
        convex16DoubleCases[i & 1]
    );
}


pragma(inline, false)
private ulong benchConvex64Double(size_t i)
{
    return evaluateCase(
        convex64DoubleCases[i & 1]
    );
}


pragma(inline, false)
private ulong benchConvex128Double(size_t i)
{
    return evaluateCase(
        convex128DoubleCases[i & 1]
    );
}


private void runBenchmark(alias operation)(
    string name,
    size_t iterations
)
{
    size_t warmupIterations =
        iterations / 10;

    if (warmupIterations == 0)
        warmupIterations = 1;

    ulong localSink = 1;

    foreach (i; 0 .. warmupIterations)
    {
        localSink =
            localSink * 1_000_003UL +
            operation(i) +
            cast(ulong)(i + 1);
    }

    long[repetitions] samples;

    foreach (sample; 0 .. repetitions)
    {
        StopWatch stopwatch;
        stopwatch.start();

        foreach (i; 0 .. iterations)
        {
            localSink =
                localSink * 1_000_003UL +
                operation(i) +
                cast(ulong)(i + 1);
        }

        stopwatch.stop();

        samples[sample] =
            stopwatch.peek.total!"nsecs";
    }

    benchmarkSink =
        benchmarkSink * 1_000_033UL +
        localSink;

    sort(samples[]);

    const double nsPerOperation =
        cast(double)
            samples[repetitions / 2] /
        cast(double) iterations;

    writefln(
        "%-42s %15.2f ns/op",
        name,
        nsPerOperation
    );
}


void main()
{
    prepareCases();
    verifyCases();

    writeln();
    writeln("Simple topology:");

    runBenchmark!benchDisjointInt(
        "int rectangles: disjoint",
        2_000
    );

    runBenchmark!benchOverlapInt(
        "int rectangles: overlap",
        1_000
    );

    runBenchmark!benchAdjacentInt(
        "int rectangles: shared edge",
        1_000
    );

    runBenchmark!benchPointTouchInt(
        "int rectangles: point contact",
        1_000
    );

    runBenchmark!benchDonutIslandInt(
        "int donut + island",
        500
    );

    runBenchmark!benchOverlapDouble(
        "double rectangles: overlap",
        500
    );


    writeln();
    writeln("Convex binary64 scaling:");

    runBenchmark!benchConvex16Double(
        "double convex overlap: 16 + 16 vertices",
        100
    );

    runBenchmark!benchConvex64Double(
        "double convex overlap: 64 + 64 vertices",
        20
    );

    runBenchmark!benchConvex128Double(
        "double convex overlap: 128 + 128 vertices",
        5
    );


    writeln();
    writefln(
        "sink=%s",
        benchmarkSink
    );
}
