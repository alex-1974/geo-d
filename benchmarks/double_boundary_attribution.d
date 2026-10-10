module geo.internal.double_boundary_attribution_bench;

import geo;
import geo.internal.segment_polygon_clip_p1 :
    DoubleBoundaryClipAttribution,
    readDoubleBoundaryClipAttribution,
    resetDoubleBoundaryClipAttribution;

import core.volatile : volatileLoad;
import std.conv : to;
import std.exception : enforce;
import std.stdio : writefln, writeln;

__gshared ulong attributionSink;

private struct Case
{
    string name;
    Point2!double[][] points;
    LinearRing2View!double[] rings;
    Polygon2View!double polygon;
    Segment2!double[2] queries;
    size_t expectedComponents;
    size_t edges;
}

private Point2!double[] rectangle(
    double x0,
    double y0,
    double x1,
    double y1
)
{
    return [
        Point2!double(x0, y0),
        Point2!double(x1, y0),
        Point2!double(x1, y1),
        Point2!double(x0, y1),
    ];
}

private Case makeCase(
    string name,
    Point2!double[][] points,
    Segment2!double query,
    size_t expectedComponents
)
{
    Case c;
    c.name = name;
    c.points = points;
    c.rings = new LinearRing2View!double[points.length];

    foreach (i; 0 .. points.length)
    {
        c.rings[i] = LinearRing2View!double(points[i]);
        c.edges += c.rings[i].segmentCount;
    }

    c.polygon = Polygon2View!double(c.rings);
    c.queries = [query, Segment2!double(query.b, query.a)];
    c.expectedComponents = expectedComponents;
    return c;
}

private Case[] cases()
{
    alias P = Point2!double;
    alias S = Segment2!double;

    auto square = rectangle(0, 0, 10, 10);
    Case[] result;

    result ~= makeCase(
        "crossing",
        [square],
        S(P(-1, 5), P(11, 5)),
        1
    );

    result ~= makeCase(
        "boundary-only",
        [square],
        S(P(0, 0), P(10, 0)),
        1
    );

    result ~= makeCase(
        "boundary-overlap",
        [square],
        S(P(-1, 0), P(11, 0)),
        1
    );

    result ~= makeCase(
        "concave-u",
        [[
            P(0, 0),
            P(10, 0),
            P(10, 10),
            P(7, 10),
            P(7, 3),
            P(3, 3),
            P(3, 10),
            P(0, 10),
        ]],
        S(P(-1, 5), P(11, 5)),
        2
    );

    result ~= makeCase(
        "hole",
        [square, rectangle(3, 3, 7, 7)],
        S(P(-1, 5), P(11, 5)),
        2
    );

    enum teeth = 4;
    enum right = 4 * teeth - 2;

    P[] dense = [
        P(0, 0),
        P(right, 0),
        P(right, 4),
    ];

    foreach_reverse (j; 1 .. teeth)
    {
        dense ~= [
            P(4 * j, 4),
            P(4 * j, 1),
            P(4 * j - 2, 1),
            P(4 * j - 2, 4),
        ];
    }

    dense ~= P(0, 4);

    result ~= makeCase(
        "dense-4",
        [dense],
        S(P(-1, 2), P(right + 1, 2)),
        4
    );

    return result;
}

private void preflight(ref Case c)
{
    enforce(
        validatePolygon(c.polygon).valid,
        "invalid fixture: " ~ c.name
    );

    foreach (query; c.queries)
    {
        auto result =
            clipSegmentToPolygon(
                query,
                c.polygon
            );

        enforce(
            result.succeeded,
            "clip failed: " ~ c.name
        );

        enforce(
            result.length ==
            c.expectedComponents,
            "component count mismatch: " ~ c.name
        );
    }
}

private void writeSample(
    ref Case c,
    size_t round,
    size_t iterations,
    DoubleBoundaryClipAttribution t
)
{
    enforce(t.calls == iterations);

    writefln(
        "sample,%s,%s,%s,%s,"
        ~ "%s,%s,%s,%s,%s,%s,%s,"
        ~ "%s,%s,%s,"
        ~ "%s,%s,%s,%s,%s,"
        ~ "%s,%s,%s,%s,%s",
        c.name,
        c.edges,
        round,
        iterations,
        t.totalNs,
        t.firstBoundaryPassNs,
        t.sortNs,
        t.secondBoundaryPassNs,
        t.vertexTopologyNs,
        t.retentionNs,
        t.materializationNs,
        t.edgeCount,
        t.rawEventCount,
        t.uniqueEventCount,
        t.secondPassContactCalls,
        t.noneContacts,
        t.touchContacts,
        t.properCrossingContacts,
        t.overlapContacts,
        t.eventLookupCalls,
        t.vertexCandidateCalls,
        t.vertexOnQueryCalls,
        t.retainedIntervalCount,
        t.componentCount
    );
}

private void run(
    string caseName,
    size_t rounds,
    size_t iterations
)
{
    auto all = cases();

    foreach (ref c; all)
    {
        if (c.name != caseName)
            continue;

        preflight(c);

        foreach (_; 0 .. 3)
        {
            foreach (size_t i; 0 .. 64)
            {
                auto result =
                    clipSegmentToPolygon(
                        c.queries[
                            volatileLoad(&i) & 1
                        ],
                        c.polygon
                    );

                enforce(result.succeeded);
                attributionSink += result.length;
            }
        }

        foreach (round; 0 .. rounds)
        {
            resetDoubleBoundaryClipAttribution();

            foreach (size_t i; 0 .. iterations)
            {
                auto result =
                    clipSegmentToPolygon(
                        c.queries[
                            volatileLoad(&i) & 1
                        ],
                        c.polygon
                    );

                enforce(result.succeeded);
                attributionSink += result.length;
            }

            writeSample(
                c,
                round,
                iterations,
                readDoubleBoundaryClipAttribution()
            );
        }

        return;
    }

    enforce(false, "unknown case: " ~ caseName);
}

void main(string[] args)
{
    enforce(args.length == 4);

    const string caseName = args[1];
    const size_t rounds = args[2].to!size_t;
    const size_t iterations = args[3].to!size_t;

    writeln(
        "sample_header,case,edges,round,iterations,"
        ~ "total_ns,first_boundary_pass_ns,sort_ns,"
        ~ "second_boundary_pass_ns,vertex_topology_ns,"
        ~ "retention_ns,materialization_ns,"
        ~ "edge_count,raw_event_count,unique_event_count,"
        ~ "second_pass_contact_calls,none_contacts,touch_contacts,"
        ~ "proper_crossing_contacts,overlap_contacts,event_lookup_calls,"
        ~ "vertex_candidate_calls,vertex_on_query_calls,"
        ~ "retained_interval_count,component_count"
    );

    run(
        caseName,
        rounds,
        iterations
    );

    writefln("sink,%s", attributionSink);
}
