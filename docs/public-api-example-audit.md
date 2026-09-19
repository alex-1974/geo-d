# Public API Example Audit

**Status:** Batch 2 complete; audit in progress
**Baseline:** DDox output generated from commit `4b3b246`  
**Public DDox symbol pages:** 92

## Purpose

This audit records which public `geo-d` declarations should have their own
documented executable example and which declarations are deliberately covered
by a type- or API-family example.

The goal is systematic user-facing example coverage without creating
mechanical duplicate examples for trivial accessors, operators, enum values,
or tightly related members.

The audit does not change the frozen v1 public API.

## Classification

Each public DDox symbol page is assigned one of three states:

- **existing** — a documented `unittest` already renders as an `Example`;
- **add** — the declaration should receive its own documented executable
  example;
- **family** — a separate example would add little value and the declaration
  should be demonstrated by the named owning type or companion operation.

Examples should use `import geo;` where practical and remain focused on
ordinary public usage rather than exhaustive regression testing.

## Baseline summary

| Classification | Count |
| --- | ---: |
| Existing rendered examples | 7 |
| Dedicated examples to add | 31 |
| Deliberately family-covered declarations | 54 |
| **Total public symbol pages** | **92** |

The seven existing rendered examples are:

- `polygonArea`;
- `tryConvert`;
- `trySegmentIntersectionPoint`;
- `distance`;
- `orientation`;
- `tryClassifyPointInPolygon`;
- `trySimplifyDouglasPeuckerInto`.

## Current progress

Batches 1 and 2 add documented executable examples for the core value types,
non-owning geometry views, scalar policies, and explicit quantisation
operations.

Current validated DDox state:

| Classification | Count |
| --- | ---: |
| Existing rendered examples | 21 |
| Dedicated examples still to add | 17 |
| Deliberately family-covered declarations | 54 |
| **Total public symbol pages** | **92** |

The six Batch 1 examples are:

- `Point2`;
- `Vector2`;
- `Segment2`;
- `PolylineView`;
- `LinearRingView`;
- `PolygonView`.

The eight Batch 2 examples are:

- `isGeoScalar`;
- `AreaScalar`;
- `MetricScalar`;
- `IntersectionScalar`;
- `rounded`;
- `floored`;
- `ceiled`;
- `truncated`.

All fourteen audit-added examples compile through the supported public package
surface with `import geo;` and render as `Example` sections in DDox.

## `geo.area`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `AreaScalar` | **existing** | Batch 2 rendered Example |
| `polygonArea` | **existing** | existing rendered Example |
| `signedArea` | **add** | dedicated operation example |

## `geo.bounding_box`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `tryBounds` | **add** | dedicated geometry-bounds example |

## `geo.bounds`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `Bounds2` | **add** | owning family example |
| `Bounds2.empty` | **family** | Bounds2 |
| `Bounds2.min` | **family** | Bounds2 |
| `Bounds2.max` | **family** | Bounds2 |
| `Bounds2.tryFromMinMax` | **add** | dedicated failure/constructor example |
| `Bounds2.tryFromPoint` | **family** | Bounds2 |
| `Bounds2.tryExtend` | **add** | dedicated transactional extension example |
| `Bounds2.extend` | **family** | Bounds2 / Bounds2.tryExtend |
| `Bounds2.contains` | **add** | dedicated relationship example |
| `Bounds2.intersects` | **add** | dedicated relationship example |
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
| `segmentIntersectionKind` | **add** | dedicated classification example |
| `trySegmentIntersectionPoint` | **existing** | existing rendered Example |
| `trySegmentIntersectionOverlap` | **add** | dedicated overlap-construction example |

## `geo.linear_ring_view`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `LinearRingView` | **existing** | Batch 1 rendered Example |
| `LinearRingView.this` | **family** | LinearRingView |
| `LinearRingView.length` | **family** | LinearRingView |
| `LinearRingView.empty` | **family** | LinearRingView |
| `LinearRingView.segmentCount` | **family** | LinearRingView |
| `LinearRingView.segment` | **family** | LinearRingView |
| `LinearRingView.opIndex` | **family** | LinearRingView |

## `geo.metric`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `MetricScalar` | **existing** | Batch 2 rendered Example |
| `distance` | **existing** | existing rendered Example |
| `squaredDistance` | **add** | dedicated metric example |
| `segmentLength` | **add** | dedicated metric example |
| `polylineLength` | **add** | dedicated aggregate metric example |
| `tryNearestPoint` | **add** | dedicated construction example |
| `tryPointSegmentDistance` | **add** | dedicated metric/failure example |

## `geo.orientation`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `Orientation` | **family** | orientation |
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
| `PolygonView` | **existing** | Batch 1 rendered Example |
| `PolygonView.this` | **family** | PolygonView |
| `PolygonView.length` | **family** | PolygonView |
| `PolygonView.empty` | **family** | PolygonView |
| `PolygonView.opIndex` | **family** | PolygonView |
| `PolygonView.exterior` | **family** | PolygonView |
| `PolygonView.holeCount` | **family** | PolygonView |
| `PolygonView.hole` | **family** | PolygonView |

## `geo.polyline_view`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `PolylineView` | **existing** | Batch 1 rendered Example |
| `PolylineView.this` | **family** | PolylineView |
| `PolylineView.length` | **family** | PolylineView |
| `PolylineView.empty` | **family** | PolylineView |
| `PolylineView.segmentCount` | **family** | PolylineView |
| `PolylineView.segment` | **family** | PolylineView |
| `PolylineView.opIndex` | **family** | PolylineView |

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
| `douglasPeuckerWorkspaceSize` | **add** | dedicated workspace-sizing example |
| `trySimplifyDouglasPeuckerInto` | **existing** | existing rendered Example |

## `geo.topology_validation`

| Public declaration | Classification | Coverage |
| --- | --- | --- |
| `RingValidationIssue` | **family** | validateRing |
| `RingValidationResult` | **family** | validateRing |
| `RingValidationResult.valid` | **family** | validateRing |
| `validateRing` | **add** | dedicated validation example |
| `PolygonValidationIssue` | **family** | validatePolygon |
| `PolygonValidationResult` | **family** | validatePolygon |
| `PolygonValidationResult.valid` | **family** | validatePolygon |
| `validatePolygon` | **add** | dedicated validation example |

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

## Implementation order

The example work should proceed in small reviewable groups:

1. core value types and views;
2. scalar policy and conversion;
3. bounds and metric operations;
4. orientation and intersection;
5. area and point-in-polygon;
6. topology validation;
7. simplification and workspace sizing.

After each group:

- run DMD and LDC unittests;
- build the external consumer;
- build DDox documentation;
- verify that every intended new `Example` section is actually rendered.

## Completion criteria

The audit is complete when:

- every one of the 92 current public DDox symbol pages remains classified;
- all declarations marked **add** have a documented executable example;
- all declarations marked **existing** remain rendered;
- family-covered declarations are exercised by the declared family example;
- examples compile through the public package surface where practical;
- DDox rendering is checked automatically or by an equivalent reproducible
  verification step.

Adding a public symbol in a future compatible release should require updating
this inventory as part of its documentation review.
