# ADR-0025 — Analytic Circle2 and explicit polygonization

**Status:** Accepted for the v4 first slice  
**Date:** 2026-11-06

## Context

Issue #164 identifies structured Euclidean shapes as a natural completeness
direction for `geo-d`, with Dunia as a later consumer. A circle carries
invariants that are lost when it is represented immediately as a polygon:
centre, radius, diameter, analytic area and circumference, and direct disk
containment.

The first v4 slice must therefore establish one useful structured value type
without introducing a broad curve hierarchy or hidden approximation policy.

## Decision

### 1. Circle2 is an analytic value type

`Circle2!T` stores only a `Point2!T` centre, a non-negative `T` radius, and
explicit validity state. It does not own or cache polygon vertices.

Successful construction uses checked `tryFromCenterRadius`. NaN, non-finite
coordinates/radius, and negative radius are rejected. Zero radius is valid and
represents a degenerate point circle.

Invalid values expose no geometric properties; property access retains the
normal development-time assertion contract used by other geo-d value types.

### 2. Direct operations precede lowering

The first public operations are:

- centre and radius access;
- finite/valid state;
- diameter;
- analytic area and circumference;
- closed disk containment without an epsilon;
- checked axis-aligned bounds.

Metric results use the existing `MetricScalar!T` policy. Direct operations are
allocation-free and use `@safe`, `nothrow`, and `@nogc` contracts.

### 3. Polygonization is explicit and caller-owned

`tryPolygonizeCircleInto` writes an inscribed, counter-clockwise regular
polygon into caller-owned point storage. The destination length is the segment
count and must be at least three. The first vertex has angle zero and the ring
is implicitly closed by `LinearRing2View`.

Polygonization is approximate and never presented as an exact circle
conversion. No global tolerance is introduced. The current first slice uses
explicit segment count; an error-bounded policy requires a separate design
decision.

The output scalar is constrained to `MetricScalar!T`, so integral input circles
produce floating-point output under the existing metric policy. No allocation
is performed and a failed preflight leaves the destination unchanged.

### 4. Scope exclusions

This ADR does not admit:

- a generic curve hierarchy;
- `Ellipse2` or `Arc2`;
- a persistent `RegularPolygon2`;
- automatic tolerance selection;
- owning polygon results;
- editor interaction, snapping, rendering, or Dunia policy.

Axis-aligned `Rect2` remains a separate design question because `Bounds2`
already provides closed axis-aligned envelope semantics. An oriented rectangle
requires its own contract and consumer evidence.

## Verification gates

- DMD and LDC unit tests cover all supported scalar domains;
- construction, invalid values, zero radius, bounds and closed containment are
  tested;
- polygonization determinism, winding, minimum segment count and failure
  atomicity are tested;
- direct analytic operations and polygonization must be benchmarked separately;
- Dunia integration remains a later consumer-validation gate.

## Consequences

Consumers can preserve analytic circle semantics and choose when to lower to
discrete geometry. The caller retains allocation and lifetime control. The
API is intentionally narrower than the complete candidate shape family;
additional shapes require separate evidence and design decisions.
