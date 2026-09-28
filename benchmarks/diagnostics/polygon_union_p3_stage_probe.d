/*
 * Research-only stage probe for Polygon Union P3 qualification.
 *
 * Compile with:
 *
 *     -version=GeoPolygonUnionP3Diagnostics
 *
 * The flag enables package-internal timing/counters in the P1 orchestration.
 * Normal geo-d builds do not contain this instrumentation.
 */
module geo.polygon_union_p3_stage_probe;

import geo;

version (GeoPolygonUnionP3Diagnostics)
{
    import geo.internal.polygon_union_p1 :
        PolygonUnionP3Diagnostics,
        polygonUnionP3Diagnostics;
}
else
{
    static assert(
        false,
        "compile with -version=GeoPolygonUnionP3Diagnostics"
    );
}

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


private struct OwnedPolygon
{
    Point2!double[] points;
    LinearRing2View!double[] rings;
    Polygon2View!double view;
}


private struct UnionCase
{
    OwnedPolygon first;
    OwnedPolygon second;

    size_t expectedComponents;
}


private struct TimingSamples
{
    long[repetitions] total;

    long[repetitions] validationAndSource;
    long[repetitions] nodingSetup;
    long[repetitions] eventStorageAllocation;
    long[repetitions] eventCountAllocation;
    long[repetitions] endpointSeeding;
    long[repetitions] envelopeScan;
    long[repetitions] pairNoding;
    long[repetitions] atomicEdge;
    long[repetitions] arrangementAndRegion;
    long[repetitions] boundaryAndComponent;
    long[repetitions] materialization;
    long[repetitions] postMaterializationValidation;
    long[repetitions] ownership;
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
        new Point2!double[count];

    foreach (i; 0 .. count)
    {
        const double angle =
            phase +
            2.0 * cast(double) PI *
            cast(double) i /
            cast(double) count;

        points[i] =
            Point2!double(
                centerX +
                    radius * cos(angle),
                centerY +
                    radius * sin(angle)
            );
    }

    return points;
}


private OwnedPolygon makePolygon(
    size_t count,
    double centerX,
    double centerY,
    double radius,
    double phase
)
{
    OwnedPolygon result;

    result.points =
        regularRing(
            count,
            centerX,
            centerY,
            radius,
            phase
        );

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


private UnionCase makeCase(
    size_t vertexCount,
    bool overlap
)
{
    UnionCase result;

    result.first =
        makePolygon(
            vertexCount,
            0.0,
            0.0,
            100.0,
            0.0
        );

    result.second =
        makePolygon(
            vertexCount,
            overlap ? 35.0 : 300.0,
            overlap ? 5.0 : 0.0,
            100.0,
            cast(double) PI /
                cast(double) vertexCount
        );

    result.expectedComponents =
        overlap ? 1 : 2;

    return result;
}


private ulong consume(
    ref const PolygonUnionResult result
)
{
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
    }

    return value;
}


private bool sameCounts(
    ref const PolygonUnionP3Diagnostics lhs,
    ref const PolygonUnionP3Diagnostics rhs
)
{
    return
        lhs.sourceEdgeCount == rhs.sourceEdgeCount &&
        lhs.allPairCount == rhs.allPairCount &&
        lhs.envelopeOverlapPairCount == rhs.envelopeOverlapPairCount &&
        lhs.exactPairTestCount == rhs.exactPairTestCount &&
        lhs.eventProducingPairCount == rhs.eventProducingPairCount &&
        lhs.eventStorageSlotCount == rhs.eventStorageSlotCount &&
        lhs.eventStorageElementBytes == rhs.eventStorageElementBytes &&
        lhs.atomicEdgeCount == rhs.atomicEdgeCount &&
        lhs.arrangementVertexCount == rhs.arrangementVertexCount &&
        lhs.arrangementEdgeCount == rhs.arrangementEdgeCount &&
        lhs.boundaryCycleCount == rhs.boundaryCycleCount &&
        lhs.componentCount == rhs.componentCount &&
        lhs.materializedBoundaryEdgeCount ==
            rhs.materializedBoundaryEdgeCount;
}


private long median(
    ref long[repetitions] samples
)
{
    sort(samples[]);

    return
        samples[
            repetitions / 2
        ];
}


private void printTime(
    string name,
    long nanoseconds
)
{
    writefln(
        "  %-34s %12.3f ms",
        name,
        cast(double) nanoseconds /
            1_000_000.0
    );
}


private void runProbe(
    string name,
    ref UnionCase benchmarkCase
)
{
    {
        const warmup =
            polygonUnion(
                benchmarkCase.first.view,
                benchmarkCase.second.view
            );

        enforce(
            warmup.succeeded,
            "warm-up polygon union failed"
        );

        enforce(
            warmup.length ==
                benchmarkCase.expectedComponents,
            "warm-up component count mismatch"
        );

        probeSink =
            probeSink * 1_000_003UL +
            consume(warmup);
    }


    TimingSamples samples;

    PolygonUnionP3Diagnostics expectedCounts;
    bool haveExpectedCounts = false;

    foreach (sample; 0 .. repetitions)
    {
        StopWatch stopwatch;
        stopwatch.start();

        const result =
            polygonUnion(
                benchmarkCase.first.view,
                benchmarkCase.second.view
            );

        stopwatch.stop();

        enforce(
            result.succeeded,
            "measured polygon union failed"
        );

        enforce(
            result.length ==
                benchmarkCase.expectedComponents,
            "measured component count mismatch"
        );

        const diagnostics =
            polygonUnionP3Diagnostics();

        enforce(
            diagnostics.exactPairTestCount ==
                diagnostics.allPairCount,
            "P1 exact-pair count mismatch"
        );

        if (!haveExpectedCounts)
        {
            expectedCounts =
                diagnostics;

            haveExpectedCounts = true;
        }
        else
        {
            enforce(
                sameCounts(
                    expectedCounts,
                    diagnostics
                ),
                "diagnostic counts changed between repetitions"
            );
        }


        samples.total[sample] =
            stopwatch.peek.total!"nsecs";

        samples.validationAndSource[sample] =
            diagnostics.validationAndSourceNs;

        samples.nodingSetup[sample] =
            diagnostics.nodingSetupNs;

        samples.eventStorageAllocation[sample] =
            diagnostics.eventStorageAllocationNs;

        samples.eventCountAllocation[sample] =
            diagnostics.eventCountAllocationNs;

        samples.endpointSeeding[sample] =
            diagnostics.endpointSeedingNs;

        samples.envelopeScan[sample] =
            diagnostics.envelopeScanNs;

        samples.pairNoding[sample] =
            diagnostics.pairNodingNs;

        samples.atomicEdge[sample] =
            diagnostics.atomicEdgeNs;

        samples.arrangementAndRegion[sample] =
            diagnostics.arrangementAndRegionNs;

        samples.boundaryAndComponent[sample] =
            diagnostics.boundaryAndComponentNs;

        samples.materialization[sample] =
            diagnostics.materializationNs;

        samples.postMaterializationValidation[sample] =
            diagnostics.postMaterializationValidationNs;

        samples.ownership[sample] =
            diagnostics.ownershipNs;


        probeSink =
            probeSink * 1_000_033UL +
            consume(result) +
            cast(ulong)
                diagnostics.eventProducingPairCount;
    }


    writeln();
    writeln(name);

    writefln(
        "  source edges                       %12s",
        expectedCounts.sourceEdgeCount
    );

    writefln(
        "  all source-edge pairs              %12s",
        expectedCounts.allPairCount
    );

    writefln(
        "  envelope-overlap pairs             %12s",
        expectedCounts.envelopeOverlapPairCount
    );

    writefln(
        "  P1 exact pair tests                %12s",
        expectedCounts.exactPairTestCount
    );

    writefln(
        "  event-producing pairs              %12s",
        expectedCounts.eventProducingPairCount
    );

    const double eventStorageMiB =
        cast(double)
            expectedCounts.eventStorageSlotCount *
        cast(double)
            expectedCounts.eventStorageElementBytes /
        (1024.0 * 1024.0);

    writefln(
        "  event storage slots                %12s",
        expectedCounts.eventStorageSlotCount
    );

    writefln(
        "  ExactOverlayPoint bytes            %12s",
        expectedCounts.eventStorageElementBytes
    );

    writefln(
        "  event storage payload              %12.3f MiB",
        eventStorageMiB
    );

    writefln(
        "  atomic / arrangement edges         %6s / %-6s",
        expectedCounts.atomicEdgeCount,
        expectedCounts.arrangementEdgeCount
    );

    writefln(
        "  arrangement vertices               %12s",
        expectedCounts.arrangementVertexCount
    );

    writefln(
        "  cycles / components                %6s / %-6s",
        expectedCounts.boundaryCycleCount,
        expectedCounts.componentCount
    );

    writefln(
        "  materialized boundary edges        %12s",
        expectedCounts.materializedBoundaryEdgeCount
    );

    writeln("  median timings:");

    printTime(
        "diagnostic public call",
        median(samples.total)
    );

    printTime(
        "validation + source build",
        median(samples.validationAndSource)
    );

    printTime(
        "noding setup",
        median(samples.nodingSetup)
    );

    printTime(
        "  exact-event allocation",
        median(samples.eventStorageAllocation)
    );

    printTime(
        "  event-count allocation",
        median(samples.eventCountAllocation)
    );

    printTime(
        "  endpoint seeding",
        median(samples.endpointSeeding)
    );

    printTime(
        "envelope scan (diagnostic only)",
        median(samples.envelopeScan)
    );

    printTime(
        "P1 all-pairs exact noding",
        median(samples.pairNoding)
    );

    printTime(
        "event sort + atomic edges",
        median(samples.atomicEdge)
    );

    printTime(
        "arrangement + region labels",
        median(samples.arrangementAndRegion)
    );

    printTime(
        "boundary + components",
        median(samples.boundaryAndComponent)
    );

    printTime(
        "materialization",
        median(samples.materialization)
    );

    printTime(
        "post-materialization validation",
        median(samples.postMaterializationValidation)
    );

    printTime(
        "ownership finalization",
        median(samples.ownership)
    );
}


void main()
{
    auto disjoint16 =
        makeCase(16, false);

    auto disjoint64 =
        makeCase(64, false);

    auto disjoint128 =
        makeCase(128, false);

    auto overlap16 =
        makeCase(16, true);

    auto overlap64 =
        makeCase(64, true);

    auto overlap128 =
        makeCase(128, true);


    writeln(
        "Polygon Union P3 research stage probe"
    );

    writeln(
        "The envelope scan is diagnostic-only and is not part of merged P1."
    );

    runProbe(
        "disjoint convex: 16 + 16 vertices",
        disjoint16
    );

    runProbe(
        "disjoint convex: 64 + 64 vertices",
        disjoint64
    );

    runProbe(
        "disjoint convex: 128 + 128 vertices",
        disjoint128
    );

    runProbe(
        "overlap convex: 16 + 16 vertices",
        overlap16
    );

    runProbe(
        "overlap convex: 64 + 64 vertices",
        overlap64
    );

    runProbe(
        "overlap convex: 128 + 128 vertices",
        overlap128
    );


    writeln();

    writefln(
        "sink=%s",
        probeSink
    );
}
