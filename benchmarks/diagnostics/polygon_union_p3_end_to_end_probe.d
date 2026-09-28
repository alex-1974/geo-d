/*
 * Research-only end-to-end differential/performance probe for Polygon Union P3.
 *
 * Build once without GeoPolygonUnionP3Prototype for the merged P1 baseline,
 * and once with GeoPolygonUnionP3Prototype for the research candidate.
 *
 * SIG lines contain only public status + canonical result geometry and should
 * compare byte-for-byte between both binaries.
 */
module geo.polygon_union_p3_end_to_end_probe;

import geo;

import std.algorithm.sorting :
    sort;

import std.datetime.stopwatch :
    StopWatch;

import std.exception :
    enforce;

import std.math :
    PI,
    cos,
    sin;

import std.stdio :
    writefln,
    writeln;


enum size_t repetitions = 7;

__gshared ulong probeSink;


private union DoubleBits
{
    double value;
    ulong bits;
}


private struct OwnedPolygon
{
    Point2!double[] points;
    LinearRing2View!double[] rings;
    Polygon2View!double view;
}


private struct DoubleCase
{
    OwnedPolygon first;
    OwnedPolygon second;
}


private ulong mix(
    ulong hash,
    ulong value
)
{
    hash ^=
        value;

    hash *=
        1_099_511_628_211UL;

    return hash;
}


private ulong doubleBits(
    double value
)
{
    DoubleBits bits;

    bits.value =
        value;

    return
        bits.bits;
}


private ulong resultSignature(
    ref const PolygonUnionResult result
)
{
    ulong hash =
        14_695_981_039_346_656_037UL;

    hash =
        mix(
            hash,
            cast(ulong) result.status
        );

    if (!result.succeeded)
        return hash;


    hash =
        mix(
            hash,
            cast(ulong) result.length
        );

    foreach (
        componentIndex;
        0 ..
        result.length
    )
    {
        const component =
            result[
                componentIndex
            ];

        hash =
            mix(
                hash,
                cast(ulong) component.length
            );

        foreach (
            ringIndex;
            0 ..
            component.length
        )
        {
            const ring =
                component[
                    ringIndex
                ];

            hash =
                mix(
                    hash,
                    cast(ulong) ring.length
                );

            foreach (
                pointIndex;
                0 ..
                ring.length
            )
            {
                const point =
                    ring[
                        pointIndex
                    ];

                hash =
                    mix(
                        hash,
                        doubleBits(
                            point.x
                        )
                    );

                hash =
                    mix(
                        hash,
                        doubleBits(
                            point.y
                        )
                    );
            }
        }
    }

    return hash;
}


private long median(
    ref long[repetitions] samples
)
{
    sort(
        samples[]
    );

    return
        samples[
            repetitions / 2
        ];
}


private void runCase(T)(
    string name,
    scope Polygon2View!T first,
    scope Polygon2View!T second,
    bool measure
)
{
    const warmup =
        polygonUnion(
            first,
            second
        );

    const ulong expectedSignature =
        resultSignature(
            warmup
        );

    const uint expectedStatus =
        cast(uint)
            warmup.status;

    const size_t expectedComponents =
        warmup.succeeded
            ? warmup.length
            : 0;


    long[repetitions] samples;

    if (measure)
    {
        foreach (sample; 0 .. repetitions)
        {
            StopWatch stopwatch;

            stopwatch.start();

            const result =
                polygonUnion(
                    first,
                    second
                );

            stopwatch.stop();


            enforce(
                cast(uint) result.status ==
                    expectedStatus,
                "status changed across repetitions"
            );

            enforce(
                resultSignature(
                    result
                ) ==
                    expectedSignature,
                "canonical result signature changed across repetitions"
            );

            samples[sample] =
                stopwatch.peek
                    .total!"nsecs";

            probeSink =
                probeSink *
                    1_000_003UL +
                resultSignature(
                    result
                );
        }
    }


    writefln(
        "SIG|%s|status=%s|components=%s|hash=%016x",
        name,
        expectedStatus,
        expectedComponents,
        expectedSignature
    );

    if (measure)
    {
        writefln(
            "TIME|%s|median_ns=%s",
            name,
            median(
                samples
            )
        );
    }


    probeSink =
        probeSink *
            1_000_033UL +
        expectedSignature;
}


private OwnedPolygon fromPoints(
    Point2!double[] points
)
{
    OwnedPolygon result;

    result.points =
        points;

    result.rings =
        new LinearRing2View!double[1];

    result.rings[0] =
        LinearRing2View!double(
            result.points
        );

    result.view =
        Polygon2View!double(
            result.rings[]
        );

    return result;
}


private Point2!double[] regularRing(
    size_t count,
    double centerX,
    double centerY,
    double radius,
    double phase
)
{
    auto points =
        new Point2!double[
            count
        ];

    foreach (i; 0 .. count)
    {
        const double angle =
            phase +
            2.0 *
                cast(double) PI *
                cast(double) i /
                cast(double) count;

        points[i] =
            Point2!double(
                centerX +
                    radius *
                    cos(angle),
                centerY +
                    radius *
                    sin(angle)
            );
    }

    return points;
}


private OwnedPolygon makeRegularPolygon(
    size_t count,
    double centerX,
    double centerY,
    double radius,
    double phase
)
{
    return
        fromPoints(
            regularRing(
                count,
                centerX,
                centerY,
                radius,
                phase
            )
        );
}


private DoubleCase makeRegularCase(
    size_t vertexCount,
    bool overlap
)
{
    DoubleCase result;

    result.first =
        makeRegularPolygon(
            vertexCount,
            0.0,
            0.0,
            100.0,
            0.0
        );

    result.second =
        makeRegularPolygon(
            vertexCount,
            overlap
                ? 35.0
                : 300.0,
            overlap
                ? 5.0
                : 0.0,
            100.0,
            cast(double) PI /
                cast(double)
                    vertexCount
        );

    return result;
}


/*
 * Valid orthogonal comb pair used by the earlier P3 high-crossing probe.
 *
 * Combined source-edge count is 8 * toothCount + 8 and the two operands
 * produce 4 * toothCount^2 proper crossings.
 */
private DoubleCase makeHighCrossingCombCase(
    size_t toothCount
)
{
    alias P = Point2!double;

    enforce(
        toothCount > 0,
        "comb tooth count must be non-zero"
    );

    const double pitch = 4.0;
    const double fingerWidth = 1.0;
    const double baseThickness = 1.0;

    const double width =
        pitch *
        cast(double) toothCount +
        4.0;

    const double height =
        width;


    P[] verticalPoints;

    verticalPoints ~= P(0.0, 0.0);
    verticalPoints ~= P(width, 0.0);
    verticalPoints ~= P(width, baseThickness);

    size_t toothIndex =
        toothCount;

    while (toothIndex > 0)
    {
        --toothIndex;

        const double left =
            2.0 +
            pitch *
            cast(double)
                toothIndex;

        const double right =
            left +
            fingerWidth;

        verticalPoints ~= P(right, baseThickness);
        verticalPoints ~= P(right, height);
        verticalPoints ~= P(left, height);
        verticalPoints ~= P(left, baseThickness);
    }

    verticalPoints ~=
        P(
            0.0,
            baseThickness
        );


    P[] horizontalPoints;

    horizontalPoints ~= P(-2.0, 0.0);
    horizontalPoints ~= P(-1.0, 0.0);

    foreach (i; 0 .. toothCount)
    {
        const double bottom =
            2.0 +
            pitch *
            cast(double) i;

        const double top =
            bottom +
            fingerWidth;

        horizontalPoints ~= P(-1.0, bottom);
        horizontalPoints ~= P(width + 1.0, bottom);
        horizontalPoints ~= P(width + 1.0, top);
        horizontalPoints ~= P(-1.0, top);
    }

    horizontalPoints ~=
        P(
            -1.0,
            height + 1.0
        );

    horizontalPoints ~=
        P(
            -2.0,
            height + 1.0
        );


    DoubleCase result;

    result.first =
        fromPoints(
            verticalPoints
        );

    result.second =
        fromPoints(
            horizontalPoints
        );

    return result;
}


private void runSemanticCases()
{
    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;


    {
        R[] emptyRings;

        runCase(
            "empty-empty",
            G(emptyRings),
            G(emptyRings),
            false
        );
    }


    {
        P[4] invalidPoints = [
            P(0, 0),
            P(4, 4),
            P(0, 4),
            P(4, 0),
        ];

        P[4] validPoints = [
            P(10, 0),
            P(14, 0),
            P(14, 4),
            P(10, 4),
        ];

        R[1] invalidRings = [
            R(invalidPoints[])
        ];

        R[1] validRings = [
            R(validPoints[])
        ];

        runCase(
            "invalid-first",
            G(invalidRings[]),
            G(validRings[]),
            false
        );
    }


    {
        P[4] firstPoints = [
            P(0, 0),
            P(4, 0),
            P(4, 4),
            P(0, 4),
        ];

        P[4] disjointPoints = [
            P(10, 0),
            P(14, 0),
            P(14, 4),
            P(10, 4),
        ];

        P[4] overlapPoints = [
            P(2, 0),
            P(6, 0),
            P(6, 4),
            P(2, 4),
        ];

        P[4] sharedEdgePoints = [
            P(4, 0),
            P(8, 0),
            P(8, 4),
            P(4, 4),
        ];

        P[4] pointContactPoints = [
            P(4, 4),
            P(8, 4),
            P(8, 8),
            P(4, 8),
        ];

        R[1] firstRings = [
            R(firstPoints[])
        ];

        R[1] disjointRings = [
            R(disjointPoints[])
        ];

        R[1] overlapRings = [
            R(overlapPoints[])
        ];

        R[1] sharedEdgeRings = [
            R(sharedEdgePoints[])
        ];

        R[1] pointContactRings = [
            R(pointContactPoints[])
        ];

        runCase(
            "int-disjoint",
            G(firstRings[]),
            G(disjointRings[]),
            false
        );

        runCase(
            "int-overlap",
            G(firstRings[]),
            G(overlapRings[]),
            false
        );

        runCase(
            "int-shared-edge",
            G(firstRings[]),
            G(sharedEdgeRings[]),
            false
        );

        runCase(
            "int-point-contact",
            G(firstRings[]),
            G(pointContactRings[]),
            false
        );
    }


    {
        P[4] outerPoints = [
            P(0, 0),
            P(10, 0),
            P(10, 10),
            P(0, 10),
        ];

        P[4] holePoints = [
            P(2, 2),
            P(8, 2),
            P(8, 8),
            P(2, 8),
        ];

        P[4] islandPoints = [
            P(4, 4),
            P(6, 4),
            P(6, 6),
            P(4, 6),
        ];

        R[2] donutRings = [
            R(outerPoints[]),
            R(holePoints[]),
        ];

        R[1] islandRings = [
            R(islandPoints[])
        ];

        runCase(
            "int-donut-island",
            G(donutRings[]),
            G(islandRings[]),
            false
        );
    }


    {
        alias LP = Point2!long;
        alias LR = LinearRing2View!long;
        alias LG = Polygon2View!long;

        LP[4] points = [
            LP(long.max - 1, 0),
            LP(long.max, 0),
            LP(long.max, 10),
            LP(long.max - 1, 10),
        ];

        LR[1] rings = [
            LR(points[])
        ];

        LR[] emptyRings;

        runCase(
            "long-unrepresentable",
            LG(rings[]),
            LG(emptyRings),
            false
        );
    }
}


void main()
{
    version (GeoPolygonUnionP3Prototype)
    {
        writeln(
            "Polygon Union P3 end-to-end probe: PROTOTYPE"
        );
    }
    else
    {
        writeln(
            "Polygon Union P3 end-to-end probe: P1 BASELINE"
        );
    }


    runSemanticCases();


    auto disjoint16 =
        makeRegularCase(
            16,
            false
        );

    auto disjoint64 =
        makeRegularCase(
            64,
            false
        );

    auto disjoint128 =
        makeRegularCase(
            128,
            false
        );

    auto overlap16 =
        makeRegularCase(
            16,
            true
        );

    auto overlap64 =
        makeRegularCase(
            64,
            true
        );

    auto overlap128 =
        makeRegularCase(
            128,
            true
        );

    auto highCrossing32 =
        makeHighCrossingCombCase(
            3
        );

    auto highCrossing128 =
        makeHighCrossingCombCase(
            15
        );


    runCase(
        "double-disjoint-16",
        disjoint16.first.view,
        disjoint16.second.view,
        true
    );

    runCase(
        "double-disjoint-64",
        disjoint64.first.view,
        disjoint64.second.view,
        true
    );

    runCase(
        "double-disjoint-128",
        disjoint128.first.view,
        disjoint128.second.view,
        true
    );

    runCase(
        "double-overlap-16",
        overlap16.first.view,
        overlap16.second.view,
        true
    );

    runCase(
        "double-overlap-64",
        overlap64.first.view,
        overlap64.second.view,
        true
    );

    runCase(
        "double-overlap-128",
        overlap128.first.view,
        overlap128.second.view,
        true
    );

    runCase(
        "double-high-crossing-32",
        highCrossing32.first.view,
        highCrossing32.second.view,
        true
    );

    runCase(
        "double-high-crossing-128",
        highCrossing128.first.view,
        highCrossing128.second.view,
        true
    );


    writeln();

    writefln(
        "sink=%s",
        probeSink
    );
}
