# ADR-0016: Robust `real` scalar policy

**Status:** Accepted

**Date:** 2026-09-12

## Context

The public geo-d scalar domain is:

```text
int
long
float
double
real
```

`real` is therefore a valid scalar for core geometry representation and for
operations whose contract can be expressed using the normal arithmetic
semantics of that scalar.

The existing API already supports `real` for areas including:

- `Point2`;
- `Vector2`;
- `Segment2`;
- `Bounds2`;
- `PolylineView`;
- `LinearRingView`;
- `PolygonView`;
- checked scalar and geometry conversion;
- geometry bounds;
- metric operations;
- Douglas-Peucker simplification.

Metric computation deliberately preserves `real`:

```text
MetricScalar!real == real
```

Robust-topology and exact-area operations have a different numerical
contract.

Those operations currently support:

```text
int
long
float
double
```

and deliberately exclude `real`.

This distinction exists because D `real` is a platform-dependent
floating-point type. geo-d must not assume one particular representation,
precision, exponent range, or binary layout for `real`.

The current robust implementations rely on numerical arguments that are
explicitly established for the supported scalar representation:

- exact fixed-width integer arithmetic;
- exact promotion from binary32 to binary64;
- certified binary64 filters;
- exact binary64 expansion or dyadic fallbacks;
- correctly-rounded binary64 construction.

Simply accepting `real` without an equivalent backend would make the public
robustness guarantee platform-dependent or silently weaker.

## Decision

`real` remains part of the general public geo-d scalar domain.

It remains supported for geometry representation and algorithms whose
documented semantics do not require an exact or certified robust predicate
backend.

For v1, robust topology and exact/correctly-rounded area operations continue
to exclude `real`.

This includes the public families for:

- orientation;
- segment-intersection classification;
- segment-intersection construction;
- signed ring area;
- polygon area;
- point-in-polygon classification;
- ring validation;
- polygon validation.

### No binary64 down-conversion

geo-d will not implement apparent robust `real` support by converting `real`
coordinates to `double`.

Such conversion can discard information before the predicate or construction
is evaluated and therefore cannot preserve the existing robust contract.

### No ordinary floating-point fallback

geo-d will not implement robust `real` support using ordinary floating-point
determinants, epsilon comparisons, or similar uncertified fallback logic.

A public operation advertised as robust must retain the same semantic class of
guarantee across every supported scalar.

### Future `real` support

A robust operation may add `real` support only when geo-d has a
platform-aware backend that can establish the operation's documented
mathematical guarantee for the actual D `real` representation in use.

Such a backend may be representation-specific internally, but the public API
must not require callers to know or assume that representation.

Before enabling `real` for an existing robust public operation, verification
must cover at least:

- the supported `real` representation or representations;
- exact or certified predicate correctness;
- extreme finite values;
- subnormal values where applicable;
- degeneracies;
- compiler behaviour for DMD and LDC;
- preservation of the operation's allocation and exception guarantees.

### Metric algorithms remain separate

Metric algorithms do not become robust topology predicates merely because
they support `real`.

For example, Douglas-Peucker simplification may use `real` because its public
contract explicitly bases decisions on computed metric distances and does not
claim exact topological classification.

This distinction between metric computation and robust topology is part of
the public numerical model.

## Consequences

The public scalar model has two intentionally different layers.

General geometry scalar domain:

```text
int
long
float
double
real
```

Current robust/exact scalar domain:

```text
int
long
float
double
```

This is not considered an inconsistency.

It is an explicit consequence of requiring robust operations to provide
meaningful, portable guarantees rather than broad but weaker type acceptance.

The narrower robust domain must remain visible in public documentation and
compile-time verification.

Adding robust `real` support in a future compatible release is permitted only
when the required backend and verification exist. The implementation must not
weaken the established guarantees for the already-supported scalar types.
