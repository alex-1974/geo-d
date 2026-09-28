/*
 * Research-only upper-density refinement for Polygon Union P3 envelope gating.
 *
 * This is a low-level segment diagnostic, not a polygon fixture.
 *
 * A dense concurrent segment cluster is placed at the origin. The remaining
 * segments are spatially isolated from that cluster and from each other.
 *
 * Therefore the candidate fraction is exactly C(denseCount, 2) / C(256, 2).
 * This refines the 50%-to-100% crossover region without changing total source
 * segment count.
 */
module geo.polygon_union_p3_envelope_upper_density_probe;

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


private struct TimingSamples
{
    long[repetitions] allExact;
    long[repetitions] envelopeGated;
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


private size_t candidateCount(
    scope Segment2!double[] segments
)
{
    size_t result = 0;

    foreach (firstIndex; 0 .. segments.length)
    {
        foreach (
            secondIndex;
            firstIndex + 1 ..
            segments.length
        )
        {
            if (
                envelopesOverlap(
                    segments[
                        firstIndex
                    ],
                    segments[
                        secondIndex
                    ]
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
                    segments[
                        firstIndex
                    ],
                    segments[
                        secondIndex
                    ]
                );

            sink =
                sink * 1_000_003UL +
                cast(ulong) contact +
                cast(ulong)
                    firstIndex +
                cast(ulong)
                    secondIndex;
        }
    }

    return sink;
}


private ulong classifyEnvelopeGated(
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
            SegmentContactKind contact =
                SegmentContactKind.none;

            if (
                envelopesOverlap(
                    segments[
                        firstIndex
                    ],
                    segments[
                        secondIndex
                    ]
                )
            )
            {
                contact =
                    segmentContactKind(
                        segments[
                            firstIndex
                        ],
                        segments[
                            secondIndex
                        ]
                    );
            }

            sink =
                sink * 1_000_003UL +
                cast(ulong) contact +
                cast(ulong)
                    firstIndex +
                cast(ulong)
                    secondIndex;
        }
    }

    return sink;
}


private void verifyFixture(
    scope Segment2!double[] segments,
    size_t denseCount
)
{
    const size_t expectedCandidates =
        denseCount *
        (denseCount - 1) /
        2;

    enforce(
        candidateCount(
            segments
        ) ==
            expectedCandidates,
        "candidate-count mismatch"
    );

    enforce(
        classifyAllExact(
            segments
        ) ==
        classifyEnvelopeGated(
            segments
        ),
        "envelope gating changed contact results"
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

            const ulong exactSink =
                classifyAllExact(
                    segments
                );

            samples.allExact[sample] =
                elapsedNs(start);


            start =
                MonoTime.currTime;

            const ulong gatedSink =
                classifyEnvelopeGated(
                    segments
                );

            samples.envelopeGated[sample] =
                elapsedNs(start);


            probeSink =
                probeSink * 1_000_003UL +
                exactSink +
                gatedSink;
        }
        else
        {
            MonoTime start =
                MonoTime.currTime;

            const ulong gatedSink =
                classifyEnvelopeGated(
                    segments
                );

            samples.envelopeGated[sample] =
                elapsedNs(start);


            start =
                MonoTime.currTime;

            const ulong exactSink =
                classifyAllExact(
                    segments
                );

            samples.allExact[sample] =
                elapsedNs(start);


            probeSink =
                probeSink * 1_000_003UL +
                exactSink +
                gatedSink;
        }
    }


    const long exactNs =
        median(
            samples.allExact
        );

    const long gatedNs =
        median(
            samples.envelopeGated
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
        "  all-exact classification           %12.3f ms",
        cast(double)
            exactNs /
        1_000_000.0
    );

    writefln(
        "  envelope+exact classification      %12.3f ms",
        cast(double)
            gatedNs /
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
        "Polygon Union P3 envelope upper-density sweep"
    );

    writeln(
        "Synthetic segment diagnostic at fixed 256 source segments."
    );

    writeln(
        "One dense concurrent cluster plus spatially isolated remainder."
    );


    foreach (
        denseCount;
        [
            216UL,
            224UL,
            232UL,
            240UL,
            248UL,
            252UL,
            254UL,
            255UL
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
