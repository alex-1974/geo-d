/*
 * Research-only control for precomputed Polygon Union P3 segment envelopes.
 *
 * This is a low-level segment diagnostic, not a polygon fixture.
 *
 * It compares the two-pass exact-classification cost required by an
 * exact-sized event workspace against:
 *
 *   one O(n) envelope-precompute step
 *   + two envelope-gated exact-classification passes.
 *
 * The precomputed envelope is deliberately local to this probe. It is not a
 * reusable spatial-index/container abstraction.
 */
module geo.polygon_union_p3_precomputed_envelope_probe;

import geo;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind;

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


enum size_t segmentCount = 256;
enum size_t repetitions = 7;

__gshared ulong probeSink;


private struct EdgeEnvelope
{
    double minX;
    double maxX;
    double minY;
    double maxY;
}


private struct TimingSamples
{
    long[repetitions] allExactTwoPass;
    long[repetitions] envelopeBuild;
    long[repetitions] gatedPassOne;
    long[repetitions] gatedPassTwo;
    long[repetitions] gatedTwoPassTotal;
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


private Segment2!double[] makeSegments(
    size_t denseCount
)
{
    enforce(
        denseCount >= 2 &&
        denseCount <= segmentCount,
        "denseCount outside supported range"
    );

    auto segments =
        new Segment2!double[
            segmentCount
        ];

    foreach (i; 0 .. denseCount)
    {
        const double angle =
            cast(double) PI *
            cast(double) i /
            cast(double) denseCount;

        const double x =
            cos(angle);

        const double y =
            sin(angle);

        segments[i] =
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

    foreach (i; denseCount .. segmentCount)
    {
        const double centerX =
            4.0 *
            cast(double)(
                i -
                denseCount +
                1
            );

        segments[i] =
            Segment2!double(
                Point2!double(
                    centerX - 1.0,
                    0.0
                ),
                Point2!double(
                    centerX + 1.0,
                    0.0
                )
            );
    }

    return segments;
}


private EdgeEnvelope[] buildEnvelopes(
    scope Segment2!double[] segments
)
{
    auto envelopes =
        new EdgeEnvelope[
            segments.length
        ];

    foreach (i, segment; segments)
    {
        envelopes[i] =
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

    return envelopes;
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


private size_t candidateCount(
    scope const EdgeEnvelope[] envelopes
)
{
    size_t result = 0;

    foreach (firstIndex; 0 .. envelopes.length)
    {
        foreach (
            secondIndex;
            firstIndex + 1 ..
            envelopes.length
        )
        {
            if (
                envelopesOverlap(
                    envelopes[firstIndex],
                    envelopes[secondIndex]
                )
            )
            {
                ++result;
            }
        }
    }

    return result;
}


private ulong classifyAllExact(
    scope Segment2!double[] segments
)
{
    ulong sink = 1;

    foreach (firstIndex; 0 .. segments.length)
    {
        foreach (
            secondIndex;
            firstIndex + 1 ..
            segments.length
        )
        {
            const SegmentContactKind contact =
                segmentContactKind(
                    segments[firstIndex],
                    segments[secondIndex]
                );

            sink =
                sink * 1_000_003UL +
                cast(ulong) contact +
                cast(ulong) firstIndex +
                cast(ulong) secondIndex;
        }
    }

    return sink;
}


private ulong classifyPrecomputedEnvelopeGated(
    scope Segment2!double[] segments,
    scope const EdgeEnvelope[] envelopes
)
{
    ulong sink = 1;

    foreach (firstIndex; 0 .. segments.length)
    {
        foreach (
            secondIndex;
            firstIndex + 1 ..
            segments.length
        )
        {
            SegmentContactKind contact =
                SegmentContactKind.none;

            if (
                envelopesOverlap(
                    envelopes[firstIndex],
                    envelopes[secondIndex]
                )
            )
            {
                contact =
                    segmentContactKind(
                        segments[firstIndex],
                        segments[secondIndex]
                    );
            }

            sink =
                sink * 1_000_003UL +
                cast(ulong) contact +
                cast(ulong) firstIndex +
                cast(ulong) secondIndex;
        }
    }

    return sink;
}


private void verifyFixture(
    scope Segment2!double[] segments,
    size_t denseCount
)
{
    auto envelopes =
        buildEnvelopes(
            segments
        );

    const size_t expectedCandidates =
        denseCount *
        (denseCount - 1) /
        2;

    enforce(
        candidateCount(
            envelopes
        ) ==
            expectedCandidates,
        "candidate-count mismatch"
    );

    enforce(
        classifyAllExact(
            segments
        ) ==
        classifyPrecomputedEnvelopeGated(
            segments,
            envelopes
        ),
        "precomputed envelope gating changed contact results"
    );
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


private void runProbe(
    size_t denseCount
)
{
    auto segments =
        makeSegments(
            denseCount
        );

    verifyFixture(
        segments,
        denseCount
    );


    const size_t allPairs =
        segmentCount *
        (segmentCount - 1) /
        2;

    const size_t candidates =
        denseCount *
        (denseCount - 1) /
        2;

    const double candidatePercent =
        100.0 *
        cast(double) candidates /
        cast(double) allPairs;


    TimingSamples samples;

    foreach (sample; 0 .. repetitions)
    {
        if ((sample & 1) == 0)
        {
            MonoTime start =
                MonoTime.currTime;

            const ulong exactOne =
                classifyAllExact(
                    segments
                );

            const ulong exactTwo =
                classifyAllExact(
                    segments
                );

            samples.allExactTwoPass[sample] =
                elapsedNs(start);


            start =
                MonoTime.currTime;

            auto envelopes =
                buildEnvelopes(
                    segments
                );

            samples.envelopeBuild[sample] =
                elapsedNs(start);


            const MonoTime gatedStart =
                MonoTime.currTime;

            start =
                gatedStart;

            const ulong gatedOne =
                classifyPrecomputedEnvelopeGated(
                    segments,
                    envelopes
                );

            samples.gatedPassOne[sample] =
                elapsedNs(start);


            start =
                MonoTime.currTime;

            const ulong gatedTwo =
                classifyPrecomputedEnvelopeGated(
                    segments,
                    envelopes
                );

            samples.gatedPassTwo[sample] =
                elapsedNs(start);

            samples.gatedTwoPassTotal[sample] =
                samples.envelopeBuild[sample] +
                elapsedNs(
                    gatedStart
                );


            probeSink =
                probeSink * 1_000_003UL +
                exactOne +
                exactTwo +
                gatedOne +
                gatedTwo;
        }
        else
        {
            MonoTime start =
                MonoTime.currTime;

            auto envelopes =
                buildEnvelopes(
                    segments
                );

            samples.envelopeBuild[sample] =
                elapsedNs(start);


            const MonoTime gatedStart =
                MonoTime.currTime;

            start =
                gatedStart;

            const ulong gatedOne =
                classifyPrecomputedEnvelopeGated(
                    segments,
                    envelopes
                );

            samples.gatedPassOne[sample] =
                elapsedNs(start);


            start =
                MonoTime.currTime;

            const ulong gatedTwo =
                classifyPrecomputedEnvelopeGated(
                    segments,
                    envelopes
                );

            samples.gatedPassTwo[sample] =
                elapsedNs(start);

            samples.gatedTwoPassTotal[sample] =
                samples.envelopeBuild[sample] +
                elapsedNs(
                    gatedStart
                );


            start =
                MonoTime.currTime;

            const ulong exactOne =
                classifyAllExact(
                    segments
                );

            const ulong exactTwo =
                classifyAllExact(
                    segments
                );

            samples.allExactTwoPass[sample] =
                elapsedNs(start);


            probeSink =
                probeSink * 1_000_003UL +
                exactOne +
                exactTwo +
                gatedOne +
                gatedTwo;
        }
    }


    const long exactNs =
        median(
            samples.allExactTwoPass
        );

    const long gatedNs =
        median(
            samples.gatedTwoPassTotal
        );

    const double gatedDeltaPercent =
        exactNs == 0
            ? 0.0
            : 100.0 *
                (
                    cast(double)
                        gatedNs /
                    cast(double)
                        exactNs -
                    1.0
                );

    const double exactOverGated =
        gatedNs == 0
            ? 0.0
            : cast(double)
                exactNs /
              cast(double)
                gatedNs;


    writeln();

    writefln(
        "dense=%s, isolated=%s",
        denseCount,
        segmentCount - denseCount
    );

    writefln(
        "  all source-segment pairs           %12s",
        allPairs
    );

    writefln(
        "  envelope candidates                %12s",
        candidates
    );

    writefln(
        "  candidate fraction                 %12.3f %%",
        candidatePercent
    );

    writefln(
        "  all-exact two-pass                 %12.3f ms",
        cast(double)
            exactNs /
        1_000_000.0
    );

    writefln(
        "  precomputed gated two-pass         %12.3f ms",
        cast(double)
            gatedNs /
        1_000_000.0
    );

    writefln(
        "    envelope build                   %12.3f ms",
        cast(double)
            median(
                samples.envelopeBuild
            ) /
        1_000_000.0
    );

    writefln(
        "    gated pass one                   %12.3f ms",
        cast(double)
            median(
                samples.gatedPassOne
            ) /
        1_000_000.0
    );

    writefln(
        "    gated pass two                   %12.3f ms",
        cast(double)
            median(
                samples.gatedPassTwo
            ) /
        1_000_000.0
    );

    writefln(
        "  gated delta vs all-exact           %12.3f %%",
        gatedDeltaPercent
    );

    writefln(
        "  all-exact / gated ratio            %12.3f x",
        exactOverGated
    );
}


void main()
{
    writeln(
        "Polygon Union P3 precomputed-envelope two-pass probe"
    );

    writeln(
        "Synthetic segment diagnostic at fixed 256 source segments."
    );

    writeln(
        "Envelope build is measured once and reused across both classification passes."
    );


    foreach (
        denseCount;
        [
            256UL,
            248UL,
            240UL,
            232UL,
            224UL,
            216UL,
            181UL,
            128UL
        ]
    )
    {
        runProbe(
            denseCount
        );
    }


    writeln();

    writefln(
        "sink=%s",
        probeSink
    );
}
