# Public API Example Audit

**Status:** Batches 1 through 7 complete; v2 audit complete
**Baseline:** DDox output generated from v2 main commit `3b99a048882571a4fd562e305dfb58aba86144ad`
**Public DDox symbol pages:** 103

## Purpose

This audit records which public `geo-d` declarations should have their own
documented executable example and which declarations are deliberately covered
by a type- or API-family example.

The goal is systematic user-facing example coverage without creating
mechanical duplicate examples for trivial accessors, operators, enum values,
or tightly related members.

The audit does not change the frozen v2 public API.

## Classification

Each public DDox symbol page is assigned one of three states:

- **existing** — a documented `unittest` already renders as an `Example`;
- **add** — the declaration should receive its own documented executable
  example;
- **family** — a separate example would add little value and the declaration
  should be demonstrated by the named owning type or companion operation.

Examples should use `import geo;` where practical and remain focused on
ordinary public usage rather than exhaustive regression testing.

## v2 documentation-surface summary

The original audit baseline covered the 92 public DDox symbol pages generated
for the v1 API.

The v2 documentation surface contains 103 public symbol pages.

The net increase of eleven pages is accounted for by:

- four canonical v2 type pages while the corresponding deprecated v1 module
  aliases remain documented;
- four root-level deprecated v1 compatibility alias pages; and
- the three public diagnostic fields `issue`, `primaryIndex`, and
  `secondaryIndex` of `RingValidationResult`.

After Batches 1 through 7, the validated v2 DDox state is:

| Classification | Count |
| --- | ---: |
| Existing rendered examples | 38 |
| Dedicated examples still to add | 0 |
| Deliberately family-covered declarations | 65 |
| **Total public symbol pages** | **103** |

The seven examples already present before the systematic audit were:

- `polygonArea`;
- `tryConvert`;
- `trySegmentIntersectionPoint`;
- `distance`;
- `orientation`;
- `tryClassifyPointInPolygon`;
- `trySimplifyDouglasPeuckerInto`.

The six Batch 1 examples are:

- `Point2`;
- `Vector2`;
- `Segment2`;
- `Polyline2View`;
- `LinearRing2View`;
- `Polygon2View`.

The eight Batch 2 examples are:

- `isGeoScalar`;
- `AreaScalar`;
- `MetricScalar`;
- `IntersectionScalar`;
- `rounded`;
- `floored`;
- `ceiled`;
- `truncated`.

The eleven Batch 3 examples are:

- `tryBounds`;
- `Bounds2`;
- `Bounds2.tryFromMinMax`;
- `Bounds2.tryExtend`;
- `Bounds2.contains`;
- `Bounds2.intersects`;
- `squaredDistance`;
- `segmentLength`;
- `polylineLength`;
- `tryNearestPoint`;
- `tryPointSegmentDistance`.

The two Batch 4 examples are:

- `segmentIntersectionKind`;
- `trySegmentIntersectionOverlap`.

The Batch 5 example is:

- `signedArea`.

The two Batch 6 examples are:

- `validateRing`;
- `validatePolygon`.

The Batch 7 example is:

- `douglasPeuckerWorkspaceSize`.

All thirty-one audit-added examples compile through the supported public
package surface with `import geo;` and render as `Example` sections in DDox.

## `geo` package compatibility aliases

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `PolylineView` | **family** | deprecated v1 root alias; Polyline2View |
| `LinearRingView` | **family** | deprecated v1 root alias; LinearRing2View |
| `PolygonView` | **family** | deprecated v1 root alias; Polygon2View |
| `Orientation` | **family** | deprecated v1 root alias; Orientation2 |

## `geo.area`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `AreaScalar` | **existing** | Batch 2 rendered Example |
| `polygonArea` | **existing** | existing rendered Example |
| `signedArea` | **existing** | Batch 5 rendered Example |

## `geo.bounding_box`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `tryBounds` | **existing** | Batch 3 rendered Example |

## `geo.bounds`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `Bounds2` | **existing** | Batch 3 rendered Example |
| `Bounds2.empty` | **family** | Bounds2 |
| `Bounds2.min` | **family** | Bounds2 |
| `Bounds2.max` | **family** | Bounds2 |
| `Bounds2.tryFromMinMax` | **existing** | Batch 3 rendered Example |
| `Bounds2.tryFromPoint` | **family** | Bounds2 |
| `Bounds2.tryExtend` | **existing** | Batch 3 rendered Example |
| `Bounds2.extend` | **family** | Bounds2 / Bounds2.tryExtend |
| `Bounds2.contains` | **existing** | Batch 3 rendered Example |
| `Bounds2.intersects` | **existing** | Batch 3 rendered Example |
| `Bounds2.isFinite` | **family** | Bounds2 |
| `Bounds2.opEquals` | **family** | Bounds2 |

## `geo.convert`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `tryConvert` | **existing** | existing rendered Example |
| `floored` | **existing** | Batch 2 rendered Example |
| `ceiled` | **existing** | Batch 2 rendered Example |
| `rounded` | **existing** | Batch 2 rendered Example |
| `truncated` | **existing** | Batch 2 rendered Example |

## `geo.intersection`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `IntersectionScalar` | **existing** | Batch 2 rendered Example |
| `SegmentIntersectionKind` | **family** | segmentIntersectionKind / construction examples |
| `segmentIntersectionKind` | **existing** | Batch 4 rendered Example |
| `trySegmentIntersectionPoint` | **existing** | existing rendered Example |
| `trySegmentIntersectionOverlap` | **existing** | Batch 4 rendered Example |

## `geo.linear_ring_view`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `LinearRing2View` | **existing** | Batch 1 rendered Example |
| `LinearRingView` | **family** | deprecated v1 module alias; LinearRing2View |
| `LinearRing2View.this` | **family** | LinearRingView |
| `LinearRing2View.length` | **family** | LinearRingView |
| `LinearRing2View.empty` | **family** | LinearRingView |
| `LinearRing2View.segmentCount` | **family** | LinearRingView |
| `LinearRing2View.segment` | **family** | LinearRingView |
| `LinearRing2View.opIndex` | **family** | LinearRingView |

## `geo.metric`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `MetricScalar` | **existing** | Batch 2 rendered Example |
| `distance` | **existing** | existing rendered Example |
| `squaredDistance` | **existing** | Batch 3 rendered Example |
| `segmentLength` | **existing** | Batch 3 rendered Example |
| `polylineLength` | **existing** | Batch 3 rendered Example |
| `tryNearestPoint` | **existing** | Batch 3 rendered Example |
| `tryPointSegmentDistance` | **existing** | Batch 3 rendered Example |

## `geo.orientation`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `Orientation2` | **family** | orientation |
| `Orientation` | **family** | deprecated v1 module alias; Orientation2 |
| `orientation` | **existing** | existing rendered Example |

## `geo.point`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `Point2` | **existing** | Batch 1 rendered Example |
| `Point2.this` | **family** | Point2 |
| `Point2.x` | **family** | Point2 |
| `Point2.y` | **family** | Point2 |
| `Point2.isFinite` | **family** | Point2 |
| `Point2.opBinary` | **family** | Point2 |
| `Point2.opBinaryRight` | **family** | Point2 |
| `Point2.opOpAssign` | **family** | Point2 |

## `geo.point_in_polygon`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `PointPolygonLocation` | **family** | tryClassifyPointInPolygon |
| `tryClassifyPointInPolygon` | **existing** | existing rendered Example |

## `geo.polygon_view`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `Polygon2View` | **existing** | Batch 1 rendered Example |
| `PolygonView` | **family** | deprecated v1 module alias; Polygon2View |
| `Polygon2View.this` | **family** | PolygonView |
| `Polygon2View.length` | **family** | PolygonView |
| `Polygon2View.empty` | **family** | PolygonView |
| `Polygon2View.opIndex` | **family** | PolygonView |
| `Polygon2View.exterior` | **family** | PolygonView |
| `Polygon2View.holeCount` | **family** | PolygonView |
| `Polygon2View.hole` | **family** | PolygonView |

## `geo.polyline_view`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `Polyline2View` | **existing** | Batch 1 rendered Example |
| `PolylineView` | **family** | deprecated v1 module alias; Polyline2View |
| `Polyline2View.this` | **family** | PolylineView |
| `Polyline2View.length` | **family** | PolylineView |
| `Polyline2View.empty` | **family** | PolylineView |
| `Polyline2View.segmentCount` | **family** | PolylineView |
| `Polyline2View.segment` | **family** | PolylineView |
| `Polyline2View.opIndex` | **family** | PolylineView |

## `geo.scalar`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `isGeoScalar` | **existing** | Batch 2 rendered Example |

## `geo.segment`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `Segment2` | **existing** | Batch 1 rendered Example |
| `Segment2.this` | **family** | Segment2 |
| `Segment2.a` | **family** | Segment2 |
| `Segment2.b` | **family** | Segment2 |
| `Segment2.isFinite` | **family** | Segment2 |

## `geo.simplification`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `douglasPeuckerWorkspaceSize` | **existing** | Batch 7 rendered Example |
| `trySimplifyDouglasPeuckerInto` | **existing** | existing rendered Example |

## `geo.topology_validation`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `RingValidationIssue` | **family** | validateRing |
| `RingValidationResult` | **family** | validateRing |
| `RingValidationResult.issue` | **family** | validateRing |
| `RingValidationResult.primaryIndex` | **family** | validateRing |
| `RingValidationResult.secondaryIndex` | **family** | validateRing |
| `RingValidationResult.valid` | **family** | validateRing |
| `validateRing` | **existing** | Batch 6 rendered Example |
| `PolygonValidationIssue` | **family** | validatePolygon |
| `PolygonValidationResult` | **family** | validatePolygon |
| `PolygonValidationResult.valid` | **family** | validatePolygon |
| `validatePolygon` | **existing** | Batch 6 rendered Example |

## `geo.vector`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `Vector2` | **existing** | Batch 1 rendered Example |
| `Vector2.this` | **family** | Vector2 |
| `Vector2.x` | **family** | Vector2 |
| `Vector2.y` | **family** | Vector2 |
| `Vector2.isFinite` | **family** | Vector2 |
| `Vector2.opUnary` | **family** | Vector2 |
| `Vector2.opBinary` | **family** | Vector2 |
| `Vector2.opBinaryRight` | **family** | Vector2 |
| `Vector2.opOpAssign` | **family** | Vector2 |

## Completed implementation batches

The example work was completed in small reviewable groups:

- [x] core value types and views;
- [x] scalar policy and conversion;
- [x] bounds and metric operations;
- [x] orientation and intersection;
- [x] area and point-in-polygon;
- [x] topology validation;
- [x] simplification and workspace sizing.

Each batch is verified through ordinary compilation and generated DDox
documentation.

## Completion criteria

The v2 executable-example audit is complete when:

- all 103 current public DDox symbol pages are classified;
- no declaration remains classified as **add**;
- all 38 declarations classified as **existing** render an `Example`;
- all 65 declarations classified as **family** are intentionally covered by
  their named type or API-family example;
- examples compile through the supported `import geo;` consumer surface where
  practical; and
- generated DDox output is checked automatically against this inventory.

`tools/verify-public-api-examples.py` enforces the inventory against generated
DDox output. It fails when a public symbol page is unclassified, an audited
page disappears, an **existing** page loses its rendered `Example`, a
**family** page unexpectedly gains one without reclassification, or any
**add** entry remains.

Adding a public symbol in a future compatible release therefore requires
updating this inventory as part of its documentation review.
