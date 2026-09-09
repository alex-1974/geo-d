# ADR-0004 — Numerical robustness and geometric predicates

**Status:** Accepted  
**Date:** 2026-09-09

## Context

`geo-d` distinguishes between numerical measurements and geometric
predicates.

Measurements such as:

- `distance`
- `squaredDistance`
- `segmentLength`
- `tryNearestPoint`

produce numerical values. Small floating-point errors may affect their
numerical accuracy without necessarily changing the control flow of a
geometric algorithm.

Predicates are different. They answer discrete geometric questions such
as:

- left / collinear / right;
- intersecting / non-intersecting;
- inside / boundary / outside.

A wrong predicate result can change topology, algorithm control flow,
polygon structure, intersection results, or spatial relationships.

The first fundamental predicate is:

~~~d
orientation(a, b, c)
~~~

It determines the position of `c` relative to the directed line
`a -> b`.

Mathematically its result is determined by the sign of:

~~~text
(b.x - a.x) * (c.y - a.y)
-
(b.y - a.y) * (c.x - a.x)
~~~

Naively evaluating this expression is not acceptable for `geo-d`.

For integral coordinates, subtraction and multiplication may overflow.

For floating-point coordinates, rounding may change the sign of a
determinant close to zero. In particular, an approximate zero must not
silently be interpreted as geometric collinearity.

The numerical contract for predicates must therefore be stronger than
the contract used for metric calculations.

---

## Decision

### 1. Predicates and measurements are different numerical domains

`geo-d` explicitly distinguishes:

~~~text
measurement
    returns a numerical approximation

predicate
    returns a discrete geometric decision
~~~

Metric operations may use promoted floating-point arithmetic according
to `MetricScalar`.

Predicates instead aim for sign correctness.

The metric computation policy must not automatically be reused for
predicates.

In particular:

~~~d
MetricScalar!long == double
~~~

does not imply that an orientation predicate for `Point2!long` may be
evaluated in `double`.

---

## 2. No global epsilon

`geo-d` will not define a global epsilon for geometric equality,
orientation, collinearity, intersection, or containment.

Code such as:

~~~text
abs(det) < epsilon
~~~

must not define geometric collinearity in the core library.

Tolerance-based operations may be introduced later as explicitly named
approximate algorithms with caller-visible tolerance semantics.

They are separate from exact or robust predicates.

---

## 3. Orientation result type

The public result type is:

~~~d
enum Orientation : byte
{
    right     = -1,
    collinear =  0,
    left      =  1,
}
~~~

The semantics are relative to the directed line `a -> b`:

~~~text
left
    c lies to the left of a -> b

right
    c lies to the right of a -> b

collinear
    a, b and c are mathematically collinear
~~~

`left` and `right` are preferred over `clockwise` and
`counterClockwise` because the API describes the position of one point
relative to a directed line.

Callers should normally compare enum values rather than depend on
arithmetic with their numerical representation.

---

## 4. Public orientation operation

The intended public API is:

~~~d
Orientation orientation(T)(
    Point2!T a,
    Point2!T b,
    Point2!T c
);
~~~

for scalar types for which a robust backend exists.

For floating-point geometry the operation requires finite coordinates.

NaN and infinity remain valid representable `Point2` values but are
outside the mathematical domain of the orientation predicate.

Violation of this requirement must not be mapped onto one of the three
orientation states.

No `unknown`, `approximatelyCollinear`, or NaN-derived state is added to
`Orientation`.

A checked API may be added later if concrete consumers require one.

---

## 5. Integral orientation must be exact

For:

~~~text
Point2!int
Point2!long
~~~

`orientation` must return the mathematically exact result over the
complete representable coordinate domain.

No signed subtraction or multiplication overflow is permitted.

### 5.1 Signed coordinate differences

Coordinate differences are represented internally as:

~~~text
sign + unsigned magnitude
~~~

rather than by evaluating `a - b` directly in the original signed
scalar.

For `int`, the magnitude fits in `uint`.

For `long`, the magnitude fits in `ulong`.

The difference between `long.min` and `long.max` therefore remains
representable as an unsigned magnitude even though it cannot be
represented as `long`.

---

## 6. Exact integer products

The orientation determinant consists of two signed products:

~~~text
p = (b.x - a.x) * (c.y - a.y)
q = (b.y - a.y) * (c.x - a.x)

det = p - q
~~~

The implementation does not need to materialize the complete
determinant.

Only its sign is required.

Each product is represented as:

~~~text
product sign
+
exact unsigned product magnitude
~~~

### 6.1 `int`

Each difference magnitude fits in 32 unsigned bits.

The product of two such magnitudes fits in `ulong`.

Therefore `Point2!int` orientation uses exact 64-bit unsigned product
magnitudes.

### 6.2 `long`

Each difference magnitude may require all 64 unsigned bits.

The exact product therefore requires 128 bits.

`geo-d` uses an internal exact unsigned 64 x 64 -> 128 bit product
representation.

The current implementation represents this value as two 64-bit limbs:

~~~d
struct Unsigned128
{
    ulong hi;
    ulong lo;
}
~~~

This is an internal implementation detail, not a general-purpose
wide-integer abstraction.

The implementation may use compiler or runtime primitives when
available, but the numerical contract must not depend on a particular
compiler intrinsic, Druntime version, or public 128-bit integer API.

---

## 7. A 129-bit determinant representation is unnecessary

A direct implementation might appear to require more than 128 signed
bits for `long` orientation.

`geo-d` avoids materializing that value.

Given:

~~~text
p = signP * magnitudeP
q = signQ * magnitudeQ
~~~

the sign of:

~~~text
p - q
~~~

can be determined from:

1. the signs of `p` and `q`;
2. whether either product is zero;
3. an unsigned comparison of `magnitudeP` and `magnitudeQ`.

For example:

~~~text
p positive, q negative
    determinant positive

p negative, q positive
    determinant negative

both positive
    compare magnitudeP and magnitudeQ

both negative
    compare magnitudeQ and magnitudeP
~~~

Thus exact 128-bit product magnitudes are sufficient even though the
fully materialized signed determinant may require another bit.

---

## 8. Floating-point predicates use filtered adaptive precision

For floating-point geometry, a naive determinant is not sufficient.

The architecture follows a filtered-predicate model:

~~~text
fast floating evaluation
        |
        v
certified error test
        |
        +---- sign guaranteed ----> result
        |
        +---- uncertain ----------> adaptive exact fallback
~~~

The fast path performs ordinary floating-point arithmetic together with
a mathematically justified error bound.

If the error bound proves that rounding cannot have changed the sign,
that sign is returned immediately.

If the result is uncertain, the predicate falls back to adaptive
higher-precision arithmetic.

The fallback computes only as much additional precision as required to
determine the mathematically correct sign.

The intended model is the adaptive robust-predicate approach described
by Shewchuk and the filtered exact-predicate approach used by mature
computational-geometry libraries.

---

## 9. Floating scalar policy

Predicate arithmetic is separate from `MetricScalar`.

Conceptually:

~~~text
input       predicate arithmetic

float       double-based robust predicate
double      double-based robust predicate
real        real-based robust predicate
~~~

Every finite `float` is exactly representable as `double`, so promotion
from `float` to `double` does not alter the mathematical input
coordinates.

`double` uses a robust adaptive backend appropriate for binary
double-precision input.

`real` must not silently be demoted to `double`.

The `real` backend must respect the actual properties of D's `real`
type on the target platform and must be validated independently.

On platforms where `real` has the same precision as `double`, both may
use the same implementation.

---

## 10. Floating-point environment

Certified floating-point error bounds require a defined floating-point
environment.

Robust floating predicates assume ordinary IEEE-style binary arithmetic
with round-to-nearest semantics.

`geo-d` must not silently change the caller's floating-point control
state for every predicate invocation.

The documented environment for robust predicates therefore requires the
default round-to-nearest mode.

Compiler options or optimizations that permit algebraic reassociation,
discard IEEE semantics, or otherwise invalidate proven error bounds must
not be used for robust predicate implementation units unless their
correctness has been independently established.

Robust predicate correctness must not depend on fast-math
transformations.

---

## 11. Fixed additional precision is not the correctness contract

A fixed wider floating representation may be useful as an intermediate
filter.

For example:

~~~text
float -> double
double -> double-double
~~~

may substantially reduce the number of inputs requiring the adaptive
fallback.

However, a fixed amount of additional floating precision is not itself
the definition of predicate correctness.

The public predicate contract is based on sign correctness.

Double-double or another fixed extended representation may therefore be
used as an optimization layer but must not replace the exact/adaptive
fallback unless correctness over the complete supported input domain
has been demonstrated.

---

## 12. Predicates return decisions, not determinant magnitudes

The initial public API exposes:

~~~d
Orientation orientation(...)
~~~

not an exact determinant magnitude.

The exact magnitude may require a substantially wider representation
than its sign.

The implementation should therefore compute only as much numerical
information as needed to establish the geometric decision.

A public cross-product, determinant, or signed-area API may be
introduced later with its own numerical contract.

---

## 13. Robust predicates are the default predicates

The initial public API will not expose parallel operations such as:

~~~text
orientationFast
orientationApprox
orientationUnchecked
~~~

next to the robust predicate.

The operation named `orientation` is intended to be the safe building
block for higher-level geometric algorithms.

Fast approximate filters are implementation details.

An explicitly approximate public API may be considered later only when
a concrete consumer demonstrates a need for it.

---

## 14. Internal implementation structure

The public predicate API belongs in:

~~~text
geo.orientation
~~~

Exact integer and adaptive floating-point machinery remain
implementation details.

Possible future internal modules include:

~~~text
geo.internal.predicates
geo.internal.expansion
~~~

The exact internal module structure is not fixed by this ADR.

Expansion arithmetic must not be generalized prematurely into a public
arbitrary-precision framework.

If another independent D library later requires the same numerical
machinery, extraction into a separate reusable library may then be
considered.

---

## 15. Predicate attributes

The target contract for core predicates is:

~~~text
@safe
pure
nothrow
@nogc
~~~

The integral orientation implementation satisfies these properties.

The floating adaptive implementation should likewise be designed around
stack/value storage and must not require GC allocation on its fallback
path.

Heap-based arbitrary precision is not the intended production
implementation.

`std.bigint.BigInt` may nevertheless be used in tests as an independent
exact oracle.

---

## 16. Testing requirements

Predicate testing must be stronger than ordinary value-type and metric
testing.

### 16.1 Basic semantics

Test:

~~~text
left
right
collinear
degenerate a == b
all three points equal
horizontal
vertical
diagonal
~~~

### 16.2 Permutation identities

For valid points:

~~~text
orientation(a, b, c)
    == orientation(b, c, a)

orientation(a, b, c)
    == orientation(c, a, b)
~~~

Swapping two points reverses orientation:

~~~text
left  <-> right
collinear remains collinear
~~~

### 16.3 Integer extremes

Tests must explicitly cover coordinate combinations involving:

~~~text
int.min
int.max
long.min
long.max
~~~

including vectors spanning the complete signed coordinate domain.

Tests must include cases where naive signed subtraction or
multiplication would overflow.

### 16.4 Wide-product arithmetic

The internal unsigned 64 x 64 -> 128 multiplication must have direct
boundary tests.

At minimum:

~~~text
0 * ulong.max
1 * ulong.max
ulong.max * ulong.max
2^63 * 2^63
~~~

must be checked against independently known exact results.

In particular:

~~~text
(2^64 - 1)^2
=
(2^64 - 2) * 2^64 + 1
~~~

therefore:

~~~text
hi = ulong.max - 1
lo = 1
~~~

### 16.5 Independent exact integer oracle

Property tests should compare the optimized integer predicate against an
independent exact implementation based on `std.bigint.BigInt` in test
code.

The oracle must remain separate from the production implementation.

Random and structured triples should cover the complete `int` and
`long` domains.

### 16.6 Floating near-degeneracy

Floating tests must include:

- exactly collinear points;
- nearly collinear points;
- large coordinate magnitudes;
- very small coordinate magnitudes;
- large exponent differences;
- cases known to fail a naive determinant;
- permutations of those cases.

Reference cases from established robust-predicate test suites should be
incorporated where licensing permits.

### 16.7 Cross-compiler validation

The predicate suite must pass at least:

~~~text
DMD unittest
LDC unittest
LDC release build
~~~

according to the project compiler policy.

Compiler-dependent numerical differences are defects unless explicitly
allowed by the documented contract.

---

## 17. Metrics remain unchanged

This ADR does not change the existing metric policy.

Operations such as:

~~~text
distance
squaredDistance
segmentLength
tryNearestPoint
~~~

continue to use `MetricScalar` and their documented floating-point
semantics.

In particular, `squaredDistance` is not an exact distance-comparison
predicate.

If robust distance ordering is needed later, it should be implemented
as a separate predicate rather than by silently strengthening the
contract of `squaredDistance`.

---

## Consequences

### Positive

- `orientation` can safely form the foundation for later topology.
- Integer orientation is exact over the complete supported coordinate
  domain.
- Full-range `long` predicates do not require a public arbitrary-
  precision dependency.
- Predicate correctness is independent of a specific Druntime 128-bit
  multiplication API.
- Floating predicates will not depend on an arbitrary epsilon.
- Common floating cases retain a cheap filtered fast path.
- Difficult floating cases pay adaptive-precision cost only when
  required.
- Predicate correctness is cleanly separated from metric precision.
- The intended production implementation remains `@nogc`.

### Costs

- Floating orientation is substantially more complex than the textbook
  determinant.
- Adaptive expansion arithmetic requires careful implementation and
  independent testing.
- Floating-point environment assumptions become part of the numerical
  contract.
- `real` requires explicit platform and compiler validation.
- Predicate implementation requires stricter optimization discipline.

These costs are accepted because predicates determine geometric control
flow and topology.

---

## Rejected alternatives

### Naive determinant in the coordinate scalar

Rejected because integral arithmetic can overflow and floating-point
arithmetic can return an incorrect sign.

### Promote every scalar to `double`

Rejected because:

- full-range `long` information cannot be represented exactly in
  `double`;
- `real` would lose precision and potentially range;
- near-degenerate floating predicates remain vulnerable to rounding.

### Materialize the `long` determinant in a signed 128-bit integer

Rejected because the determinant itself may require more signed range
than a 128-bit value provides.

Only its sign is required, and that sign can be established from exact
128-bit product magnitudes.

### Depend on a specific `core.int128` API

Rejected because available overloads differ between Druntime versions.

The architecture requires exact unsigned 64 x 64 -> 128 multiplication,
not a specific runtime implementation.

### `std.bigint` in production predicates

Rejected as the default runtime strategy because core predicates should
remain lightweight and `@nogc`.

It remains useful as an independent test oracle.

### Global epsilon

Rejected because mathematical collinearity is a topological decision,
not a global application tolerance.

### Double-double as the sole robust fallback

Rejected as the architectural correctness definition because it
provides a fixed amount of additional precision rather than an adaptive
sign-correctness guarantee.

It may still be useful as an intermediate filter.

---

## References

- Jonathan Richard Shewchuk,
  *Robust Adaptive Floating-Point Geometric Predicates*,
  Symposium on Computational Geometry, 1996.
- Jonathan Richard Shewchuk,
  *Adaptive Precision Floating-Point Arithmetic and Fast Robust
  Predicates for Computational Geometry*,
  Discrete & Computational Geometry, 1997.
- CGAL filtered kernels and filtered predicates.
- GEOS / JTS robust orientation algorithms.
- Boost.Geometry Cartesian orientation strategies.
- D standard library and runtime numerical facilities.

## Implementation status

As of 2026-09-09, the orientation predicate described by this ADR is
implemented for:

~~~text
int
long
float
double
~~~

The implementation satisfies the following domain contracts.

### Integral coordinates

`int` and `long` orientation are exact over their complete respective
coordinate domains.

Signed coordinate differences are formed without signed overflow.
Product magnitudes are represented exactly, and only the determinant
sign is determined; the potentially one-bit-wider signed determinant
does not need to be materialised.

### `float`

Every finite binary32 value is exactly representable as binary64.

`Point2!float` orientation therefore promotes coordinates exactly to
the binary64 robust backend. This promotion does not weaken predicate
correctness.

### `double`

Finite binary64 inputs are handled by a staged robust backend:

~~~text
certified floating-point filter
        ↓ uncertain
exact expansion arithmetic
        ↓ outside conservative expansion working range
exact fixed-width dyadic fallback
~~~

The final fallback decodes each finite binary64 coordinate exactly as
an integer multiple of `2^-1074` and evaluates the orientation sign
using fixed-width integer arithmetic.

This fixed-width dyadic representation is an internal implementation
choice. The architectural contract remains exact sign correctness for
the supported predicate domain.

NaN and infinity remain outside the floating orientation predicate
domain.

### `real`

A public `Point2!real` orientation overload remains deliberately
unimplemented.

`real` must not be demoted to `double`. A future implementation must
provide a backend appropriate to the actual platform representation
and must demonstrate the same sign-correctness contract.

### Independent verification

Production orientation implementations are checked in unittest builds
against an independent `std.bigint.BigInt` determinant oracle.

The oracle tests cover scalar extremes, arbitrary finite floating-point
bit patterns, subnormal values, near-degenerate configurations and
orientation permutation identities.

`BigInt` is not a runtime dependency of `geo-d`.
