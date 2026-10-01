/** Public segment/polygon benchmark. See segment-polygon/README.md. */
module segment_polygon_bench;

import geo;
import core.memory : GC;
import core.volatile : volatileLoad;
import std.algorithm.sorting : sort;
import std.algorithm.mutation : reverse;
import std.conv : to;
import std.datetime.stopwatch : StopWatch;
import std.exception : enforce;
import std.stdio : writefln, writeln;

__gshared ulong benchmarkSink;

private struct Case(T)
{
    string name;
    Point2!T[][] points;
    LinearRing2View!T[] rings;
    Polygon2View!T polygon;
    Segment2!T[2] queries;
    uint expectedFacts;
    SegmentPolygonClipStatus expectedStatus = SegmentPolygonClipStatus.success;
    Segment2!double[] expected;
    size_t edges;
}

private uint facts(SegmentPolygonRelationship r) pure nothrow @safe @nogc
{
    return r.hasExterior | (r.hasBoundary << 1) |
        (r.hasInterior << 2) | (r.hasBoundaryOverlap << 3);
}

private ulong bits(double value) nothrow @nogc
{
    union Value { double number; ulong representation; }
    Value v;
    v.number = value;
    return v.representation;
}

// Keep the call dependent on runtime inputs even under whole-module inlining.
pragma(inline, false)
private ulong relationship(T)(ref Case!T c, size_t i) @nogc
{
    return facts(classifySegmentPolygonRelationship(c.queries[volatileLoad(&i) & 1], c.polygon));
}

pragma(inline, false)
private ulong clipping(T)(ref Case!T c, size_t i)
{
    auto result = clipSegmentToPolygon(c.queries[volatileLoad(&i) & 1], c.polygon);
    ulong signature = cast(ulong) result.status;
    if (!result.succeeded)
        return signature;
    signature = signature * 1_000_003UL + result.length;
    foreach (j; 0 .. result.length)
    {
        auto s = result[j];
        signature = signature * 1_000_003UL + bits(s.a.x);
        signature = signature * 1_000_003UL + bits(s.a.y);
        signature = signature * 1_000_003UL + bits(s.b.x);
        signature = signature * 1_000_003UL + bits(s.b.y);
    }
    return signature;
}

private Point2!T[] rectangle(T)(T x0, T y0, T x1, T y1)
{
    return [Point2!T(x0, y0), Point2!T(x1, y0),
        Point2!T(x1, y1), Point2!T(x0, y1)];
}

private Segment2!double piece(double x0, double y0, double x1, double y1)
{
    return Segment2!double(Point2!double(x0, y0), Point2!double(x1, y1));
}

private Case!T makeCase(T)(string name, Point2!T[][] points,
    Segment2!T query, uint expectedFacts, Segment2!double[] expected,
    SegmentPolygonClipStatus status = SegmentPolygonClipStatus.success)
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
    c.expectedFacts = expectedFacts;
    c.expected = expected;
    c.expectedStatus = status;
    return c;
}

private Case!T[] corpus(T)()
{
    alias P = Point2!T;
    alias S = Segment2!T;
    auto square = [rectangle!T(0, 0, 10, 10)];
    Case!T[] cases;
    cases ~= makeCase!T("exterior", square, S(P(-2, 2), P(-1, 8)), 1, []);
    cases ~= makeCase!T("interior", square, S(P(1, 1), P(9, 1)), 4,
        [piece(1, 1, 9, 1)]);
    cases ~= makeCase!T("crossing", square, S(P(-1, 5), P(11, 5)), 7,
        [piece(0, 5, 10, 5)]);
    cases ~= makeCase!T("boundary-only", square, S(P(0, 0), P(10, 0)), 10,
        [piece(0, 0, 10, 0)]);
    cases ~= makeCase!T("boundary-overlap", square, S(P(-1, 0), P(11, 0)), 11,
        [piece(0, 0, 10, 0)]);
    cases ~= makeCase!T("isolated-tangent", square, S(P(-2, 2), P(2, -2)), 3, []);
    cases ~= makeCase!T("degenerate-interior", square, S(P(5, 5), P(5, 5)), 4, []);
    cases ~= makeCase!T("degenerate-boundary", square, S(P(0, 5), P(0, 5)), 2, []);
    cases ~= makeCase!T("empty", [], S(P(-1, 5), P(11, 5)), 1, []);
    cases ~= makeCase!T("concave-u", [[P(0, 0), P(10, 0), P(10, 10),
        P(7, 10), P(7, 3), P(3, 3), P(3, 10), P(0, 10)]],
        S(P(-1, 5), P(11, 5)), 7, [piece(0, 5, 3, 5), piece(7, 5, 10, 5)]);
    cases ~= makeCase!T("hole", [square[0], rectangle!T(3, 3, 7, 7)],
        S(P(-1, 5), P(11, 5)), 7, [piece(0, 5, 3, 5), piece(7, 5, 10, 5)]);
    auto reversedOuter = square[0].dup;
    auto reversedHole = rectangle!T(3, 3, 7, 7);
    reverse(reversedOuter);
    reverse(reversedHole);
    cases ~= makeCase!T("hole-reversed", [reversedOuter, reversedHole],
        S(P(-1, 5), P(11, 5)), 7, [piece(0, 5, 3, 5), piece(7, 5, 10, 5)]);
    cases ~= makeCase!T("rational-crossing", [[P(0, 0), P(4, 0), P(0, 3)]],
        S(P(-1, 1), P(5, 1)), 7, [piece(0, 1, 8.0 / 3.0, 1)]);

    // Sparse event scaling: redundant collinear vertices, fixed result size.
    foreach (subdivisions; [1, 4, 16, 64])
    {
        P[] ring;
        foreach (j; 0 .. subdivisions) ring ~= P(cast(T)(4 * j), 0);
        foreach (j; 0 .. subdivisions) ring ~= P(cast(T)(4 * subdivisions), cast(T)(4 * j));
        foreach (j; 0 .. subdivisions) ring ~= P(cast(T)(4 * (subdivisions - j)), cast(T)(4 * subdivisions));
        foreach (j; 0 .. subdivisions) ring ~= P(0, cast(T)(4 * (subdivisions - j)));
        cases ~= makeCase!T("sparse-" ~ subdivisions.to!string, [ring],
            S(P(-1, 1), P(cast(T)(4 * subdivisions + 1), 1)), 7,
            [piece(0, 1, 4 * subdivisions, 1)]);
    }

    // Dense event and component scaling: a simple comb with n separated teeth.
    foreach (teeth; [1, 4, 16, 64])
    {
        int right = 4 * teeth - 2;
        P[] ring = [P(0, 0), P(cast(T) right, 0), P(cast(T) right, 4)];
        foreach_reverse (j; 1 .. teeth)
        {
            ring ~= [P(cast(T)(4 * j), 4), P(cast(T)(4 * j), 1),
                P(cast(T)(4 * j - 2), 1), P(cast(T)(4 * j - 2), 4)];
        }
        ring ~= P(0, 4);
        Segment2!double[] expected;
        foreach (j; 0 .. teeth) expected ~= piece(4 * j, 2, 4 * j + 2, 2);
        cases ~= makeCase!T("dense-" ~ teeth.to!string, [ring],
            S(P(-1, 2), P(cast(T)(right + 1), 2)), 7, expected);
    }

    static if (is(T == float) || is(T == double))
    {
        foreach (scale; [T.min_normal * T.epsilon, T.max / 16])
        {
            string name = scale < 1 ? "subnormal" : "large-finite";
            cases ~= makeCase!T(name, [rectangle!T(0, 0, 4 * scale, 4 * scale)],
                S(P(-scale, 2 * scale), P(5 * scale, 2 * scale)), 7,
                [piece(0, 2 * scale, 4 * scale, 2 * scale)]);
        }
    }
    static if (is(T == int) || is(T == long))
    {
        enum scale = T.max / 16;
        cases ~= makeCase!T("wide-integral", [rectangle!T(0, 0, 4 * scale, 4 * scale)],
            S(P(-scale, 2 * scale), P(5 * scale, 2 * scale)), 7,
            [piece(0, cast(double)(2 * scale), cast(double)(4 * scale), cast(double)(2 * scale))]);
    }
    static if (is(T == long))
    {
        enum x0 = long.max - 1;
        cases ~= makeCase!T("endpoint-collapse", [rectangle!T(x0, 0, long.max, 10)],
            S(P(x0, 5), P(long.max, 5)), 6, [],
            SegmentPolygonClipStatus.unrepresentableConstruction);
        enum long base = 9_007_199_254_740_992L;
        cases ~= makeCase!T("gap-collapse", [rectangle!T(base - 2, 0, base + 4, 10),
            rectangle!T(base, 2, base + 1, 8)], S(P(base - 2, 5), P(base + 4, 5)),
            7, [], SegmentPolygonClipStatus.unrepresentableConstruction);
    }
    return cases;
}

private void preflight(T)(ref Case!T c)
{
    enforce(validatePolygon(c.polygon).valid, "invalid fixture: " ~ c.name);
    foreach (direction; 0 .. 2)
    {
        auto query = c.queries[direction];
        enforce(query.isFinite, "nonfinite fixture: " ~ c.name);
        enforce(facts(classifySegmentPolygonRelationship(query, c.polygon)) == c.expectedFacts,
            "relationship mismatch: " ~ c.name);
        auto result = clipSegmentToPolygon(query, c.polygon);
        enforce(result.status == c.expectedStatus, "status mismatch: " ~ c.name);
        if (!result.succeeded) continue; // Never read geometry on failure.
        enforce(result.length == c.expected.length, "component count: " ~ c.name);
        foreach (i; 0 .. result.length)
        {
            auto expected = c.expected[direction ? c.expected.length - 1 - i : i];
            if (direction) expected = Segment2!double(expected.b, expected.a);
            enforce(result[i] == expected, "component coordinates/order: " ~ c.name);
        }
    }
}

private void measure(alias operation, T)(ref Case!T c, string name,
    size_t rounds, size_t fixedIterations, long targetMilliseconds)
{
    size_t iterations = fixedIterations ? fixedIterations : 1;
    ulong sink = 1;
    if (!fixedIterations)
    {
        while (true)
        {
            StopWatch calibration;
            calibration.start();
            foreach (i; 0 .. iterations) sink = sink * 1_000_003UL + operation(c, i);
            calibration.stop();
            if (calibration.peek.total!"msecs" >= targetMilliseconds || iterations >= 65_536)
                break;
            iterations *= 2;
        }
    }
    size_t warmup = iterations / 10 + 1;
    foreach (i; 0 .. warmup) sink = sink * 1_000_003UL + operation(c, i);
    double[] timings = new double[rounds];
    foreach (round; 0 .. rounds)
    {
        // Collection is outside timing; automatic collection stays enabled.
        GC.collect();
        auto beforeBytes = GC.stats().allocatedInCurrentThread;
        auto beforeCollections = GC.profileStats().numCollections;
        StopWatch watch;
        watch.start();
        foreach (i; 0 .. iterations) sink = sink * 1_000_003UL + operation(c, i);
        watch.stop();
        auto elapsed = watch.peek.total!"nsecs";
        auto bytes = GC.stats().allocatedInCurrentThread - beforeBytes;
        auto collections = GC.profileStats().numCollections - beforeCollections;
        timings[round] = cast(double) elapsed / iterations;
        writefln("sample,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", T.stringof, c.name,
            name, c.edges, c.expected.length, round, iterations, warmup,
            elapsed, bytes, collections);
        static if (__traits(isSame, operation, relationship!T))
            enforce(bytes == 0, "relationship allocated GC bytes");
    }
    sort(timings);
    double median = (timings[(rounds - 1) / 2] + timings[rounds / 2]) / 2;
    writefln("summary,%s,%s,%s,%.3f,%.3f,%.3f", T.stringof, c.name, name,
        timings[0], median, timings[$ - 1]);
    benchmarkSink = benchmarkSink * 1_000_033UL + sink;
}

private void run(T)(bool checkOnly, size_t rounds, size_t iterations, long target)
{
    auto cases = corpus!T();
    foreach (ref c; cases)
    {
        preflight(c);
        writefln("fixture,%s,%s,%s,%s,%s,%s", T.stringof, c.name,
            c.edges, c.expectedFacts, c.expectedStatus, c.expected.length);
    }
    writefln("preflight,%s,%s,PASS", T.stringof, cases.length);
    if (checkOnly) return;
    foreach (ref c; cases)
    {
        measure!(relationship!T)(c, "relationship", rounds, iterations, target);
        measure!(clipping!T)(c, "clipping", rounds, iterations, target);
    }
}

void main(string[] args)
{
    bool checkOnly;
    size_t rounds = 7, iterations;
    long target = 20;
    foreach (arg; args[1 .. $])
    {
        if (arg == "--check") checkOnly = true;
        else if (arg.length > 9 && arg[0 .. 9] == "--rounds=") rounds = arg[9 .. $].to!size_t;
        else if (arg.length > 13 && arg[0 .. 13] == "--iterations=") iterations = arg[13 .. $].to!size_t;
        else if (arg.length > 12 && arg[0 .. 12] == "--target-ms=") target = arg[12 .. $].to!long;
        else enforce(false, "unknown option: " ~ arg);
    }
    enforce(rounds > 0 && rounds <= 100 && target > 0 && target <= 60_000 &&
        iterations <= 10_000_000, "invalid measurement limits");
    writeln("fixture_header,scalar,case,edges,expected_fact_bits,expected_status,expected_components");
    writeln("sample_header,scalar,case,operation,edges,expected_components,round,iterations,warmup,elapsed_ns,gc_bytes,gc_collections");
    writeln("summary_header,scalar,case,operation,min_ns_per_op,median_ns_per_op,max_ns_per_op");
    run!int(checkOnly, rounds, iterations, target);
    run!long(checkOnly, rounds, iterations, target);
    run!float(checkOnly, rounds, iterations, target);
    run!double(checkOnly, rounds, iterations, target);
    writefln("sink,%s", benchmarkSink);
}
