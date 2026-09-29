# Boolean polygon overlay research

Status: research gate for GitHub issue #49
Branch: `research/boolean-overlay`
Scope: coordinate-system-agnostic Euclidean 2D polygon Boolean overlay beyond
the already public polygon-union operation
Research observation date: 2026-09-28

## 1. Purpose

`geo-d` already exposes robust polygon union under the contract established by
ADR-0023.

ADR-0023 deliberately did not promote the remaining Boolean polygon
operations:

- intersection;
- difference;
- symmetric difference.

Each additional operation requires independent consumer or research evidence
and an explicit design/API decision.

This document is a research artifact.

It does **not** authorize:

- implementation;
- public API expansion;
- a generalized public overlay selector;
- renaming or refactoring of the production union implementation.

## 2. Existing contract baseline

Any future Boolean polygon construction must begin from the already accepted
`geo-d` geometry and numerical contracts.

Relevant established properties include:

- inputs are valid `Polygon2View` geometries;
- topology is decided exactly for supported robust scalar domains;
- supported polygon-union scalar inputs are `int`, `long`, `float`, `double`;
- `real` remains separately deferred;
- no global epsilon is used to guess topology;
- no implicit snap-rounding or quantization is performed;
- exact arrangement topology is fixed before public coordinate materialization;
- materialization is all-or-nothing when rounded coordinates cannot preserve
  required exact topology;
- allocation/resource failure is not a geometric result status;
- multiple disconnected result components and holes are representable;
- result ordering is deterministic.

These rules are the baseline, not an automatic contract for additional
operations.

## 3. Consumer evidence

### 3.1 Existing OSM-editor audit

`docs/osm-editor-workflow-requirements.md` established polygon union as a
directly consumer-backed missing geometry capability through the JOSM
"Join overlapping Areas" workflow.

The same audit explicitly left:

- polygon intersection;
- polygon difference;
- polygon symmetric difference;

as research candidates rather than consumer-backed candidates.

That distinction remains in force for Issue #49.

### 3.2 Polygon splitting is not automatically polygon difference

JOSM exposes a `Split Object` workflow that can split a closed area or
multipolygon along boundary points or an open splitting way.

This establishes a real polygon split-by-line/path workflow.

It does not by itself establish a requirement for:

```text
A \ B
```

where `B` is another polygonal region.

Current disposition:

```text
polygon split workflow
    != demonstrated polygon-difference consumer
```

Evidence:

- <https://josm.openstreetmap.de/wiki/Help/Action/SplitObject>

### 3.3 Multipolygon inner rings are not automatically polygon difference

OSM/JOSM multipolygon workflows assign existing selected ways to `outer` and
`inner` roles. Multiple ways may together form one complete ring.

Adding an inner ring changes the interpretation of existing geometry. It does
not necessarily construct a new boundary equivalent to:

```text
outer \ inner
```

The ordinary multipolygon relation workflow is therefore insufficient consumer
evidence for a generic polygon-difference constructor.

Evidence:

- <https://josm.openstreetmap.de/wiki/Help/Action/CreateMultipolygon>
- <https://josm.openstreetmap.de/wiki/Help/Action/UpdateMultipolygon>

### 3.4 Intersection consumer status

No current evidence establishes an editor workflow whose reusable Euclidean
result specifically requires:

```text
polygon A intersection polygon B
    -> constructed polygon set
```

Overlap detection, crossing validation, containment and intersection predicates
are separate requirements.

Current disposition:

```text
polygon intersection
    research candidate
    consumer-backed construction requirement not yet established
```

### 3.5 Difference consumer status

No current evidence establishes an editor workflow whose reusable Euclidean
requirement specifically requires:

```text
A \ B
```

Current disposition:

```text
polygon difference
    research candidate
    consumer-backed construction requirement not yet established
```

### 3.6 Symmetric-difference consumer status

No concrete editor workflow has yet been identified whose reusable Euclidean
requirement is:

```text
(A \ B) union (B \ A)
```

Current disposition:

```text
polygon symmetric difference
    research candidate
    no concrete consumer evidence currently established
```

## 4. Candidate semantic model

### 4.1 Regularized 2D Boolean sets

CGAL `Boolean_set_operations_2` is the strongest semantic reference identified
so far.

Its polygon Boolean operations use regularized set semantics.

Conceptually:

```text
regularized(P op Q)
    =
closure(interior(P op Q))
```

Regularization removes lower-dimensional remnants such as isolated points and
one-dimensional contacts.

For polygon input this permits a polygon-only result rather than requiring a
heterogeneous collection containing polygons, lines and points.

Primary semantic reference:

- <https://doc.cgal.org/latest/Boolean_set_operations_2/index.html>

### 4.2 JTS / GEOS OverlayNG strict mode

OverlayNG supports:

- intersection;
- union;
- difference;
- symmetric difference.

Strict mode is useful as a secondary reference for homogeneous polygon overlay
because lower-dimensional collapse artifacts are excluded.

Its precision and noding choices are not automatically the `geo-d` numerical
contract.

In particular, snap-rounding or quantization must not silently become default
`geo-d` semantics.

Secondary semantic/architecture reference:

- <https://locationtech.github.io/jts/javadoc/org/locationtech/jts/operation/overlayng/OverlayNG.html>

### 4.3 Research semantic disposition

For the retained Boolean-overlay candidates, the research semantic model is
**regularized two-dimensional polygon-set semantics**.

Conceptually:

```text
regularized(P op Q)
    =
closure(interior(P op Q))
```

Accordingly, lower-dimensional remnants do not become result objects:

- an isolated shared point does not become an intersection result;
- a shared boundary segment alone does not require a line result;
- point and line artifacts removed by regularization are not represented as
  heterogeneous output alongside polygons.

This disposition is supported by several independent observations:

1. CGAL/EPECK regularized Boolean set operations are the primary exact oracle
   used by the research corpus.
2. The complete 16-fixture x 5-operation differential corpus agrees with that
   oracle at the regularized point-set level.
3. Point-contact fixtures explicitly demonstrate zero polygon intersection
   where the operands meet only in lower dimension.
4. The existing geo-d result model naturally represents the regularized
   polygonal result domain: empty output, polygon components and holes.
5. A non-regularized operation would require a materially different,
   heterogeneous result domain containing line and/or point remnants.
6. No current consumer evidence justifies that additional heterogeneous
   result domain for intersection, difference or symmetric difference.

The non-regularized alternative is therefore **rejected for these retained
polygon Boolean candidates**, not silently emulated or encoded inside
`Polygon2View`.

This research decision constrains the semantics of any later design proposal.
It does **not** itself promote intersection, difference or symmetric difference
to production or public API.

## 5. Region truth table

The production union implementation already derives exact two-operand region
membership:

```text
insideA
insideB
```

For regularized two-operand polygon overlay:

| A | B | Union | Intersection | A \ B | B \ A | XOR |
|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0 | 1 | 1 | 0 | 0 | 1 | 1 |
| 1 | 0 | 1 | 0 | 1 | 0 | 1 |
| 1 | 1 | 1 | 1 | 0 | 0 | 0 |

Equivalent predicates:

```text
union                 A || B
intersection          A && B
difference A \ B      A && !B
difference B \ A      B && !A
symmetric difference  A != B
```

This truth table is mathematical evidence only. It does not authorize a
generic production overlay selector.

## 6. Production architecture reuse audit

The production union pipeline appears to contain substantial operation-neutral
machinery before result-boundary selection.

Candidate reusable stages include:

1. polygon validation;
2. source-edge extraction and provenance;
3. P3 envelope-gated candidate discovery;
4. exact segment-contact classification;
5. exact event accumulation and noding;
6. arrangement construction;
7. half-edge embedding;
8. exact A/B side-label propagation;
9. containment seeding;
10. selected-boundary tracing;
11. exact cycle reconstruction;
12. component/hole reconstruction;
13. canonicalization;
14. binary64 materialization;
15. topology-preservation verification;
16. immutable owning storage.

The clearest union-specific decision currently identified is:

```text
exact A/B side membership
    ->
selected oriented result boundary
```

For union the region predicate is:

```text
A || B
```

Research must determine whether changing only this predicate is sufficient for
intersection, difference and symmetric difference.

No production refactor is authorized yet.

### 6.1 Static production-code audit

A direct audit of the production implementation on the Issue #49 baseline
refines the preliminary reuse hypothesis.

| Stage | Current assessment | Reason |
|---|---|---|
| Input validation | reusable semantics, union-specific orchestration | Both operands are validated independently as `Polygon2View`; status spelling remains union-specific. |
| Source-edge extraction/provenance | operation-neutral semantics | Operand A/B provenance is required by every two-operand Boolean operation. |
| P3 candidate discovery | operation-neutral | Envelope rejection and candidate enumeration do not depend on the Boolean result predicate. |
| Exact contact/event accumulation | operation-neutral | Noding must resolve the same exact operand boundaries before any result operation is selected. |
| Atomic-edge construction | operation-neutral | Atomic arrangement spans and A/B provenance precede result membership selection. |
| Half-edge embedding | operation-neutral | Exact angular embedding represents the arrangement, not one Boolean operation. |
| A/B side-label propagation | operation-neutral | The implementation computes exact `insideA` / `insideB` state before applying union semantics. |
| Containment seeding | operation-neutral | Missing operand parity on disconnected arrangement components is a two-operand topology concern. |
| Result-boundary selection | operation-specific | Production currently selects boundaries using the union predicate `A || B`. |
| Boundary continuation/tracing | reusable subject to selector invariant | It consumes selected half-edges already oriented with result interior on the left. |
| Exterior/hole grouping | reusable for regularized polygonal results | Exterior versus hole follows cycle orientation and exact containment after result selection. |
| Canonical ordering | reusable | Ordering is defined over reconstructed result cycles/components, independent of source operand identity. |
| Binary64 boundary materialization | reusable in principle | It materializes only selected exact result vertices/edges and verifies preserved incidence. |
| Materialized component validation | reusable for normalized polygon-set output | It verifies valid components plus absence of new filled-interior overlap/containment. |
| Immutable owning storage | structurally reusable | Storage represents zero or more `Polygon2View!double` components with holes; only naming is union-specific. |
| P1 orchestration/status types | union-specific | Function names, internal status names and selected-boundary call encode polygon union explicitly. |

This classification distinguishes three categories:

```text
operation-neutral semantics
    implementation may retain union-specific names today

operation-specific semantics
    region/result-boundary predicate

public/API semantics
    remain independently gated even if internals are reusable
```

The audit therefore does **not** justify mechanically renaming
`polygon_union_*` modules to generic overlay modules.

A production refactor would require executable evidence that the same
post-selection invariants hold for every retained operation.

### 6.2 Boundary-selector invariant

The downstream boundary tracer assumes that a selected directed half-edge has
result interior on its left and that its twin is not also selected.

For any Boolean region predicate `R(A, B)`, an arrangement edge belongs to the
regularized result boundary exactly when:

```text
R(leftA, leftB) != R(rightA, rightB)
```

The selected orientation is the direction for which:

```text
R(leftA, leftB) == true
```

If the selector is implemented according to those rules, exactly one of the
two half-edge directions is selected for a result boundary.

This is the key invariant that an executable generalized-selector probe must
verify before the existing tracing/component pipeline can be classified as
proven reusable.

### 6.3 Empty-result path

Intersection, difference and symmetric difference introduce an important case
that union does not exercise in the same way:

```text
both inputs non-empty
    ->
zero selected result boundaries
```

Examples include:

```text
disjoint A and B:
    intersection = empty

identical A and B:
    A \ B = empty
    A xor B = empty
```

A static audit of the existing downstream production functions finds that zero
selected cycles/components are structurally supported:

1. boundary tracing can complete with `cycleCount == 0`;
2. exact component construction accepts an empty cycle slice and leaves
   `componentCount == 0`;
3. canonical layout writes the initial component-ring offset `0` and succeeds
   with no cycles/components;
4. boundary materialization computes zero required edges and points;
5. ring writing records offset `0` with zero rings;
6. final component validation accepts:
   - `ringPointOffsets == [0]`;
   - `componentRingOffsets == [0]`;
7. immutable owning storage already represents zero components.

This is strong static evidence that an empty regularized result does not require
a new result representation.

At this static-audit checkpoint, executable proof that a generalized Boolean
selector could drive the complete production pipeline was still pending.
Section 6.5 records the subsequent executable reuse evidence.

### 6.4 Required executable reuse gate

Before any production generalization, a research-only probe should establish
at least:

- one common exact arrangement can be labelled once and evaluated under all
  candidate predicates;
- selected half-edges satisfy the interior-left / twin-unselected invariant;
- the existing boundary tracer succeeds unchanged;
- exterior/hole classification succeeds unchanged;
- canonicalization succeeds unchanged;
- binary64 materialization succeeds unchanged where representable;
- zero-result cases succeed through the complete downstream pipeline;
- union generated through the research selector is bit-for-bit equivalent to
  current production union on the selected corpus.

The research probe may duplicate or wrap internal machinery.

It must not refactor the production implementation merely to make the
experiment convenient.

### 6.5 Executable reuse evidence checkpoint

The static reuse audit is now backed by executable research evidence on the
Issue #49 baseline.

A research-only internal module evaluates five regularized two-operand region
predicates over the same exact A/B side-label model:

```text
union:
    A || B

intersection:
    A && B

A \ B:
    A && !B

B \ A:
    B && !A

symmetric difference:
    A != B
```

The probe does not modify production selectors or downstream production
stages.

#### Exhaustive selector evidence

For every complete left/right A/B membership pair:

- no boundary is selected when result membership is equal on both sides;
- exactly one half-edge direction is selected when result membership differs;
- the selected direction has result interior on its left;
- generalized research union selection is identical to production
  `selectExactUnionBoundaryHalfEdges`.

The selector matrix covers all:

```text
4 left A/B states
x
4 right A/B states
x
5 Boolean predicates
```

#### Point-contact arrangement

Two squares meeting at one exact vertex were evaluated through the same exact
arrangement and complete A/B side labels.

Observed regularized result-cycle counts:

| Operation | Result cycles |
|---|---:|
| union | 2 |
| intersection | 0 |
| A \ B | 1 |
| B \ A | 1 |
| symmetric difference | 2 |

The intersection result therefore confirms that a point-only contact does not
become polygon output.

The selected boundaries were passed unchanged to production
`tryBuildExactUnionBoundaryCycles`.

#### Containment and hole formation

For an outer square A and a strictly contained square B:

| Operation | Result |
|---|---|
| union | A |
| intersection | B |
| A \ B | one component with one B-shaped hole |
| B \ A | empty |
| symmetric difference | one component with one B-shaped hole |

This fixture also exercises containment seeding because the two operand
boundaries are disconnected arrangement components.

After research-only result selection, the following production stages run
unchanged:

1. `tryBuildExactUnionBoundaryCycles`;
2. `tryBuildExactUnionComponents`;
3. `tryBuildCanonicalExactUnionLayout`;
4. `tryMaterializeExactUnionBoundaryGraph`;
5. `tryWriteMaterializedUnionRings`;
6. `materializedUnionComponentsRemainValidAndDisjoint`;
7. `takePolygonUnionOwnedResultInternal`.

The empty `B \ A` case traverses the same downstream path with zero cycles,
zero components, zero materialized points and an empty immutable owning result.

The `A \ B` and symmetric-difference cases demonstrate that the existing
orientation-based component logic recognizes an operation-created reversed
inner boundary as a hole without modification.

#### Compiler evidence

The complete research module passes the ordinary library unittest build on
both workspace baseline compilers:

```text
DMD 2.111.0:
    48 modules passed unittests

LDC 1.41.0
DMD frontend 2.111.0:
    48 modules passed unittests
```

#### Current interpretation

Executable evidence now supports the following narrower statement:

> For the tested point-contact and containment fixtures, the existing
> post-selection polygon-union pipeline is reusable unchanged for regularized
> polygonal union, intersection, difference and symmetric-difference results.

At this executable-reuse checkpoint, this evidence did **not** by itself
establish:

- complete Boolean-overlay semantics;
- coverage of the required degeneracy matrix;
- numerical failure equivalence for all operations;
- oracle agreement over a differential corpus;
- consumer justification for public API promotion;
- justification for renaming or refactoring production `polygon_union_*`
  internals.

Those remaining evidence gaps are addressed by the semantic matrix,
algebraic/invariance checks, numerical/materialization probes and independent
oracle work recorded in the following sections.

Internal reuse remains evidence only and does not authorize implementation
promotion.

## 7. Required semantic matrix

Each retained candidate must be checked independently for:

### Ordinary relationships

- disjoint polygons;
- ordinary overlap;
- containment;
- identical operands;
- first operand empty;
- second operand empty;
- both operands empty.

### Boundary contacts

- shared vertex;
- multiple isolated shared vertices;
- shared complete edge;
- partial collinear overlap;
- adjacent polygons;
- coincident boundaries;
- T-junction-style contacts after noding.

### Holes and components

- polygon intersecting a hole;
- polygon filling a hole;
- polygon entirely inside a hole;
- operation creating a hole;
- operation removing a hole;
- operation splitting one component into several;
- disconnected output components;
- island inside a hole.

### Numerical/materialization cases

- proper rational intersections;
- distinct exact events;
- distinct exact events that collide after binary64 rounding;
- rounded edge collapse;
- new crossing/contact introduced by rounding;
- lost exact topology after materialization.

### 7.1 Coverage after the initial 45-case oracle

The initial nine-fixture / five-operation differential corpus does not by
itself complete the required semantic matrix.

The following coverage audit distinguishes deliberately exercised evidence
from cases that are still missing.

#### Ordinary relationships

| Required case | Current evidence | Status |
|---|---|---|
| disjoint polygons | `disjoint` | covered |
| ordinary overlap | `overlap` | covered |
| containment | `containment` | covered |
| identical operands | `identical` | covered |
| first operand empty | `empty_first` | covered |
| second operand empty | `empty_second` | covered |
| both operands empty | `both_empty` | covered |

The three explicit empty-input relationships are now covered by the
independent differential oracle. Across all five operations, the 15 additional
results agree between geo-d and CGAL/EPECK.

The complete normalized 60-result corpus is byte-for-byte identical with
SHA-256
`763fc24ea82a2d7052092cb429e5655909dc2aef5d0a7ef2ead51d9b8e7e88d0`.

The original 45-result normalized corpus also retains its previously recorded
SHA-256, so the empty-input extension did not change earlier oracle evidence.


#### Boundary contacts

| Required case | Current evidence | Status |
|---|---|---|
| shared vertex | `point_touch` | covered |
| multiple isolated shared vertices | `multiple_point_contacts` | covered |
| shared complete edge | `adjacent` | covered |
| partial collinear overlap | `partial_collinear_overlap` | covered |
| adjacent polygons | `adjacent` | covered |
| coincident boundaries | `identical` | covered |
| T-junction-style contact after noding | `t_junction_contact` | covered |

`plus` exercises proper crossings. It is not counted as a T-junction-style
contact because both crossing segments continue through the intersection.

#### Holes and components

| Required case | Current evidence | Status |
|---|---|---|
| polygon intersecting a hole boundary | `hole_boundary_crossing` | covered |
| polygon filling a hole | `donut_fill` | covered |
| polygon entirely inside a hole | `donut_island` | covered |
| operation creating a hole | `containment`, `A \ B` | covered |
| operation removing a hole | `donut_fill` | covered |
| operation splitting one component into several | `plus`, directional differences | covered |
| disconnected output components | `disjoint`, `point_touch`, `plus` | covered |
| island inside a hole | `donut_island` | covered |

`donut_fill` has a polygon coincident with the existing hole boundary and
`donut_island` lies strictly inside the hole. Neither is counted as evidence
for an operand that crosses a hole boundary.

#### Numerical/materialization cases

The initial 45-case corpus uses small integer-coordinate fixtures and is a
semantic/topological oracle corpus.

It does **not** qualify the numerical/materialization matrix merely because
the common implementation path performs exact noding and binary64
materialization.

The following remain separate explicit evidence requirements:

| Required case | Status |
|---|---|
| proper rational intersections | covered by `properRationalMaterializationStatusMatrix` |
| distinct exact events | covered by `distinctExactEventsStatusMatrix` |
| distinct exact events colliding after binary64 rounding | covered by `exactEventCollisionStatusMatrix` |
| rounded edge collapse | covered by `longMaxMaterializationStatusMatrix` |
| new crossing/contact introduced by rounding | covered by `roundedContactStatusMatrix` |
| lost exact topology after materialization | covered by collapse and new-contact failure fixtures |

The numerical/materialization matrix is now qualified by purpose-built
end-to-end research probes against ADR-0023.

All of these probes execute through
`tryBooleanOverlayP1ResearchInternal`, so the evidence covers the generalized
research selector together with the production exact noding, arrangement,
canonicalization and materialization path.

The matrix is supported as follows:

- `properRationalMaterializationStatusMatrix` embeds a proper intersection at
  exactly `(2/3, 2/3)`. All five Boolean operations succeed, and the required
  rational result vertex is correctly materialized to binary64.
- `distinctExactEventsStatusMatrix` produces two ordered exact events at
  `1/3` and `2/3` on one source edge. All five operations succeed and retain
  both as distinct materialized result vertices.
- `exactEventCollisionStatusMatrix` embeds two mathematically distinct exact
  overlay events that both correctly round to binary64 `0.5`. All five
  operations reject the unrepresentable result with
  `unrepresentableConstruction`, exposing no partial geometry.
- `longMaxMaterializationStatusMatrix` reuses the established width-one
  signed-`long` rectangle at `long.max`. With the second operand empty,
  union, A-minus-B and symmetric difference require the hazardous geometry
  and fail with `unrepresentableConstruction`; intersection and B-minus-A
  select the empty result and succeed. This verifies both selected-result-only
  materialization and all-or-nothing failure.
- `roundedContactStatusMatrix` reuses the established signed-`long` fixture
  near `2^53` where every rounded vertex remains distinct but two exact
  non-adjacent edges acquire a new binary64 contact. Operations requiring the
  geometry reject it with `unrepresentableConstruction`; operations selecting
  the empty result succeed.
- loss of exact topology after materialization is therefore demonstrated by
  at least two independent mechanisms: required-vertex/edge collapse and a
  newly introduced boundary contact without vertex collapse.

The complete research probe passes under both DMD 2.111.0 and LDC 1.41.0
(frontend 2.111.0). The normalized 80-result topological oracle output is
byte-for-byte identical between DMD, LDC and CGAL/EPECK where applicable, with
SHA-256
`6b832da4df1b351ebd582f89d1ec898118d9ffa29ec7f63d4cc3f26c085084a2`.

The additional numerical probes run before the 80 emitted differential
results, so they do not alter the retained topological oracle corpus.

#### Topological oracle matrix status

The non-numerical topological matrix is now covered by 16 fixtures, each run
through all five research operations:

- union;
- intersection;
- difference A minus B;
- difference B minus A;
- symmetric difference.

This gives 80 differential results. The normalized regularized-set output is
byte-for-byte identical between geo-d and CGAL/EPECK with SHA-256
`6b832da4df1b351ebd582f89d1ec898118d9ffa29ec7f63d4cc3f26c085084a2`.

The expansion added explicit evidence for:

- empty operands in both orders and both empty;
- multiple isolated shared vertices;
- partial collinear boundary overlap;
- a vertex-on-edge T-junction requiring noding;
- an operand crossing an interior-ring boundary.

The differential evidence continues to distinguish set semantics from result
representation. In particular, point-contact and hole-crossing cases can have
different component/hole decompositions in geo-d and CGAL while representing
the same regularized point set. geo-d's own component/hole decomposition is
therefore checked independently inside the D probe.

This completes the non-numerical topological portion of the required matrix.

Together with the independently exercised numerical/materialization cases
above, Section 7 now covers the complete semantic/degeneracy matrix required
by this research issue.

The semantic/degeneracy matrix gate is therefore satisfied.

The other research questions that were previously open alongside this matrix
are resolved elsewhere in this document:

- Section 4.3 records the regularized semantic disposition;
- Section 9.1 records the ownership/multiplicity disposition;
- Section 12 records the final promote/defer/reject dispositions.

## 8. Operation-specific algebraic laws

### Intersection

```text
A ∩ B = B ∩ A
A ∩ A = A
A ∩ empty = empty
```

### Difference

Difference is intentionally operand-order sensitive:

```text
A \ B != B \ A    in general
A \ A = empty
A \ empty = A
empty \ A = empty
```

Operand exchange is therefore not a valid invariance property for difference.

### Symmetric difference

```text
A xor B = B xor A
A xor A = empty
A xor empty = A
```

### Cross-operation relationship

Where the chosen regularized semantics make the identity applicable:

```text
A xor B
    =
(A \ B) union (B \ A)
```

This can later provide independent property evidence.

### 8.1 Executable algebraic and invariance evidence

The operation-specific laws above are now executable research evidence across
all 16 retained semantic/topological fixtures.

The geo-d research probe checks canonical materialized results directly for:

- intersection commutativity;
- intersection idempotence for both operands;
- intersection with the empty set;
- difference self-subtraction;
- difference identity with the empty set;
- empty-set difference;
- consistency between `differenceAB(A, B)` and `differenceBA(B, A)`;
- symmetric-difference commutativity;
- symmetric-difference self-cancellation;
- symmetric-difference identity with the empty set;
- union commutativity as a common canonicalization check.

Canonical result comparison includes component count, ring count, point count,
component order, ring order and every materialized binary64 point. No geometric
tolerance is used.

The cross-operation identity

A xor B = (A minus B) union (B minus A)

is checked separately because the current geo-d research entry point accepts
one polygon per operand rather than an arbitrary polygon set.

For geo-d, the identity is checked for every retained fixture using both
twice-area equality and regularized-set membership on a half-unit probe grid.

The independent CGAL/EPECK oracle checks the same identity as an exact
polygon-set equality: the symmetric difference between both sides must be
empty.

All algebraic checks run before emission of the existing differential output.
The normalized 80-result oracle corpus therefore remains unchanged at
SHA-256
`6b832da4df1b351ebd582f89d1ec898118d9ffa29ec7f63d4cc3f26c085084a2`.

This evidence establishes the operation-specific algebraic and invariance
properties required by this research gate. It does not qualify the still-open
numerical/materialization behavior or authorize a public API.

## 9. Result representation questions

The existing polygon-union result shape can already represent:

- empty output;
- one polygon;
- multiple polygons;
- holes;
- immutable owning storage.

That shape appears structurally capable of holding regularized intersection,
difference and symmetric-difference results.

This does not decide the public API.

Later design options include:

- operation-specific public result types;
- one shared polygon-set result type;
- shared internal storage only;
- dedicated public functions;
- a generalized public overlay selector.

A generic public selector must not be chosen merely because the implementation
may share an internal truth predicate.

### 9.1 Ownership and multiplicity disposition

For the retained regularized polygon Boolean candidates, the existing internal
owning result representation is sufficient in structure.

The production result storage already provides the required ownership model:

- materialized point storage is immutable and owned by the result;
- ring descriptors reference that immutable point backing;
- component boundaries are represented by immutable component-ring offsets;
- mutable build arrays are consumed and frozen before publication;
- ordinary result-descriptor copies share immutable backing rather than
  deep-copying geometry;
- read-only `Polygon2View!double` component views may safely reference the
  immutable GC-managed backing;
- an empty result is represented directly by zero components, zero rings and
  zero points.

The same representation also covers the required multiplicities:

- zero or more polygon components;
- one exterior ring per component;
- zero or more holes per component;
- disconnected components;
- components that meet only at isolated boundary points.

The differential oracle demonstrates an important distinction between
regularized set semantics and representation multiplicity.

Component count and hole count are not cross-library semantic invariants.
For some point-contact and symmetric-difference cases, geo-d and CGAL/EPECK
use different polygon-with-holes decompositions while representing the same
regularized point set.

Therefore:

- geo-d may retain its deterministic canonical component/hole decomposition;
- isolated point contacts do not require components to be merged merely to
  imitate another library's representation;
- cross-library correctness is judged by regularized set semantics, not by
  matching component or hole multiplicity;
- geo-d's own component/hole multiplicity remains checked independently
  against explicit research expectations.

No operation-specific ownership requirement was found for intersection,
difference or symmetric difference. The same internal immutable owning
polygon-set shape can therefore serve the retained research operations.

This conclusion applies to the internal result model only. It does not decide
whether a later public API should expose one shared polygon-set result type,
operation-specific result types, dedicated functions, or another design.

## 10. Numerical and failure questions

ADR-0023 was treated as a transfer hypothesis rather than assumed to apply
automatically to the additional Boolean operations.

The purpose-built numerical/materialization evidence in Section 7 now
qualifies the materialization-sensitive parts of that transfer:

- exact topology remains authoritative before coordinate materialization;
- proper rational result vertices can be materialized successfully;
- distinct exact events remain distinct when binary64 can represent them
  distinctly;
- distinct exact events that collide after binary64 rounding are rejected;
- required result vertices/edges that collapse during rounding are rejected;
- new boundary contact introduced only by rounding is rejected;
- failure is all-or-nothing and exposes no partial result;
- operations selecting an empty result can succeed even when hazardous exact
  geometry exists elsewhere in the input arrangement.

No evidence from this research requires implicit repair, snapping or
quantization, or a different geometric materialization status model for
intersection, difference or symmetric difference.

The established separation between geometric construction status and runtime
resource failure remains unchanged.

## 11. Oracle strategy

Primary semantic and exact oracle:

- CGAL exact-kernel regularized Boolean set operations.

Secondary implementation diversity:

- JTS / GEOS OverlayNG strict mode;
- Clipper2 for integer/scaled-integer diagnostics;
- Boost.Geometry where semantics are compatible.

Disagreement must be investigated semantically rather than decided by
majority vote.

### 11.1 Executable CGAL/EPECK differential oracle

The proposed regularized polygon-set semantics are now backed by an
independent executable CGAL/EPECK differential probe.

The geo-d side does not call a simplified selector fixture directly. Real
`Polygon2View!int` operands run through the complete research-only duplicated
P1 path:

```text
input validation
    ->
source-edge extraction
    ->
exact candidate discovery and noding
    ->
exact arrangement
    ->
half-edge embedding
    ->
A/B side-label resolution
    ->
operation-specific research selector
    ->
unchanged production boundary tracing
    ->
unchanged production component/hole reconstruction
    ->
unchanged production canonicalization
    ->
unchanged binary64 materialization
    ->
unchanged topology validation
    ->
immutable owning result
```

The production implementation remains unchanged. The P1 orchestration is
duplicated intentionally in the research module rather than refactoring
production merely to make the experiment convenient.

The independent C++ oracle uses:

```text
CGAL
Exact_predicates_exact_constructions_kernel
Boolean_set_operations_2
```

and evaluates:

```text
union
intersection
A \ B
B \ A
symmetric difference
```

for each retained fixture.

#### Initial differential corpus

The first corpus contains nine fixture relationships:

1. disjoint rectangles;
2. ordinary overlapping rectangles;
3. strict containment;
4. identical operands;
5. adjacent polygons sharing a complete edge;
6. isolated point contact;
7. a polygon with a hole plus a polygon filling that hole;
8. a polygon with a hole plus an island strictly inside the hole;
9. crossing horizontal/vertical rectangles (`plus`).

Every fixture is evaluated under all five Boolean predicates:

```text
9 fixtures
x
5 operations
=
45 differential results
```

The corpus therefore already exercises:

- non-empty operands producing an empty result;
- proper crossings;
- containment;
- complete edge coincidence;
- isolated point contact;
- identical boundaries;
- result holes;
- disconnected result components;
- source polygons containing holes;
- operation-created component splitting.

It does not complete the full semantic/degeneracy matrix.

#### Set-semantic versus representation comparison

The differential contract deliberately distinguishes the regularized result set
from one library's polygon decomposition.

Cross-library comparison includes:

```text
operation
exact integral twice-area for the retained integer corpus
dense outside / boundary / inside classification signature
```

The dense classification grid is the same on both sides and samples the
retained fixture domain.

Cross-library comparison deliberately excludes:

```text
component count
hole count
```

because those values are not representation-invariant when result pieces meet
only at isolated vertices.

geo-d does not stop checking its own representation. The D probe independently
checks an explicit expected component/hole matrix for every one of the 45
results before emitting the differential signature.

This separation was required by observed contact cases.

For example:

```text
overlap symmetric difference:

    geo-d:
        2 components
        0 holes

    CGAL:
        1 Polygon_with_holes
        1 hole

    regularized set:
        identical area
        identical dense classification signature
```

and:

```text
plus symmetric difference:

    geo-d:
        4 components
        0 holes

    CGAL:
        1 Polygon_with_holes
        1 hole

    regularized set:
        identical area
        identical dense classification signature
```

The already known isolated-point-contact representation difference is also
visible for union and symmetric difference:

```text
geo-d:
    retains two polygon components meeting at one exact vertex

CGAL:
    may encode the same regularized set in one Polygon_with_holes object
```

Therefore CGAL component/hole multiplicity is diagnostic evidence rather than
a cross-library semantic invariant.

#### Harness qualification

The first differential attempt exposed a probe defect rather than a geometry
difference:

```text
assert(
    tryClassifyPointInPolygon(...)
)
```

was compiled with `-release`, so the classification call itself was removed.

The probe was corrected so classification executes independently of assertions.

The runner also removes all previous temporary output before every run so a
failed build or execution cannot make stale files appear to be current oracle
evidence.

#### Initial 45-case result

The qualified differential run produced:

```text
geo-d result lines:
    45

CGAL/EPECK result lines:
    45

normalized geo-d SHA-256:
    dd562a63eecd718164570e5b9b903172d07913088afea3bc2a88c26b977e380e

normalized CGAL/EPECK SHA-256:
    dd562a63eecd718164570e5b9b903172d07913088afea3bc2a88c26b977e380e
```

The normalized outputs are byte-for-byte identical:

```text
45 / 45
regularized set signatures match
```

This demonstrates an independent executable oracle strategy for the retained
corpus.

At that initial 45-case checkpoint, this evidence did **not** by itself
establish:

- completion of the required semantic/degeneracy matrix;
- all operation-specific algebraic and invariance laws;
- equivalence of numerical/materialization failure behavior;
- behavior near binary64 materialization limits;
- a public API requirement for intersection, difference, or symmetric
  difference;
- authorization to refactor production into a generalized overlay engine.

## 12. Final research disposition

| Operation | Consumer status | Semantic / technical evidence | Research disposition |
|---|---|---|---|
| Union | consumer-backed and already public | accepted by ADR-0023 | retain existing production operation |
| Intersection | no demonstrated construction consumer | regularized semantics and implementation path qualified | **defer** |
| Difference | no demonstrated generic polygon-difference consumer | regularized semantics and implementation path qualified | **defer** |
| Symmetric difference | no demonstrated construction consumer | regularized semantics and implementation path qualified | **defer** |

The three additional Boolean operations are technically credible candidates:
the research work qualifies their regularized semantics, common exact-overlay
architecture, degeneracy behavior, algebraic properties, ownership model,
numerical/materialization behavior and independent oracle agreement.

That technical qualification is not sufficient reason to expand the public
API.

The explicit Issue #49 dispositions are therefore:

- intersection: **defer**;
- difference: **defer**;
- symmetric difference: **defer**.

None is rejected as mathematically or architecturally unsuitable.

None is promoted to a design gate now because the consumer audit has not
established a concrete reusable construction requirement for any of the three.

A future candidate may be reconsidered when concrete downstream consumer
evidence appears. Promotion would then require a separate design/API gate that
decides at least:

- the public operation spelling;
- the public result type;
- checked failure/status spelling;
- relationship to the existing polygon-union API;
- whether shared production internals should be generalized or remain
  operation-specific at the orchestration layer.

The research-only generalized P1 probe remains evidence, not a production
Boolean-overlay API. No production implementation or public API expansion is
authorized by this research result.

Accordingly, Issue #49 does not itself authorize implementation promotion.
Any future production implementation or public API expansion for intersection,
difference or symmetric difference requires the subsequent design gate.

## 13. Deferred follow-up questions

Issue #49 has answered the research questions required for the current
disposition.

The remaining questions are future triggers or design questions rather than
unfinished Issue #49 research:

1. Is there a concrete downstream workflow requiring constructed polygon
   intersection?
2. Is there a concrete downstream workflow requiring polygon-region
   difference?
3. Is there a credible consumer requirement for symmetric difference?
4. If one of the deferred candidates is later promoted, what public API and
   result type should expose the already-qualified internal regularized
   polygon-set representation?

The first three questions determine whether a deferred operation should be
reopened. The fourth belongs to the subsequent design/API gate required before
any implementation or public API expansion.

## 14. Research gates

Issue #49 is complete only when:

- [x] intersection consumer evidence is classified;
- [x] difference consumer evidence is classified;
- [x] symmetric-difference consumer evidence is classified;
- [x] regularized versus non-regularized semantics are decided;
- [x] the semantic/degeneracy matrix is independently checked;
- [x] production union-core reuse boundaries are audited directly;
- [x] operation-specific algebraic and invariance properties are defined;
- [x] result ownership and multiplicity implications are evaluated;
- [x] numerical/materialization/failure behavior is checked against ADR-0023;
- [x] an independent oracle strategy is demonstrated;
- [x] every candidate receives an explicit disposition:
      promote to design gate, defer, or reject;
- [x] no implementation or public API expansion occurs without a subsequent
      design gate.
