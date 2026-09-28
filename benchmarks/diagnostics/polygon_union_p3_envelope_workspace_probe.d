/*
 * Research-only control probe for Polygon Union P3 candidate gating.
 *
 * This file does not modify polygonUnion() or the production P1 orchestration.
 *
 * It compares two exact-sized event-workspace strategies:
 *
 * 1. exact contact classification for every source-edge pair;
 * 2. the same deterministic all-pairs traversal, but exact classification is
 *    performed only when the closed source-coordinate segment envelopes
 *    overlap.
 *
 * The second strategy deliberately remains O(n^2) in cheap envelope tests.
 * It is a low-complexity control, not a sweep-line implementation and not a
 * reusable spatial-index/container abstraction.
 */
module geo.polygon_union_p3_envelope_workspace_probe;

import geo;

import geo.internal.polygon_union_exact :
    ExactOverlayPoint,
    appendSegmentPairNodingEvents,
    exactOverlayPointsEqual,
    seedExactEdgeEvents;

import geo.internal.polygon_union_input :
    ExactPolygonBoundaryEdge,
    buildExactPolygonBoundaryEdges,
    tryPolygonBoundaryEdgeCount;

import geo.internal.polygon_union_noding :
    polygonUnionOperandA,
    polygonUnionOperandB;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind;

import geo.topology_validation :
    validatePolygon;

import core.memory :
    GC;

import core.time :
    MonoTime;

import std.algorithm.sorting :
    sort;

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
}


private struct WorkspaceBuild
{
    ExactOverlayPoint[] storage;
    size_t[] counts;
    size_t[] offsets;

    size_t allocatedSlots;

    size_t countEnvelopeTests;
    size_t countExactTests;

    size_t appendEnvelopeTests;
    size_t appendExactTests;

    long totalNs;
    long capacityCountNs;
    long offsetBuildNs;
    long storageAllocationNs;
    long endpointSeedingNs;
    long appendNs;
}


private struct TimingSamples
{
    long[repetitions] total;
    long[repetitions] capacityCount;
    long[repetitions] offsetBuild;
    long[repetitions] storageAllocation;
    long[repetitions] endpointSeeding;
    long[repetitions] append;
}


private long elapsedNs(
    MonoTime start
)
{
    return
        (
            MonoTime.currTime -
            start
        ).total!"nsecs";
}


private bool checkedAdd(
    size_t lhs,
    size_t rhs,
    out size_t result
)
{
    result = 0;

    if (
        lhs >
        size_t.max - rhs
    )
    {
        return false;
    }

    result =
        lhs + rhs;

    return true;
}


private size_t requiredEvents(
    SegmentContactKind contact
)
{
    final switch (contact)
    {
        case SegmentContactKind.none:
            return 0;

        case SegmentContactKind.touch:
        case SegmentContactKind.properCrossing:
            return 1;

        case SegmentContactKind.overlap:
            return 2;
    }
}


private bool envelopesOverlap(
    Segment2!double first,
    Segment2!double second
)
{
    const double firstMinX =
        first.a.x < first.b.x
            ? first.a.x
            : first.b.x;

    const double firstMaxX =
        first.a.x < first.b.x
            ? first.b.x
            : first.a.x;

    const double firstMinY =
        first.a.y < first.b.y
            ? first.a.y
            : first.b.y;

    const double firstMaxY =
        first.a.y < first.b.y
            ? first.b.y
            : first.a.y;

    const double secondMinX =
        second.a.x < second.b.x
            ? second.a.x
            : second.b.x;

    const double secondMaxX =
        second.a.x < second.b.x
            ? second.b.x
            : second.a.x;

    const double secondMinY =
        second.a.y < second.b.y
            ? second.a.y
            : second.b.y;

    const double secondMaxY =
        second.a.y < second.b.y
            ? second.b.y
            : second.a.y;

    return
        firstMaxX >= secondMinX &&
        secondMaxX >= firstMinX &&
        firstMaxY >= secondMinY &&
        secondMaxY >= firstMinY;
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

    return result;
}


private ExactPolygonBoundaryEdge!double[] buildSources(
    ref UnionCase benchmarkCase
)
{
    enforce(
        validatePolygon(
            benchmarkCase.first.view
        ).valid,
        "first diagnostic polygon is invalid"
    );

    enforce(
        validatePolygon(
            benchmarkCase.second.view
        ).valid,
        "second diagnostic polygon is invalid"
    );

    size_t firstCount;
    size_t secondCount;

    enforce(
        tryPolygonBoundaryEdgeCount(
            benchmarkCase.first.view,
            firstCount
        ),
        "first source-edge count overflow"
    );

    enforce(
        tryPolygonBoundaryEdgeCount(
            benchmarkCase.second.view,
            secondCount
        ),
        "second source-edge count overflow"
    );

    size_t sourceCount;

    enforce(
        checkedAdd(
            firstCount,
            secondCount,
            sourceCount
        ),
        "combined source-edge count overflow"
    );

    auto sources =
        new ExactPolygonBoundaryEdge!double[
            sourceCount
        ];

    size_t builtFirst;
    size_t builtSecond;

    enforce(
        buildExactPolygonBoundaryEdges(
            benchmarkCase.first.view,
            polygonUnionOperandA,
            sources[
                0 ..
                firstCount
            ],
            builtFirst
        ) &&
        builtFirst == firstCount,
        "first source-edge build failed"
    );

    enforce(
        buildExactPolygonBoundaryEdges(
            benchmarkCase.second.view,
            polygonUnionOperandB,
            sources[
                firstCount ..
                sourceCount
            ],
            builtSecond
        ) &&
        builtSecond == secondCount,
        "second source-edge build failed"
    );

    return sources;
}


private WorkspaceBuild buildWorkspace(
    scope ExactPolygonBoundaryEdge!double[] sources,
    bool envelopeGated
)
{
    WorkspaceBuild result;

    const MonoTime totalStart =
        MonoTime.currTime;

    const size_t sourceCount =
        sources.length;

    auto capacities =
        new size_t[
            sourceCount
        ];

    foreach (ref capacity; capacities)
    {
        capacity = 2;
    }


    MonoTime stageStart =
        MonoTime.currTime;

    foreach (firstIndex; 0 .. sourceCount)
    {
        foreach (
            secondIndex;
            firstIndex + 1 ..
            sourceCount
        )
        {
            if (envelopeGated)
            {
                ++result.countEnvelopeTests;

                if (
                    !envelopesOverlap(
                        sources[
                            firstIndex
                        ].segment,
                        sources[
                            secondIndex
                        ].segment
                    )
                )
                {
                    continue;
                }
            }

            ++result.countExactTests;

            const size_t required =
                requiredEvents(
                    segmentContactKind(
                        sources[
                            firstIndex
                        ].segment,
                        sources[
                            secondIndex
                        ].segment
                    )
                );

            if (required == 0)
                continue;

            size_t firstUpdated;
            size_t secondUpdated;

            enforce(
                checkedAdd(
                    capacities[
                        firstIndex
                    ],
                    required,
                    firstUpdated
                ) &&
                checkedAdd(
                    capacities[
                        secondIndex
                    ],
                    required,
                    secondUpdated
                ),
                "event capacity overflow"
            );

            capacities[
                firstIndex
            ] =
                firstUpdated;

            capacities[
                secondIndex
            ] =
                secondUpdated;
        }
    }

    result.capacityCountNs =
        elapsedNs(stageStart);


    stageStart =
        MonoTime.currTime;

    result.offsets =
        new size_t[
            sourceCount + 1
        ];

    foreach (sourceIndex; 0 .. sourceCount)
    {
        enforce(
            checkedAdd(
                result.offsets[
                    sourceIndex
                ],
                capacities[
                    sourceIndex
                ],
                result.offsets[
                    sourceIndex + 1
                ]
            ),
            "event offset overflow"
        );
    }

    result.allocatedSlots =
        result.offsets[
            sourceCount
        ];

    result.offsetBuildNs =
        elapsedNs(stageStart);


    stageStart =
        MonoTime.currTime;

    result.storage =
        new ExactOverlayPoint[
            result.allocatedSlots
        ];

    result.storageAllocationNs =
        elapsedNs(stageStart);


    result.counts =
        new size_t[
            sourceCount
        ];


    stageStart =
        MonoTime.currTime;

    foreach (sourceIndex; 0 .. sourceCount)
    {
        const size_t begin =
            result.offsets[
                sourceIndex
            ];

        const size_t capacity =
            result.offsets[
                sourceIndex + 1
            ] -
            begin;

        size_t count;

        enforce(
            seedExactEdgeEvents(
                sources[
                    sourceIndex
                ].segment,
                result.storage[
                    begin ..
                    begin +
                    capacity
                ],
                count
            ),
            "endpoint seeding failed"
        );

        result.counts[
            sourceIndex
        ] =
            count;
    }

    result.endpointSeedingNs =
        elapsedNs(stageStart);


    stageStart =
        MonoTime.currTime;

    foreach (firstIndex; 0 .. sourceCount)
    {
        const size_t firstBegin =
            result.offsets[
                firstIndex
            ];

        const size_t firstCapacity =
            result.offsets[
                firstIndex + 1
            ] -
            firstBegin;

        foreach (
            secondIndex;
            firstIndex + 1 ..
            sourceCount
        )
        {
            if (envelopeGated)
            {
                ++result.appendEnvelopeTests;

                if (
                    !envelopesOverlap(
                        sources[
                            firstIndex
                        ].segment,
                        sources[
                            secondIndex
                        ].segment
                    )
                )
                {
                    continue;
                }
            }

            ++result.appendExactTests;

            const size_t secondBegin =
                result.offsets[
                    secondIndex
                ];

            const size_t secondCapacity =
                result.offsets[
                    secondIndex + 1
                ] -
                secondBegin;

            enforce(
                appendSegmentPairNodingEvents(
                    sources[
                        firstIndex
                    ].segment,
                    sources[
                        secondIndex
                    ].segment,
                    result.storage[
                        firstBegin ..
                        firstBegin +
                        firstCapacity
                    ],
                    result.counts[
                        firstIndex
                    ],
                    result.storage[
                        secondBegin ..
                        secondBegin +
                        secondCapacity
                    ],
                    result.counts[
                        secondIndex
                    ]
                ),
                "event append failed"
            );
        }
    }

    result.appendNs =
        elapsedNs(stageStart);

    result.totalNs =
        elapsedNs(totalStart);

    return result;
}


private void verifyEquivalent(
    ref const WorkspaceBuild allPairs,
    ref const WorkspaceBuild envelopeGated
)
{
    enforce(
        allPairs.counts.length ==
            envelopeGated.counts.length,
        "workspace edge-count mismatch"
    );

    enforce(
        allPairs.allocatedSlots ==
            envelopeGated.allocatedSlots,
        "workspace allocated-slot mismatch"
    );

    enforce(
        allPairs.countExactTests ==
            allPairs.appendExactTests,
        "all-pairs exact-test mismatch"
    );

    enforce(
        envelopeGated.countEnvelopeTests ==
            allPairs.countExactTests &&
        envelopeGated.appendEnvelopeTests ==
            allPairs.appendExactTests,
        "envelope traversal pair-count mismatch"
    );

    enforce(
        envelopeGated.countExactTests ==
            envelopeGated.appendExactTests,
        "envelope exact-test mismatch"
    );

    foreach (
        sourceIndex;
        0 ..
        allPairs.counts.length
    )
    {
        enforce(
            allPairs.counts[
                sourceIndex
            ] ==
            envelopeGated.counts[
                sourceIndex
            ],
            "workspace event-count mismatch"
        );

        const size_t allBegin =
            allPairs.offsets[
                sourceIndex
            ];

        const size_t envelopeBegin =
            envelopeGated.offsets[
                sourceIndex
            ];

        foreach (
            eventIndex;
            0 ..
            allPairs.counts[
                sourceIndex
            ]
        )
        {
            enforce(
                exactOverlayPointsEqual(
                    allPairs.storage[
                        allBegin +
                        eventIndex
                    ],
                    envelopeGated.storage[
                        envelopeBegin +
                        eventIndex
                    ]
                ),
                "workspace exact event mismatch"
            );
        }
    }
}


private ulong consumeWorkspace(
    ref const WorkspaceBuild workspace
)
{
    ulong value =
        cast(ulong)
            workspace.allocatedSlots +
        1;

    value =
        value * 1_000_003UL +
        cast(ulong)
            workspace.countExactTests;

    value =
        value * 1_000_033UL +
        cast(ulong)
            workspace.appendExactTests;

    foreach (count; workspace.counts)
    {
        value =
            value * 1_000_037UL +
            cast(ulong) count;
    }

    return value;
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


private void record(
    ref TimingSamples samples,
    size_t sample,
    ref const WorkspaceBuild workspace
)
{
    samples.total[sample] =
        workspace.totalNs;

    samples.capacityCount[sample] =
        workspace.capacityCountNs;

    samples.offsetBuild[sample] =
        workspace.offsetBuildNs;

    samples.storageAllocation[sample] =
        workspace.storageAllocationNs;

    samples.endpointSeeding[sample] =
        workspace.endpointSeedingNs;

    samples.append[sample] =
        workspace.appendNs;
}


private void printTime(
    string name,
    long nanoseconds
)
{
    writefln(
        "    %-30s %10.3f ms",
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
    auto sources =
        buildSources(
            benchmarkCase
        );

    {
        auto allPairs =
            buildWorkspace(
                sources,
                false
            );

        auto envelopeGated =
            buildWorkspace(
                sources,
                true
            );

        verifyEquivalent(
            allPairs,
            envelopeGated
        );

        probeSink =
            probeSink * 1_000_081UL +
            consumeWorkspace(allPairs) +
            consumeWorkspace(envelopeGated);
    }

    GC.collect();


    TimingSamples allPairsSamples;
    TimingSamples envelopeSamples;

    size_t allPairsCount;
    size_t candidateCount;
    size_t allocatedSlots;

    foreach (sample; 0 .. repetitions)
    {
        if ((sample & 1) == 0)
        {
            {
                auto allPairs =
                    buildWorkspace(
                        sources,
                        false
                    );

                record(
                    allPairsSamples,
                    sample,
                    allPairs
                );

                allPairsCount =
                    allPairs.countExactTests;

                allocatedSlots =
                    allPairs.allocatedSlots;

                probeSink =
                    probeSink * 1_000_003UL +
                    consumeWorkspace(
                        allPairs
                    );
            }

            {
                auto envelopeGated =
                    buildWorkspace(
                        sources,
                        true
                    );

                record(
                    envelopeSamples,
                    sample,
                    envelopeGated
                );

                candidateCount =
                    envelopeGated
                        .countExactTests;

                probeSink =
                    probeSink * 1_000_033UL +
                    consumeWorkspace(
                        envelopeGated
                    );
            }
        }
        else
        {
            {
                auto envelopeGated =
                    buildWorkspace(
                        sources,
                        true
                    );

                record(
                    envelopeSamples,
                    sample,
                    envelopeGated
                );

                candidateCount =
                    envelopeGated
                        .countExactTests;

                probeSink =
                    probeSink * 1_000_033UL +
                    consumeWorkspace(
                        envelopeGated
                    );
            }

            {
                auto allPairs =
                    buildWorkspace(
                        sources,
                        false
                    );

                record(
                    allPairsSamples,
                    sample,
                    allPairs
                );

                allPairsCount =
                    allPairs.countExactTests;

                allocatedSlots =
                    allPairs.allocatedSlots;

                probeSink =
                    probeSink * 1_000_003UL +
                    consumeWorkspace(
                        allPairs
                    );
            }
        }

        GC.collect();
    }


    const double candidatePercent =
        allPairsCount == 0
            ? 0.0
            : 100.0 *
                cast(double)
                    candidateCount /
                cast(double)
                    allPairsCount;

    const double payloadMiB =
        cast(double)
            allocatedSlots *
        cast(double)
            ExactOverlayPoint.sizeof /
        (1024.0 * 1024.0);

    const long allPairsTotal =
        median(
            allPairsSamples.total
        );

    const long envelopeTotal =
        median(
            envelopeSamples.total
        );

    const double speedRatio =
        envelopeTotal == 0
            ? 0.0
            : cast(double)
                allPairsTotal /
              cast(double)
                envelopeTotal;


    writeln();
    writeln(name);

    writefln(
        "  source edges                       %12s",
        sources.length
    );

    writefln(
        "  all source-edge pairs              %12s",
        allPairsCount
    );

    writefln(
        "  envelope candidates                %12s",
        candidateCount
    );

    writefln(
        "  candidate fraction                 %12.3f %%",
        candidatePercent
    );

    writefln(
        "  exact-sized event slots            %12s",
        allocatedSlots
    );

    writefln(
        "  exact event payload                %12.3f MiB",
        payloadMiB
    );


    writeln("  exact-sized / all exact pairs:");

    printTime(
        "total noding workspace",
        allPairsTotal
    );

    printTime(
        "capacity-count pass",
        median(
            allPairsSamples.capacityCount
        )
    );

    printTime(
        "all-pairs append",
        median(
            allPairsSamples.append
        )
    );


    writeln("  exact-sized / envelope gated:");

    printTime(
        "total noding workspace",
        envelopeTotal
    );

    printTime(
        "envelope+count pass",
        median(
            envelopeSamples.capacityCount
        )
    );

    printTime(
        "envelope+append pass",
        median(
            envelopeSamples.append
        )
    );

    writefln(
        "  all-exact / envelope total ratio   %12.3f x",
        speedRatio
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
        "Polygon Union P3 envelope-gated workspace probe"
    );

    writeln(
        "Both strategies use exact-sized event storage and deterministic all-pairs order."
    );

    writeln(
        "Envelope gating remains O(n^2) and introduces no reusable spatial index."
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
