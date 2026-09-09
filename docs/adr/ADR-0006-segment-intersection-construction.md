# ADR-0006 — Segment intersection construction

- Status: Accepted
- Date: 2026-09-09
- Implementation status: Implemented and verified
- Implementation verified: 2026-09-10

## Context

ADR-0005 defines exact topological classification of two closed
segments:

~~~d
SegmentIntersectionKind segmentIntersectionKind(...);
~~~

with the results:

~~~text
none
point
overlap
~~~

Classification deliberately does not construct the intersection
geometry.

That separation is necessary because topological predicates and
geometric construction have different numerical requirements.

For example, two integral segments may intersect at:

~~~text
(1/2, 1/2)
~~~

The topology is exactly:

~~~text
point
~~~

but that point cannot be represented as `Point2!int`.

More generally, even when all input coordinates are exactly
representable binary floating-point values, a proper line intersection
may contain division and therefore need not itself be a dyadic rational.

Consequently, exact predicate semantics do not imply that an exact
intersection coordinate can be returned in one of the existing
`geo-d` scalar types.

---

## Decision

### 1. Classification remains the authoritative topology API

`segmentIntersectionKind()` remains the operation used when a caller
needs to know whether two segments:

- do not intersect;
- intersect in exactly one point;
- overlap along a segment of positive length.

Constructed coordinates must not be used as a replacement for this
classification.

In particular, a caller must not infer topology by computing a rounded
intersection point and testing whether it appears to lie inside both
segments.

---

## 2. Point construction and overlap construction are separate

The implemented construction API does not introduce one heterogeneous
result object containing all possible intersection geometry.

Instead, two focused operations are provided:

~~~d
bool trySegmentIntersectionPoint(T, R)(
    Segment2!T first,
    Segment2!T second,
    out Point2!R point
)
if (
    isIntersectionScalar!T &&
    is(R == IntersectionScalar!T)
);
~~~

and:

~~~d
bool trySegmentIntersectionOverlap(T)(
    Segment2!T first,
    Segment2!T second,
    out Segment2!T overlap
);
~~~

The separately deduced result scalar `R` is an implementation detail
required by D template argument deduction. The constraint enforces the
semantic API decided here:

~~~text
R == IntersectionScalar!T
~~~

The semantic separation between unique-point construction and overlap
construction is unchanged.

---

## 3. Point construction succeeds only for a unique-point intersection

`trySegmentIntersectionPoint()` returns `true` exactly when:

~~~text
segmentIntersectionKind(first, second)
==
SegmentIntersectionKind.point
~~~

It returns `false` for:

~~~text
none
overlap
~~~

Therefore:

~~~text
true
    exactly one geometric intersection point exists

false
    there is either no intersection or more than one intersection point
~~~

The operation does not use `false` to represent ordinary floating-point
rounding.

For valid supported finite inputs, every unique mathematical
intersection has a representable rounded construction result in the
chosen floating result domain.

---

## 4. Point construction is a numerical construction, not a predicate

The point returned by `trySegmentIntersectionPoint()` is a numerical
approximation to the unique mathematical intersection.

Its coordinates are rounded according to the result scalar type.

The operation does not promise an exact algebraic representation of a
proper intersection.

This distinction is intentional:

~~~text
segmentIntersectionKind
    exact topological decision

trySegmentIntersectionPoint
    rounded geometric construction
~~~

The construction result must never feed back into robust topology
decisions as if it were exact.

---

## 5. Point result scalar

The initial construction scalar policy is:

~~~text
input scalar     point result scalar

int              double
long             double
float            double
double           double
real             deferred
~~~

Define conceptually:

~~~d
template IntersectionScalar(T)
{
    alias IntersectionScalar = double;
}
~~~

for the initially supported input domains.

The actual implementation may express this through an alias template
or equivalent compile-time machinery.

A separate intersection-construction scalar policy is preferred over
silently assuming that the metric scalar policy and construction scalar
policy must always remain identical.

---

## 6. Why integral point construction returns `double`

Returning `Point2!T` for integral `T` would be incorrect because a
proper intersection need not have integral coordinates.

Automatically rounding back to an integer would silently change the
constructed geometry.

A general exact rational coordinate type is not introduced at this
stage because that would require additional public numerical machinery,
including decisions about:

- arbitrary-width integer representation;
- normalization;
- equality;
- arithmetic;
- conversions;
- serialization;
- interoperability.

Such a type may be justified later by more than one concrete consumer,
but segment intersection alone is not sufficient reason to introduce a
general-purpose rational-number subsystem into `geo-d`.

---

## 7. Why floating point construction also returns `double`

Every finite binary32 coordinate is exactly representable as binary64.

Using `double` for `float` input therefore preserves all input
information before the intersection calculation.

For `double` input, construction remains in binary64.

The result may still be rounded because line intersection normally
contains division.

This is a construction accuracy issue, not a topology issue.

---

## 8. `real` remains deferred

`real` point construction is not introduced in the initial API.

This is consistent with the current robust-predicate policy.

A future `real` implementation must consider the actual platform
representation and should be designed together with the future robust
`real` orientation backend.

The initial API must not silently demote `real` inputs to `double`.

---

## 9. Endpoint and degenerate intersections

Not every unique intersection requires solving two lines.

When the unique intersection is already represented by an input
endpoint, construction should use that known point directly.

This includes:

- shared endpoints;
- one endpoint lying on the other segment;
- a degenerate segment lying on the other segment;
- two identical degenerate segments.

The endpoint is converted to `IntersectionScalar!T`.

For `float`, conversion to `double` is exact.

For `int` and `long`, conversion to `double` may lose integer precision
for sufficiently large values. This is part of the documented rounded
construction contract.

The topological classification remains exact regardless of that
conversion.

---

## 10. Proper crossing construction

A proper crossing is constructed without evaluating a rounded
floating-point line parameter or a naive unscaled floating-point
determinant.

For segment `AB` intersecting `CD`, the implementation computes the
exact dyadic orientation determinants:

~~~text
dA = orient(C, D, A)
dB = orient(C, D, B)
~~~

For a proper crossing their signs are opposite. Their exact magnitudes
define barycentric weights on `AB`:

~~~text
wA = |dB|
wB = |dA|
~~~

and therefore:

~~~text
P =
    wA * A + wB * B
    ----------------
        wA + wB
~~~

All coordinates, differences, products, determinant magnitudes,
weighted numerators and the common denominator are represented with
bounded fixed-width exact integer arithmetic.

The common dyadic scale cancels algebraically. No rounded
floating-point segment parameter is formed.

Each final coordinate is represented internally as:

~~~text
signed exact numerator
---------------------- * 2^-1074
positive denominator
~~~

and converted to binary64 using an explicit integer-arithmetic
round-to-nearest, ties-to-even algorithm.

This construction therefore avoids intermediate floating-point
overflow and underflow throughout the supported finite binary64 input
domain.

The implementation specifically verifies the motivating case where a
binary64 segment parameter would underflow to zero although the final
intersection coordinate remains normally representable.

---

## 11. Construction must reuse exact classification

The implementation must determine the geometric case using
`segmentIntersectionKind()` or equivalent shared robust internal logic.

It must not implement a second approximate intersection classifier.

Conceptually:

~~~text
kind = segmentIntersectionKind(first, second)

kind == none
    -> no point

kind == overlap
    -> no unique point

kind == point
    -> identify endpoint case
       or construct proper crossing
~~~

This prevents divergence between topological and construction
semantics.

---

## 12. Overlap construction is exact in the input scalar type

A collinear positive-length overlap has endpoints selected from the
original four segment endpoints.

No new coordinate needs to be numerically constructed.

Therefore overlap construction can preserve the original scalar type:

~~~d
bool trySegmentIntersectionOverlap(T)(
    Segment2!T first,
    Segment2!T second,
    out Segment2!T overlap
);
~~~

When it returns `true`, the returned overlap geometry is exact with
respect to the represented input coordinates.

---

## 13. Overlap construction succeeds only for positive-length overlap

`trySegmentIntersectionOverlap()` returns `true` exactly when:

~~~text
segmentIntersectionKind(first, second)
==
SegmentIntersectionKind.overlap
~~~

It returns `false` for:

~~~text
none
point
~~~

A zero-length common part is therefore never returned as a segment.

Such an intersection belongs to the unique-point operation.

---

## 14. Canonical overlap endpoint order

The returned overlap segment uses canonical lexicographic endpoint
ordering.

Conceptually:

~~~text
overlap.a <= overlap.b
~~~

under the same exact lexicographic point ordering used for collinear
classification:

~~~text
first compare x
then y when x is equal
~~~

This gives deterministic output independent of:

- argument order;
- endpoint order of the first input segment;
- endpoint order of the second input segment.

Therefore all equivalent input representations yield the same overlap
segment.

---

## 15. No tolerance is introduced

Neither construction operation introduces a geometric epsilon.

Topology is still determined by the robust predicate layer.

A numerical construction algorithm may naturally incur floating-point
rounding in the returned point, but that rounding must not be
reinterpreted as tolerance-based topology.

There remains no core-library rule equivalent to:

~~~text
distance < epsilon
    means intersection
~~~

---

## 16. Result-point limitations are explicit

For a proper crossing, the returned `Point2!double` is the rounded
binary64 representation of the constructed intersection.

The API does not guarantee that subsequent exact floating comparisons
will observe:

~~~text
orientation(first.a, first.b, point)
==
Orientation.collinear
~~~

or:

~~~text
orientation(second.a, second.b, point)
==
Orientation.collinear
~~~

because the mathematically exact intersection may not itself be
representable as binary64.

Likewise, the rounded point may lie microscopically outside a closed
segment according to exact predicate semantics.

Callers requiring topology must retain and use
`segmentIntersectionKind()`.

This limitation is inherent in rounded coordinate construction and must
be documented rather than hidden behind an implicit tolerance.

---

## 17. No public rational type yet

This ADR deliberately does not introduce:

~~~text
Rational
BigRational
ExactPoint2
RationalPoint2
HomogeneousPoint2
~~~

into the public API.

An exact rational construction API may be considered later if concrete
use cases demonstrate sufficient value.

Such an API would require its own numerical-design ADR.

The internal implementation is free to use exact arithmetic for
validation or intermediate decisions without exposing it publicly.

---

## 18. No unified intersection result initially

The initial construction API does not introduce:

~~~d
struct SegmentIntersection(T)
{
    SegmentIntersectionKind kind;
    ...
}
~~~

A unified result would immediately encounter incompatible payload
semantics:

~~~text
none
    no geometry

point
    rounded Point2!double

overlap
    exact Segment2!T
~~~

Keeping focused operations avoids:

- awkward tagged-union storage;
- mixed scalar ownership;
- implicit precision expectations;
- coupling simple classification to construction machinery.

A unified convenience API may be considered later if actual callers
demonstrate that it improves usability.

---

## 19. Symmetry and determinism

Topology remains exactly symmetric:

~~~text
kind(a, b) == kind(b, a)
~~~

Overlap construction is exactly symmetric because the result is
canonicalized.

Proper-crossing construction first derives the exact mathematical
intersection as rational fixed-width data and only then performs one
defined binary64 rounding operation per coordinate.

Equivalent representations of the same proper crossing therefore
produce the same correctly rounded binary64 point.

The verification suite checks bit-identical point construction under:

- argument order reversal;
- endpoint reversal of the first segment;
- endpoint reversal of the second segment;
- reversal of both segments.

Endpoint-based unique intersections are likewise deterministic because
the known geometric endpoint is converted directly to
`IntersectionScalar!T`.

---

## 20. Allocation and error model

The intended construction operations use only constant-size local
state.

The target contracts are:

~~~text
pure
nothrow
@safe
@nogc
~~~

No heap allocation is required for the initial rounded point or exact
overlap construction APIs.

The `bool` return communicates whether the requested geometric result
kind exists, not exceptional failure.

---

## 21. Complexity

Both construction operations are constant-time:

~~~text
time:   O(1)
space:  O(1)
~~~

Robust classification may enter exact fallback arithmetic internally,
but its storage remains bounded for the supported scalar domains.

---

## 22. Verification status for point construction

`trySegmentIntersectionPoint()` is implemented and its verification
suite covers at least:

- proper crossing at exactly representable coordinates;
- proper crossing at non-integral coordinates;
- proper crossing whose exact result is not binary64-representable;
- shared endpoint;
- endpoint on segment interior;
- degenerate point versus segment;
- equal degenerate segments;
- `none` returns `false`;
- `overlap` returns `false`;
- `int` inputs with fractional intersections;
- full-range `long` inputs;
- near-parallel floating segments;
- large finite binary64 exponents;
- very small finite binary64 exponents;
- argument-order symmetry;
- endpoint-reversal invariance.

Additional construction-specific verification covers:

- exact non-dyadic rational intersections such as `1/3`;
- correct binary64 round-to-nearest, ties-to-even behavior;
- the subnormal/normal boundary;
- signed zero behavior;
- the largest finite binary64 value;
- a segment parameter that underflows to zero although the final
  intersection coordinate remains normally representable;
- bit-identical construction under argument and endpoint reversal;
- classifier/construction consistency over deterministic geometry
  sweeps.

The exact construction backend itself supplies the rational reference
value before the final independently specified binary64 rounding step.

---

## 23. Verification requirements for overlap construction

Tests must cover:

- partial horizontal overlap;
- partial vertical overlap;
- positive-slope overlap;
- negative-slope overlap;
- complete containment;
- identical segments;
- reversed identical segments;
- argument-order symmetry;
- endpoint-reversal invariance;
- exact preservation of large integral coordinates;
- exact preservation of finite floating endpoint bit patterns;
- `none` returns `false`;
- unique-point contact returns `false`.

The returned segment must always be in canonical lexicographic endpoint
order.

---

## 24. Consequences

### Positive

- exact topology remains clearly separated from rounded construction;
- no artificial integer rounding is introduced;
- no general rational subsystem is required prematurely;
- overlap geometry remains exact;
- callers can request only the geometry they actually need;
- the existing robust predicate layer remains authoritative;
- APIs can remain allocation-free.

### Negative

- proper intersection coordinates are not exact in general;
- a caller needing exact rational coordinates needs a future API;
- two construction functions exist instead of one unified result;
- callers needing both topology and geometry may perform classification
  plus construction;
- `real` remains deferred.

These trade-offs are intentional.

---

## 25. Implementation structure

The implementation followed the intended independent construction
slices.

### Slice A — exact overlap construction

`trySegmentIntersectionOverlap()` selects overlap endpoints directly
from the represented input geometry.

No new coordinate is constructed and the result remains exact in the
input scalar type.

### Slice B — rounded unique-point construction

`trySegmentIntersectionPoint()` uses two paths:

~~~text
unique endpoint-based contact
    -> convert known endpoint to IntersectionScalar!T

proper interior/interior crossing
    -> exact dyadic determinants
    -> exact barycentric weights
    -> exact weighted rational coordinates
    -> correctly rounded binary64 coordinates
~~~

The main internal layers are:

~~~text
fixed_uint.d
    bounded fixed-width unsigned arithmetic

dyadic.d
    exact scalar decoding
    exact signed differences
    exact signed products
    exact product differences

orientation_dyadic.d
    exact orient2d determinant

intersection_exact.d
    exact proper-crossing rational construction

intersection_round.d
    correctly rounded rational-to-binary64 conversion
~~~

All production construction paths use bounded local storage and retain
the intended:

~~~text
pure
nothrow
@safe
@nogc
~~~

contracts.

