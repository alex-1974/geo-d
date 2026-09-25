# ADR-0021: Vector metric and directional primitives

**Status:** Accepted

**Date:** 2026-09-25

## Context

`geo-d` v2.0.0 deliberately keeps its public API small and admits new
functionality only from concrete consumer requirements or sufficiently strong
research evidence.

Research derived from OSM editor workflows identified a missing low-level
vector family needed by interactive geometry work:

- scalar products;
- vector magnitude;
- normalization;
- relative direction angles;
- explicit 90-degree vector rotation.

These operations belong to coordinate-system-agnostic Euclidean geometry and
therefore fit the scope of `geo-d`.

The research was tracked in GitHub issue #23 and investigated before public API
was selected.

Several numerical questions required explicit decisions:

- whether integral dot products should be exact before conversion;
- whether norm should derive from squared norm;
- how normalization should behave for very large and very small vectors;
- how relative angles should handle the `-pi` / `+pi` branch cut;
- whether a perpendicular-vector operation should preserve the input scalar
  type or promote to `MetricScalar`;
- whether these operations should be members or free functions.

The resulting API must also remain compatible with the established
`geo-d` / `geo3-d` family conventions without introducing a dependency between
the sibling libraries.

## Decision

### 1. Add a small vector metric and directional family

The accepted public operations are:

```d
MetricScalar!T dot(T)(
    Vector2!T a,
    Vector2!T b
)
    pure nothrow @safe @nogc
if (isGeoScalar!T);

MetricScalar!T squaredNorm(T)(
    Vector2!T vector
)
    pure nothrow @safe @nogc
if (isGeoScalar!T);

MetricScalar!T norm(T)(
    Vector2!T vector
)
    pure nothrow @safe @nogc
if (isGeoScalar!T);

bool tryNormalize(T, R)(
    Vector2!T vector,
    out Vector2!R result
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
);

bool trySignedAngle(T, R)(
    Vector2!T from,
    Vector2!T to,
    out R result
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
);

Vector2!T perpendicularCCW(T)(
    Vector2!T vector
)
    pure nothrow @safe @nogc
if (isGeoScalar!T);
```

These names, parameter order, and supported parameter names form the intended
public source contract.

### 2. Metric operations belong in `geo.metric`

The following functions belong in `geo.metric`:

```text
dot
squaredNorm
norm
tryNormalize
trySignedAngle
```

`geo.metric` already owns:

- `MetricScalar`;
- Euclidean distance and length operations;
- the distinction between coordinate storage precision and metric computation
  precision.

These vector operations use the same policy.

They are not added as `Vector2` members.

Free functions remain the canonical form and naturally support UFCS.

For example:

```d
dot(a, b);
a.dot(b);

norm(vector);
vector.norm();

vector.tryNormalize(result);
from.trySignedAngle(to, angle);
```

### 3. `dot` uses ordinary `MetricScalar` arithmetic

`dot` returns:

```d
MetricScalar!T
```

For the supported scalar domain:

```text
int     -> double
long    -> double
float   -> double
double  -> double
real    -> real
```

Each component participates in metric floating-point arithmetic.

For integral vectors, `dot` does not promise exact integral arithmetic before
rounding.

`dot` is a numerical metric/algebra operation, not a robust exact predicate.

Floating-point NaN and infinity follow ordinary floating-point arithmetic.

No hidden allocation is performed.

### 4. `squaredNorm` shares the `dot(v, v)` policy

`squaredNorm(vector)` has the same scalar policy and numerical semantics as:

```d
dot(vector, vector)
```

The two operations must not acquire different integral or rounding policies.

Large finite results may overflow to infinity.

`squaredNorm` is not an exact magnitude-comparison predicate.

### 5. `norm` is computed directly with `hypot`

`norm(vector)` returns `MetricScalar!T`.

It is calculated using the equivalent of:

```d
hypot(x, y)
```

in the metric computation type.

It must not be implemented as:

```d
sqrt(squaredNorm(vector))
```

because direct `hypot` avoids unnecessary intermediate overflow and underflow.

### 6. `tryNormalize` uses scale-first normalization

`tryNormalize` returns a:

```d
Vector2!(MetricScalar!T)
```

through its `out` parameter.

It succeeds only when the input vector:

- contains finite components; and
- is exactly non-zero.

No epsilon or tolerance defines zero.

The implementation first converts the components to `MetricScalar!T` and
scales that metric vector by its maximum absolute component before computing
its magnitude.

Integral absolute value is therefore not formed in the source scalar type;
in particular, normalization does not require negating `T.min` in `T`.

Conceptually, with `M = MetricScalar!T`:

```text
mx = cast(M) vector.x
my = cast(M) vector.y

scale = max(abs(mx), abs(my))

scaled = (mx / scale, my / scale)
length = hypot(scaled.x, scaled.y)

result = scaled / length
```

The operation returns `false` for:

- the zero vector;
- any vector containing NaN;
- any vector containing positive or negative infinity;
- any case in which the required successful finite result cannot be produced.

On failure, the `out` parameter remains:

```d
Vector2!R.init
```

### 7. `trySignedAngle` returns a canonical signed relative angle

`trySignedAngle(from, to, result)` computes the signed angle from `from` to
`to`.

The result:

- is measured in radians;
- uses `MetricScalar!T`;
- lies in `(-pi, pi]`.

Positive angles correspond to positive two-dimensional determinant:

```text
from.x * to.y - from.y * to.x > 0
```

Both vectors must be finite and exactly non-zero.

Otherwise the operation returns `false` and leaves `result` at zero.

No epsilon is used.

Both vectors are converted to `MetricScalar!T` and independently scaled by
positive finite factors before determinant and dot terms are formed.

The ordinary case is based on:

```text
atan2(determinant, dot)
```

When the computed determinant is exactly zero, the branch cut is
canonicalized from the computed dot value:

```text
dot >= 0    -> +0
dot <  0    -> +pi
```

This zero-determinant handling is part of the numerical angle construction;
it does not classify the original vectors as robustly collinear.

`trySignedAngle` is a numerical directional measurement, not a replacement
for robust `orientation`.

### 8. `perpendicularCCW` is ordinary `Vector2` algebra

`perpendicularCCW` belongs in `geo.vector`, not `geo.metric`.

Its definition is:

```text
(x, y) -> (-y, x)
```

The result remains:

```d
Vector2!T
```

There is no `MetricScalar` promotion.

The operation follows the existing ordinary `Vector2` scalar arithmetic
contract.

In particular, signed-integral negation does not promise overflow-free
mathematical behaviour for `T.min`, just as existing unary vector negation
does not.

The clockwise operation does not initially receive a second public function.

It is expressible as:

```d
-perpendicularCCW(vector)
```

### 9. Mixed-scalar vector arguments remain unsupported

The new binary vector operation does not introduce implicit mixed-coordinate
conversion.

For example:

```d
dot(Vector2!int(...), Vector2!double(...))
```

is not part of the API.

### 10. Parameter names are intentional source API

The accepted public parameter names are:

```text
dot                 a, b
squaredNorm         vector
norm                vector
tryNormalize        vector, result
trySignedAngle      from, to, result
perpendicularCCW    vector
```

Representative named-argument calls were verified across the supported
compiler matrix before accepting this ADR.

### 11. The functions remain `geo-d` owned

This ADR does not add new declarations to `euclid-core-d`.

The new operations consume the 2D `Vector2` type and belong to the public
`geo-d` geometry API.

## Numerical research

Exact-before-round integral dot products were investigated.

They preserve distinctions that ordinary binary64 metric arithmetic can lose,
but the measured implementations were substantially more expensive than the
ordinary metric path.

The OSM editor consumer does not require exact integral dot products as
topological predicates.

The accepted policy is therefore ordinary `MetricScalar` arithmetic.

Stronger exact arithmetic remains appropriate for operations whose semantic
contract actually requires it.

## Evidence

The accepted API is based on consumer research in GitHub issue #23.

The investigation included:

- OSM editor workflow analysis;
- current `geo-d` vector and metric API audit;
- API-family and UFCS review;
- integral cancellation and full-range numerical probes;
- exact bounded-integer experiments;
- normalization probes for maximum, subnormal, zero, NaN, and infinity;
- signed-angle branch-cut experiments;
- DMD/LDC performance comparison;
- compiler/code-generation isolation around `core.int128`;
- public-signature and named-argument probes.

The complete public API shape was verified with:

```text
DMD 2.111.0
DMD 2.112.1
DMD 2.113.0

LDC 1.41.0
LDC 1.42.0
LDC 1.43.0
```

using `-preview=dip1000`.

All six controlled compiler configurations passed.

## Consequences

Positive consequences:

- editor consumers gain the foundational vector operations they require;
- the API remains small and explicit;
- free functions preserve the established UFCS style;
- metric result precision follows the existing `MetricScalar` policy;
- topology and numerical directional measurement remain separate;
- quarter-turn direction is explicit;
- implementation can remain allocation-free and `@nogc`.

Costs and limitations:

- integral `dot` and `squaredNorm` are not exact for every full-range integer
  input;
- callers must not use them as robust topology predicates;
- `perpendicularCCW` inherits ordinary signed-scalar negation limitations;
- signed-angle semantics require explicit branch-cut handling;
- the new public names become compatibility commitments after release.

## Alternatives considered

### Add vector operations as `Vector2` members

Rejected. Free functions plus UFCS already provide the intended API style.

### Overload `Vector2 * Vector2` as dot product

Rejected. `Vector2 * scalar` already means scaling.

### Exact-before-round integral `dot`

Rejected for this public primitive because the stronger property is not
required by the demonstrated consumer and carries substantial measured cost.

### Compute `norm` as `sqrt(squaredNorm(vector))`

Rejected because it introduces avoidable intermediate overflow and underflow.

### Use an epsilon to define zero

Rejected. Exact algebraic zero remains distinct from tolerance-based
algorithms.

### Expose unqualified `perpendicular`

Rejected because a perpendicular vector has two possible 90-degree
directions.

### Add both `perpendicularCCW` and `perpendicularCW`

Deferred. The clockwise form is already expressible through unary negation.

### Promote `perpendicularCCW` to `MetricScalar`

Rejected because it would unnecessarily change an ordinary algebraic
permutation/sign operation into floating-point representation.

## Relationship to other decisions

ADR-0002 defines the core type and scalar model.

ADR-0004 defines the numerical-robustness principles.

ADR-0014 defines the explicit binary64 rounding backend for operations that
actually require exact-before-round semantics.

ADR-0019 defines the `geo-d` / `geo3-d` API-family conventions.

ADR-0020 defines the narrowly scoped shared Euclidean contract core.

`docs/v2-api-conventions.md` defines the free-function and UFCS naming grammar.

This ADR adds a consumer-driven post-v2.0 vector primitive family without
changing those architectural boundaries.
