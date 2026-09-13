/*
 * Public-API benchmark for PolygonView topology validation.
 *
 * The benchmark separates:
 *
 * - exterior-only validation;
 * - increasing numbers of disjoint interior rings;
 * - two high-vertex nested rings;
 * - a valid tangential boundary contact;
 * - representative polygon-topology failures.
 *
 * Geometry construction occurs before timing.
 */
module polygon_validation_bench;

import geo.linear_ring_view :
    LinearRingView;

import geo.point :
    Point2;

import geo.polygon_view :
    PolygonView;

import geo.topology_validation :
    PolygonValidationIssue,
    PolygonValidationResult,
    validatePolygon;

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


alias P = Point2!double;
alias R = LinearRingView!double;
alias V = PolygonView!double;

enum size_t repetitions = 7;

__gshared ulong benchmarkSink;


/*
 * Owns the backing point and ring-descriptor storage referenced by view.
 *
 * All construction happens before timing.
 */
private struct OwnedPolygon
{
    P[][] points;
    R[] rings;
    V view;
}


__gshared OwnedPolygon[2] exteriorOnlyCases;
__gshared OwnedPolygon[2] oneHoleCases;
__gshared OwnedPolygon[2] fourHoleCases;
__gshared OwnedPolygon[2] sixteenHoleCases;
__gshared OwnedPolygon[2] highVertexCases;

__gshared OwnedPolygon[2] tangentCases;
__gshared OwnedPolygon[2] outsideCases;
__gshared OwnedPolygon[2] nestedCases;
__gshared OwnedPolygon[2] crossingCases;


private P[] rectangle(
    double minX,
    double minY,
    double maxX,
    double maxY
)
{
    return [
        P(minX, minY),
        P(maxX, minY),
        P(maxX, maxY),
        P(minX, maxY)
    ];
}


private P[] regularRing(
    size_t count,
    double centerX,
    double centerY,
    double radius,
    double phase
)
{
    auto result =
        new P[count];

    foreach (i; 0 .. count)
    {
        const double angle =
            phase +
            2.0 * cast(double) PI *
            cast(double) i /
            cast(double) count;

        result[i] =
            P(
                centerX + radius * cos(angle),
                centerY + radius * sin(angle)
            );
    }

    return result;
}


private OwnedPolygon fromPointArrays(
    P[][] points
)
{
    OwnedPolygon result;

    result.points =
        points;

    result.rings =
        new R[result.points.length];

    foreach (i; 0 .. result.points.length)
    {
        result.rings[i] =
            R(result.points[i]);
    }

    result.view =
        V(result.rings);

    return result;
}


private OwnedPolygon makeExteriorOnly(
    double shift
)
{
    P[][] points;

    points ~=
        rectangle(
            shift,
            shift,
            shift + 100.0,
            shift + 100.0
        );

    return fromPointArrays(points);
}


/*
 * Builds one exterior rectangle and a regular grid of mutually disjoint
 * rectangular holes.
 */
private OwnedPolygon makeGridPolygon(
    size_t holeCount,
    double shift
)
{
    size_t side = 1;

    while (side * side < holeCount)
        ++side;

    const double extent =
        cast(double)(side + 1) * 10.0;

    P[][] points;

    points ~=
        rectangle(
            shift,
            shift,
            shift + extent,
            shift + extent
        );

    foreach (hole; 0 .. holeCount)
    {
        const size_t row =
            hole / side;

        const size_t column =
            hole % side;

        const double centerX =
            shift +
            10.0 * cast(double)(column + 1);

        const double centerY =
            shift +
            10.0 * cast(double)(row + 1);

        points ~=
            rectangle(
                centerX - 2.0,
                centerY - 2.0,
                centerX + 2.0,
                centerY + 2.0
            );
    }

    return fromPointArrays(points);
}


/*
 * One high-vertex exterior and one high-vertex interior ring.
 *
 * Their ring-level bounding boxes overlap by containment, while almost all
 * individual edge pairs remain spatially disjoint.
 */
private OwnedPolygon makeHighVertexPolygon(
    double shift
)
{
    P[][] points;

    points ~=
        regularRing(
            128,
            shift,
            shift,
            1000.0,
            0.0
        );

    points ~=
        regularRing(
            64,
            shift,
            shift,
            200.0,
            0.013
        );

    return fromPointArrays(points);
}


/*
 * Valid polygon with a single tangential exterior/hole contact.
 */
private OwnedPolygon makeTangentPolygon(
    double shift
)
{
    P[][] points;

    points ~=
        rectangle(
            shift,
            shift,
            shift + 20.0,
            shift + 20.0
        );

    points ~= [
        P(shift + 10.0, shift),
        P(shift + 12.0, shift + 2.0),
        P(shift + 10.0, shift + 4.0),
        P(shift + 8.0,  shift + 2.0)
    ];

    return fromPointArrays(points);
}


private OwnedPolygon makeOutsidePolygon(
    double shift
)
{
    P[][] points;

    points ~=
        rectangle(
            shift,
            shift,
            shift + 20.0,
            shift + 20.0
        );

    points ~=
        rectangle(
            shift + 30.0,
            shift + 30.0,
            shift + 34.0,
            shift + 34.0
        );

    return fromPointArrays(points);
}


private OwnedPolygon makeNestedPolygon(
    double shift
)
{
    P[][] points;

    points ~=
        rectangle(
            shift,
            shift,
            shift + 30.0,
            shift + 30.0
        );

    points ~=
        rectangle(
            shift + 5.0,
            shift + 5.0,
            shift + 25.0,
            shift + 25.0
        );

    points ~=
        rectangle(
            shift + 10.0,
            shift + 10.0,
            shift + 15.0,
            shift + 15.0
        );

    return fromPointArrays(points);
}


private OwnedPolygon makeCrossingPolygon(
    double shift
)
{
    P[][] points;

    points ~=
        rectangle(
            shift,
            shift,
            shift + 20.0,
            shift + 20.0
        );

    points ~=
        rectangle(
            shift + 18.0,
            shift + 18.0,
            shift + 24.0,
            shift + 24.0
        );

    return fromPointArrays(points);
}


private void prepareCases()
{
    exteriorOnlyCases[0] =
        makeExteriorOnly(0.0);

    exteriorOnlyCases[1] =
        makeExteriorOnly(0.125);


    oneHoleCases[0] =
        makeGridPolygon(1, 0.0);

    oneHoleCases[1] =
        makeGridPolygon(1, 0.125);


    fourHoleCases[0] =
        makeGridPolygon(4, 0.0);

    fourHoleCases[1] =
        makeGridPolygon(4, 0.125);


    sixteenHoleCases[0] =
        makeGridPolygon(16, 0.0);

    sixteenHoleCases[1] =
        makeGridPolygon(16, 0.125);


    highVertexCases[0] =
        makeHighVertexPolygon(0.0);

    highVertexCases[1] =
        makeHighVertexPolygon(0.125);


    tangentCases[0] =
        makeTangentPolygon(0.0);

    tangentCases[1] =
        makeTangentPolygon(0.125);


    outsideCases[0] =
        makeOutsidePolygon(0.0);

    outsideCases[1] =
        makeOutsidePolygon(0.125);


    nestedCases[0] =
        makeNestedPolygon(0.0);

    nestedCases[1] =
        makeNestedPolygon(0.125);


    crossingCases[0] =
        makeCrossingPolygon(0.0);

    crossingCases[1] =
        makeCrossingPolygon(0.125);
}


private void assertIssue(
    ref OwnedPolygon[2] cases,
    PolygonValidationIssue expected
)
{
    foreach (ref polygon; cases)
    {
        const result =
            validatePolygon(
                polygon.view
            );

        assert(
            result.issue ==
            expected
        );
    }
}


private void verifyCases()
{
    writeln("Case verification:");

    assertIssue(
        exteriorOnlyCases,
        PolygonValidationIssue.none
    );

    assertIssue(
        oneHoleCases,
        PolygonValidationIssue.none
    );

    assertIssue(
        fourHoleCases,
        PolygonValidationIssue.none
    );

    assertIssue(
        sixteenHoleCases,
        PolygonValidationIssue.none
    );

    assertIssue(
        highVertexCases,
        PolygonValidationIssue.none
    );

    assertIssue(
        tangentCases,
        PolygonValidationIssue.none
    );

    assertIssue(
        outsideCases,
        PolygonValidationIssue.interiorRingOutsideExterior
    );

    assertIssue(
        nestedCases,
        PolygonValidationIssue.nestedInteriorRings
    );

    assertIssue(
        crossingCases,
        PolygonValidationIssue.interRingCrossing
    );

    writeln("  PASS");
}


private ulong encode(
    PolygonValidationResult result
)
    pure nothrow @safe @nogc
{
    ulong value =
        cast(ulong) result.issue;

    value ^=
        cast(ulong) result.primaryRingIndex *
        0x9e37_79b9_7f4a_7c15UL;

    value ^=
        cast(ulong) result.secondaryRingIndex *
        0xbf58_476d_1ce4_e5b9UL;

    value ^=
        cast(ulong) result.primaryEdgeIndex *
        0x94d0_49bb_1331_11ebUL;

    value ^=
        cast(ulong) result.secondaryEdgeIndex *
        0xd6e8_feb8_6659_fd93UL;

    value ^=
        cast(ulong) result.ringResult.issue << 8;

    value ^=
        cast(ulong) result.ringResult.primaryIndex *
        0xa076_1d64_78bd_642fUL;

    value ^=
        cast(ulong) result.ringResult.secondaryIndex *
        0xe703_7ed1_a0b4_28dbUL;

    return value;
}


private ulong validateCase(
    ref OwnedPolygon[2] cases,
    size_t i
)
{
    return
        encode(
            validatePolygon(
                cases[i & 1].view
            )
        );
}


pragma(inline, false)
private ulong benchExteriorOnly(size_t i)
{
    return validateCase(
        exteriorOnlyCases,
        i
    );
}


pragma(inline, false)
private ulong benchOneHole(size_t i)
{
    return validateCase(
        oneHoleCases,
        i
    );
}


pragma(inline, false)
private ulong benchFourHoles(size_t i)
{
    return validateCase(
        fourHoleCases,
        i
    );
}


pragma(inline, false)
private ulong benchSixteenHoles(size_t i)
{
    return validateCase(
        sixteenHoleCases,
        i
    );
}


pragma(inline, false)
private ulong benchHighVertex(size_t i)
{
    return validateCase(
        highVertexCases,
        i
    );
}


pragma(inline, false)
private ulong benchTangent(size_t i)
{
    return validateCase(
        tangentCases,
        i
    );
}


pragma(inline, false)
private ulong benchOutside(size_t i)
{
    return validateCase(
        outsideCases,
        i
    );
}


pragma(inline, false)
private ulong benchNested(size_t i)
{
    return validateCase(
        nestedCases,
        i
    );
}


pragma(inline, false)
private ulong benchCrossing(size_t i)
{
    return validateCase(
        crossingCases,
        i
    );
}


private void runBenchmark(alias operation)(
    string name,
    size_t iterations,
    size_t ringPairs = 0
)
{
    const size_t warmupIterations =
        iterations / 10;

    ulong localSink;

    foreach (i; 0 .. warmupIterations)
        localSink ^= operation(i);

    long[repetitions] samples;

    foreach (sample; 0 .. repetitions)
    {
        StopWatch stopwatch;
        stopwatch.start();

        foreach (i; 0 .. iterations)
            localSink ^= operation(i);

        stopwatch.stop();

        samples[sample] =
            stopwatch.peek.total!"nsecs";
    }

    benchmarkSink ^=
        localSink;

    sort(samples[]);

    const double nsPerOperation =
        cast(double) samples[repetitions / 2] /
        cast(double) iterations;

    if (ringPairs == 0)
    {
        writefln(
            "%-38s %12.2f ns/op",
            name,
            nsPerOperation
        );

        return;
    }

    writefln(
        "%-38s %12.2f ns/op %10.2f ns/ring-pair",
        name,
        nsPerOperation,
        nsPerOperation /
            cast(double) ringPairs
    );
}


void main()
{
    prepareCases();
    verifyCases();

    writeln();
    writeln("Valid polygons:");

    runBenchmark!benchExteriorOnly(
        "exterior only, 4 vertices",
        300_000
    );

    runBenchmark!benchOneHole(
        "1 hole, 4 vertices/ring",
        100_000,
        1
    );

    runBenchmark!benchFourHoles(
        "4 holes, 4 vertices/ring",
        20_000,
        10
    );

    runBenchmark!benchSixteenHoles(
        "16 holes, 4 vertices/ring",
        2_000,
        136
    );

    runBenchmark!benchHighVertex(
        "outer 128 + hole 64 vertices",
        500,
        1
    );

    runBenchmark!benchTangent(
        "1 tangent hole",
        50_000,
        1
    );


    writeln();
    writeln("Invalid polygon paths:");

    runBenchmark!benchOutside(
        "hole outside exterior",
        100_000,
        1
    );

    runBenchmark!benchNested(
        "nested holes",
        50_000,
        3
    );

    runBenchmark!benchCrossing(
        "inter-ring crossing",
        100_000,
        1
    );


    writeln();
    writefln(
        "sink=%s",
        benchmarkSink
    );
}
