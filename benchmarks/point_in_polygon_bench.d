/*
 * Public-API benchmark for robust point-in-polygon classification.
 *
 * Covers:
 *
 * - ordinary finite binary64 polygons with 16, 128 and 1,024 vertices;
 * - interior, exterior and boundary queries;
 * - an exterior ring with four interior rings;
 * - a near-collinear binary64 query intended to exercise robust fallback;
 * - a full-range long triangle.
 *
 * Ordinary moderate binary64 cases are compared with a local even-odd
 * reference. The reference uses a y-range prefilter before computing an
 * ordinary floating-point determinant.
 *
 * That reference is diagnostic only. It does not implement geo-d's full
 * robust numerical contract and is used only for exactly representable,
 * moderate benchmark coordinates.
 *
 * All dynamic allocation and geometry construction occur before timing.
 */
module point_in_polygon_bench;

import geo.linear_ring_view :
    LinearRingView;

import geo.point :
    Point2;

import geo.point_in_polygon :
    PointPolygonLocation,
    tryClassifyPointInPolygon;

import geo.polygon_view :
    PolygonView;

import std.algorithm.sorting :
    sort;

import std.datetime.stopwatch :
    StopWatch;

import std.stdio :
    writefln,
    writeln;


alias P = Point2!double;
alias R = LinearRingView!double;
alias V = PolygonView!double;

alias LP = Point2!long;
alias LR = LinearRingView!long;
alias LV = PolygonView!long;


enum size_t repetitions = 7;

__gshared ulong benchmarkSink;


/*
 * Ordinary single-ring scaling cases.
 */
__gshared P[] points16;
__gshared R[] rings16;
__gshared V polygon16;

__gshared P[] points128;
__gshared R[] rings128;
__gshared V polygon128;

__gshared P[] points1024;
__gshared R[] rings1024;
__gshared V polygon1024;


/*
 * One exterior plus four holes.
 */
__gshared P[][] holedPointStorage;
__gshared R[] holedRings;
__gshared V holedPolygon;


/*
 * Near-collinear robust binary64 case.
 */
__gshared P[] hardPoints;
__gshared R[] hardRings;
__gshared V hardPolygon;


/*
 * Full-range long case.
 */
__gshared LP[] fullLongPoints;
__gshared LR[] fullLongRings;
__gshared LV fullLongPolygon;


/*
 * Runtime query pairs.
 *
 * Every timed wrapper alternates between two queries so an optimizing
 * compiler cannot hoist a constant classification out of the benchmark
 * loop.
 */
__gshared P[2] insideQueries;
__gshared P[2] outsideQueries;
__gshared P[2] boundaryQueries;

__gshared P[2] shellQueries;
__gshared P[2] insideHoleQueries;
__gshared P[2] holeBoundaryQueries;

__gshared P[2] hardQueries;
__gshared LP[2] fullLongQueries;


/*
 * Construct a rectangle with n stored vertices.
 *
 * n must be divisible by four. Each side contributes n/4 vertices and
 * corners are stored once. Closure remains implicit.
 *
 * Benchmark sizes and extents are selected so generated coordinates are
 * exact integer-valued binary64 numbers.
 */
private P[] makeRectangle(
    size_t n,
    double centerX,
    double centerY,
    double halfExtent
)
{
    assert(n >= 4);
    assert(n % 4 == 0);

    auto result =
        new P[n];

    const size_t quarter =
        n / 4;

    foreach (i; 0 .. quarter)
    {
        const double offset =
            2.0 * halfExtent *
            cast(double) i /
            cast(double) quarter;

        /*
         * Bottom edge, left -> right.
         */
        result[i] =
            P(
                centerX - halfExtent + offset,
                centerY - halfExtent
            );

        /*
         * Right edge, bottom -> top.
         */
        result[quarter + i] =
            P(
                centerX + halfExtent,
                centerY - halfExtent + offset
            );

        /*
         * Top edge, right -> left.
         */
        result[2 * quarter + i] =
            P(
                centerX + halfExtent - offset,
                centerY + halfExtent
            );

        /*
         * Left edge, top -> bottom.
         */
        result[3 * quarter + i] =
            P(
                centerX - halfExtent,
                centerY + halfExtent - offset
            );
    }

    return result;
}


private bool withinClosedBounds(
    double value,
    double first,
    double second
)
    pure nothrow @safe @nogc
{
    return
        (
            first <= value &&
            value <= second
        ) ||
        (
            second <= value &&
            value <= first
        );
}


private enum DirectRingLocation : ubyte
{
    outside,
    boundary,
    inside,
}


/*
 * Ordinary binary64 edge handling used by the diagnostic reference.
 *
 * The y-range test is deliberately performed before determinant work.
 *
 * For the moderate exactly representable benchmark geometry this preserves
 * the same boundary and half-open even-odd semantics as the public operation.
 * It is not a robust replacement for arbitrary binary64 input.
 */
pragma(inline, true)
private void directProcessEdge(
    P a,
    P b,
    P point,
    ref bool inside,
    ref bool boundaryFound
)
    pure nothrow @safe @nogc
{
    if (boundaryFound)
        return;

    const double minY =
        a.y < b.y
            ? a.y
            : b.y;

    const double maxY =
        a.y > b.y
            ? a.y
            : b.y;

    /*
     * If the query y-coordinate does not lie within the closed edge
     * y-range, the point cannot be on the edge and the edge cannot
     * contribute a horizontal-ray crossing.
     */
    if (
        point.y < minY ||
        point.y > maxY
    )
    {
        return;
    }

    const double determinant =
        (b.x - a.x) *
        (point.y - a.y) -
        (b.y - a.y) *
        (point.x - a.x);

    if (
        determinant == 0.0 &&
        withinClosedBounds(
            point.x,
            a.x,
            b.x
        )
    )
    {
        boundaryFound = true;
        return;
    }

    if (
        a.y <= point.y &&
        point.y < b.y
    )
    {
        if (determinant > 0.0)
            inside = !inside;
    }
    else if (
        b.y <= point.y &&
        point.y < a.y
    )
    {
        if (determinant < 0.0)
            inside = !inside;
    }
}


private DirectRingLocation directClassifyRing(
    R ring,
    P point
)
    pure nothrow @safe @nogc
{
    if (ring.empty)
        return DirectRingLocation.outside;

    const P first =
        ring[0];

    P previous =
        first;

    bool inside = false;
    bool boundaryFound = false;

    foreach (i; 1 .. ring.length)
    {
        const P current =
            ring[i];

        directProcessEdge(
            previous,
            current,
            point,
            inside,
            boundaryFound
        );

        previous =
            current;
    }

    directProcessEdge(
        previous,
        first,
        point,
        inside,
        boundaryFound
    );

    if (boundaryFound)
        return DirectRingLocation.boundary;

    return
        inside
            ? DirectRingLocation.inside
            : DirectRingLocation.outside;
}


/*
 * Role-based polygon reference.
 *
 * Every ring is inspected, matching the public polygon-level semantics for
 * the finite benchmark cases:
 *
 * - ring zero is exterior;
 * - subsequent rings subtract their interiors;
 * - boundary has global precedence.
 */
private PointPolygonLocation directClassifyPolygon(
    V polygon,
    P point
)
    pure nothrow @safe @nogc
{
    if (polygon.empty)
        return PointPolygonLocation.outside;

    const auto exteriorLocation =
        directClassifyRing(
            polygon.exterior,
            point
        );

    bool boundaryFound =
        exteriorLocation ==
        DirectRingLocation.boundary;

    const bool insideExterior =
        exteriorLocation ==
        DirectRingLocation.inside;

    bool insideHole = false;

    foreach (i; 0 .. polygon.holeCount)
    {
        const auto holeLocation =
            directClassifyRing(
                polygon.hole(i),
                point
            );

        if (
            holeLocation ==
            DirectRingLocation.boundary
        )
        {
            boundaryFound = true;
        }
        else if (
            holeLocation ==
            DirectRingLocation.inside
        )
        {
            insideHole = true;
        }
    }

    if (boundaryFound)
        return PointPolygonLocation.boundary;

    if (
        insideExterior &&
        !insideHole
    )
    {
        return PointPolygonLocation.inside;
    }

    return PointPolygonLocation.outside;
}


private ulong encode(
    bool success,
    PointPolygonLocation location
)
    pure nothrow @safe @nogc
{
    return
        cast(ulong) location ^
        (
            success
                ? 0x9e37_79b9_7f4a_7c15UL
                : 0x243f_6a88_85a3_08d3UL
        );
}


private void prepareCases()
{
    /*
     * 2 * halfExtent / (n / 4) is integral for all three cases.
     */
    points16 =
        makeRectangle(
            16,
            0.0,
            0.0,
            4096.0
        );

    rings16 = [
        R(points16)
    ];

    polygon16 =
        V(rings16);


    points128 =
        makeRectangle(
            128,
            0.0,
            0.0,
            4096.0
        );

    rings128 = [
        R(points128)
    ];

    polygon128 =
        V(rings128);


    points1024 =
        makeRectangle(
            1024,
            0.0,
            0.0,
            4096.0
        );

    rings1024 = [
        R(points1024)
    ];

    polygon1024 =
        V(rings1024);


    /*
     * Exterior: 1,024 vertices.
     * Four holes: 128 vertices each.
     * Total: 1,536 stored vertices.
     */
    holedPointStorage.length = 5;

    holedPointStorage[0] =
        makeRectangle(
            1024,
            0.0,
            0.0,
            8192.0
        );

    holedPointStorage[1] =
        makeRectangle(
            128,
            -2048.0,
            -2048.0,
            512.0
        );

    holedPointStorage[2] =
        makeRectangle(
            128,
            2048.0,
            -2048.0,
            512.0
        );

    holedPointStorage[3] =
        makeRectangle(
            128,
            -2048.0,
            2048.0,
            512.0
        );

    holedPointStorage[4] =
        makeRectangle(
            128,
            2048.0,
            2048.0,
            512.0
        );

    holedRings.length = 5;

    foreach (i; 0 .. holedRings.length)
    {
        holedRings[i] =
            R(
                holedPointStorage[i]
            );
    }

    holedPolygon =
        V(holedRings);


    /*
     * The query is one binary64 step above the line y=x at x=0.5.
     *
     * The determinant is small relative to the error bound of the ordinary
     * binary64 orientation filter, making this a focused robust-predicate
     * fallback workload.
     */
    hardPoints = [
        P(
            0.0,
            0.0
        ),
        P(
            1.0,
            1.0
        ),
        P(
            0.0,
            2.0
        )
    ];

    hardRings = [
        R(hardPoints)
    ];

    hardPolygon =
        V(hardRings);


    fullLongPoints = [
        LP(
            long.min,
            long.min
        ),
        LP(
            long.max,
            long.min
        ),
        LP(
            0,
            long.max
        )
    ];

    fullLongRings = [
        LR(fullLongPoints)
    ];

    fullLongPolygon =
        LV(fullLongRings);


    insideQueries = [
        P(0.0, 0.0),
        P(1024.0, 512.0)
    ];

    outsideQueries = [
        P(8192.0, 0.0),
        P(-8192.0, 1024.0)
    ];

    boundaryQueries = [
        P(0.0, -4096.0),
        P(4096.0, 0.0)
    ];


    shellQueries = [
        P(0.0, 0.0),
        P(0.0, 1024.0)
    ];

    insideHoleQueries = [
        P(-2048.0, -2048.0),
        P(2048.0, 2048.0)
    ];

    holeBoundaryQueries = [
        P(-2048.0, -2560.0),
        P(2048.0, 1536.0)
    ];


    hardQueries = [
        P(
            0x1p-1,
            0x1.0000000000001p-1
        ),
        P(
            0x1p-2,
            0x1.0000000000001p-2
        )
    ];


    fullLongQueries = [
        LP(0, 0),
        LP(0, -1)
    ];
}


private void verifyPublicVsDirect(
    V polygon,
    P point
)
{
    PointPolygonLocation publicLocation;

    assert(
        tryClassifyPointInPolygon(
            polygon,
            point,
            publicLocation
        )
    );

    const auto directLocation =
        directClassifyPolygon(
            polygon,
            point
        );

    assert(
        publicLocation ==
        directLocation
    );
}


private void verifyCases()
{
    writeln("Reference verification:");

    /*
     * Single-ring scaling inputs.
     */
    verifyPublicVsDirect(
        polygon16,
        P(0.0, 0.0)
    );

    verifyPublicVsDirect(
        polygon128,
        P(0.0, 0.0)
    );

    verifyPublicVsDirect(
        polygon1024,
        P(0.0, 0.0)
    );

    verifyPublicVsDirect(
        polygon1024,
        P(8192.0, 0.0)
    );

    verifyPublicVsDirect(
        polygon1024,
        P(0.0, -4096.0)
    );


    /*
     * Polygon with holes.
     */
    verifyPublicVsDirect(
        holedPolygon,
        P(0.0, 0.0)
    );

    verifyPublicVsDirect(
        holedPolygon,
        P(-2048.0, -2048.0)
    );

    verifyPublicVsDirect(
        holedPolygon,
        P(-2048.0, -2560.0)
    );


    /*
     * Verify the alternate runtime queries used by the timed wrappers.
     */
    verifyPublicVsDirect(
        polygon16,
        insideQueries[1]
    );

    verifyPublicVsDirect(
        polygon128,
        insideQueries[1]
    );

    verifyPublicVsDirect(
        polygon1024,
        insideQueries[1]
    );

    verifyPublicVsDirect(
        polygon1024,
        outsideQueries[1]
    );

    verifyPublicVsDirect(
        polygon1024,
        boundaryQueries[1]
    );

    verifyPublicVsDirect(
        holedPolygon,
        shellQueries[1]
    );

    verifyPublicVsDirect(
        holedPolygon,
        insideHoleQueries[1]
    );

    verifyPublicVsDirect(
        holedPolygon,
        holeBoundaryQueries[1]
    );


    /*
     * Robust binary64 case.
     */
    {
        PointPolygonLocation location;

        assert(
            tryClassifyPointInPolygon(
                hardPolygon,
                P(
                    0x1p-1,
                    0x1.0000000000001p-1
                ),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.inside
        );
    }


    /*
     * Full-range long case.
     */
    {
        PointPolygonLocation location;

        assert(
            tryClassifyPointInPolygon(
                fullLongPolygon,
                LP(
                    0,
                    0
                ),
                location
            )
        );

        assert(
            location ==
            PointPolygonLocation.inside
        );
    }

    writeln("  PASS");
}


pragma(inline, false)
private ulong public16Inside(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            polygon16,
            insideQueries[i & 1],
            location
        );

    return encode(
        success,
        location
    );
}


pragma(inline, false)
private ulong direct16Inside(size_t i)
{
    return encode(
        true,
        directClassifyPolygon(
            polygon16,
            insideQueries[i & 1]
        )
    );
}


pragma(inline, false)
private ulong public128Inside(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            polygon128,
            insideQueries[i & 1],
            location
        );

    return encode(
        success,
        location
    );
}


pragma(inline, false)
private ulong direct128Inside(size_t i)
{
    return encode(
        true,
        directClassifyPolygon(
            polygon128,
            insideQueries[i & 1]
        )
    );
}


pragma(inline, false)
private ulong public1024Inside(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            polygon1024,
            insideQueries[i & 1],
            location
        );

    return encode(
        success,
        location
    );
}


pragma(inline, false)
private ulong direct1024Inside(size_t i)
{
    return encode(
        true,
        directClassifyPolygon(
            polygon1024,
            insideQueries[i & 1]
        )
    );
}


pragma(inline, false)
private ulong public1024Outside(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            polygon1024,
            outsideQueries[i & 1],
            location
        );

    return encode(
        success,
        location
    );
}


pragma(inline, false)
private ulong direct1024Outside(size_t i)
{
    return encode(
        true,
        directClassifyPolygon(
            polygon1024,
            outsideQueries[i & 1]
        )
    );
}


pragma(inline, false)
private ulong public1024Boundary(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            polygon1024,
            boundaryQueries[i & 1],
            location
        );

    return encode(
        success,
        location
    );
}


pragma(inline, false)
private ulong direct1024Boundary(size_t i)
{
    return encode(
        true,
        directClassifyPolygon(
            polygon1024,
            boundaryQueries[i & 1]
        )
    );
}


pragma(inline, false)
private ulong publicHoledShell(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            holedPolygon,
            shellQueries[i & 1],
            location
        );

    return encode(
        success,
        location
    );
}


pragma(inline, false)
private ulong directHoledShell(size_t i)
{
    return encode(
        true,
        directClassifyPolygon(
            holedPolygon,
            shellQueries[i & 1]
        )
    );
}


pragma(inline, false)
private ulong publicInsideHole(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            holedPolygon,
            insideHoleQueries[i & 1],
            location
        );

    return encode(
        success,
        location
    );
}


pragma(inline, false)
private ulong directInsideHole(size_t i)
{
    return encode(
        true,
        directClassifyPolygon(
            holedPolygon,
            insideHoleQueries[i & 1]
        )
    );
}


pragma(inline, false)
private ulong publicHoleBoundary(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            holedPolygon,
            holeBoundaryQueries[i & 1],
            location
        );

    return encode(
        success,
        location
    );
}


pragma(inline, false)
private ulong directHoleBoundary(size_t i)
{
    return encode(
        true,
        directClassifyPolygon(
            holedPolygon,
            holeBoundaryQueries[i & 1]
        )
    );
}


pragma(inline, false)
private ulong publicHardDouble(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            hardPolygon,
            hardQueries[i & 1],
            location
        );

    return encode(
        success,
        location
    );
}


pragma(inline, false)
private ulong publicFullLong(size_t i)
{
    PointPolygonLocation location;

    const bool success =
        tryClassifyPointInPolygon(
            fullLongPolygon,
            fullLongQueries[i & 1],
            location
        );

    return
        cast(ulong) location ^
        (
            success
                ? 0xd6e8_feb8_6659_fd93UL
                : 0xa409_3822_299f_31d0UL
        );
}


private void runBenchmark(alias operation)(
    string name,
    size_t iterations,
    size_t vertexCount
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

    benchmarkSink ^= localSink;

    sort(samples[]);

    const double nsPerOperation =
        cast(double) samples[repetitions / 2] /
        cast(double) iterations;

    const double nsPerVertex =
        nsPerOperation /
        cast(double) vertexCount;

    writefln(
        "%-34s %11.2f ns/op %8.3f ns/vertex  n=%s",
        name,
        nsPerOperation,
        nsPerVertex,
        vertexCount
    );
}


void main()
{
    prepareCases();
    verifyCases();

    writeln();
    writeln("Single-ring scaling, inside:");

    runBenchmark!public16Inside(
        "public n=16",
        500_000,
        16
    );

    runBenchmark!direct16Inside(
        "direct n=16",
        500_000,
        16
    );


    runBenchmark!public128Inside(
        "public n=128",
        100_000,
        128
    );

    runBenchmark!direct128Inside(
        "direct n=128",
        100_000,
        128
    );


    runBenchmark!public1024Inside(
        "public n=1024",
        20_000,
        1024
    );

    runBenchmark!direct1024Inside(
        "direct n=1024",
        20_000,
        1024
    );


    writeln();
    writeln("Single-ring query location, n=1024:");

    runBenchmark!public1024Outside(
        "public outside",
        20_000,
        1024
    );

    runBenchmark!direct1024Outside(
        "direct outside",
        20_000,
        1024
    );


    runBenchmark!public1024Boundary(
        "public boundary",
        20_000,
        1024
    );

    runBenchmark!direct1024Boundary(
        "direct boundary",
        20_000,
        1024
    );


    writeln();
    writeln("Exterior plus four holes, total n=1536:");

    runBenchmark!publicHoledShell(
        "public shell interior",
        12_000,
        1536
    );

    runBenchmark!directHoledShell(
        "direct shell interior",
        12_000,
        1536
    );


    runBenchmark!publicInsideHole(
        "public inside hole",
        12_000,
        1536
    );

    runBenchmark!directInsideHole(
        "direct inside hole",
        12_000,
        1536
    );


    runBenchmark!publicHoleBoundary(
        "public hole boundary",
        12_000,
        1536
    );

    runBenchmark!directHoleBoundary(
        "direct hole boundary",
        12_000,
        1536
    );


    writeln();
    writeln("Robust special cases:");

    runBenchmark!publicHardDouble(
        "public near-collinear double",
        1_000_000,
        3
    );

    runBenchmark!publicFullLong(
        "public full-range long",
        500_000,
        3
    );


    writeln();
    writefln(
        "sink=%s",
        benchmarkSink
    );
}
