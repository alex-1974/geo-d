#!/usr/bin/env python3
"""Untimed native-GEOS semantic assessment; this is not a C++ speed benchmark."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import platform
import struct
import sys
import warnings

import shapely
from shapely.geometry import LineString, Polygon


def number(value, encoding):
    return value if encoding == "integer" else struct.unpack("=d", struct.pack("=Q", value))[0]


def point(values, encoding):
    return tuple(number(value, encoding) for value in values)


def bits(value):
    return struct.unpack("=Q", struct.pack("=d", float(value)))[0]


def normalized_lines(geometry, query):
    """Ordinary-case adapter: omit points, orient/sort and join exact endpoint equality.

    This cannot restore exact topology lost by input conversion or native overlay,
    and does not implement geo-d's checked construction failure policy.
    """
    pieces = []
    omitted_points = 0

    def visit(g):
        nonlocal omitted_points
        if g.is_empty:
            return
        if g.geom_type == "Point":
            omitted_points += 1
        elif g.geom_type == "LineString":
            coordinates = list(g.coords)
            a, b = tuple(coordinates[0]), tuple(coordinates[-1])
            if a != b:
                pieces.append([a, b])
        elif g.geom_type in ("MultiLineString", "MultiPoint", "GeometryCollection"):
            for child in g.geoms:
                visit(child)
        else:
            raise ValueError("unexpected intersection type: " + g.geom_type)

    visit(geometry)
    axis = 0 if query[0][0] != query[1][0] else 1
    reverse = query[1][axis] < query[0][axis]
    for piece in pieces:
        if (piece[1][axis] < piece[0][axis]) != reverse:
            piece.reverse()
    pieces.sort(key=lambda piece: piece[0][axis], reverse=reverse)
    joined = []
    for piece in pieces:
        if joined and joined[-1][1] == piece[0]:
            joined[-1][1] = piece[1]
        else:
            joined.append(piece)
    return joined, omitted_points


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if shapely.__version__ != "2.1.2" or shapely.geos_version_string != "3.13.1":
        parser.error("this retained assessment pins Shapely 2.1.2 / GEOS 3.13.1")
    cases = json.loads(args.corpus.read_text())
    if Counter(case["scalar"] for case in cases) != {"int": 22, "long": 24, "float": 23, "double": 23}:
        parser.error("expected the exported 92-case benchmark corpus")
    if len({(case["scalar"], case["case"]) for case in cases}) != 92:
        parser.error("duplicate fixture identity")
    for case in cases:
        encoding = "integer" if case["scalar"] in ("int", "long") else "binary64-bits"
        if case["coordinate_encoding"] != encoding:
            parser.error("unexpected coordinate encoding")
    records = []
    for case in cases:
        encoding = case["coordinate_encoding"]
        rings = [[point(p, encoding) for p in ring] for ring in case["rings"]]
        forward = [point(p, encoding) for p in case["query"]]
        expected = [[point(p, "binary64-bits") for p in segment]
                    for segment in case["expected_segments_binary64_bits"]]
        input_coordinates = [v for ring in rings for p in ring for v in p] + [v for p in forward for v in p]
        loss = encoding == "integer" and any(int(float(v)) != v for v in input_coordinates)
        for reverse in (False, True):
            query = forward[::-1] if reverse else forward
            wanted = [segment[::-1] for segment in expected[::-1]] if reverse else expected
            record = {"scalar": case["scalar"], "case": case["case"], "reverse": reverse,
                      "expected_geo_status": case["expected_status"],
                      "integer_to_binary64_input_loss": loss}
            polygon = Polygon(rings[0], rings[1:]) if rings else Polygon()
            line = LineString(query)
            record["native_polygon_valid"] = bool(polygon.is_valid)
            record["native_query_valid"] = bool(line.is_valid)
            if loss:
                # Refuse to present a changed input as the same geometry contract.
                record["assessment"] = "excluded_input_domain"
            else:
                try:
                    with warnings.catch_warnings(record=True) as observed:
                        warnings.simplefilter("always")
                        result = shapely.intersection(line, polygon)
                    record["native_warnings"] = [str(w.message) for w in observed]
                    pieces, omitted = normalized_lines(result, query)
                    record.update(native_type=result.geom_type,
                                  omitted_point_components=omitted,
                                  normalized_segments_binary64_bits=[[[bits(v) for v in p] for p in piece]
                                                                    for piece in pieces])
                    equal = case["expected_status"] == "success" and pieces == wanted
                    record["assessment"] = "matches_after_adapter" if equal else "output_mismatch"
                except (shapely.errors.GEOSException, ValueError) as error:
                    record.update(assessment="native_error", error_type=type(error).__name__, error=str(error))
            records.append(record)
    summary = dict(Counter(record["assessment"] for record in records))
    report = {"purpose": "semantic assessment only; no timing or full-contract equivalence claim",
              "geo_source_base": "1ed69cb77ad55fcb89bfbbabc38360fbcdb6431f",
              "python": sys.version, "platform": platform.platform(),
              "shapely": shapely.__version__, "geos": shapely.geos_version_string,
              "corpus_sha256": hashlib.sha256(args.corpus.read_bytes()).hexdigest(),
              "probe_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "command": sys.argv, "grid_size": "not supplied",
              "adapter": "drop isolated points, preserve positive endpoint-distinct lines, orient/sort/join exact endpoint equality",
              "summary": summary, "records": records}
    with args.output.open("x") as file:
        json.dump(report, file, indent=2, allow_nan=False)
        file.write("\n")
    print("GEOS SEMANTIC ASSESSMENT:", summary, "records:", len(records))


if __name__ == "__main__":
    main()
