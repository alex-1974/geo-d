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

### 4.3 Provisional semantic direction

Current research hypothesis:

> If another polygon Boolean operation is promoted, investigate it first as a
> regularized 2D polygon-set operation whose result contains polygons with
> holes only, not lower-dimensional point or line artifacts.

This is not yet an accepted contract.

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

It is not yet executable proof that a generalized Boolean selector can drive
the complete production pipeline to that state.

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

This evidence does **not** yet establish:

- complete Boolean-overlay semantics;
- coverage of the required degeneracy matrix;
- numerical failure equivalence for all operations;
- oracle agreement over a differential corpus;
- consumer justification for public API promotion;
- justification for renaming or refactoring production `polygon_union_*`
  internals.

The next research work must broaden semantic/topological/oracle evidence rather
than treating internal reuse as authorization for implementation promotion.

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

## 10. Numerical and failure questions

Research must verify rather than assume that ADR-0023 transfers unchanged.

Initial hypothesis:

- invalid first and second operands remain distinguishable;
- exact topology remains authoritative;
- no implicit repair, snapping or quantization occurs;
- unrepresentable binary64 construction remains an all-or-nothing checked
  geometry failure;
- resource failures remain outside geometry status;
- no partial result is exposed.

Operation-specific counterexamples may require different conclusions.

## 11. Oracle strategy

Primary semantic and exact oracle:

- CGAL exact-kernel regularized Boolean set operations.

Secondary implementation diversity:

- JTS / GEOS OverlayNG strict mode;
- Clipper2 for integer/scaled-integer diagnostics;
- Boost.Geometry where semantics are compatible.

Disagreement must be investigated semantically rather than decided by
majority vote.

## 12. Current disposition

| Operation | Consumer status | Semantic status | Implementation status |
|---|---|---|---|
| Union | consumer-backed, public | ADR-0023 accepted | production |
| Intersection | research candidate | regularized model plausible | blocked |
| Difference | research candidate | regularized model plausible | blocked |
| Symmetric difference | research candidate | regularized model plausible | blocked |

The production architecture provides evidence that a common internal exact
overlay core may be practical.

That architectural convenience is not evidence for public API promotion.

## 13. Open questions

1. Is there a concrete downstream workflow requiring constructed polygon
   intersection?
2. Is there a concrete downstream workflow requiring polygon-region
   difference?
3. Is there a credible consumer requirement for symmetric difference?
4. Should every retained operation use regularized polygon-only semantics?
5. Which union production stages are actually operation-neutral?
6. Are union assumptions hidden in tracing, component reconstruction,
   canonicalization or materialization validation?
7. Can one internal result representation safely serve all operations?
8. What operation-specific exact/materialization counterexamples exist?
9. What differential corpus is sufficient to test the semantic matrix?

## 14. Research gates

Issue #49 is complete only when:

- [x] intersection consumer evidence is classified;
- [x] difference consumer evidence is classified;
- [x] symmetric-difference consumer evidence is classified;
- [ ] regularized versus non-regularized semantics are decided;
- [ ] the semantic/degeneracy matrix is independently checked;
- [x] production union-core reuse boundaries are audited directly;
- [ ] operation-specific algebraic and invariance properties are defined;
- [ ] result ownership and multiplicity implications are evaluated;
- [ ] numerical/materialization/failure behavior is checked against ADR-0023;
- [ ] an independent oracle strategy is demonstrated;
- [ ] every candidate receives an explicit disposition:
      promote to design gate, defer, or reject;
- [ ] no implementation or public API expansion occurs without a subsequent
      design gate.
