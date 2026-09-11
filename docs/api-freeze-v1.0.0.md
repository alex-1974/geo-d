# geo-d v1 public API freeze

**Status:** Frozen
**Target release:** v1.0.0
**Public top-level names:** 41

## Purpose

This document records the public-API freeze for the first stable `geo-d`
release.

The freeze marks the point after which v1.0.0 preparation is concerned with
maturity, verification, documentation, portability, performance regression
work, and defect correction rather than expansion of the public API.

It is not itself the v1.0.0 release.

## Scope

The supported public package entry point is:

```d
import geo;
```

The package exports 41 top-level public names.

The frozen API covers:

- points, vectors, segments, and axis-aligned bounds;
- non-owning polyline, linear-ring, and polygon views;
- scalar conversion and explicit floating-point quantization;
- distance and nearest-point operations;
- geometry bounding-box computation;
- robust orientation predicates;
- segment-intersection classification and construction;
- signed area and polygon area;
- point-in-polygon classification;
- ring and polygon topology validation;
- Douglas-Peucker polyline simplification.

The public package remains deliberately small.

## Completeness decision

The final v1 public-API completeness audit found no remaining fundamental
operation missing within the defined `geo-d` scope.

The last identified fundamental gap was geometry-to-`Bounds2` computation.
ADR-0015 defined that contract and the resulting `tryBounds` overload family
completed the required bounding-box capability.

Useful operations that are not required for the v1 foundation remain eligible
for later releases.

Examples include:

- ring length and polygon perimeter;
- bounds union and bounds intersection construction;
- bounds width, height, and center convenience operations;
- point-to-polyline nearest-point or distance operations;
- public point-in-ring classification;
- centroid and midpoint convenience operations;
- additional vector helpers;
- segment-to-segment distance;
- convex hull;
- clipping;
- transformations;
- owning variable-size geometry containers.

Their absence is intentional and is not a v1 completeness defect.

## Out of scope

The v1 geometry foundation does not provide:

- coordinate reference systems;
- map projections;
- ellipsoidal or geodesic calculations;
- raster processing;
- spatial indexes;
- geospatial file formats;
- application-specific GIS or editor semantics.

Those concerns belong in higher-level or separate libraries.

## Freeze rule

After this freeze, v1.0.0 preparation must not introduce:

- new public top-level names;
- new public overload families;
- incompatible public signature changes;
- changes to documented public semantics;
- accidental exposure of internal implementation details.

A change that would alter the frozen public API requires the freeze to be
explicitly reopened and the reason documented before the change is merged.

If the freeze is reopened, the completeness audit must be repeated before a
new freeze milestone is recorded.

## Changes still permitted

The following work remains permitted when it preserves the frozen public
contract:

- bug fixes;
- additional unit tests;
- property and invariant tests;
- fuzzing;
- portability fixes;
- compiler compatibility fixes;
- CI hardening;
- platform coverage;
- documentation improvements;
- examples;
- benchmark expansion;
- performance regression fixes;
- internal refactoring;
- implementation optimization;
- strengthening internal invariants.

SemVer compatibility rules apply once v1.0.0 is released.

## Verification at freeze

The freeze follows successful verification of the current API surface.

### Public surface

The package-level audit found:

```text
public top-level names: 41
```

All supported package exports are selective `public import` declarations from
`source/geo/package.d`.

### Compiler and test gates

The final geometry-bounds implementation was verified with:

```text
DMD: 30 modules passed unittests
LDC: 30 modules passed unittests
LDC release build: PASS
```

The complete `tryBounds` overload family was also compiled through the
supported package entry point:

```d
import geo;
```

with both DMD and LDC.

### Documentation gate

The public documentation build completed successfully for all 18 public
modules:

```text
PASS: public-only ddox documentation
```

The generated documentation includes `geo.bounding_box` and the package module
`geo`.

### Performance gate

Geometry-bounds computation has a reproducible public-API benchmark covering
multiple polyline sizes and representative polygon traversal.

The retained implementation has the expected linear scaling, constant
auxiliary storage, allocation-free execution, and no identified performance
blocker under the primary performance compiler.

Existing robust-orientation performance work likewise has no current
performance blocker for the v1 maturity milestone.

## Source of truth

The authoritative public surface remains:

```text
source/geo/package.d
```

Public Ddoc defines the callable contract of individual symbols.

Architecture Decision Records under `docs/adr/` define the persistent design
decisions behind that contract.

This document records the milestone at which that public surface was frozen;
it does not replace either source Ddoc or the ADRs.
