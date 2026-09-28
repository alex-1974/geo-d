/*
 * Research-only candidate-discovery comparison for Polygon Union P3.
 *
 * Compares:
 *   1. two precomputed-envelope all-pairs scans;
 *   2. one deterministic X sweep-and-prune setup + two sweep scans.
 *
 * This probe measures envelope candidate discovery only. Exact segment
 * classification/event construction is deliberately outside the timed region
 * because both strategies feed the same candidate pairs into the same exact
 * predicates.
 */
module geo.polygon_union_p3_sweep_prune_probe;

import geo;

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


private struct EdgeEnvelope
{
    double minX;
    double maxX;
    double minY;
    double maxY;
}


private struct CandidateStats
{
    size_t candidates;
    size_t xWindowPairs;
    ulong sum;
    ulong xor;
}


private struct TimingSamples
{
    long[repetitions] allPairsTwoPass;
    long[repetitions] sweepSetup;
    long[repetitions] sweepTwoPass;
    long[repetitions] sweepTotal;
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


private ulong pairKey(
    size_t first,
    size_t second
)
{
    if (second < first)
    {
        const size_t temporary =
            first;

        first =
            second;

        second =
            temporary;
    }

    return
        (
            cast(ulong) first <<
            32
        ) |
        cast(ulong) second;
}


private ulong pairHash(
    ulong key
)
{
    key ^=
        key >> 30;

    key *=
        0xbf58476d1ce4e5b9UL;

    key ^=
        key >> 27;

    key *=
        0x94d049bb133111ebUL;

    key ^=
        key >> 31;

    return key;
}


private void recordCandidate(
    ref CandidateStats stats,
    size_t first,
    size_t second
)
{
    const ulong hash =
        pairHash(
            pairKey(
                first,
                second
            )
        );

    ++stats.candidates;

    stats.sum +=
        hash;

    stats.xor ^=
        hash;
}


private bool envelopesOverlap(
    ref const EdgeEnvelope first,
    ref const EdgeEnvelope second
)
{
    return
        first.maxX >= second.minX &&
        second.maxX >= first.minX &&
        first.maxY >= second.minY &&
        second.maxY >= first.minY;
}


private bool yOverlaps(
    ref const EdgeEnvelope first,
    ref const EdgeEnvelope second
)
{
    return
        first.maxY >= second.minY &&
        second.maxY >= first.minY;
}


private EdgeEnvelope[] buildEnvelopes(
    scope Segment2!double[] segments
)
{
    auto result =
        new EdgeEnvelope[
            segments.length
        ];

    foreach (i, segment; segments)
    {
        result[i] =
            EdgeEnvelope(
                segment.a.x < segment.b.x
                    ? segment.a.x
                    : segment.b.x,
                segment.a.x < segment.b.x
                    ? segment.b.x
                    : segment.a.x,
                segment.a.y < segment.b.y
                    ? segment.a.y
                    : segment.b.y,
                segment.a.y < segment.b.y
                    ? segment.b.y
                    : segment.a.y
            );
    }

    return result;
}


private CandidateStats allPairsCandidates(
    scope const EdgeEnvelope[] envelopes
)
{
    CandidateStats stats;

    foreach (first; 0 .. envelopes.length)
    {
        foreach (
            second;
            first + 1 ..
            envelopes.length
        )
        {
            if (
                envelopesOverlap(
                    envelopes[first],
                    envelopes[second]
                )
            )
            {
                recordCandidate(
                    stats,
                    first,
                    second
                );
            }
        }
    }

    return stats;
}


private size_t[] buildSweepOrder(
    scope const EdgeEnvelope[] envelopes
)
{
    auto order =
        new size_t[
            envelopes.length
        ];

    foreach (i; 0 .. order.length)
    {
        order[i] =
            i;
    }

    sort!(
        (lhs, rhs)
        {
            const left =
                envelopes[lhs];

            const right =
                envelopes[rhs];

            if (left.minX < right.minX)
                return true;

            if (right.minX < left.minX)
                return false;

            if (left.minY < right.minY)
                return true;

            if (right.minY < left.minY)
                return false;

            if (left.maxX < right.maxX)
                return true;

            if (right.maxX < left.maxX)
                return false;

            if (left.maxY < right.maxY)
                return true;

            if (right.maxY < left.maxY)
                return false;

            return
                lhs <
                rhs;
        }
    )(
        order
    );

    return order;
}


private CandidateStats sweepCandidates(
    scope const EdgeEnvelope[] envelopes,
    scope const size_t[] order
)
{
    CandidateStats stats;

    foreach (
        sweepIndex;
        0 ..
        order.length
    )
    {
        const size_t first =
            order[
                sweepIndex
            ];

        const auto firstEnvelope =
            envelopes[
                first
            ];

        foreach (
            nextSweepIndex;
            sweepIndex + 1 ..
            order.length
        )
        {
            const size_t second =
                order[
                    nextSweepIndex
                ];

            const auto secondEnvelope =
                envelopes[
                    second
                ];

            if (
                secondEnvelope.minX >
                firstEnvelope.maxX
            )
            {
                break;
            }

            ++stats.xWindowPairs;

            if (
                yOverlaps(
                    firstEnvelope,
                    secondEnvelope
                )
            )
            {
                recordCandidate(
                    stats,
                    first,
                    second
                );
            }
        }
    }

    return stats;
}


private ulong[] allPairsKeys(
    scope const EdgeEnvelope[] envelopes
)
{
    ulong[] result;

    foreach (first; 0 .. envelopes.length)
    {
        foreach (
            second;
            first + 1 ..
            envelopes.length
        )
        {
            if (
                envelopesOverlap(
                    envelopes[first],
                    envelopes[second]
                )
            )
            {
                result ~=
                    pairKey(
                        first,
                        second
                    );
            }
        }
    }

    return result;
}


private ulong[] sweepKeys(
    scope const EdgeEnvelope[] envelopes,
    scope const size_t[] order
)
{
    ulong[] result;

    foreach (
        sweepIndex;
        0 ..
        order.length
    )
    {
        const size_t first =
            order[
                sweepIndex
            ];

        const auto firstEnvelope =
            envelopes[
                first
            ];

        foreach (
            nextSweepIndex;
            sweepIndex + 1 ..
            order.length
        )
        {
            const size_t second =
                order[
                    nextSweepIndex
                ];

            const auto secondEnvelope =
                envelopes[
                    second
                ];

            if (
                secondEnvelope.minX >
                firstEnvelope.maxX
            )
            {
                break;
            }

            if (
                yOverlaps(
                    firstEnvelope,
                    secondEnvelope
                )
            )
            {
                result ~=
                    pairKey(
                        first,
                        second
                    );
            }
        }
    }

    return result;
}


private void verifyCandidates(
    scope const EdgeEnvelope[] envelopes
)
{
    auto order =
        buildSweepOrder(
            envelopes
        );

    auto allKeys =
        allPairsKeys(
            envelopes
        );

    auto sweepPairKeys =
        sweepKeys(
            envelopes,
            order
        );

    sort(
        allKeys
    );

    sort(
        sweepPairKeys
    );

    enforce(
        allKeys ==
            sweepPairKeys,
        "sweep-and-prune candidate set differs from all-pairs AABB set"
    );
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


private Segment2!double[] ringSegments(
    scope const Point2!double[] points
)
{
    auto segments =
        new Segment2!double[
            points.length
        ];

    foreach (i; 0 .. points.length)
    {
        const size_t next =
            i + 1 ==
                points.length
                    ? 0
                    : i + 1;

        segments[i] =
            Segment2!double(
                points[i],
                points[next]
            );
    }

    return segments;
}


private Segment2!double[] regularCaseSegments(
    size_t perRing,
    bool overlap
)
{
    auto firstPoints =
        regularRing(
            perRing,
            0.0,
            0.0,
            100.0,
            0.0
        );

    auto secondPoints =
        regularRing(
            perRing,
            overlap
                ? 35.0
                : 300.0,
            overlap
                ? 5.0
                : 0.0,
            100.0,
            cast(double) PI /
                cast(double) perRing
        );

    auto firstSegments =
        ringSegments(
            firstPoints
        );

    auto secondSegments =
        ringSegments(
            secondPoints
        );

    auto result =
        new Segment2!double[
            firstSegments.length +
            secondSegments.length
        ];

    result[
        0 ..
        firstSegments.length
    ] =
        firstSegments[];

    result[
        firstSegments.length ..
        $
    ] =
        secondSegments[];

    return result;
}


private Point2!double[] verticalCombPoints(
    size_t toothCount
)
{
    alias P = Point2!double;

    const double pitch = 4.0;
    const double fingerWidth = 1.0;
    const double baseThickness = 1.0;

    const double width =
        pitch *
        cast(double) toothCount +
        4.0;

    const double height =
        width;

    P[] points;

    points ~= P(0.0, 0.0);
    points ~= P(width, 0.0);
    points ~= P(width, baseThickness);

    size_t toothIndex =
        toothCount;

    while (toothIndex > 0)
    {
        --toothIndex;

        const double left =
            2.0 +
            pitch *
            cast(double) toothIndex;

        const double right =
            left +
            fingerWidth;

        points ~= P(right, baseThickness);
        points ~= P(right, height);
        points ~= P(left, height);
        points ~= P(left, baseThickness);
    }

    points ~= P(0.0, baseThickness);

    return points;
}


private Point2!double[] horizontalCombPoints(
    size_t toothCount
)
{
    alias P = Point2!double;

    const double pitch = 4.0;
    const double fingerWidth = 1.0;

    const double width =
        pitch *
        cast(double) toothCount +
        4.0;

    const double height =
        width;

    P[] points;

    points ~= P(-2.0, 0.0);
    points ~= P(-1.0, 0.0);

    foreach (i; 0 .. toothCount)
    {
        const double bottom =
            2.0 +
            pitch *
            cast(double) i;

        const double top =
            bottom +
            fingerWidth;

        points ~= P(-1.0, bottom);
        points ~= P(width + 1.0, bottom);
        points ~= P(width + 1.0, top);
        points ~= P(-1.0, top);
    }

    points ~= P(-1.0, height + 1.0);
    points ~= P(-2.0, height + 1.0);

    return points;
}


private Segment2!double[] highCrossingCombSegments(
    size_t toothCount
)
{
    auto first =
        ringSegments(
            verticalCombPoints(
                toothCount
            )
        );

    auto second =
        ringSegments(
            horizontalCombPoints(
                toothCount
            )
        );

    auto result =
        new Segment2!double[
            first.length +
            second.length
        ];

    result[
        0 ..
        first.length
    ] =
        first[];

    result[
        first.length ..
        $
    ] =
        second[];

    return result;
}


private Segment2!double[] concurrentSegments(
    size_t count
)
{
    auto result =
        new Segment2!double[
            count
        ];

    foreach (i; 0 .. count)
    {
        const double angle =
            cast(double) PI *
            cast(double) i /
            cast(double) count;

        const double x =
            cos(angle);

        const double y =
            sin(angle);

        result[i] =
            Segment2!double(
                Point2!double(
                    -x,
                    -y
                ),
                Point2!double(
                    x,
                    y
                )
            );
    }

    return result;
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


private void runProbe(
    string name,
    scope Segment2!double[] segments
)
{
    auto envelopes =
        buildEnvelopes(
            segments
        );

    verifyCandidates(
        envelopes
    );


    const CandidateStats expected =
        allPairsCandidates(
            envelopes
        );

    auto expectedOrder =
        buildSweepOrder(
            envelopes
        );

    const CandidateStats expectedSweep =
        sweepCandidates(
            envelopes,
            expectedOrder
        );

    enforce(
        expected.candidates ==
            expectedSweep.candidates &&
        expected.sum ==
            expectedSweep.sum &&
        expected.xor ==
            expectedSweep.xor,
        "candidate fingerprints differ"
    );


    TimingSamples samples;

    foreach (sample; 0 .. repetitions)
    {
        if ((sample & 1) == 0)
        {
            MonoTime start =
                MonoTime.currTime;

            const CandidateStats first =
                allPairsCandidates(
                    envelopes
                );

            const CandidateStats second =
                allPairsCandidates(
                    envelopes
                );

            samples.allPairsTwoPass[sample] =
                elapsedNs(
                    start
                );


            const MonoTime sweepStart =
                MonoTime.currTime;

            start =
                sweepStart;

            auto order =
                buildSweepOrder(
                    envelopes
                );

            samples.sweepSetup[sample] =
                elapsedNs(
                    start
                );


            start =
                MonoTime.currTime;

            const CandidateStats sweepFirst =
                sweepCandidates(
                    envelopes,
                    order
                );

            const CandidateStats sweepSecond =
                sweepCandidates(
                    envelopes,
                    order
                );

            samples.sweepTwoPass[sample] =
                elapsedNs(
                    start
                );

            samples.sweepTotal[sample] =
                elapsedNs(
                    sweepStart
                );


            probeSink ^=
                first.sum +
                second.xor +
                sweepFirst.sum +
                sweepSecond.xor;
        }
        else
        {
            const MonoTime sweepStart =
                MonoTime.currTime;

            MonoTime start =
                sweepStart;

            auto order =
                buildSweepOrder(
                    envelopes
                );

            samples.sweepSetup[sample] =
                elapsedNs(
                    start
                );


            start =
                MonoTime.currTime;

            const CandidateStats sweepFirst =
                sweepCandidates(
                    envelopes,
                    order
                );

            const CandidateStats sweepSecond =
                sweepCandidates(
                    envelopes,
                    order
                );

            samples.sweepTwoPass[sample] =
                elapsedNs(
                    start
                );

            samples.sweepTotal[sample] =
                elapsedNs(
                    sweepStart
                );


            start =
                MonoTime.currTime;

            const CandidateStats first =
                allPairsCandidates(
                    envelopes
                );

            const CandidateStats second =
                allPairsCandidates(
                    envelopes
                );

            samples.allPairsTwoPass[sample] =
                elapsedNs(
                    start
                );


            probeSink ^=
                first.sum +
                second.xor +
                sweepFirst.sum +
                sweepSecond.xor;
        }
    }


    const size_t allPairCount =
        segments.length *
        (segments.length - 1) /
        2;

    const double candidatePercent =
        allPairCount == 0
            ? 0.0
            : 100.0 *
                cast(double)
                    expected.candidates /
                cast(double)
                    allPairCount;

    const double xWindowPercent =
        allPairCount == 0
            ? 0.0
            : 100.0 *
                cast(double)
                    expectedSweep.xWindowPairs /
                cast(double)
                    allPairCount;

    const long allPairsNs =
        median(
            samples.allPairsTwoPass
        );

    const long sweepNs =
        median(
            samples.sweepTotal
        );

    const double ratio =
        sweepNs == 0
            ? 0.0
            : cast(double)
                allPairsNs /
              cast(double)
                sweepNs;


    writeln();
    writeln(name);

    writefln(
        "  source edges                       %12s",
        segments.length
    );

    writefln(
        "  all source-edge pairs              %12s",
        allPairCount
    );

    writefln(
        "  AABB candidates                    %12s",
        expected.candidates
    );

    writefln(
        "  candidate fraction                 %12.3f %%",
        candidatePercent
    );

    writefln(
        "  sweep X-window pairs               %12s",
        expectedSweep.xWindowPairs
    );

    writefln(
        "  X-window fraction                  %12.3f %%",
        xWindowPercent
    );

    writefln(
        "  all-pairs two-pass                 %12.3f ms",
        cast(double)
            allPairsNs /
        1_000_000.0
    );

    writefln(
        "  sweep setup                        %12.3f ms",
        cast(double)
            median(
                samples.sweepSetup
            ) /
        1_000_000.0
    );

    writefln(
        "  sweep two-pass                     %12.3f ms",
        cast(double)
            median(
                samples.sweepTwoPass
            ) /
        1_000_000.0
    );

    writefln(
        "  sweep setup + two-pass             %12.3f ms",
        cast(double)
            sweepNs /
        1_000_000.0
    );

    writefln(
        "  all-pairs / sweep ratio            %12.3f x",
        ratio
    );
}


void main()
{
    writeln(
        "Polygon Union P3 sweep-and-prune candidate-discovery probe"
    );

    writeln(
        "Both paths use the same precomputed source-edge envelopes."
    );

    writeln(
        "Timing models two noding passes: all-pairs twice vs sort once + sweep twice."
    );


    foreach (
        perRing;
        [
            16UL,
            32UL,
            64UL,
            128UL,
            256UL,
            512UL,
            1024UL
        ]
    )
    {
        runProbe(
            "disjoint regular convex",
            regularCaseSegments(
                perRing,
                false
            )
        );
    }


    foreach (
        perRing;
        [
            64UL,
            256UL,
            1024UL
        ]
    )
    {
        runProbe(
            "overlap regular convex",
            regularCaseSegments(
                perRing,
                true
            )
        );
    }


    foreach (
        toothCount;
        [
            15UL,
            31UL,
            63UL
        ]
    )
    {
        runProbe(
            "valid high-crossing comb",
            highCrossingCombSegments(
                toothCount
            )
        );
    }


    foreach (
        count;
        [
            256UL,
            1024UL
        ]
    )
    {
        runProbe(
            "100%-candidate concurrent segments",
            concurrentSegments(
                count
            )
        );
    }


    writeln();

    writefln(
        "sink=%s",
        probeSink
    );
}
