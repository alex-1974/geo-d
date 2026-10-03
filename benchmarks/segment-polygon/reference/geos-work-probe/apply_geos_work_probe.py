#!/usr/bin/env python3
"""Apply the geo-d diagnostic work-attribution instrumentation to GEOS 3.13.1.

This is research-only instrumentation.  It deliberately changes execution cost
and must never be used as the native wall-clock reference.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

EXPECTED_COMMIT = "431568d6e311e0bbfb057b4ec3d44d0d3ba3335f"

EXPECTED_BLOBS = {
    "src/operation/overlayng/OverlayNGRobust.cpp": "e9af20896a96c2fbc12e227871ba9b51a834c4c8",
    "src/algorithm/CGAlgorithmsDD.cpp": "ccfef602efc51b465f84cc1edd06f545dc537d48",
    "src/noding/MCIndexNoder.cpp": "6cdd9a45bb05864ec5c2503336c0527341f7afad",
    "src/noding/IntersectionAdder.cpp": "1ad9d2fbfa3fcaf167aa63eb82b472ef7bb6eaf3",
    "src/operation/overlayng/EdgeNodingBuilder.cpp": "fd3fd8557081f567be8c2f6f949b449893fd23d4",
    "src/operation/overlayng/OverlayNG.cpp": "02cfb93111c396adb329dd3c8042e690a8d13113",
    "src/operation/overlayng/InputGeometry.cpp": "794971887f793e5a4776695a2caa6ebc2568137e",
    "src/operation/overlayng/RobustClipEnvelopeComputer.cpp": "2786701d6d05c3131f6e225d34ff0ce49c0c4436",
}

HEADER = r"""#pragma once

#include <chrono>
#include <cstdint>

namespace geos {
namespace diagnostic {

struct GeoDWorkProbeCounters {
    std::uint64_t overlayCalls = 0;
    std::uint64_t fixedPrecisionOverlayCalls = 0;
    std::uint64_t floatingOverlayAttempts = 0;
    std::uint64_t floatingOverlaySuccesses = 0;
    std::uint64_t floatingOverlayFailures = 0;
    std::uint64_t snappingOverlaySuccesses = 0;
    std::uint64_t snapRoundingOverlaySuccesses = 0;

    std::uint64_t orientationCalls = 0;
    std::uint64_t orientationFilterSuccesses = 0;
    std::uint64_t orientationDDFallbacks = 0;
    std::uint64_t ddIntersectionConstructions = 0;

    std::uint64_t monotoneChains = 0;
    std::uint64_t chainPairs = 0;
    std::uint64_t segmentIntersectionTests = 0;
    std::uint64_t segmentIntersections = 0;
    std::uint64_t properIntersections = 0;

    std::uint64_t clipEnvelopeSegmentTests = 0;
    std::uint64_t polygonSegmentsInput = 0;
    std::uint64_t polygonSegmentsAfterClip = 0;
    std::uint64_t lineSegmentsInput = 0;
    std::uint64_t lineSegmentsAfterLimit = 0;

    std::uint64_t pointInAreaCalls = 0;
    std::uint64_t pointLocatorBuilds = 0;

    std::uint64_t clipEnvelopeNs = 0;
    std::uint64_t nodingNs = 0;
    std::uint64_t graphBuildNs = 0;
    std::uint64_t labellingNs = 0;
    std::uint64_t extractionNs = 0;
};

inline GeoDWorkProbeCounters geoDWorkProbe;

inline void
resetGeoDWorkProbe()
{
    geoDWorkProbe = GeoDWorkProbeCounters{};
}

class GeoDWorkProbeTimer {
public:
    explicit GeoDWorkProbeTimer(std::uint64_t& sink)
        : target(sink)
        , start(std::chrono::steady_clock::now())
    {}

    ~GeoDWorkProbeTimer()
    {
        const auto elapsed =
            std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::steady_clock::now() - start
            ).count();

        if (elapsed > 0) {
            target += static_cast<std::uint64_t>(elapsed);
        }
    }

    GeoDWorkProbeTimer(const GeoDWorkProbeTimer&) = delete;
    GeoDWorkProbeTimer& operator=(const GeoDWorkProbeTimer&) = delete;

private:
    std::uint64_t& target;
    std::chrono::steady_clock::time_point start;
};

} // namespace diagnostic
} // namespace geos
"""


def git_blob_sha(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:80]!r}")
    path.write_text(text.replace(old, new, 1))


def verify_source(root: Path) -> None:
    head = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    if head != EXPECTED_COMMIT:
        raise RuntimeError(f"GEOS commit mismatch: expected {EXPECTED_COMMIT}, got {head}")

    dirty = subprocess.check_output(
        ["git", "-C", str(root), "status", "--short"], text=True
    )
    if dirty:
        raise RuntimeError("GEOS checkout must be clean before instrumentation")

    for rel, expected in EXPECTED_BLOBS.items():
        path = root / rel
        actual = git_blob_sha(path.read_bytes())
        if actual != expected:
            raise RuntimeError(
                f"GEOS source mismatch for {rel}: expected blob {expected}, got {actual}"
            )


def apply(root: Path) -> None:
    verify_source(root)

    header = root / "include/geos/diagnostic/GeoDWorkProbe.h"
    header.parent.mkdir(parents=True, exist_ok=True)
    if header.exists():
        raise RuntimeError(f"diagnostic header already exists: {header}")
    header.write_text(HEADER)

    path = root / "src/operation/overlayng/OverlayNGRobust.cpp"
    replace_once(
        path,
        "#include <geos/operation/overlayng/OverlayNGRobust.h>\n",
        "#include <geos/operation/overlayng/OverlayNGRobust.h>\n"
        "#include <geos/diagnostic/GeoDWorkProbe.h>\n",
    )
    replace_once(
        path,
        """OverlayNGRobust::Overlay(const Geometry* geom0, const Geometry* geom1, int opCode)
{
    geos::util::ensureNoCurvedComponents(geom0);""",
        """OverlayNGRobust::Overlay(const Geometry* geom0, const Geometry* geom1, int opCode)
{
    ++::geos::diagnostic::geoDWorkProbe.overlayCalls;
    geos::util::ensureNoCurvedComponents(geom0);""",
    )
    replace_once(
        path,
        """    if (!geom0->getPrecisionModel()->isFloating()) {
#if GEOS_DEBUG""",
        """    if (!geom0->getPrecisionModel()->isFloating()) {
        ++::geos::diagnostic::geoDWorkProbe.fixedPrecisionOverlayCalls;
#if GEOS_DEBUG""",
    )
    replace_once(
        path,
        """    try {
        geom::PrecisionModel PM_FLOAT;""",
        """    ++::geos::diagnostic::geoDWorkProbe.floatingOverlayAttempts;
    try {
        geom::PrecisionModel PM_FLOAT;""",
    )
    replace_once(
        path,
        """        result = OverlayNG::overlay(geom0, geom1, opCode, &PM_FLOAT);

        // Simple noding with no validation""",
        """        result = OverlayNG::overlay(geom0, geom1, opCode, &PM_FLOAT);
        ++::geos::diagnostic::geoDWorkProbe.floatingOverlaySuccesses;

        // Simple noding with no validation""",
    )
    replace_once(
        path,
        """    catch (const std::runtime_error &ex) {
        /**
        * Capture original exception,""",
        """    catch (const std::runtime_error &ex) {
        ++::geos::diagnostic::geoDWorkProbe.floatingOverlayFailures;
        /**
        * Capture original exception,""",
    )
    replace_once(
        path,
        """    result = overlaySnapTries(geom0, geom1, opCode);
    if (result != nullptr)
        return result;""",
        """    result = overlaySnapTries(geom0, geom1, opCode);
    if (result != nullptr) {
        ++::geos::diagnostic::geoDWorkProbe.snappingOverlaySuccesses;
        return result;
    }""",
    )
    replace_once(
        path,
        """    result = overlaySR(geom0, geom1, opCode);
    if (result != nullptr)
        return result;""",
        """    result = overlaySR(geom0, geom1, opCode);
    if (result != nullptr) {
        ++::geos::diagnostic::geoDWorkProbe.snapRoundingOverlaySuccesses;
        return result;
    }""",
    )

    path = root / "src/algorithm/CGAlgorithmsDD.cpp"
    replace_once(
        path,
        "#include <geos/algorithm/CGAlgorithmsDD.h>\n",
        "#include <geos/algorithm/CGAlgorithmsDD.h>\n"
        "#include <geos/diagnostic/GeoDWorkProbe.h>\n",
    )
    replace_once(
        path,
        """    // fast filter for orientation index
    // avoids use of slow extended-precision arithmetic in many cases
    int index = orientationIndexFilter(p1x, p1y, p2x, p2y, qx, qy);
    if(index <= 1) {
        return index;
    }

    // normalize coordinates""",
        """    ++::geos::diagnostic::geoDWorkProbe.orientationCalls;

    // fast filter for orientation index
    // avoids use of slow extended-precision arithmetic in many cases
    int index = orientationIndexFilter(p1x, p1y, p2x, p2y, qx, qy);
    if(index <= 1) {
        ++::geos::diagnostic::geoDWorkProbe.orientationFilterSuccesses;
        return index;
    }

    ++::geos::diagnostic::geoDWorkProbe.orientationDDFallbacks;

    // normalize coordinates""",
    )
    replace_once(
        path,
        """CGAlgorithmsDD::intersection(const CoordinateXY& p1, const CoordinateXY& p2,
                             const CoordinateXY& q1, const CoordinateXY& q2)
{
    DD q1x(q1.x);""",
        """CGAlgorithmsDD::intersection(const CoordinateXY& p1, const CoordinateXY& p2,
                             const CoordinateXY& q1, const CoordinateXY& q2)
{
    ++::geos::diagnostic::geoDWorkProbe.ddIntersectionConstructions;
    DD q1x(q1.x);""",
    )

    path = root / "src/noding/MCIndexNoder.cpp"
    replace_once(
        path,
        "#include <geos/noding/MCIndexNoder.h>\n",
        "#include <geos/noding/MCIndexNoder.h>\n"
        "#include <geos/diagnostic/GeoDWorkProbe.h>\n",
    )
    replace_once(
        path,
        """    index.queryPairs([this, &overlapAction](const MonotoneChain* queryChain, const MonotoneChain* testChain) {
        queryChain->computeOverlaps(testChain, overlapTolerance, &overlapAction);""",
        """    index.queryPairs([this, &overlapAction](const MonotoneChain* queryChain, const MonotoneChain* testChain) {
        ++::geos::diagnostic::geoDWorkProbe.chainPairs;
        queryChain->computeOverlaps(testChain, overlapTolerance, &overlapAction);""",
    )
    replace_once(
        path,
        """    // segChains will contain newly allocated MonotoneChain objects
    MonotoneChainBuilder::getChains(segStr->getCoordinates(),
                                    segStr, monoChains);

}""",
        """    // segChains will contain newly allocated MonotoneChain objects
    const std::size_t before = monoChains.size();
    MonotoneChainBuilder::getChains(segStr->getCoordinates(),
                                    segStr, monoChains);
    ::geos::diagnostic::geoDWorkProbe.monotoneChains +=
        monoChains.size() - before;

}""",
    )

    path = root / "src/noding/IntersectionAdder.cpp"
    replace_once(
        path,
        "#include <geos/noding/IntersectionAdder.h>\n",
        "#include <geos/noding/IntersectionAdder.h>\n"
        "#include <geos/diagnostic/GeoDWorkProbe.h>\n",
    )
    replace_once(
        path,
        """    numTests++;

    const CoordinateSequence& seq0""",
        """    numTests++;
    ++::geos::diagnostic::geoDWorkProbe.segmentIntersectionTests;

    const CoordinateSequence& seq0""",
    )
    replace_once(
        path,
        """    //intersectionFound = true;
    numIntersections++;""",
        """    //intersectionFound = true;
    numIntersections++;
    ++::geos::diagnostic::geoDWorkProbe.segmentIntersections;""",
    )
    replace_once(
        path,
        """        if(li.isProper()) {
            numProperIntersections++;""",
        """        if(li.isProper()) {
            numProperIntersections++;
            ++::geos::diagnostic::geoDWorkProbe.properIntersections;""",
    )

    path = root / "src/operation/overlayng/RobustClipEnvelopeComputer.cpp"
    replace_once(
        path,
        "#include <geos/operation/overlayng/RobustClipEnvelopeComputer.h>\n",
        "#include <geos/operation/overlayng/RobustClipEnvelopeComputer.h>\n"
        "#include <geos/diagnostic/GeoDWorkProbe.h>\n",
    )
    replace_once(
        path,
        """RobustClipEnvelopeComputer::addSegment(const Coordinate& p1, const Coordinate& p2)
{
    if (intersectsSegment(targetEnv, p1, p2)) {""",
        """RobustClipEnvelopeComputer::addSegment(const Coordinate& p1, const Coordinate& p2)
{
    ++::geos::diagnostic::geoDWorkProbe.clipEnvelopeSegmentTests;
    if (intersectsSegment(targetEnv, p1, p2)) {""",
    )

    path = root / "src/operation/overlayng/EdgeNodingBuilder.cpp"
    replace_once(
        path,
        "#include <geos/operation/overlayng/EdgeNodingBuilder.h>\n",
        "#include <geos/operation/overlayng/EdgeNodingBuilder.h>\n"
        "#include <geos/diagnostic/GeoDWorkProbe.h>\n",
    )
    replace_once(
        path,
        """    // don't add empty rings
    if (ring->isEmpty()) return;

    if (isClippedCompletely(ring->getEnvelopeInternal()))
      return;

    std::unique_ptr<geom::CoordinateSequence> pts = clip(ring);

    /**
    * Don't add edges that collapse to a point
    */""",
        """    // don't add empty rings
    if (ring->isEmpty()) return;

    const CoordinateSequence* originalPts = ring->getCoordinatesRO();
    if (originalPts->size() > 1) {
        ::geos::diagnostic::geoDWorkProbe.polygonSegmentsInput +=
            originalPts->size() - 1;
    }

    if (isClippedCompletely(ring->getEnvelopeInternal()))
      return;

    std::unique_ptr<geom::CoordinateSequence> pts = clip(ring);
    if (pts->size() > 1) {
        ::geos::diagnostic::geoDWorkProbe.polygonSegmentsAfterClip +=
            pts->size() - 1;
    }

    /**
    * Don't add edges that collapse to a point
    */""",
    )
    replace_once(
        path,
        """    // don't add empty lines
    if (line->isEmpty()) return;

    if (isClippedCompletely(line->getEnvelopeInternal()))
        return;

    if (isToBeLimited(line)) {
        std::vector<std::unique_ptr<CoordinateSequence>>& sections = limit(line);
        for (auto& pts : sections) {
            addLine(pts, geomIndex);
        }
    }
    else {
        std::unique_ptr<CoordinateSequence> ptsNoRepeat = removeRepeatedPoints(line);
        addLine(ptsNoRepeat, geomIndex);
    }""",
        """    // don't add empty lines
    if (line->isEmpty()) return;

    const CoordinateSequence* originalPts = line->getCoordinatesRO();
    if (originalPts->size() > 1) {
        ::geos::diagnostic::geoDWorkProbe.lineSegmentsInput +=
            originalPts->size() - 1;
    }

    if (isClippedCompletely(line->getEnvelopeInternal()))
        return;

    if (isToBeLimited(line)) {
        std::vector<std::unique_ptr<CoordinateSequence>>& sections = limit(line);
        for (auto& pts : sections) {
            if (pts->size() > 1) {
                ::geos::diagnostic::geoDWorkProbe.lineSegmentsAfterLimit +=
                    pts->size() - 1;
            }
            addLine(pts, geomIndex);
        }
    }
    else {
        std::unique_ptr<CoordinateSequence> ptsNoRepeat = removeRepeatedPoints(line);
        if (ptsNoRepeat->size() > 1) {
            ::geos::diagnostic::geoDWorkProbe.lineSegmentsAfterLimit +=
                ptsNoRepeat->size() - 1;
        }
        addLine(ptsNoRepeat, geomIndex);
    }""",
    )

    path = root / "src/operation/overlayng/OverlayNG.cpp"
    replace_once(
        path,
        "#include <geos/operation/overlayng/OverlayNG.h>\n",
        "#include <geos/operation/overlayng/OverlayNG.h>\n"
        "#include <geos/diagnostic/GeoDWorkProbe.h>\n",
    )
    replace_once(
        path,
        """    if (isOptimized) {
        bool gotClipEnv = OverlayUtil::clippingEnvelope(opCode, &inputGeom, pm, clipEnv);
        if (gotClipEnv) {
            nodingBuilder.setClipEnvelope(&clipEnv);
        }
    }

    std::vector<Edge*> edges = nodingBuilder.build(
        inputGeom.getGeometry(0),
        inputGeom.getGeometry(1));""",
        """    if (isOptimized) {
        bool gotClipEnv = false;
        {
            ::geos::diagnostic::GeoDWorkProbeTimer timer(
                ::geos::diagnostic::geoDWorkProbe.clipEnvelopeNs
            );
            gotClipEnv = OverlayUtil::clippingEnvelope(opCode, &inputGeom, pm, clipEnv);
        }
        if (gotClipEnv) {
            nodingBuilder.setClipEnvelope(&clipEnv);
        }
    }

    std::vector<Edge*> edges;
    {
        ::geos::diagnostic::GeoDWorkProbeTimer timer(
            ::geos::diagnostic::geoDWorkProbe.nodingNs
        );
        edges = nodingBuilder.build(
            inputGeom.getGeometry(0),
            inputGeom.getGeometry(1));
    }""",
    )
    replace_once(
        path,
        """    OverlayGraph graph;
    for (Edge* e : edges) {
        // Write out edge coordinates
        // std::cout << *e->getCoordinatesRO() << std::endl;
        graph.addEdge(e);
    }""",
        """    OverlayGraph graph;
    {
        ::geos::diagnostic::GeoDWorkProbeTimer timer(
            ::geos::diagnostic::geoDWorkProbe.graphBuildNs
        );
        for (Edge* e : edges) {
            // Write out edge coordinates
            // std::cout << *e->getCoordinatesRO() << std::endl;
            graph.addEdge(e);
        }
    }""",
    )
    replace_once(
        path,
        """    GEOS_CHECK_FOR_INTERRUPTS();
    labelGraph(&graph);

    // std::cout << std::endl << graph << std::endl;""",
        """    GEOS_CHECK_FOR_INTERRUPTS();
    {
        ::geos::diagnostic::GeoDWorkProbeTimer timer(
            ::geos::diagnostic::geoDWorkProbe.labellingNs
        );
        labelGraph(&graph);
    }

    // std::cout << std::endl << graph << std::endl;""",
    )
    replace_once(
        path,
        """    GEOS_CHECK_FOR_INTERRUPTS();
    std::unique_ptr<Geometry> result = extractResult(opCode, &graph);

    /**
     * Heuristic check on result area.""",
        """    GEOS_CHECK_FOR_INTERRUPTS();
    std::unique_ptr<Geometry> result;
    {
        ::geos::diagnostic::GeoDWorkProbeTimer timer(
            ::geos::diagnostic::geoDWorkProbe.extractionNs
        );
        result = extractResult(opCode, &graph);
    }

    /**
     * Heuristic check on result area.""",
    )

    path = root / "src/operation/overlayng/InputGeometry.cpp"
    replace_once(
        path,
        "#include <geos/operation/overlayng/InputGeometry.h>\n",
        "#include <geos/operation/overlayng/InputGeometry.h>\n"
        "#include <geos/diagnostic/GeoDWorkProbe.h>\n",
    )
    replace_once(
        path,
        """    PointOnGeometryLocator* ptLocator = getLocator(geomIndex);
    Location loc = ptLocator->locate(&pt);""",
        """    ++::geos::diagnostic::geoDWorkProbe.pointInAreaCalls;
    PointOnGeometryLocator* ptLocator = getLocator(geomIndex);
    Location loc = ptLocator->locate(&pt);""",
    )
    replace_once(
        path,
        """    if (geomIndex == 0) {
        if (ptLocatorA == nullptr)
            ptLocatorA.reset(new IndexedPointInAreaLocator(*getGeometry(geomIndex)));
        return ptLocatorA.get();
    }
    else {
        if (ptLocatorB == nullptr)
            ptLocatorB.reset(new IndexedPointInAreaLocator(*getGeometry(geomIndex)));
        return ptLocatorB.get();
    }""",
        """    if (geomIndex == 0) {
        if (ptLocatorA == nullptr) {
            ++::geos::diagnostic::geoDWorkProbe.pointLocatorBuilds;
            ptLocatorA.reset(new IndexedPointInAreaLocator(*getGeometry(geomIndex)));
        }
        return ptLocatorA.get();
    }
    else {
        if (ptLocatorB == nullptr) {
            ++::geos::diagnostic::geoDWorkProbe.pointLocatorBuilds;
            ptLocatorB.reset(new IndexedPointInAreaLocator(*getGeometry(geomIndex)));
        }
        return ptLocatorB.get();
    }""",
    )

    print(json.dumps({
        "status": "patched",
        "geos_commit": EXPECTED_COMMIT,
        "files": sorted(EXPECTED_BLOBS),
        "header": str(header.relative_to(root)),
    }, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("geos_source", type=Path)
    args = parser.parse_args()
    root = args.geos_source.resolve()
    if not (root / ".git").is_dir():
        raise SystemExit("geos_source must be a Git checkout")
    try:
        apply(root)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
