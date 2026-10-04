module geo.internal.hybrid_dispatch_probe;

import geo.internal.segment_polygon_clip_p1 :
    HybridClipPath,
    hybridClipPath,
    trySegmentPolygonClipP1Internal;
import geo.internal.segment_polygon_clip_result :
    SegmentPolygonClipOwnedResultInternal;
import geo.linear_ring_view : LinearRing2View;
import geo.point : Point2;
import geo.polygon_view : Polygon2View;
import geo.segment : Segment2;

import std.conv : to;
import std.exception : enforce;
import std.stdio : writeln;

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

private HybridClipPath runCase(T)(
    Point2!T[][] ringPoints,
    Segment2!T query
)
{
    auto rings =
        new LinearRing2View!T[
            ringPoints.length
        ];

    foreach (i; 0 .. ringPoints.length)
        rings[i] = LinearRing2View!T(ringPoints[i]);

    const polygon = Polygon2View!T(rings);

    SegmentPolygonClipOwnedResultInternal owned;

    const status =
        trySegmentPolygonClipP1Internal(
            query,
            polygon,
            owned
        );

    enforce(
        cast(int) status == 0,
        "clip probe failed"
    );

    return hybridClipPath();
}

private void runType(T)()
{
    alias P = Point2!T;
    alias S = Segment2!T;

    auto square =
        rectangle!T(
            cast(T)0,
            cast(T)0,
            cast(T)10,
            cast(T)10
        );

    enforce(
        runCase!T(
            [square],
            S(
                P(cast(T)-1, cast(T)5),
                P(cast(T)11, cast(T)5)
            )
        ) == HybridClipPath.baseline,
        "crossing must use baseline path"
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

        enforce(
            runCase!T(
                [ring],
                S(
                    P(cast(T)-1, cast(T)1),
                    P(
                        cast(T)(4 * subdivisions + 1),
                        cast(T)1
                    )
                )
            ) == HybridClipPath.baseline,
            "sparse-" ~ subdivisions.to!string ~
                " must use baseline path"
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

        ring ~= P(cast(T)0, cast(T)4);

        const auto expected =
            teeth >= 4
                ? HybridClipPath.denseParameter
                : HybridClipPath.baseline;

        enforce(
            runCase!T(
                [ring],
                S(
                    P(cast(T)-1, cast(T)2),
                    P(cast(T)(right + 1), cast(T)2)
                )
            ) == expected,
            "dense-" ~ teeth.to!string ~
                " dispatch mismatch"
        );
    }
}

void main()
{
    runType!int();
    runType!long();
    runType!float();
    runType!double();

    writeln("hybrid dispatch probe PASS");
}
