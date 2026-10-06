module geo.internal.boundary_clipping_attribution_bench;

import geo;
import geo.internal.segment_polygon_clip_p1 :
    BoundaryClipAttribution,
    readBoundaryClipAttribution,
    resetBoundaryClipAttribution;

import core.volatile : volatileLoad;
import std.conv : to;
import std.exception : enforce;
import std.stdio : writefln, writeln;

__gshared ulong attributionSink;

private struct Case(T)
{
    string name;
    Point2!T[][] points;
    LinearRing2View!T[] rings;
    Polygon2View!T polygon;
    Segment2!T[2] queries;
    size_t expectedComponents;
    size_t edges;
}

private Point2!T[] rectangle(T)(T x0, T y0, T x1, T y1)
{
    return [
        Point2!T(x0, y0),
        Point2!T(x1, y0),
        Point2!T(x1, y1),
        Point2!T(x0, y1),
    ];
}

private Case!T makeCase(T)(
    string name,
    Point2!T[][] points,
    Segment2!T query,
    size_t expectedComponents
)
{
    Case!T c;
    c.name = name;
    c.points = points;
    c.rings = new LinearRing2View!T[points.length];

    foreach (i; 0 .. points.length)
    {
        c.rings[i] = LinearRing2View!T(points[i]);
        c.edges += c.rings[i].segmentCount;
    }

    c.polygon = Polygon2View!T(c.rings);
    c.queries = [query, Segment2!T(query.b, query.a)];
    c.expectedComponents = expectedComponents;
    return c;
}

private Case!T[] cases(T)()
{
    alias P = Point2!T;
    alias S = Segment2!T;

    auto square = rectangle!T(0, 0, 10, 10);
    Case!T[] result;

    result ~= makeCase!T(
        "crossing",
        [square],
        S(P(-1, 5), P(11, 5)),
        1
    );

    result ~= makeCase!T(
        "boundary-only",
        [square],
        S(P(0, 0), P(10, 0)),
        1
    );

    result ~= makeCase!T(
        "boundary-overlap",
        [square],
        S(P(-1, 0), P(11, 0)),
        1
    );

    enum teeth = 4;
    enum right = 4 * teeth - 2;

    P[] dense = [
        P(0, 0),
        P(cast(T) right, 0),
        P(cast(T) right, 4),
    ];

    foreach_reverse (j; 1 .. teeth)
    {
        dense ~= [
            P(cast(T)(4 * j), 4),
            P(cast(T)(4 * j), 1),
            P(cast(T)(4 * j - 2), 1),
            P(cast(T)(4 * j - 2), 4),
        ];
    }

    dense ~= P(0, 4);

    result ~= makeCase!T(
        "dense-4",
        [dense],
        S(P(-1, 2), P(cast(T)(right + 1), 2)),
        4
    );

    return result;
}

private void preflight(T)(ref Case!T c)
{
    enforce(validatePolygon(c.polygon).valid, "invalid fixture: " ~ c.name);

    foreach (query; c.queries)
    {
        auto result = clipSegmentToPolygon(query, c.polygon);
        enforce(result.succeeded, "clip failed: " ~ c.name);
        enforce(
            result.length == c.expectedComponents,
            "component count mismatch: " ~ c.name
        );
    }
}

private void writeSample(T)(
    string scalar,
    ref Case!T c,
    size_t round,
    size_t iterations,
    BoundaryClipAttribution t
)
{
    enforce(t.calls == iterations);

    writefln(
        "sample,%s,%s,%s,%s,%s,"
        ~ "%s,%s,%s,%s,%s,%s,%s,"
        ~ "%s,%s,%s,%s,"
        ~ "%s,%s,%s,%s,%s,"
        ~ "%s,%s,%s,%s,%s",
        scalar,
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
        t.eventLookupNs,
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

private void run(T)(
    string caseName,
    size_t rounds,
    size_t iterations
)
{
    auto all = cases!T();

    foreach (ref c; all)
    {
        if (c.name != caseName)
            continue;

        preflight(c);

        foreach (warmup; 0 .. 3)
        {
            foreach (size_t i; 0 .. 64)
            {
                auto result = clipSegmentToPolygon(
                    c.queries[volatileLoad(&i) & 1],
                    c.polygon
                );

                enforce(result.succeeded);
                attributionSink += result.length;
            }
        }

        foreach (round; 0 .. rounds)
        {
            resetBoundaryClipAttribution();

            foreach (size_t i; 0 .. iterations)
            {
                auto result = clipSegmentToPolygon(
                    c.queries[volatileLoad(&i) & 1],
                    c.polygon
                );

                enforce(result.succeeded);
                attributionSink += result.length;
            }

            writeSample(
                T.stringof,
                c,
                round,
                iterations,
                readBoundaryClipAttribution()
            );
        }

        return;
    }

    enforce(false, "unknown case: " ~ caseName);
}

void main(string[] args)
{
    enforce(args.length == 5);

    const string scalar = args[1];
    const string caseName = args[2];
    const size_t rounds = args[3].to!size_t;
    const size_t iterations = args[4].to!size_t;

    writeln(
        "sample_header,scalar,case,edges,round,iterations,"
        ~ "total_ns,first_boundary_pass_ns,sort_ns,second_boundary_pass_ns,"
        ~ "vertex_topology_ns,retention_ns,materialization_ns,event_lookup_ns,"
        ~ "edge_count,raw_event_count,unique_event_count,"
        ~ "second_pass_contact_calls,none_contacts,touch_contacts,"
        ~ "proper_crossing_contacts,overlap_contacts,event_lookup_calls,"
        ~ "vertex_candidate_calls,vertex_on_query_calls,"
        ~ "retained_interval_count,component_count"
    );

    if (scalar == "int")
        run!int(caseName, rounds, iterations);
    else if (scalar == "long")
        run!long(caseName, rounds, iterations);
    else if (scalar == "float")
        run!float(caseName, rounds, iterations);
    else if (scalar == "double")
        run!double(caseName, rounds, iterations);
    else
        enforce(false, "unknown scalar");

    writefln("sink,%s", attributionSink);
}
