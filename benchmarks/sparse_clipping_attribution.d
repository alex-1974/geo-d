module geo.internal.sparse_clipping_attribution_bench;

import geo;
import geo.internal.segment_polygon_clip_p1 :
    SparseClipAttribution,
    readSparseClipAttribution,
    resetSparseClipAttribution;

import core.volatile : volatileLoad;
import std.conv : to;
import std.exception : enforce;
import std.stdio : writefln, writeln;

__gshared ulong attributionSink;

private struct SparseCase(T)
{
    Point2!T[] points;
    LinearRing2View!T[1] rings;
    Polygon2View!T polygon;
    Segment2!T[2] queries;
    size_t edges;
}

private SparseCase!T makeSparseCase(T)(size_t subdivisions)
{
    alias P = Point2!T;
    alias S = Segment2!T;

    enforce(subdivisions >= 1);

    P[] ring;

    foreach (j; 0 .. subdivisions)
        ring ~= P(cast(T)(4 * j), 0);

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
            0,
            cast(T)(4 * (subdivisions - j))
        );

    SparseCase!T result;
    result.points = ring;
    result.rings[0] =
        LinearRing2View!T(
            result.points[]
        );
    result.polygon =
        Polygon2View!T(
            result.rings[]
        );
    result.edges =
        result.rings[0].segmentCount;

    const S forward =
        S(
            P(-1, 1),
            P(cast(T)(4 * subdivisions + 1), 1)
        );

    result.queries = [
        forward,
        S(forward.b, forward.a),
    ];

    return result;
}

private void preflight(T)(ref SparseCase!T c)
{
    foreach (query; c.queries)
    {
        auto result =
            clipSegmentToPolygon(
                query,
                c.polygon
            );

        enforce(result.succeeded);
        enforce(result.length == 1);
    }
}

private void writeSample(
    string scalar,
    size_t subdivisions,
    size_t edges,
    size_t round,
    size_t iterations,
    SparseClipAttribution t
)
{
    enforce(t.calls == iterations);

    writefln(
        "sample,%s,%s,%s,%s,%s,"
        ~ "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"
        ~ "%s,%s,%s,%s,%s,%s,%s",
        scalar,
        subdivisions,
        edges,
        round,
        iterations,
        t.totalNs,
        t.setupNs,
        t.capacityNs,
        t.eventSetupNs,
        t.firstBoundaryPassNs,
        t.sortNs,
        t.metadataAllocationNs,
        t.ringOrientationNs,
        t.secondBoundaryPassNs,
        t.vertexTopologyNs,
        t.retentionNs,
        t.pointInPolygonNs,
        t.materializationNs,
        t.edgeCount,
        t.candidateEdgeCount,
        t.firstPassCandidateEdges,
        t.rawEventCount,
        t.uniqueEventCount,
        t.secondPassContactCalls,
        t.nonNoneContacts,
        t.vertexContactCalls
    );
}

private void run(T)(
    size_t subdivisions,
    size_t rounds,
    size_t iterations
)
{
    auto c =
        makeSparseCase!T(
            subdivisions
        );

    preflight(c);

    foreach (warmup; 0 .. 3)
    {
        foreach (size_t i; 0 .. 64)
        {
            auto result =
                clipSegmentToPolygon(
                    c.queries[volatileLoad(&i) & 1],
                    c.polygon
                );

            attributionSink += result.length;
        }
    }

    foreach (round; 0 .. rounds)
    {
        resetSparseClipAttribution();

        foreach (size_t i; 0 .. iterations)
        {
            auto result =
                clipSegmentToPolygon(
                    c.queries[volatileLoad(&i) & 1],
                    c.polygon
                );

            enforce(result.succeeded);
            attributionSink +=
                result.length;
        }

        writeSample(
            T.stringof,
            subdivisions,
            c.edges,
            round,
            iterations,
            readSparseClipAttribution()
        );
    }
}

void main(string[] args)
{
    enforce(args.length == 5);

    const scalar =
        args[1];

    const subdivisions =
        args[2].to!size_t;

    const rounds =
        args[3].to!size_t;

    const iterations =
        args[4].to!size_t;

    writeln(
        "sample_header,scalar,subdivisions,edges,round,iterations,"
        ~ "total_ns,setup_ns,capacity_ns,event_setup_ns,"
        ~ "first_boundary_pass_ns,sort_ns,metadata_allocation_ns,"
        ~ "ring_orientation_ns,second_boundary_pass_ns,vertex_topology_ns,"
        ~ "retention_ns,point_in_polygon_ns,materialization_ns,"
        ~ "edge_count,candidate_edge_count,first_pass_candidate_edges,"
        ~ "raw_event_count,unique_event_count,second_pass_contact_calls,"
        ~ "non_none_contacts,vertex_contact_calls"
    );

    if (scalar == "int")
        run!int(subdivisions, rounds, iterations);
    else if (scalar == "long")
        run!long(subdivisions, rounds, iterations);
    else if (scalar == "float")
        run!float(subdivisions, rounds, iterations);
    else if (scalar == "double")
        run!double(subdivisions, rounds, iterations);
    else
        enforce(false, "unknown scalar");

    writefln(
        "sink,%s",
        attributionSink
    );
}
