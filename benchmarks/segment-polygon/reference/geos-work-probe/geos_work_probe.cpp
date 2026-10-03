// Research-only GEOS 3.13.1 work-attribution driver.
// Uses the same admitted corpus and normalization semantics as geos_native_bench.cpp,
// but reports internal diagnostic counters from an instrumented static GEOS build.

#include <geos_c.h>
#include <geos/diagnostic/GeoDWorkProbe.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

struct Point {
    double x;
    double y;
};

struct Segment {
    Point a;
    Point b;
};

bool operator==(Point a, Point b)
{
    return a.x == b.x && a.y == b.y;
}

bool operator==(Segment a, Segment b)
{
    return a.a == b.a && a.b == b.b;
}

double number(std::uint64_t bits)
{
    static_assert(sizeof(double) == sizeof(bits));
    double value;
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

Point bp(std::uint64_t x, std::uint64_t y)
{
    return {number(x), number(y)};
}

struct Fixture {
    std::string scalar;
    std::string name;
    std::vector<std::vector<Point>> rings;
    Segment query;
    std::vector<Segment> expected;
    std::size_t edges;
};

#include "native_corpus.hpp"

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

struct Context {
    GEOSContextHandle_t handle = GEOS_init_r();
    std::string error;

    static void onError(const char* message, void* data)
    {
        static_cast<Context*>(data)->error = message;
    }

    Context()
    {
        require(handle != nullptr, "GEOS context allocation");
        GEOSContext_setErrorMessageHandler_r(handle, onError, this);
    }

    ~Context()
    {
        GEOS_finish_r(handle);
    }

    Context(const Context&) = delete;
    Context& operator=(const Context&) = delete;
};

struct DeleteGeometry {
    GEOSContextHandle_t context;

    void operator()(GEOSGeometry* geometry) const
    {
        if (geometry) {
            GEOSGeom_destroy_r(context, geometry);
        }
    }
};

using Geometry = std::unique_ptr<GEOSGeometry, DeleteGeometry>;

Geometry own(Context& ctx, GEOSGeometry* geometry)
{
    if (!geometry) {
        throw std::runtime_error("GEOS: " + ctx.error);
    }
    return Geometry(geometry, DeleteGeometry{ctx.handle});
}

Geometry line(Context& ctx, const std::vector<Point>& points, bool ring)
{
    auto sequence = GEOSCoordSeq_create_r(ctx.handle, points.size(), 2);
    require(sequence != nullptr, "coordinate allocation");

    for (std::size_t i = 0; i < points.size(); ++i) {
        if (!GEOSCoordSeq_setXY_r(ctx.handle, sequence, i, points[i].x, points[i].y)) {
            GEOSCoordSeq_destroy_r(ctx.handle, sequence);
            throw std::runtime_error("coordinate assignment");
        }
    }

    return own(
        ctx,
        ring
            ? GEOSGeom_createLinearRing_r(ctx.handle, sequence)
            : GEOSGeom_createLineString_r(ctx.handle, sequence)
    );
}

Geometry polygon(Context& ctx, const Fixture& fixture)
{
    if (fixture.rings.empty()) {
        return own(ctx, GEOSGeom_createEmptyPolygon_r(ctx.handle));
    }

    std::vector<Geometry> rings;
    for (auto points : fixture.rings) {
        points.push_back(points.front());
        rings.push_back(line(ctx, points, true));
    }

    std::vector<GEOSGeometry*> holes;
    for (std::size_t i = 1; i < rings.size(); ++i) {
        holes.push_back(rings[i].get());
    }

    auto shell = rings.front().release();
    for (std::size_t i = 1; i < rings.size(); ++i) {
        rings[i].release();
    }

    return own(
        ctx,
        GEOSGeom_createPolygon_r(
            ctx.handle,
            shell,
            holes.data(),
            holes.size()
        )
    );
}

struct Prepared {
    const Fixture* fixture;
    Geometry polygon;
    std::array<Geometry, 2> queries;
};

Point coordinate(Context& ctx, const GEOSCoordSequence* sequence, unsigned int i)
{
    Point p;
    require(
        GEOSCoordSeq_getXY_r(ctx.handle, sequence, i, &p.x, &p.y),
        "coordinate read"
    );
    require(std::isfinite(p.x) && std::isfinite(p.y), "nonfinite native output");
    return p;
}

void collect(Context& ctx, const GEOSGeometry* geometry, std::vector<Segment>& pieces)
{
    const char empty = GEOSisEmpty_r(ctx.handle, geometry);
    require(empty != 2, "native emptiness error");
    if (empty) {
        return;
    }

    switch (GEOSGeomTypeId_r(ctx.handle, geometry)) {
    case GEOS_POINT:
        return;

    case GEOS_LINESTRING: {
        auto sequence = GEOSGeom_getCoordSeq_r(ctx.handle, geometry);
        require(sequence != nullptr, "native line coordinates");

        unsigned int count;
        require(
            GEOSCoordSeq_getSize_r(ctx.handle, sequence, &count) && count >= 2,
            "native line size"
        );

        Segment segment{
            coordinate(ctx, sequence, 0),
            coordinate(ctx, sequence, count - 1)
        };

        if (!(segment.a == segment.b)) {
            pieces.push_back(segment);
        }
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

    default:
        throw std::runtime_error("unexpected native intersection type");
    }
}

std::vector<Segment> clip(Context& ctx, const Prepared& c, std::size_t direction)
{
    auto result = own(
        ctx,
        GEOSIntersection_r(
            ctx.handle,
            c.queries[direction].get(),
            c.polygon.get()
        )
    );

    std::vector<Segment> pieces;
    collect(ctx, result.get(), pieces);

    Segment query = c.fixture->query;
    if (direction) {
        std::swap(query.a, query.b);
    }

    const bool xaxis = query.a.x != query.b.x;
    const auto axis = [xaxis](Point p) {
        return xaxis ? p.x : p.y;
    };

    const bool reverse = axis(query.b) < axis(query.a);

    for (auto& piece : pieces) {
        if ((axis(piece.b) < axis(piece.a)) != reverse) {
            std::swap(piece.a, piece.b);
        }
    }

    std::sort(
        pieces.begin(),
        pieces.end(),
        [&](Segment a, Segment b) {
            return reverse
                ? axis(a.a) > axis(b.a)
                : axis(a.a) < axis(b.a);
        }
    );

    std::size_t count = 0;
    for (const auto piece : pieces) {
        if (count && pieces[count - 1].b == piece.a) {
            pieces[count - 1].b = piece.b;
        }
        else {
            pieces[count++] = piece;
        }
    }

    pieces.resize(count);
    return pieces;
}

std::uint64_t bits(double value)
{
    std::uint64_t result;
    std::memcpy(&result, &value, sizeof(result));
    return result;
}

std::uint64_t signature(const std::vector<Segment>& result)
{
    std::uint64_t value = 1000003ULL + result.size();

    for (auto s : result) {
        for (double coordinateValue : {s.a.x, s.a.y, s.b.x, s.b.y}) {
            value = value * 1000003ULL + bits(coordinateValue);
        }
    }

    return value;
}

void printHeader()
{
    std::cout
        << "probe,scalar,case,direction,edges,components,iterations,"
        << "overlay_calls,fixed_precision_overlay_calls,"
        << "floating_overlay_attempts,floating_overlay_successes,floating_overlay_failures,"
        << "snapping_overlay_successes,snap_rounding_overlay_successes,"
        << "orientation_calls,orientation_filter_successes,orientation_dd_fallbacks,"
        << "dd_intersection_constructions,monotone_chains,chain_pairs,"
        << "segment_intersection_tests,segment_intersections,proper_intersections,"
        << "clip_envelope_segment_tests,polygon_segments_input,polygon_segments_after_clip,"
        << "line_segments_input,line_segments_after_limit,"
        << "point_in_area_calls,point_locator_builds,"
        << "clip_envelope_ns,noding_ns,graph_build_ns,labelling_ns,extraction_ns,"
        << "signature\n";
}

void printProbe(
    const Fixture& fixture,
    std::size_t direction,
    std::size_t iterations,
    std::uint64_t resultSignature
)
{
    const auto& p = geos::diagnostic::geoDWorkProbe;

    std::cout
        << "probe,"
        << fixture.scalar << ','
        << fixture.name << ','
        << direction << ','
        << fixture.edges << ','
        << fixture.expected.size() << ','
        << iterations << ','
        << p.overlayCalls << ','
        << p.fixedPrecisionOverlayCalls << ','
        << p.floatingOverlayAttempts << ','
        << p.floatingOverlaySuccesses << ','
        << p.floatingOverlayFailures << ','
        << p.snappingOverlaySuccesses << ','
        << p.snapRoundingOverlaySuccesses << ','
        << p.orientationCalls << ','
        << p.orientationFilterSuccesses << ','
        << p.orientationDDFallbacks << ','
        << p.ddIntersectionConstructions << ','
        << p.monotoneChains << ','
        << p.chainPairs << ','
        << p.segmentIntersectionTests << ','
        << p.segmentIntersections << ','
        << p.properIntersections << ','
        << p.clipEnvelopeSegmentTests << ','
        << p.polygonSegmentsInput << ','
        << p.polygonSegmentsAfterClip << ','
        << p.lineSegmentsInput << ','
        << p.lineSegmentsAfterLimit << ','
        << p.pointInAreaCalls << ','
        << p.pointLocatorBuilds << ','
        << p.clipEnvelopeNs << ','
        << p.nodingNs << ','
        << p.graphBuildNs << ','
        << p.labellingNs << ','
        << p.extractionNs << ','
        << resultSignature
        << '\n';
}

int main(int argc, char** argv) try
{
    std::size_t iterations = 50;

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];

        if (arg.rfind("--iterations=", 0) == 0) {
            iterations = std::stoul(arg.substr(13));
        }
        else {
            throw std::runtime_error("unknown argument");
        }
    }

    require(iterations >= 1 && iterations <= 100000, "invalid iteration count");
    require(
        std::string(GEOSversion()).rfind("3.13.1-CAPI-", 0) == 0,
        "GEOS 3.13.1 required"
    );

    Context ctx;
    auto fixtures = corpus();
    require(fixtures.size() == 87, "87 admitted fixtures required");

    std::vector<Prepared> prepared;
    prepared.reserve(fixtures.size());

    for (const auto& fixture : fixtures) {
        auto poly = polygon(ctx, fixture);
        require(GEOSisValid_r(ctx.handle, poly.get()) == 1, "native polygon validation");

        auto forward = line(ctx, {fixture.query.a, fixture.query.b}, false);
        auto reverse = line(ctx, {fixture.query.b, fixture.query.a}, false);

        Prepared c{
            &fixture,
            std::move(poly),
            {std::move(forward), std::move(reverse)}
        };

        for (std::size_t direction = 0; direction < 2; ++direction) {
            auto expected = fixture.expected;

            if (direction) {
                std::reverse(expected.begin(), expected.end());
                for (auto& s : expected) {
                    std::swap(s.a, s.b);
                }
            }

            require(
                clip(ctx, c, direction) == expected,
                "native endpoint/order mismatch"
            );
        }

        prepared.push_back(std::move(c));
    }

    std::cout << "native_version," << GEOSversion() << '\n';
    std::cout << "preflight,native,87,174,PASS\n";
    printHeader();

    std::uint64_t sink = 1;

    for (const auto& c : prepared) {
        for (std::size_t direction = 0; direction < 2; ++direction) {
            auto expected = c.fixture->expected;

            if (direction) {
                std::reverse(expected.begin(), expected.end());
                for (auto& s : expected) {
                    std::swap(s.a, s.b);
                }
            }

            geos::diagnostic::resetGeoDWorkProbe();

            std::uint64_t rowSignature = 1;
            for (std::size_t i = 0; i < iterations; ++i) {
                const auto result = clip(ctx, c, direction);

                if (i == 0) {
                    require(result == expected, "probe endpoint/order mismatch");
                }

                rowSignature =
                    rowSignature * 1000003ULL +
                    signature(result);
            }

            sink = sink * 1000033ULL + rowSignature;

            printProbe(
                *c.fixture,
                direction,
                iterations,
                rowSignature
            );
        }
    }

    std::cout << "checksum," << sink << '\n';
    return 0;
}
catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
}
