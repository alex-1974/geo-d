# geo-d Ddoc Style Guide

**Status:** Draft  
**Scope:** Public API documentation for `geo-d`

## 1. Purpose

Public Ddoc is part of the `geo-d` API contract.

Its primary purpose is not to describe implementation details, but to let a caller understand:

- what an operation means;
- which inputs are supported;
- which degenerate cases are valid;
- how failure is represented;
- how non-finite values are handled;
- whether the operation allocates;
- how the operation scales;
- which numerical guarantees it provides;
- and how ownership or lifetime affects its use.

Documentation should be sufficient to use the public API correctly without reading the implementation.

## 2. Scope

This guide applies to every public symbol reachable through:

```d
import geo;
```

It also applies to public members of exported types.

Package-private and internal implementation symbols do not need to follow the complete public-API format, although non-obvious internal invariants should still be documented where useful.

## 3. General style

Documentation is written in English.

The first paragraph should be a short semantic summary of the symbol.

Prefer direct statements:

> Computes the exact topological intersection classification of two closed segments.

rather than implementation-oriented descriptions:

> Calls the robust orientation backend several times and then checks the results.

Public documentation describes observable behaviour. Implementation details belong in source comments or ADRs unless they are necessary to explain a numerical or semantic guarantee.

Avoid repeating information that is already obvious from the declaration unless it materially affects use.

### Module metadata

Every public module directly under `source/geo/` must have a module-level
Ddoc comment immediately preceding its `module` declaration.

The module documentation must contain the following Ddoc sections:

```text
Authors:
Copyright:
License:
Date:
```

For `geo-d`, the standard metadata form is:

```d
Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2026 Alexander Bernardi

License:
    MIT

Date:
    September 12, 2026
```

`Authors:`, `Date:`, and `License:` are standard Ddoc sections.
`Copyright:` has special meaning in module documentation and is likewise part
of the required `geo-d` module metadata.

`Date:` records the current revision date of the module documentation. It must
be updated when the module-level public contract or its documentation is
materially revised.

`Version:` is deliberately not maintained per module. Package versions are
defined by released `geo-d` versions and Git tags. Duplicating package-version
state in every source module would create unnecessary synchronization risk.

These metadata sections are a `geo-d` documentation requirement. Their
presence must be verified automatically as part of the public documentation
build.

## 4. Documentation order

For non-trivial public functions, document relevant topics in this order:

1. summary;
2. semantic meaning;
3. supported input domain;
4. preconditions;
5. return or result semantics;
6. failure behaviour;
7. degenerate cases;
8. non-finite input behaviour;
9. ownership and allocation;
10. complexity;
11. numerical guarantees;
12. example.

Sections that are genuinely irrelevant may be omitted.

The goal is completeness, not ceremonial repetition.

## 5. Types

Public types should document:

- the domain concept represented by the type;
- important invariants;
- supported scalar types;
- `.init` semantics when they are intentionally defined;
- equality semantics when they are not obvious;
- valid degenerate states;
- non-finite-value policy where relevant;
- ownership and lifetime where relevant.

Example:

```d
/**
 * A closed axis-aligned bounds in two-dimensional Euclidean space.
 *
 * Bounds2 has two semantic states:
 *
 * - empty: contains no point;
 * - non-empty: min <= max component-wise.
 *
 * Bounds2.init is empty.
 *
 * Degenerate non-empty bounds with min == max are valid.
 *
 * Floating-point bounds may contain infinities but never NaN.
 */
```

## 6. Views and ownership

Non-owning types must state explicitly:

- that they do not own their backing storage;
- whether they are read-only;
- whether construction copies data;
- how long the backing storage must remain valid;
- whether mutation through the owner remains visible;
- whether normalization or validation occurs.

For `PolylineView`, `LinearRingView`, and `PolygonView`, this ownership contract is part of the primary type documentation.

DIP1000 is an enforcement mechanism, not a substitute for explaining the lifetime contract.

## 7. Scalar domains

Supported scalar domains must be explicit whenever the public operation supports less than the complete `geo-d` scalar set.

Do not require callers to infer an important limitation solely from template constraints.

For example:

```text
Supported scalar types:

    int
    long
    float
    double
```

When `real` is intentionally excluded, document that exclusion when it is relevant to users.

Scalar-policy templates such as `MetricScalar`, `AreaScalar`, and `IntersectionScalar` should document their complete mapping.

## 8. Preconditions

A condition enforced through `assert` is a precondition and should be documented when a caller can violate it.

Example:

```text
Preconditions:

    all floating-point coordinates are finite.
```

Do not describe an assertion failure as an ordinary recoverable failure.

The distinction must remain clear between:

- invalid use violating a precondition; and
- supported input for which a `try...` operation returns `false`.

## 9. Failure semantics

Functions using the `try...` naming convention must document every supported reason for returning `false`.

Where an `out` parameter has defined state after failure, document it.

Example:

```text
Returns false when:

- an input coordinate is non-finite; or
- the required metric computation cannot be represented finitely.

On failure, result is zero.
```

Do not use vague descriptions such as:

> Returns false on invalid input.

unless “invalid input” has already been defined precisely.

## 10. Degenerate geometry

Degenerate cases are part of the geometry contract and should be documented deliberately.

Relevant examples include:

- empty views;
- singleton polylines;
- one- or two-vertex rings;
- zero-length segments;
- collinear segments;
- endpoint contacts;
- empty polygons;
- algebraically zero-area rings.

Do not leave degenerate behaviour to inference from tests.

## 11. Non-finite values

For floating-point APIs, distinguish explicitly among:

- NaN;
- positive or negative infinity;
- finite values.

Document whether non-finite input:

- is representable;
- is rejected by a `try...` function;
- violates a precondition;
- produces NaN;
- or is handled according to normal IEEE arithmetic.

For example, these are materially different contracts:

```text
A ring containing any non-finite coordinate returns NaN.
```

and:

```text
All coordinates must be finite.
```

and:

```text
Returns false when any coordinate is non-finite.
```

## 12. Allocation

Allocation behaviour should be explicit for computationally meaningful APIs.

Use direct wording such as:

```text
No allocation is performed.
```

or:

```text
This operation may allocate temporary storage.
```

Caller-owned destination and workspace APIs should document the required buffer sizes and overlap restrictions.

Do not infer “no allocation” only from `@nogc`; state it where it forms part of the useful API contract.

## 13. Complexity

Every non-trivial algorithm should document asymptotic complexity.

Preferred form:

```text
Complexity:

    time  O(n)
    space O(1)
```

or:

```text
Complexity:

    time  O(n^2)
    space O(1)
```

Complexity should describe the public operation, not an internal helper.

For algorithms whose complexity depends on several dimensions, name them explicitly.

Trivial constructors and constant-time field accessors do not need repetitive complexity sections unless their cost could be surprising.

## 14. Numerical guarantees

Numerical documentation must distinguish among:

- exact predicates;
- exact intermediate arithmetic;
- correctly rounded construction;
- ordinary floating-point metric computation;
- deliberately approximate algorithms.

Use precise terminology consistently.

### Exact topology

When applicable:

```text
Classification is mathematically exact for every supported finite input.
No epsilon or tolerance is used.
```

### Rounded construction

When topology is exact but a coordinate must be constructed:

```text
Topology is established exactly.

The constructed coordinate is rounded to binary64 according to the
documented construction policy and must not be used as evidence for the
already established topology.
```

### Metric computation

Metric operations must not imply exactness they do not provide.

Preferred wording:

```text
This is a metric computation, not an exact topological predicate.
```

Where integer coordinates are converted only after exact component differences have been obtained, that distinction should remain documented.

### Exact accumulation

For area operations, document the existing contract explicitly:

```text
The determinant sum is accumulated exactly before one final
correctly-rounded binary64 conversion.
```

## 15. Tolerances

`geo-d` has no global epsilon.

Do not describe an operation as tolerant or approximate unless tolerance is an explicit part of that operation.

A caller-supplied algorithmic tolerance, such as the Douglas-Peucker tolerance, is distinct from an implicit numerical epsilon.

## 16. Attributes

The declaration remains authoritative for D attributes such as:

```text
@safe
@nogc
pure
nothrow
```

Documentation does not need to repeat them mechanically.

Mention an attribute-related property in prose when it matters to the caller, especially:

- allocation behaviour;
- mutation;
- ownership;
- lifetime;
- or an intentional absence of `@nogc`.

## 17. Examples

Examples should demonstrate realistic public usage rather than reproduce exhaustive tests.

Where practical, examples should use only:

```d
import geo;
```

This verifies the intended package-level API.

Each example should illustrate one concept clearly.

Large numerical edge-case suites, property checks, regression cases, and implementation verification remain ordinary unittests rather than documentation examples.

Examples should be compilable.

The public API documentation renderer is `ddox`.

Generated API documentation is build output and is not stored under `docs/` or committed to the repository. It is generated with:

    ./tools/build-docs.sh

The documentation build includes only the public modules directly under `source/geo/` and filters the generated symbol model to documented public declarations.

Documented unit tests may be used as executable API examples where appropriate. Examples should remain focused on realistic public usage through `import geo;` rather than reproducing exhaustive verification tests.

## 18. Tests are not documentation

Unit tests may establish behaviour, but behaviour intended as part of the public contract must also appear in Ddoc.

In particular, the following should not exist only in tests:

- `.init` semantics;
- supported scalar domains;
- exact equality semantics;
- non-finite policies;
- degenerate behaviour;
- failure-state guarantees;
- numerical guarantees.

Tests verify the contract. They do not replace it.

## 19. ADRs and Ddoc

ADRs explain why a persistent design decision was made.

Ddoc explains the resulting public contract.

Do not copy an ADR into source comments.

Instead, Ddoc should state the behaviour that callers need to know, while the ADR retains the design rationale and alternatives.

## 20. Reference quality

The existing documentation of the segment-intersection API is the initial quality reference for algorithm documentation.

It already demonstrates the intended separation between:

- supported scalar domain;
- exact topology;
- rounded construction;
- finite-input requirements;
- degenerate cases;
- failure semantics;
- and complexity.

Future documentation should aim for comparable precision without becoming unnecessarily verbose.

## 21. Definition of done

A public API family is documentation-complete when a caller can determine, where applicable:

- what the operation means;
- which scalar and input domain it accepts;
- which preconditions exist;
- what happens for degenerate geometry;
- what happens for non-finite input;
- how failure is represented;
- whether memory is allocated;
- what the asymptotic cost is;
- what numerical guarantee is provided;
- and how to use it through the public `geo` import.

Documentation completeness is judged by semantic coverage, not by comment length.