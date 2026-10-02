// Public native GEOS C-API clipping benchmark. See native.md for scope/costs.
#include <geos_c.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

struct Point { double x, y; };
struct Segment { Point a, b; };
bool operator==(Point a, Point b) { return a.x == b.x && a.y == b.y; }
bool operator==(Segment a, Segment b) { return a.a == b.a && a.b == b.b; }
double number(std::uint64_t bits) {
    static_assert(sizeof(double) == sizeof(bits));
    double value;
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}
Point bp(std::uint64_t x, std::uint64_t y) { return {number(x), number(y)}; }
struct Fixture {
    std::string scalar, name;
    std::vector<std::vector<Point>> rings;
    Segment query;
    std::vector<Segment> expected;
    std::size_t edges;
};
#include "native_corpus.hpp" // Generated from the shared, preflighted JSON export.

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
struct Context {
    GEOSContextHandle_t handle = GEOS_init_r();
    std::string error;
    static void onError(const char* message, void* data) {
        static_cast<Context*>(data)->error = message;
    }
    Context() {
        require(handle != nullptr, "GEOS context allocation");
        GEOSContext_setErrorMessageHandler_r(handle, onError, this);
    }
    ~Context() { GEOS_finish_r(handle); }
    Context(const Context&) = delete;
};
struct DeleteGeometry {
    GEOSContextHandle_t context;
    void operator()(GEOSGeometry* geometry) const {
        if (geometry) GEOSGeom_destroy_r(context, geometry);
    }
};
using Geometry = std::unique_ptr<GEOSGeometry, DeleteGeometry>;
Geometry own(Context& ctx, GEOSGeometry* geometry) {
    if (!geometry) throw std::runtime_error("GEOS: " + ctx.error);
    return Geometry(geometry, DeleteGeometry{ctx.handle});
}
Geometry line(Context& ctx, const std::vector<Point>& points, bool ring) {
    auto sequence = GEOSCoordSeq_create_r(ctx.handle, points.size(), 2);
    require(sequence != nullptr, "coordinate allocation");
    for (std::size_t i = 0; i < points.size(); ++i) {
        if (!GEOSCoordSeq_setXY_r(ctx.handle, sequence, i, points[i].x, points[i].y)) {
            GEOSCoordSeq_destroy_r(ctx.handle, sequence);
            throw std::runtime_error("coordinate assignment");
        }
    }
    // GEOS constructors take ownership of the sequence, including on error.
    return own(ctx, ring ? GEOSGeom_createLinearRing_r(ctx.handle, sequence)
                         : GEOSGeom_createLineString_r(ctx.handle, sequence));
}
Geometry polygon(Context& ctx, const Fixture& fixture) {
    if (fixture.rings.empty()) return own(ctx, GEOSGeom_createEmptyPolygon_r(ctx.handle));
    std::vector<Geometry> rings;
    for (auto points : fixture.rings) {
        points.push_back(points.front()); // Explicit closure outside timing.
        rings.push_back(line(ctx, points, true));
    }
    std::vector<GEOSGeometry*> holes;
    for (std::size_t i = 1; i < rings.size(); ++i) holes.push_back(rings[i].get());
    auto shell = rings.front().release();
    for (std::size_t i = 1; i < rings.size(); ++i) rings[i].release();
    return own(ctx, GEOSGeom_createPolygon_r(ctx.handle, shell, holes.data(), holes.size()));
}
struct Prepared {
    const Fixture* fixture;
    Geometry polygon;
    std::array<Geometry, 2> queries;
};
Point coordinate(Context& ctx, const GEOSCoordSequence* sequence, unsigned int i) {
    Point p;
    require(GEOSCoordSeq_getXY_r(ctx.handle, sequence, i, &p.x, &p.y), "coordinate read");
    require(std::isfinite(p.x) && std::isfinite(p.y), "nonfinite native output");
    return p;
}
void collect(Context& ctx, const GEOSGeometry* geometry, std::vector<Segment>& pieces) {
    const char empty = GEOSisEmpty_r(ctx.handle, geometry);
    require(empty != 2, "native emptiness error");
    if (empty) return;
    switch (GEOSGeomTypeId_r(ctx.handle, geometry)) {
    case GEOS_POINT: return; // One-dimensional regularization: omit isolated contacts.
    case GEOS_LINESTRING: {
        auto sequence = GEOSGeom_getCoordSeq_r(ctx.handle, geometry);
        require(sequence != nullptr, "native line coordinates");
        unsigned int count;
        require(GEOSCoordSeq_getSize_r(ctx.handle, sequence, &count) && count >= 2,
                "native line size");
        Segment segment{coordinate(ctx, sequence, 0), coordinate(ctx, sequence, count - 1)};
        if (!(segment.a == segment.b)) pieces.push_back(segment);
        return;
    }
    case GEOS_MULTILINESTRING:
    case GEOS_MULTIPOINT:
    case GEOS_GEOMETRYCOLLECTION: {
        const int count = GEOSGetNumGeometries_r(ctx.handle, geometry);
        require(count >= 0, "native component count");
        for (int i = 0; i < count; ++i) {
            auto child = GEOSGetGeometryN_r(ctx.handle, geometry, i);
            require(child != nullptr, "native component read");
            collect(ctx, child, pieces);
        }
        return;
    }
    default: throw std::runtime_error("unexpected native intersection type");
    }
}
std::vector<Segment> clip(Context& ctx, const Prepared& c, std::size_t direction) {
    auto result = own(ctx, GEOSIntersection_r(ctx.handle, c.queries[direction].get(), c.polygon.get()));
    std::vector<Segment> pieces;
    collect(ctx, result.get(), pieces);
    Segment query = c.fixture->query;
    if (direction) std::swap(query.a, query.b);
    const bool xaxis = query.a.x != query.b.x;
    const auto axis = [xaxis](Point p) { return xaxis ? p.x : p.y; };
    const bool reverse = axis(query.b) < axis(query.a);
    for (auto& piece : pieces)
        if ((axis(piece.b) < axis(piece.a)) != reverse) std::swap(piece.a, piece.b);
    std::sort(pieces.begin(), pieces.end(), [&](Segment a, Segment b) {
        return reverse ? axis(a.a) > axis(b.a) : axis(a.a) < axis(b.a);
    });
    // In-place coalescing keeps one owning contiguous result; no persistent workspace.
    std::size_t count = 0;
    for (const auto piece : pieces) {
        if (count && pieces[count - 1].b == piece.a) pieces[count - 1].b = piece.b;
        else pieces[count++] = piece;
    }
    pieces.resize(count);
    return pieces; // Native geometry disposed here; owning vector disposed by caller.
}
std::uint64_t bits(double value) {
    std::uint64_t result;
    std::memcpy(&result, &value, sizeof(result));
    return result;
}
std::uint64_t benchmarkSink = 0;
#if defined(__GNUC__) || defined(__clang__)
__attribute__((noinline))
#endif
std::uint64_t operation(Context& ctx, const Prepared& c, std::size_t i) {
    volatile std::size_t input = i;
    auto result = clip(ctx, c, input & 1);
    std::uint64_t signature = 1000003ULL + result.size(); // geo-d success == 1.
    for (auto s : result)
        for (double value : {s.a.x, s.a.y, s.b.x, s.b.y})
            signature = signature * 1000003ULL + bits(value);
    return signature; // Owned normalized result released inside the timed operation.
}
void measure(Context& ctx, const Prepared& c, std::size_t rounds,
             std::size_t fixedIterations, std::size_t target) {
    using Clock = std::chrono::steady_clock;
    std::size_t iterations = fixedIterations ? fixedIterations : 1;
    std::uint64_t sink = 1;
    const auto run = [&](std::size_t count) {
        const auto start = Clock::now();
        for (std::size_t i = 0; i < count; ++i) sink = sink * 1000003ULL + operation(ctx, c, i);
        return std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - start).count();
    };
    if (!fixedIterations) while (run(iterations) < static_cast<long long>(target) * 1000000
                                && iterations < 65536) iterations *= 2;
    const std::size_t warmup = iterations / 10 + 1;
    run(warmup);
    std::vector<double> times;
    for (std::size_t round = 0; round < rounds; ++round) {
        const auto elapsed = run(iterations);
        times.push_back(static_cast<double>(elapsed) / iterations);
        std::cout << "sample," << c.fixture->scalar << ',' << c.fixture->name << ",clipping,"
                  << c.fixture->edges << ',' << c.fixture->expected.size() << ',' << round << ','
                  << iterations << ',' << warmup << ',' << elapsed << ",NA,NA\n";
    }
    std::sort(times.begin(), times.end());
    std::cout << "summary," << c.fixture->scalar << ',' << c.fixture->name << ",clipping,"
              << times.front() << ',' << (times[(rounds - 1) / 2] + times[rounds / 2]) / 2
              << ',' << times.back() << '\n';
    benchmarkSink = benchmarkSink * 1000033ULL + sink;
}
int main(int argc, char** argv) try {
    bool check = false;
    std::size_t rounds = 7, iterations = 0, target = 20;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--check") check = true;
        else if (arg.rfind("--rounds=", 0) == 0) rounds = std::stoul(arg.substr(9));
        else if (arg.rfind("--iterations=", 0) == 0) iterations = std::stoul(arg.substr(13));
        else if (arg.rfind("--target-ms=", 0) == 0) target = std::stoul(arg.substr(12));
        else throw std::runtime_error("unknown argument");
    }
    require(rounds && rounds <= 100 && iterations <= 10000000 && target && target <= 60000,
            "invalid measurement limits");
    require(std::string(GEOSversion()).rfind("3.13.1-CAPI-", 0) == 0, "GEOS 3.13.1 required");
    std::cout << "native_version," << GEOSversion() << '\n' << std::fixed << std::setprecision(3);
    Context ctx;
    auto fixtures = corpus();
    require(fixtures.size() == 87, "87 admitted fixtures required");
    std::vector<Prepared> prepared;
    for (const auto& fixture : fixtures) {
        auto poly = polygon(ctx, fixture);
        require(GEOSisValid_r(ctx.handle, poly.get()) == 1, "native polygon validation");
        auto forward = line(ctx, {fixture.query.a, fixture.query.b}, false);
        auto reverse = line(ctx, {fixture.query.b, fixture.query.a}, false);
        Prepared c{&fixture, std::move(poly), {std::move(forward), std::move(reverse)}};
        for (std::size_t direction = 0; direction < 2; ++direction) {
            auto expected = fixture.expected;
            if (direction) {
                std::reverse(expected.begin(), expected.end());
                for (auto& s : expected) std::swap(s.a, s.b);
            }
            require(clip(ctx, c, direction) == expected, "native endpoint/order mismatch");
        }
        std::cout << "fixture," << fixture.scalar << ',' << fixture.name << ',' << fixture.edges
                  << ',' << fixture.expected.size() << ",PASS,query_valid,"
                  << int(GEOSisValid_r(ctx.handle, c.queries[0].get())) << ','
                  << int(GEOSisValid_r(ctx.handle, c.queries[1].get())) << '\n';
        prepared.push_back(std::move(c));
    }
    std::cout << "preflight,native,87,174,PASS\n";
    if (!check) for (const auto& c : prepared) measure(ctx, c, rounds, iterations, target);
    std::cout << "checksum," << benchmarkSink << '\n';
} catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
}
