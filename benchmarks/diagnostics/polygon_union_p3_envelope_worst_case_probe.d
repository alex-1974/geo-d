/*
 * Research-only worst-case selectivity probe for Polygon Union P3 envelope
 * gating.
 *
 * This is intentionally a low-level segment diagnostic, not a polygon fixture.
 * Every segment passes through the origin, so every pair has overlapping
 * axis-aligned segment envelopes and the envelope guard rejects nothing.
 *
 * The probe compares:
 *
 * 1. exact segment contact classification for every pair;
 * 2. the same traversal with the envelope guard before the same exact
 *    classification.
 *
 * This isolates the cost of the guard when candidate selectivity is 100%.
 */
module geo.polygon_union_p3_envelope_worst_case_probe;

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


private Segment2!double[] makeConcurrentSegments(
    size_t count
)
{
    enforce(
        count >= 2,
        "segment count must be at least two"
    );

    auto segments =
        new Segment2!double[count];

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

    return segments;
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
            if (
                !envelopesOverlap(
                    segments[
                        firstIndex
                    ],
                    segments[
                        secondIndex
                    ]
                )
            )
            {
                sink =
                    sink * 1_000_003UL +
                    17UL;

                continue;
            }

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


private void verifyWorstCase(
    scope Segment2!double[] segments
)
{
    size_t pairCount = 0;

    foreach (firstIndex; 0 .. segments.length)
    {
        foreach (
            secondIndex;
            firstIndex + 1 ..
            segments.length
        )
        {
            ++pairCount;

            enforce(
                envelopesOverlap(
                    segments[
                        firstIndex
                    ],
                    segments[
                        secondIndex
                    ]
                ),
                "synthetic pair failed 100% envelope-overlap requirement"
            );

            enforce(
                segmentContactKind(
                    segments[
                        firstIndex
                    ],
                    segments[
                        secondIndex
                    ]
                ) ==
                    SegmentContactKind
                        .properCrossing,
                "synthetic pair is not a proper crossing"
            );
        }
    }

    enforce(
        pairCount ==
            segments.length *
            (segments.length - 1) /
            2,
        "synthetic pair-count mismatch"
    );

    enforce(
        classifyAllExact(
            segments
        ) ==
        classifyEnvelopeGated(
            segments
        ),
        "envelope-gated classification changed results"
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
    size_t segmentCount
)
{
    auto segments =
        makeConcurrentSegments(
            segmentCount
        );

    verifyWorstCase(
        segments
    );


    probeSink =
        probeSink * 1_000_033UL +
        classifyAllExact(
            segments
        ) +
        classifyEnvelopeGated(
            segments
        );


    TimingSamples samples;

    foreach (sample; 0 .. repetitions)
    {
        if ((sample & 1) == 0)
        {
            MonoTime start =
                MonoTime.currTime;

            const ulong allExactSink =
                classifyAllExact(
                    segments
                );

            samples.allExact[sample] =
                elapsedNs(start);


            start =
                MonoTime.currTime;

            const ulong envelopeSink =
                classifyEnvelopeGated(
                    segments
                );

            samples.envelopeGated[sample] =
                elapsedNs(start);


            probeSink =
                probeSink * 1_000_003UL +
                allExactSink +
                envelopeSink;
        }
        else
        {
            MonoTime start =
                MonoTime.currTime;

            const ulong envelopeSink =
                classifyEnvelopeGated(
                    segments
                );

            samples.envelopeGated[sample] =
                elapsedNs(start);


            start =
                MonoTime.currTime;

            const ulong allExactSink =
                classifyAllExact(
                    segments
                );

            samples.allExact[sample] =
                elapsedNs(start);


            probeSink =
                probeSink * 1_000_003UL +
                allExactSink +
                envelopeSink;
        }
    }


    const size_t pairCount =
        segmentCount *
        (segmentCount - 1) /
        2;

    const long allExactNs =
        median(
            samples.allExact
        );

    const long envelopeNs =
        median(
            samples.envelopeGated
        );

    const double gatedOverheadPercent =
        allExactNs == 0
            ? 0.0
            : 100.0 *
                (
                    cast(double)
                        envelopeNs /
                    cast(double)
                        allExactNs -
                    1.0
                );

    const double allExactOverGated =
        envelopeNs == 0
            ? 0.0
            : cast(double)
                allExactNs /
              cast(double)
                envelopeNs;


    writeln();

    writefln(
        "100%% candidates: %s concurrent segments",
        segmentCount
    );

    writefln(
        "  source-segment pairs               %12s",
        pairCount
    );

    writefln(
        "  envelope candidates                %12s",
        pairCount
    );

    writefln(
        "  candidate fraction                 %12.3f %%",
        100.0
    );

    writefln(
        "  all-exact classification           %12.3f ms",
        cast(double)
            allExactNs /
        1_000_000.0
    );

    writefln(
        "  envelope+exact classification      %12.3f ms",
        cast(double)
            envelopeNs /
        1_000_000.0
    );

    writefln(
        "  envelope overhead                  %12.3f %%",
        gatedOverheadPercent
    );

    writefln(
        "  all-exact / gated ratio            %12.3f x",
        allExactOverGated
    );
}


void main()
{
    writeln(
        "Polygon Union P3 envelope 100%-candidate stress probe"
    );

    writeln(
        "Synthetic segment diagnostic: every pair overlaps in envelope and crosses properly."
    );

    writeln(
        "No polygon-validity claim is made for this low-level segment set."
    );


    runProbe(32);
    runProbe(128);
    runProbe(256);


    writeln();

    writefln(
        "sink=%s",
        probeSink
    );
}
