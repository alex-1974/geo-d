module geo.internal.clip_event_survivor_probe;

import geo.internal.segment_polygon_clip_p1 :
    SegmentPolygonClipEventCensus,
    SegmentPolygonClipInternalStatus,
    segmentPolygonClipEventCensus,
    trySegmentPolygonClipP1Internal;
import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;
import geo.linear_ring_view : LinearRing2View;
import geo.point : Point2;
import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;

import std.conv : to;
import std.stdio : writefln;

private Point2!T[] rectangle(T)(T x0, T y0, T x1, T y1)
{
    alias P = Point2!T;

    return [
        P(x0, y0),
        P(x1, y0),
        P(x1, y1),
        P(x0, y1),
    ];
}

private void runCase(T)(
    string name,
    Point2!T[][] ringPoints,
    Segment2!T query
)
{
    auto rings =
        new LinearRing2View!T[
            ringPoints.length
        ];

    foreach (i; 0 .. ringPoints.length)
    {
        rings[i] =
            LinearRing2View!T(
                ringPoints[i]
            );
    }

    const polygon =
        Polygon2View!T(
            rings
        );

    SegmentPolygonClipOwnedResultInternal owned;

    const status =
        trySegmentPolygonClipP1Internal(
            query,
            polygon,
            owned
        );

    const SegmentPolygonClipEventCensus census =
        segmentPolygonClipEventCensus();

    const size_t eagerCartesianConstructions =
        census.properCrossings +
        census.secondPassCrossingReconstructions;

    writefln(
        "census,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
        T.stringof,
        name,
        status,
        census.properCrossings,
        census.secondPassCrossingReconstructions,
        eagerCartesianConstructions,
        census.rawEventCount,
        census.uniqueEventCount,
        census.uniqueProperCrossingEventCount,
        census.materializedEndpointCount,
        census.materializedProperCrossingEndpointCount,
        census.componentCount
    );
}

private void runType(T)()
{
    alias P = Point2!T;
    alias S = Segment2!T;

    auto square =
        rectangle!T(
            cast(T) 0,
            cast(T) 0,
            cast(T) 10,
            cast(T) 10
        );

    runCase!T(
        "crossing",
        [square],
        S(
            P(cast(T)-1, cast(T) 5),
            P(cast(T)11, cast(T) 5)
        )
    );

    runCase!T(
        "concave-u",
        [[
            P(cast(T)0, cast(T)0),
            P(cast(T)10, cast(T)0),
            P(cast(T)10, cast(T)10),
            P(cast(T)7, cast(T)10),
            P(cast(T)7, cast(T)3),
            P(cast(T)3, cast(T)3),
            P(cast(T)3, cast(T)10),
            P(cast(T)0, cast(T)10),
        ]],
        S(
            P(cast(T)-1, cast(T)5),
            P(cast(T)11, cast(T)5)
        )
    );

    runCase!T(
        "hole",
        [
            square,
            rectangle!T(
                cast(T)3,
                cast(T)3,
                cast(T)7,
                cast(T)7
            ),
        ],
        S(
            P(cast(T)-1, cast(T)5),
            P(cast(T)11, cast(T)5)
        )
    );

    runCase!T(
        "rational-crossing",
        [[
            P(cast(T)0, cast(T)0),
            P(cast(T)4, cast(T)0),
            P(cast(T)0, cast(T)3),
        ]],
        S(
            P(cast(T)-1, cast(T)1),
            P(cast(T)5, cast(T)1)
        )
    );

    foreach (subdivisions; [4, 16, 64])
    {
        P[] ring;

        foreach (j; 0 .. subdivisions)
            ring ~= P(cast(T)(4 * j), cast(T)0);

        foreach (j; 0 .. subdivisions)
            ring ~= P(
                cast(T)(4 * subdivisions),
                cast(T)(4 * j)
            );

        foreach (j; 0 .. subdivisions)
            ring ~= P(
                cast(T)(4 * (subdivisions - j)),
                cast(T)(4 * subdivisions)
            );

        foreach (j; 0 .. subdivisions)
            ring ~= P(
                cast(T)0,
                cast(T)(4 * (subdivisions - j))
            );

        runCase!T(
            "sparse-" ~ subdivisions.to!string,
            [ring],
            S(
                P(cast(T)-1, cast(T)1),
                P(
                    cast(T)(4 * subdivisions + 1),
                    cast(T)1
                )
            )
        );
    }

    foreach (teeth; [4, 16, 64])
    {
        const int right =
            4 * teeth - 2;

        P[] ring = [
            P(cast(T)0, cast(T)0),
            P(cast(T)right, cast(T)0),
            P(cast(T)right, cast(T)4),
        ];

        foreach_reverse (j; 1 .. teeth)
        {
            ring ~= [
                P(cast(T)(4 * j), cast(T)4),
                P(cast(T)(4 * j), cast(T)1),
                P(cast(T)(4 * j - 2), cast(T)1),
                P(cast(T)(4 * j - 2), cast(T)4),
            ];
        }

        ring ~=
            P(cast(T)0, cast(T)4);

        runCase!T(
            "dense-" ~ teeth.to!string,
            [ring],
            S(
                P(cast(T)-1, cast(T)2),
                P(cast(T)(right + 1), cast(T)2)
            )
        );
    }
}

void main()
{
    runType!int();
    runType!long();
    runType!float();
    runType!double();
}
