# ADR-0020: Shared Euclidean contract core for geo-d and geo3-d

**Status:** Accepted

**Date:** 2026-09-21

## Context

`geo-d` and `geo3-d` are independent public libraries for two-dimensional and
three-dimensional Euclidean geometry.

Their APIs are intentionally designed as one family, but neither library
should depend on the other merely to reuse implementation.

D coexistence experiments performed during the v2 migration exposed a
different requirement from ordinary code reuse.

When both packages declare separate ordinary public declarations with the
same API role, importing both libraries can produce conflicting declaration
identities. Re-exporting one common original declaration instead allows the
siblings to coexist while referring to the same contract.

This matters for neutral contracts whose identity should genuinely be common
to the 2D and 3D libraries.

The requirement is therefore not:

```text
share implementation wherever possible
```

but:

```text
share declaration origin where common identity is part of the API-family
contract
```

This distinction requires a narrowly scoped common package.

It also supersedes the blanket rejection of any shared foundation package in
ADR-0001 while preserving that ADR's purpose: `geo-d` must not become coupled
to unrelated workspace domains or to a generic catch-all base library.

## Decision

### 1. Public sibling libraries remain independent

The public family is:

```text
geo-d       Euclidean 2D geometry
geo3-d      Euclidean 3D geometry
```

The module roots are:

```d
import geo;
import geo3;
```

Neither sibling depends on the other.

In particular:

```text
geo-d  -> geo3-d    prohibited as a family architecture
geo3-d -> geo-d     prohibited as a family architecture
```

Shared contracts do not change this relationship.

### 2. A small neutral shared core owns declarations that require common identity

A separate package named:

```text
euclid-core-d
```

provides modules under:

```text
euclid_core.*
```

Its purpose is limited to Euclidean contracts whose common declaration
identity is required by both sibling libraries.

The current shared-contract family is:

```text
isGeoScalar
MetricScalar
IntersectionScalar
SegmentIntersectionKind
RingValidationIssue
RingValidationResult
douglasPeuckerWorkspaceSize
```

`AreaScalar` remains `geo-d`-owned.

The current set is evidence of the admission rule, not a mandate to centralize
all similar code.

### 3. Admission to the shared core is identity-driven

A declaration belongs in `euclid-core-d` only when all of the following are
true:

1. it is semantically neutral with respect to 2D versus 3D;
2. both sibling libraries genuinely require the same public contract;
3. one common D declaration identity is required for correct simultaneous use
   of the siblings;
4. placing it in the core does not move dimension-specific geometry semantics
   into a generic abstraction.

Code duplication, implementation convenience, or aesthetic symmetry alone are
not sufficient reasons.

The default remains to keep geometry-specific implementation in the owning
sibling library.

### 4. The shared core is not a public N-dimensional geometry library

`euclid-core-d` does not establish a public API such as:

```d
Point!(T, N)
Vector!(T, N)
Geometry!(T, N)
```

It does not own generic N-dimensional geometry merely because both siblings
use it.

Dimension-bearing geometry remains explicit in `geo-d` and `geo3-d`.

Likewise, the existence of `Polygon2View` does not require a generic polygon
type or a `Polygon3View` in the core.

### 5. Runtime declaration identity comes from the core

For shared contracts, the runtime `geo.*` declaration refers to the original
core declaration rather than defining a second nominal declaration.

The sibling libraries therefore expose their public family vocabulary while
preserving one underlying declaration identity where required.

This allows a consumer to use:

```d
import geo;
import geo3;
```

without treating equivalent shared contracts as unrelated declarations.

### 6. Public documentation remains sibling-owned

The internal declaration origin must not cause ordinary public DDox
documentation to expose `euclid_core.*` as the user-facing API.

For affected `geo-d` declarations, the established facade uses:

```text
private selective import
+
runtime alias to the core declaration
+
version(D_Ddoc) local documentation declaration
```

The runtime build therefore preserves common declaration identity, while the
documentation build provides the expected `geo.*` symbol page and vocabulary.

The same principle applies to `geo3-d`.

The generated public documentation must not expose internal-core naming as
the preferred consumer surface.

### 7. Documentation facades preserve semantics, not necessarily nominal identity

A `version(D_Ddoc)` documentation declaration exists to represent the public
contract in generated documentation.

It is not required to be nominally identical to the runtime core declaration
inside the documentation build itself.

Where a facade contains nested nominal types, verification must instead cover
the relevant public contract, including as applicable:

```text
declared field type
layout
offsets
enumerator values
default initialization
semantic meaning
```

`RingValidationResult.issue` is the current concrete example of this rule.

### 8. No hidden core leakage through the root API

Consumers should reason about:

```text
geo.*
geo3.*
```

not about internal module placement.

Internal-core names must not become a second competing public vocabulary.

The shared package exists to support declaration identity and sibling
coexistence, not to create a third geometry API that ordinary users must
understand.

### 9. Dependency direction remains narrow

The intended architecture is:

```text
             euclid-core-d
                /     \
               /       \
            geo-d     geo3-d
```

This dependency is permitted because it represents a genuine common Euclidean
contract layer.

It does not permit `geo-d` to acquire dependencies on higher-level workspace
domains such as:

```text
geodesy-d
imagery-d
osm-d
locationref-d
proj-d
spatial-d
raster-d
```

merely because those projects are workspace siblings or consumers.

ADR-0001 continues to govern those domain boundaries.

### 10. Packaging is separate from architectural ownership

During workspace development the DUB dependency may be resolved through a
local path.

That path is not part of the architectural contract.

Release preparation must verify the appropriate published DUB dependency and
must not hard-code workspace filesystem layout into compiler or tooling logic.

Tools that invoke DMD or LDC directly should obtain dependency import paths
through DUB rather than by naming the local `euclid-core-d` source directory.

## Evidence

The v2 integration work established the following behaviour:

```text
separate equivalent ordinary declarations
    -> can conflict when sibling packages are imported together

one original declaration re-exported by both siblings
    -> common identity and coexistence

geo3-d depending on geo-d
    -> unnecessary sibling coupling

small neutral common origin
    -> preserves sibling independence
```

The integration additionally verified that the documentation facade can
provide sibling-owned symbol pages while runtime builds retain the shared
declaration origin.

The direct-compiler tooling was changed to resolve DUB import paths rather
than relying on a workspace-specific core path.

## Consequences

Positive consequences:

- `geo-d` and `geo3-d` remain independently versioned public geometry
  libraries;
- consumers can import both siblings without duplicate identities for
  genuinely shared contracts;
- the public API remains dimension-explicit;
- common identity does not require a public N-dimensional abstraction;
- implementation can remain sibling-specific;
- DDox can present the intended sibling vocabulary rather than internal core
  implementation names.

Costs:

- there is one additional package in the dependency graph;
- documentation facades require explicit verification;
- release packaging must include a compatible `euclid-core-d` dependency;
- moving a declaration into or out of the core is an architectural decision,
  not a routine refactor.

## Alternatives considered

### Duplicate the shared declarations in both siblings

Rejected where declaration identity is part of correct coexistence. Equivalent
source text does not create one D declaration identity.

### Make `geo3-d` depend on `geo-d`

Rejected. Three-dimensional Euclidean geometry is not conceptually layered on
two-dimensional Euclidean geometry.

### Make `geo-d` depend on `geo3-d`

Rejected for the corresponding reason.

### Build a generic public N-dimensional geometry library

Rejected. It would turn an identity problem into an unnecessary public
abstraction and would constrain both siblings before consumer evidence exists.

### Copy shared source between repositories

Rejected for contracts requiring common declaration identity. Source equality
is not declaration identity and duplicated copies can drift.

### Use a Git submodule or subtree as the sharing model

Rejected. Repository embedding does not define the intended D package
ownership model and would couple source-management mechanics to API identity.

### Put all reusable implementation into the core

Rejected. Reuse alone is insufficient. The core exists for common neutral
contracts, not as a general-purpose implementation bucket.

## Relationship to other decisions

ADR-0001 continues to define the `geo-d` domain and workspace boundaries,
subject to its 2026-09-21 amendment for this narrowly scoped shared-contract
dependency.

ADR-0019 defines the public 2D/3D API-family migration and compatibility
policy.

This ADR defines only the sibling/shared-core architecture needed to make that
family coexist correctly in D.
