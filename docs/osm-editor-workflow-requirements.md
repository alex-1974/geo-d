# OSM editor workflow requirements for geo-d

## Status

Research note for GitHub issue #23.

Date: 2026-09-26

Repository baseline:

~~~text
38d4af82d907ae9e6a36b0c5129b72533ab307d2
~~~

Branch:

~~~text
research/osm-editor-workflows
~~~

This document derives possible `geo-d` requirements from concrete editing and
validation workflows in established OpenStreetMap editors.

It is a requirements and gap-analysis document.

It does **not** authorize new public API or implementation.

Any candidate identified here must still pass the normal `geo-d` gate:

~~~text
consumer evidence / research
            |
            v
      geo-d scope check
            |
            v
 semantic + numerical design
            |
            v
 compatibility analysis
            |
            v
 ADR where architecturally relevant
            |
            v
 implementation + verification
~~~

API symmetry with `geo3-d` is not sufficient justification.

## Scope boundary

`geo-d` owns reusable coordinate-system-agnostic Euclidean 2D geometry.

The editor or surrounding workspace owns concerns such as:

- OSM object identity;
- OSM node/way/relation semantics;
- tag interpretation;
- layer, bridge, tunnel, level and routing semantics;
- CRS selection;
- map projection;
- geodesic distance;
- spatial indexing and broad-phase candidate discovery;
- screen-space hit testing;
- snapping thresholds expressed in pixels;
- GUI interaction state;
- undo/redo;
- persistence and network/API operations.

A consumer may project geographic coordinates into an appropriate local
Euclidean coordinate space before invoking `geo-d`.

This separation is not hypothetical. JOSM performs ordinary point/segment and
line geometry using its projected `EastNorth` representation and treats
projection/geographic conversion separately.

## Evidence sources

The workflow inventory was checked against concrete user-visible editor
operations and implementation sources.

The evidence below is pinned where practical so that this research does not
depend only on a moving documentation page or repository branch.

Research observation date:

~~~text
2026-09-26
~~~

### JOSM

User-visible JOSM documentation establishes the following workflows:

- `Move Node onto Way` moves a selected node to the nearest way segment and
  includes it in the way:
  <https://josm.openstreetmap.de/wiki/Help/Action/MoveNodeWay>
- `Join Node to Way` inserts a selected node into the nearest way segment while
  retaining the node position:
  <https://josm.openstreetmap.de/wiki/Help/Action/JoinNodeWay>
- the Tools menu documents align-in-line, distribute, orthogonalize, mirror,
  circle creation, join-node-to-way, move-node-onto-way and join-overlapping-
  areas operations:
  <https://josm.openstreetmap.de/wiki/Help/Menu/Tools>
- current shortcut documentation additionally exposes intersection-node
  creation, simplify-way, parallel-line, rotation and scaling workflows:
  <https://josm.openstreetmap.de/wiki/Shortcuts>
- `Orthogonalize Shape` moves nodes so angles become 90 or 180 degrees:
  <https://josm.openstreetmap.de/wiki/Help/Action/OrthogonalizeShape>
- `Join overlapping Areas` merges overlapping areas and forms a larger target
  area with their common outline:
  <https://josm.openstreetmap.de/wiki/Help/Action/JoinAreas>

JOSM's geometry API independently demonstrates the reusable Euclidean
operations underlying several of these workflows.

The current generated `Geometry` API documentation includes, among other
operations:

- closest point on a bounded segment;
- closest point on an unbounded line;
- line intersection;
- clockwise-angle classification;
- parallel-segment testing.

Source:

<https://josm.openstreetmap.de/doc/org/openstreetmap/josm/tools/Geometry.html>

These operations use JOSM's projected `EastNorth` coordinate representation.

For orthogonalization, JOSM's source explicitly converts nodes to `EastNorth`,
performs angle/vector/rotation calculations in that representation, and only
then converts/moves the resulting OSM nodes.

The inspected `OrthogonalizeAction.java` file reports its last file-changing
SVN revision as:

~~~text
19115
~~~

Source:

<https://josm.openstreetmap.de/browser/trunk/src/org/openstreetmap/josm/actions/OrthogonalizeAction.java>

Recent parallel-way work is independently visible in JOSM changeset 19624
from 2026-09-16:

<https://josm.openstreetmap.de/changeset/19624/josm/trunk/src>

This separation is important for `geo-d`: the projected planar calculation is
a reusable Euclidean concern; projection choice and geographic conversion are
not.

### iD

The iD repository was inspected at commit:

~~~text
d9879e101917f8f2d768c24934f5c510bf5377ba
~~~

Commit:

<https://github.com/openstreetmap/iD/commit/d9879e101917f8f2d768c24934f5c510bf5377ba>

Relevant pinned implementation paths include:

- `modules/geo/geom.ts`:
  <https://github.com/openstreetmap/iD/blob/d9879e101917f8f2d768c24934f5c510bf5377ba/modules/geo/geom.ts>
- `modules/actions/orthogonalize.ts`:
  <https://github.com/openstreetmap/iD/blob/d9879e101917f8f2d768c24934f5c510bf5377ba/modules/actions/orthogonalize.ts>
- `modules/actions/circularize.ts`:
  <https://github.com/openstreetmap/iD/blob/d9879e101917f8f2d768c24934f5c510bf5377ba/modules/actions/circularize.ts>
- `modules/validations/crossing_ways.ts`:
  <https://github.com/openstreetmap/iD/blob/d9879e101917f8f2d768c24934f5c510bf5377ba/modules/validations/crossing_ways.ts>
- `modules/actions/add_midpoint.ts`:
  <https://github.com/openstreetmap/iD/blob/d9879e101917f8f2d768c24934f5c510bf5377ba/modules/actions/add_midpoint.ts>
- `modules/modes/drag_node.js`:
  <https://github.com/openstreetmap/iD/blob/d9879e101917f8f2d768c24934f5c510bf5377ba/modules/modes/drag_node.js>

Of particular relevance, `geoChooseEdge` in `modules/geo/geom.ts`:

1. projects way nodes into Euclidean coordinates;
2. scans every segment;
3. computes the closest point on each segment;
4. selects the minimum-distance segment;
5. returns the selected edge index, closest location and distance.

The same module contains path/path and self-intersection loops built from
segment-pair intersection tests.

The current iD orthogonalization implementation also demonstrates that the
full editor operation is substantially more than one low-level geometry
primitive: it classifies near-straight sections, iteratively moves vertices,
scores candidate geometry and applies OSM graph/node policy.

The circularization implementation similarly combines planar geometry with
editor-specific policy, including key-node preservation and vertex-count /
segment-length decisions.

These sources therefore provide evidence for reusable primitive and aggregate
geometry needs without making the complete editor action itself a `geo-d`
feature requirement.

## Current geo-d capability baseline

The current package-level API already contains the following relevant
primitives.

### Point, vector and affine algebra

- `Point2`;
- `Vector2`;
- ordinary affine point/vector operations;
- `dot`;
- `squaredNorm`;
- `norm`;
- `tryNormalize`;
- `trySignedAngle`;
- `perpendicularCCW`.

### Bounded segment operations

- `Segment2`;
- `distance`;
- `squaredDistance`;
- `segmentLength`;
- `tryNearestPoint`;
- `tryPointSegmentDistance`.

### Unbounded line operations

- `Line2`;
- `tryNearestPoint(Line2, ...)`;
- `LineIntersectionKind`;
- `lineIntersectionKind`;
- `tryLineIntersectionPoint`.

`Line2` supports both point/point and point/direction construction.

Degeneracy is exact and no global epsilon is used.

### Segment intersection

- `SegmentIntersectionKind`;
- `segmentIntersectionKind`;
- `trySegmentIntersectionPoint`;
- `trySegmentIntersectionOverlap`.

Classification and coordinate construction remain separate.

### Area and polygon primitives

- `signedArea`;
- `polygonArea`;
- `tryClassifyPointInPolygon`;
- `validateRing`;
- `validatePolygon`.

### Simplification

- `douglasPeuckerWorkspaceSize`;
- `trySimplifyDouglasPeuckerInto`.

The current simplifier deliberately makes no topology-preservation claim.

## Workflow capability matrix

| Editor workflow | Reusable Euclidean operation | Current `geo-d` coverage | Gap | Scope | Disposition |
|---|---|---|---|---|---|
| Move node onto known way segment | Closest point on bounded segment | `tryNearestPoint(Segment2, point, ...)` | None | `geo-d` primitive | Already covered |
| Point-to-way snapping | Select nearest segment and closest point | Fully expressible from `Polyline2View` + segment metric API | No primitive gap; recurring aggregate scan only | Aggregate may fit `geo-d`; candidate discovery outside | Consumer-backed aggregate candidate |
| Join node to way | Nearest segment then insert existing point | Projection primitives exist | OSM insertion semantics | Insertion outside `geo-d` | Already covered geometrically |
| Improve Way Accuracy | Nearest node/segment to pointer | Segment primitives exist | Screen-space discovery | GUI/spatial layer | Deliberately out of scope |
| Align nodes into straight line | Unbounded line plus point projection | `Line2` + `tryNearestPoint` | None | `geo-d` | Already covered |
| Distribute nodes along line | Affine interpolation | Point/vector algebra | No proven dedicated primitive gap | `geo-d` composition | Already covered by composition |
| Add node at crossing | Segment intersection plus construction | Intersection API | OSM iteration/insertion | Mixed | Already covered geometrically |
| Detect crossing ways | Segment-pair intersection | Intersection API | Broad phase and OSM legitimacy | Mixed | Already covered geometrically |
| Detect self-crossing open way | Non-adjacent segment intersections | Primitive available | No aggregate polyline helper | Possible `geo-d` | Useful but currently unproven |
| Ring self-intersection | Ring topology validation | `validateRing` | None | `geo-d` | Already covered |
| Polygon topology validation | Ring relationships and containment | `validatePolygon` | OSM semantic checks | Mixed | Already covered geometrically |
| Parallel-way editing | Perpendicular direction, offsets, line intersections | A1/A2 primitives | No proven dedicated offset abstraction | `geo-d` composition | Already covered by composition |
| Extrude segment | Parallel/perpendicular construction | A1/A2 primitives | OSM topology mutation | Mixed | Already covered geometrically |
| Angle/direction constraints | Vector angle and orientation | A1 vector family | UI policy | GUI layer | Already covered geometrically |
| Orthogonalize building/way | Angle tests plus iterative relocation | Low-level primitives exist | Complete relocation algorithm | Generic ownership uncertain | Useful but currently unproven |
| Rotate selection | Rotation around pivot | Composable arithmetic | No transform abstraction | Generic need unproven | Useful but currently unproven |
| Scale/reflect selection | Affine transformation | Composable arithmetic | No transform abstraction | Generic need unproven | Useful but currently unproven |
| Circularize area | Centroid/radius/hull redistribution | Partial primitives | No circle/circularization family | Semantics editor-dependent | Useful but currently unproven |
| Determine ring winding | Sign of signed area | `signedArea` | None | `geo-d` | Already covered |
| Simplify way | Douglas-Peucker | Existing simplifier | OSM required-node policy | Mixed | Already covered geometrically |
| Join overlapping areas | Polygon union and result-boundary reconstruction | Not present | Polygon union construction | Plausible `geo-d` scope | Consumer-backed candidate |
| Repair crossing/overlap errors | Detection plus graph mutation | Detection partly covered | Repair policy | OSM/editor layer | Deliberately out of scope |

## Finding 1 — bounded point-to-segment snapping is already solved

The basic geometry needed to move a point onto a known way segment is already
present.

Given:

~~~text
Segment2!T segment
Point2!T point
~~~

the consumer can use:

~~~d
tryNearestPoint(segment, point, result)
~~~

and obtain the clamped nearest point on the segment.

The editor remains responsible for:

- deciding which ways are candidates;
- converting screen coordinates;
- applying pixel thresholds;
- choosing whether endpoint snapping is allowed;
- modifying the OSM graph.

No new primitive is justified for this case.

## Finding 2 — nearest segment on a polyline is a real aggregate gap

Both JOSM and iD contain logic that scans the segments of a known way and
selects the segment nearest to a point.

iD's `geoChooseEdge` makes the required result especially explicit:

~~~text
segment / edge index
nearest point
distance
~~~

The current `geo-d` API can implement this externally by iterating the segments
and calling the existing bounded-segment metric operations.

However, the operation is:

- reusable outside OSM;
- coordinate-system-agnostic;
- naturally defined over `Polyline2View`;
- independently useful once spatial candidate discovery has selected a
  particular polyline;
- already duplicated in established editor geometry code.

The consumer requirement is real, but the external-consumer probe below shows
that no new mathematical primitive is missing. The existing public API already
expresses the complete O(n) operation.

The remaining possible addition is therefore specifically a
**consumer-backed aggregate/convenience candidate**, not a new geometry
primitive and not yet an approved API.

### External consumer composition probe

A standalone consumer was built outside `geo-d` using only:

~~~d
import geo;
~~~

and the current public package surface.

The probe implemented an iD-style nearest-segment scan over
`Polyline2View` using:

- `Polyline2View.segmentCount`;
- `Polyline2View.segment(index)`;
- `tryPointSegmentDistance`;
- `tryNearestPoint`;
- `MetricScalar`.

No package-private or internal `geo-d` declaration was used.

The consumer implemented the following provisional policy locally:

- empty or singleton polyline -> failure because no segment exists;
- degenerate segments participate normally;
- first minimum wins equal-distance ties;
- failure of any segment metric aborts the aggregate operation;
- nearest-point construction is performed only for the selected segment;
- integral input coordinates use the existing `MetricScalar` result policy.

The probe covered:

- an ordinary interior projection on the first segment;
- selection of a later segment;
- an equal-distance tie;
- a degenerate segment;
- empty and singleton polylines;
- a non-finite coordinate failure;
- integral storage producing binary64 metric coordinates and distance.

It compiled and ran successfully with both local default compiler families:

~~~text
DMD: PASS
LDC: PASS
~~~

Observed conclusion:

~~~text
The current public geo-d API is sufficient to express the complete
O(n) nearest-segment / nearest-point composition externally.
~~~

This changes the nature of the gap.

There is no demonstrated need for:

- another segment projection primitive;
- another distance primitive;
- internal access to polyline backing storage;
- spatial-index functionality in `geo-d`.

A possible future public addition would instead package recurring aggregate
iteration and its semantic policy.

### Questions requiring a separate design step

A future design investigation must resolve at least:

1. result shape:
   - nearest point only;
   - nearest point plus distance;
   - segment index;
   - segment parameter;
   - explicit result aggregate;
2. deterministic tie-breaking;
3. degenerate segments;
4. empty and singleton polylines;
5. non-finite input policy;
6. computation and output scalar policy;
7. whether distance should be returned or independently computed;
8. O(n) complexity for an already selected polyline;
9. allocation behaviour;
10. UFCS and overload-family relationship with existing `tryNearestPoint`.

No API spelling is proposed by this research note.

## Finding 3 — unbounded-line projection and intersection are already solved

Editor operations such as:

- align nodes in line;
- constrain movement to a direction;
- parallel/extrude helper geometry;
- construction from extended edges;

require unbounded-line semantics.

A2 already supplies:

~~~text
Line2
tryNearestPoint(Line2, ...)
lineIntersectionKind
tryLineIntersectionPoint
~~~

These workflows do not justify another line representation.

## Finding 4 — angle and direction primitives are already sufficient

The A1 vector family supplies the main reusable low-level operations required
by editor angle logic:

~~~text
dot
squaredNorm
norm
tryNormalize
trySignedAngle
perpendicularCCW
~~~

Together with `orientation`, this covers the reusable mathematical layer for:

- angle snapping;
- clockwise/counter-clockwise decisions;
- orthogonality tests;
- perpendicular directions;
- parallel constructions;
- rotation-direction decisions.

Editor policy such as permitted snap increments or UI thresholds remains a
consumer concern.

## Finding 5 — full orthogonalization is not yet a geo-d requirement

Both JOSM and iD expose building/way orthogonalization.

The complete operation is not merely an angle primitive.

For example, iD's implementation:

- simplifies near-straight sections;
- iteratively moves vertices;
- scores candidate geometry;
- preserves or removes certain OSM nodes according to graph semantics;
- uses editor-specific thresholds and transition behaviour.

The reusable low-level vector operations already exist in `geo-d`.

There is currently insufficient evidence that the entire editor
orthogonalization algorithm should become one generic public geometry
operation.

Disposition:

~~~text
useful but currently unproven
~~~

## Finding 6 — circularization is real but semantically editor-specific

JOSM and iD both contain circularization tools.

iD's implementation uses a combination of:

- projected coordinates;
- polygon centroid;
- median radius;
- polygon winding;
- convex hull;
- key OSM nodes;
- interpolation;
- minimum/maximum vertex policy;
- editor-specific segment-length thresholds.

This establishes a real editing workflow but does **not** yet establish a
stable generic `geo-d` circle/circularization contract.

Questions include:

- whether `geo-d` needs a `Circle2` value at all;
- circumcircle versus fitted or median-radius circle;
- preservation of selected/key vertices;
- output vertex count;
- arc discretisation;
- error metric;
- degeneracy;
- ownership and allocation.

Disposition:

~~~text
useful but currently unproven
~~~

## Finding 7 — polygon union is a strong missing capability

Joining overlapping areas requires construction of the geometric union of the
selected areas.

JOSM explicitly describes this workflow as merging overlapping areas into a
larger target area with their common outline. It also documents a multipolygon
result when an area is surrounded by another selected area without boundary
intersection.

The directly evidenced generic geometric requirement is therefore **polygon
union** plus reconstruction of its resulting boundaries and holes.

Current `geo-d` has:

- ring and polygon representations;
- robust segment intersection;
- point-in-polygon classification;
- ring/polygon topology validation;
- area;

but no operation that constructs the union of polygons.

Unlike OSM tag merging and relation updates, Boolean polygon geometry is:

- coordinate-system-agnostic;
- reusable outside OSM;
- a genuine Euclidean 2D geometry problem;
- directly evidenced by an editor workflow.

Therefore polygon union is a **consumer-backed candidate**.

The broader Boolean-overlay family is related but is **not** established as
consumer-backed by this workflow alone. Intersection, difference and symmetric
difference remain research candidates until separate consumer evidence or a
strong architectural reason establishes them.

Polygon union itself is not ready for implementation.

### Required research before any API design

At least the following must be investigated for polygon union:

1. result multiplicity:
   - empty result where applicable to the chosen contract;
   - one polygon;
   - multiple disconnected polygon components;
2. hole semantics and nested boundaries;
3. point contacts;
4. shared edges and partially overlapping collinear edges;
5. degenerate input and output;
6. validation preconditions;
7. exact topology versus constructed-coordinate rounding;
8. scalar-domain policy;
9. output ownership and allocation;
10. caller-provided destination/workspace feasibility;
11. complexity and performance;
12. deterministic component and ring ordering;
13. canonicalization policy, if any;
14. relationship to `Polygon2View`;
15. whether this remains appropriately scoped directly in `geo-d`.

A separate research/design issue is required before public API design.

A broader Boolean-overlay investigation may additionally study:

- intersection;
- difference;
- symmetric difference;
- whether one robust arrangement/overlay core should support several
  operations internally.

Those additional public operations are not promoted to consumer-backed status
by Issue #23.

## Finding 8 — validation separates geometry from OSM semantics

OSM editor validation demonstrates two distinct layers.

### Generic geometry

Examples include:

- segment crossings;
- overlaps;
- self-intersections;
- point/segment proximity;
- ring validity;
- polygon validity.

These are either already covered or composable from current `geo-d`
primitives.

### OSM semantics

Examples include:

- whether crossing ways should connect;
- bridge/tunnel interpretation;
- layer and level;
- road/waterway/railway classes;
- shared tagged nodes;
- relation membership;
- whether an automatically generated repair is appropriate.

These do not belong in `geo-d`.

## Finding 9 — spatial candidate discovery remains outside geo-d

A geometry primitive answers questions such as:

~~~text
What is the nearest point on this segment?
Do these two segments intersect?
~~~

An editor also needs questions such as:

~~~text
Which of millions of segments near the cursor should be tested?
~~~

The latter is a spatial-index/query problem.

It belongs in the consumer or a future `spatial-d`, not in `geo-d`.

A possible nearest-polyline aggregate would operate only after the caller has
already selected the candidate polyline.

## Candidate summary

### Already covered

- point-to-point distance;
- point-to-segment nearest point;
- point-to-segment distance;
- point-to-line projection;
- segment intersection classification;
- segment unique-point construction;
- segment overlap construction;
- unbounded-line intersection;
- vector norm/dot/normalization;
- signed vector angle;
- perpendicular direction;
- orientation;
- signed ring area;
- polygon area;
- point-in-polygon;
- ring validation;
- polygon validation;
- ordinary polyline Douglas-Peucker simplification.

### Deliberately outside geo-d

- screen-space hit testing;
- pixel snap thresholds;
- CRS/projection;
- geodesic measurement;
- spatial indexing/candidate discovery;
- OSM object mutation;
- OSM tag/relation semantics;
- bridge/tunnel/layer/level interpretation;
- editor repair policy;
- UI interaction state.

### Useful but currently unproven

- aggregate open-polyline self-intersection helpers;
- generic transform abstraction;
- full orthogonalization;
- circle/circularization family;
- topology-preserving editing/simplification.

### Research candidates

- the broader polygon Boolean-overlay family beyond union:
  - intersection;
  - difference;
  - symmetric difference.

### Consumer-backed candidates

1. nearest point / nearest segment on a known `Polyline2View` as an aggregate
   convenience operation over already-sufficient public primitives;
2. polygon union with robust result-boundary reconstruction as a genuinely
   missing geometry-construction capability.

Neither candidate is authorized for implementation by this document.

The two candidates therefore have materially different status:

~~~text
Polyline nearest:
    consumer-backed aggregate convenience
    no missing mathematical primitive

Polygon union:
    consumer-backed geometric capability
    construction algorithm currently missing
~~~

## Recommended next research gates

### Candidate A — nearest point on Polyline2View

This is the smaller and better-bounded candidate.

The external-consumer probe has already established that the current public
API is sufficient to implement the operation without changes to `geo-d`.

A follow-up design gate is justified only if packaging the repeated O(n)
composition provides enough value to warrant additional public surface.

Research should next determine:

- exact result semantics;
- tie-breaking;
- degenerate and empty behaviour;
- numerical policy;
- overload-family relationship;
- whether a public result aggregate is justified.

The required external consumer prototype has been completed successfully with
both DMD and LDC using only current public primitives.

### Candidate B — polygon union

Polygon union requires a dedicated research phase before API design.

Research should compare robust overlay/arrangement models and algorithms,
including:

- sweep-line and arrangement approaches;
- exact or adaptive predicates;
- intersection-coordinate construction;
- topology reconstruction;
- disconnected components and holes;
- result ownership;
- handling of shared boundaries and degeneracy.

The research may determine that a more general Boolean-overlay core is the
best internal architecture. That would not by itself justify exposing
intersection, difference or symmetric difference as public API.

The problem should not be implemented opportunistically inside an editor.

## Issue #23 acceptance mapping

- [x] real OSM editor workflows inventoried rather than inferred solely from
      generic geometry-library APIs;
- [x] workflows decomposed into reusable Euclidean operations;
- [x] existing `geo-d` coverage mapped explicitly;
- [x] non-`geo-d` concerns assigned to their proper layer;
- [x] missing capabilities classified by evidence strength;
- [x] no implementation or public API addition made.

The research identifies two consumer-backed candidates but intentionally leaves
both behind separate follow-up gates.
