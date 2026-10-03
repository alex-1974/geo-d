#!/usr/bin/env python3
"""Audit and summarize research-only GEOS work-attribution output."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from statistics import fmean

COUNT_FIELDS = [
    "overlay_calls",
    "fixed_precision_overlay_calls",
    "floating_overlay_attempts",
    "floating_overlay_successes",
    "floating_overlay_failures",
    "snapping_overlay_successes",
    "snap_rounding_overlay_successes",
    "orientation_calls",
    "orientation_filter_successes",
    "orientation_dd_fallbacks",
    "dd_intersection_constructions",
    "monotone_chains",
    "chain_pairs",
    "segment_intersection_tests",
    "segment_intersections",
    "proper_intersections",
    "clip_envelope_segment_tests",
    "polygon_segments_input",
    "polygon_segments_after_clip",
    "line_segments_input",
    "line_segments_after_limit",
    "point_in_area_calls",
    "point_locator_builds",
]

TIME_FIELDS = [
    "clip_envelope_ns",
    "noding_ns",
    "graph_build_ns",
    "labelling_ns",
    "extraction_ns",
]

REPRESENTATIVE_CASES = [
    "crossing",
    "sparse-64",
    "dense-16",
    "dense-64",
]


def load_rows(path: Path):
    lines = path.read_text().splitlines()
    try:
        header_index = next(
            i for i, line in enumerate(lines)
            if line.startswith("probe,scalar,case,direction,")
        )
    except StopIteration as exc:
        raise RuntimeError("missing probe header") from exc

    reader = csv.DictReader(lines[header_index:])
    rows = []

    for raw in reader:
        if raw.get("probe") != "probe":
            continue

        row = {
            "scalar": raw["scalar"],
            "case": raw["case"],
            "direction": int(raw["direction"]),
            "edges": int(raw["edges"]),
            "components": int(raw["components"]),
            "iterations": int(raw["iterations"]),
            "signature": int(raw["signature"]),
        }

        for field in COUNT_FIELDS + TIME_FIELDS:
            row[field] = int(raw[field])

        rows.append(row)

    return lines, rows


def audit(lines, rows):
    if not any(line.startswith("native_version,3.13.1-CAPI-") for line in lines):
        raise RuntimeError("missing pinned GEOS 3.13.1 version")
    if "preflight,native,87,174,PASS" not in lines:
        raise RuntimeError("missing native semantic preflight")
    if not any(line.startswith("checksum,") for line in lines):
        raise RuntimeError("missing checksum")
    if len(rows) != 174:
        raise RuntimeError(f"expected 174 probe rows, got {len(rows)}")

    identities = {
        (row["scalar"], row["case"], row["direction"])
        for row in rows
    }
    if len(identities) != 174:
        raise RuntimeError("duplicate probe identities")

    for row in rows:
        iterations = row["iterations"]
        if iterations <= 0:
            raise RuntimeError("invalid iteration count")
        if row["overlay_calls"] != iterations:
            raise RuntimeError(
                f"{row['scalar']}/{row['case']}/{row['direction']}: "
                "robust overlay call count differs from iterations"
            )
        if row["floating_overlay_attempts"] + row["fixed_precision_overlay_calls"] != iterations:
            raise RuntimeError(
                f"{row['scalar']}/{row['case']}/{row['direction']}: "
                "floating/fixed overlay accounting mismatch"
            )
        if (
            row["floating_overlay_successes"] +
            row["floating_overlay_failures"]
            != row["floating_overlay_attempts"]
        ):
            raise RuntimeError(
                f"{row['scalar']}/{row['case']}/{row['direction']}: "
                "floating overlay accounting mismatch"
            )
        if (
            row["orientation_filter_successes"] +
            row["orientation_dd_fallbacks"]
            != row["orientation_calls"]
        ):
            raise RuntimeError(
                f"{row['scalar']}/{row['case']}/{row['direction']}: "
                "orientation accounting mismatch"
            )
        if row["segment_intersections"] > row["segment_intersection_tests"]:
            raise RuntimeError("intersection count exceeds tests")
        if row["proper_intersections"] > row["segment_intersections"]:
            raise RuntimeError("proper intersections exceed intersections")


def normalize(row):
    iterations = row["iterations"]
    result = {
        "scalar": row["scalar"],
        "case": row["case"],
        "direction": row["direction"],
        "edges": row["edges"],
        "components": row["components"],
    }

    for field in COUNT_FIELDS + TIME_FIELDS:
        result[field + "_per_call"] = row[field] / iterations

    orientation_calls = result["orientation_calls_per_call"]
    result["orientation_dd_fraction"] = (
        result["orientation_dd_fallbacks_per_call"] / orientation_calls
        if orientation_calls else 0.0
    )

    attempts = result["floating_overlay_attempts_per_call"]
    result["floating_success_fraction"] = (
        result["floating_overlay_successes_per_call"] / attempts
        if attempts else 0.0
    )

    input_segments = result["polygon_segments_input_per_call"]
    result["polygon_clip_retention"] = (
        result["polygon_segments_after_clip_per_call"] / input_segments
        if input_segments else 0.0
    )

    stage_total = sum(result[field + "_per_call"] for field in TIME_FIELDS)
    result["instrumented_stage_total_ns_per_call"] = stage_total
    for field in TIME_FIELDS:
        key = field + "_per_call"
        result[field.replace("_ns", "") + "_stage_fraction"] = (
            result[key] / stage_total if stage_total else 0.0
        )

    return result


def aggregate(rows):
    if not rows:
        return None

    numeric = [
        key for key, value in rows[0].items()
        if isinstance(value, (int, float))
        and key not in {"direction", "edges", "components"}
    ]

    result = {
        "rows": len(rows),
        "edges": sorted({row["edges"] for row in rows}),
        "components": sorted({row["components"] for row in rows}),
    }

    for key in numeric:
        result[key] = fmean(row[key] for row in rows)

    return result


def family(case):
    if case.startswith("sparse-"):
        return "sparse"
    if case.startswith("dense-"):
        return "dense"
    return case


def summary(rows):
    normalized = [normalize(row) for row in rows]

    by_fixture = {}
    for row in normalized:
        key = f"{row['scalar']}/{row['case']}"
        by_fixture.setdefault(key, []).append(row)

    fixture_summary = {
        key: aggregate(value)
        for key, value in sorted(by_fixture.items())
    }

    by_case = {}
    by_family = {}
    by_scalar = {}

    for row in normalized:
        by_case.setdefault(row["case"], []).append(row)
        by_family.setdefault(family(row["case"]), []).append(row)
        by_scalar.setdefault(row["scalar"], []).append(row)

    total_orientation = sum(row["orientation_calls"] for row in rows)
    total_dd = sum(row["orientation_dd_fallbacks"] for row in rows)
    total_float_attempts = sum(row["floating_overlay_attempts"] for row in rows)
    total_float_success = sum(row["floating_overlay_successes"] for row in rows)

    return {
        "status": "passed",
        "rows": len(rows),
        "directed_fixtures": len(rows),
        "undirected_fixtures": len(rows) // 2,
        "overall": {
            "floating_success_fraction": (
                total_float_success / total_float_attempts
                if total_float_attempts else 0.0
            ),
            "orientation_dd_fraction": (
                total_dd / total_orientation
                if total_orientation else 0.0
            ),
            "orientation_calls": total_orientation,
            "orientation_dd_fallbacks": total_dd,
        },
        "representative": {
            case: aggregate(by_case.get(case, []))
            for case in REPRESENTATIVE_CASES
            if case in by_case
        },
        "families": {
            key: aggregate(value)
            for key, value in sorted(by_family.items())
        },
        "scalars": {
            key: aggregate(value)
            for key, value in sorted(by_scalar.items())
        },
        "fixtures": fixture_summary,
    }


def pct(value):
    return f"{100.0 * value:.3f}%"


def us(value):
    return f"{value / 1000.0:.3f}"


def markdown(report):
    lines = [
        "# GEOS 3.13.1 work-attribution summary",
        "",
        "Research-only mechanism evidence. Instrumentation changes execution cost;",
        "the existing uninstrumented native runner remains the wall-clock reference.",
        "",
        f"- directed fixtures: {report['directed_fixtures']}",
        f"- floating overlay success: {pct(report['overall']['floating_success_fraction'])}",
        f"- orientation DD fallback share: {pct(report['overall']['orientation_dd_fraction'])}",
        "",
        "## Representative cases",
        "",
        "| Case | DD orientation | Orientations/call | DD intersections/call | Segment tests/call | Polygon segments in -> after clip | Point-in-area/call | Clip env us | Noding us | Graph us | Label us | Extract us |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]

    for case, row in report["representative"].items():
        lines.append(
            "| "
            + " | ".join([
                case,
                pct(row["orientation_dd_fraction"]),
                f"{row['orientation_calls_per_call']:.2f}",
                f"{row['dd_intersection_constructions_per_call']:.2f}",
                f"{row['segment_intersection_tests_per_call']:.2f}",
                (
                    f"{row['polygon_segments_input_per_call']:.2f}"
                    f" -> {row['polygon_segments_after_clip_per_call']:.2f}"
                ),
                f"{row['point_in_area_calls_per_call']:.2f}",
                us(row["clip_envelope_ns_per_call"]),
                us(row["noding_ns_per_call"]),
                us(row["graph_build_ns_per_call"]),
                us(row["labelling_ns_per_call"]),
                us(row["extraction_ns_per_call"]),
            ])
            + " |"
        )

    lines += [
        "",
        "Stage timings are internal instrumented timings, not comparable to the",
        "uninstrumented GEOS or geo-d wall-clock medians.",
        "",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("probe_stdout", type=Path)
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    args = parser.parse_args()

    lines, rows = load_rows(args.probe_stdout)
    audit(lines, rows)
    report = summary(rows)

    args.json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    args.markdown.write_text(markdown(report) + "\n")
    print(json.dumps({
        "status": "passed",
        "rows": report["rows"],
        "floating_success_fraction": report["overall"]["floating_success_fraction"],
        "orientation_dd_fraction": report["overall"]["orientation_dd_fraction"],
    }, indent=2))


if __name__ == "__main__":
    main()
