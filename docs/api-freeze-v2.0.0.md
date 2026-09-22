# geo-d v2 public API freeze

**Status:** Frozen
**Target release:** v2.0.0
**Package exports:** 45
**Public audit declarations:** 151

## Purpose

This document records the public-API freeze for `geo-d v2.0.0`.

The freeze marks the point after which v2.0.0 preparation is concerned with
release verification, packaging, documentation, defect correction, and
registry publication rather than further public API design.

It is not itself the v2.0.0 release.

## Scope

`geo-d` remains exclusively a coordinate-system-agnostic Euclidean 2D
geometry library.

The supported package entry point remains:

~~~d
import geo;
~~~

The v2 migration aligns the public API with the independent `geo3-d` sibling
while preserving the scope boundary between the dimensional libraries.

Canonical v2 dimension-explicit names include:

~~~text
Polyline2View
LinearRing2View
Polygon2View
Orientation2
~~~

Supported v1 spellings remain available in v2 as deprecated compatibility
aliases or forwarding overloads where documented.

## Frozen public surface

The historical frozen v1 audit baseline remains:

~~~text
package exports:             41
total audit declarations:   146
~~~

The frozen v2 surface is:

~~~text
package exports:             45
total audit declarations:   151
~~~

The complete declaration-by-declaration migration disposition and reproducible
surface audit are recorded in:

~~~text
docs/v2-public-api-audit.md
~~~

The v1 baseline remains historical migration input and is not rewritten to
match the v2 declaration count.

## 2D/3D family contract

The v2 API follows the family rule:

> Symmetry where the mathematics is symmetric; specialization where it is not.

Dimension-bearing geometry types use explicit dimensional suffixes where
required.

Operation names remain dimension-neutral where the mathematics forms a genuine
family.

API symmetry alone does not authorize new public geometry functionality.

## Shared declaration identity

Seven dimension-neutral contracts require one declaration identity across
`geo-d` and `geo3-d`:

~~~text
isGeoScalar
MetricScalar
IntersectionScalar
SegmentIntersectionKind
RingValidationIssue
RingValidationResult
douglasPeuckerWorkspaceSize
~~~

Their declaration origin is the independently versioned `euclid-core-d`
package.

The frozen integration state resolves:

~~~text
euclid-core-d ~>0.1.0
~~~

through the public DUB registry.

Neither dimensional sibling uses a workspace-relative Core dependency.

`AreaScalar` remains owned by `geo-d`.

## Compatibility policy

The intended compatibility lifecycle is:

~~~text
v1.x    existing v1 API
v2.0    canonical v2 API plus deprecated v1 compatibility
v2.x    deprecated v1 compatibility remains functional
v3.0    earliest normal removal point
~~~

Deprecated compatibility declarations alias or forward to canonical
implementations rather than maintaining independent implementations.

## Freeze rule

After this freeze, v2.0.0 release preparation must not introduce:

- new public top-level names;
- new public overload families;
- incompatible public signature changes;
- changes to frozen public semantics;
- new speculative geometry functionality;
- accidental exposure of internal `euclid_core.*` implementation ownership.

A change that alters the frozen public API requires the v2 freeze to be
explicitly reopened and the reason documented before that change is merged.

If the freeze is reopened, the complete public API audit and integration
verification must be repeated before a new freeze milestone is recorded.

## Changes still permitted

Release preparation may still include changes that preserve the frozen public
contract, including:

- defect fixes;
- additional tests;
- CI hardening;
- portability fixes;
- documentation corrections;
- release metadata;
- packaging verification;
- registry consumer verification;
- internal refactoring where externally observable contracts remain
  unchanged.

Any defect fix that requires a public semantic or signature change must reopen
the freeze rather than being treated as ordinary release preparation.

## Verification at freeze

The freeze follows successful verification of the integrated v2 state.

### Public API audit

The complete v1-to-v2 declaration audit reports:

~~~text
v1 package exports:             41
v1 total audit declarations:   146

v2 package exports:             45
v2 total audit declarations:   151

unresolved declarations:        0
~~~

### Shared-Core packaging

`euclid-core-d v0.1.0` is published through the public DUB registry.

Both dimensional siblings use the versioned dependency:

~~~text
~>0.1.0
~~~

The durable family consumer verifies that:

- Core remains transitive rather than being injected by the root consumer;
- exactly one registry-backed Core instance is resolved;
- all seven shared contracts retain common D declaration identity;
- `geo` and `geo3` can be imported simultaneously;
- representative 2D and 3D operation-family overloads coexist.

The test pins the verified `geo3-d` sibling commit and Core version.

### Compiler and CI verification

The durable family consumer has passed with:

~~~text
DMD 2.111.0
current DMD
current LDC
~~~

The complete post-merge CI matrix passed on the frozen integration state:

~~~text
geo-d integration commit:
0a1434c90a793ad4f079a0ba957e10c6ad4218cd

GitHub Actions run:
35713348711
~~~

That verification includes:

- DMD 2.111.0;
- current DMD;
- current LDC;
- lifetime compile-negative tests;
- external consumer verification;
- durable 2D/3D family coexistence verification;
- release builds;
- Linux ARM64;
- Windows x86-64;
- macOS x86-64;
- macOS ARM64;
- generated public API documentation.

### Documentation

The public DDox documentation build succeeds without exposing internal
`euclid_core.*` ownership as the ordinary public API vocabulary.

## Source of truth

The authoritative package surface remains:

~~~text
source/geo/package.d
~~~

Source-level Ddoc defines individual callable contracts.

The normative v2 family conventions are recorded in:

~~~text
docs/v2-api-conventions.md
~~~

The complete public migration audit is recorded in:

~~~text
docs/v2-public-api-audit.md
~~~

ADR-0019 defines the v2 API-family migration and ADR-0020 defines the shared
declaration-core architecture.

The annotated Git tag:

~~~text
api-freeze-v2.0.0
~~~

is the repository marker for the exact commit at which this freeze record is
established.

The API-freeze tag is distinct from the later `v2.0.0` release tag.
