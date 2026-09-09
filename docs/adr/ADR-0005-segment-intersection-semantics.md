# ADR-0005 — Segment intersection semantics

- Status: Accepted
- Date: 2026-09-09

## Context

`geo-d` now provides a robust orientation predicate for the scalar
domains:

~~~text
int
long
float
double
~~~

The next topology-oriented primitive is segment-segment intersection.

A segment intersection is not adequately described by a single boolean.

Two closed segments may:

- be disjoint;
- meet at exactly one point;
- overlap along a segment of positive length.

The one-point case itself includes:

- a proper crossing;
- a shared endpoint;
- an endpoint lying in the interior of the other segment;
- two coincident degenerate segments;
- a degenerate segment lying on a non-degenerate segment.

A robust topology API must distinguish these cases without introducing
a numerical tolerance.

At the same time, topological classification and construction of the
actual intersection coordinate are numerically different problems.

For example, two `Segment2!int` values may intersect at:

~~~text
(1/2, 1/2)
~~~

which cannot be represented as `Point2!int`.

Therefore the first segment-intersection API must not conflate exact
classification with numerical construction of an intersection point.

---

## Decision

### 1. The first public operation is a classification predicate

The initial public result type is:

~~~d
enum SegmentIntersectionKind : ubyte
{
    none,
    point,
    overlap
}
~~~

The initial operation is conceptually:

~~~d
SegmentIntersectionKind segmentIntersectionKind(T)(
    Segment2!T a,
    Segment2!T b
);
~~~

for scalar types with a robust orientation backend.

The exact module and template spelling may follow the established
`geo-d` public-module conventions, but the semantic contract described
by this ADR is fixed.

---

## 2. Result semantics

### `none`

The two closed segments have no common geometric point.

Examples include:

- separated non-collinear segments;
- separated collinear segments;
- two distinct degenerate segments;
- a degenerate segment that does not lie on the other segment.

### `point`

The intersection contains exactly one geometric point.

This includes:

- a proper crossing;
- a shared endpoint;
- an endpoint touching the interior of the other segment;
- collinear segments whose closed intervals meet at exactly one point;
- a degenerate segment lying on the other segment;
- two identical degenerate segments.

### `overlap`

The intersection contains a line segment of positive geometric length.

This includes:

- partial collinear overlap;
- one non-degenerate segment wholly contained in the other;
- two identical non-degenerate segments;
- segments with reversed endpoint order that describe the same
  geometric segment.

`overlap` never denotes a zero-length intersection.

A zero-length common part is classified as `point`.

---

## 3. Segments are closed

`Segment2` represents the closed segment between endpoints `a` and `b`.

Both endpoints therefore participate in intersection.

Endpoint contact is not considered disjoint.

For example:

~~~text
A-------B
        C-------D
~~~

with `B == C` is classified as:

~~~text
point
~~~

---

## 4. Degenerate segments are valid

A segment with:

~~~text
segment.a == segment.b
~~~

is a valid zero-length segment representing one point.

No separate invalid state is introduced.

The following semantics apply.

### Point versus point

Equal points:

~~~text
point
~~~

Different points:

~~~text
none
~~~

### Point versus non-degenerate segment

Point lies on the closed segment:

~~~text
point
~~~

Otherwise:

~~~text
none
~~~

Degenerate segments therefore require no separate public result kind.

---

## 5. Collinear overlap is classified exactly

When both segments lie on the same supporting line, their overlap is
determined using exact endpoint ordering rather than projection through
floating-point arithmetic.

For finite coordinates, endpoints may be ordered lexicographically:

~~~text
first compare x
then compare y when x is equal
~~~

For a collinear set of points this defines a consistent linear order
along the line.

For each segment, normalize its endpoints conceptually as:

~~~text
lower = lexicographically smaller endpoint
upper = lexicographically larger endpoint
~~~

Then compute:

~~~text
lo = max(lower1, lower2)
hi = min(upper1, upper2)
~~~

The classification is:

~~~text
lo > hi    -> none
lo == hi   -> point
lo < hi    -> overlap
~~~

Only exact scalar comparisons are used.

No distance, projection, slope, division or epsilon is required.

---

## 6. Non-collinear classification uses robust orientation

The general classifier is built on the public robust orientation
predicate.

Conceptually evaluate:

~~~text
o1 = orientation(a.a, a.b, b.a)
o2 = orientation(a.a, a.b, b.b)
o3 = orientation(b.a, b.b, a.a)
o4 = orientation(b.a, b.b, a.b)
~~~

A proper crossing occurs when the endpoints of each segment lie on
opposite sides of the other segment's supporting line.

Boundary cases in which one orientation is `collinear` are handled as
closed point-on-segment cases.

When all relevant points are collinear, the exact collinear interval
classification described above is used.

The implementation must not calculate a floating determinant
independently of `orientation()`.

---

## 7. No epsilon defines intersection

`segmentIntersectionKind` must not use a global or implicit tolerance.

In particular, code equivalent to:

~~~text
abs(det) < epsilon
~~~

must not define collinearity or intersection.

For supported scalar domains, the result describes the mathematical
intersection of the represented coordinates.

Explicit approximate or tolerance-based intersection operations may be
introduced later under separate names and contracts if a concrete
consumer requires them.

---

## 8. Supported scalar domains

The initial classification operation follows the robust orientation
backend.

Supported:

~~~text
int
long
float
double
~~~

Deferred:

~~~text
real
~~~

Mixed scalar types are not accepted implicitly.

A caller that wants to intersect segments with different scalar types
must perform an explicit conversion according to the normal `geo-d`
conversion policy.

---

## 9. Floating-point domain

For `float` and `double`, every segment endpoint coordinate must be
finite.

NaN and infinity may remain representable by the underlying geometry
types, but they are outside the domain of the robust intersection
predicate.

This follows the same domain policy as floating-point orientation.

No fourth intersection result is introduced for invalid numerical
inputs.

The finite-input requirement is a predicate precondition.

---

## 10. Exact classification is separate from intersection construction

This ADR does not define an API that returns the coordinates of a
proper intersection.

In particular, it does not define:

~~~d
Point2!T intersectionPoint(...);
~~~

or:

~~~d
SegmentIntersection!T intersection(...);
~~~

The reason is numerical.

For integral input coordinates, the exact intersection point may be
rational and therefore not representable by the input scalar type.

For floating-point coordinates, construction of the point is a
measurement/construction operation whose rounding contract must be
defined separately from the topological predicate.

Therefore:

~~~text
segmentIntersectionKind
    exact topological decision

intersection-point construction
    separate future numerical API
~~~

A later ADR may define:

- the result scalar type;
- exact versus rounded construction;
- checked failure semantics;
- rational representation, if justified;
- overlap geometry construction.

None of those choices are fixed here.

---

## 11. No overlap geometry is returned initially

Although `overlap` means the common set contains a segment of positive
length, the initial classifier does not return that segment.

The overlap endpoints can be derived exactly from existing input
endpoints, but exposing overlap geometry would require a richer result
type and would couple classification to construction.

The first implementation deliberately keeps the API small.

A richer operation may be introduced later if demonstrated consumers
need the actual common geometry.

---

## 12. Endpoint order does not affect classification

`Segment2` itself retains ordered structural endpoint semantics:

~~~text
Segment2(a, b) != Segment2(b, a)
~~~

in general.

Intersection classification, however, is geometric.

Therefore reversing either segment must not change
`segmentIntersectionKind`.

Required invariant:

~~~text
kind(s1, s2)
==
kind(reverse(s1), s2)
==
kind(s1, reverse(s2))
==
kind(reverse(s1), reverse(s2))
~~~

The operation is also symmetric:

~~~text
kind(s1, s2) == kind(s2, s1)
~~~

---

## 13. Classification is allocation-free

The classifier requires only:

- four orientation decisions;
- endpoint comparisons;
- constant-size local state.

The intended implementation contract is therefore:

~~~text
pure
nothrow
@safe
@nogc
~~~

where supported by the existing component APIs.

No heap allocation or garbage-collector dependency is justified.

---

## 14. Complexity

Segment intersection classification is constant-time:

~~~text
time:   O(1)
space:  O(1)
~~~

The robust floating orientation backend may internally enter more
expensive exact fallback paths, but their storage requirements remain
bounded for the fixed binary32/binary64 domains.

---

## 15. Required tests

The implementation must cover at least the following cases.

### Proper crossing

~~~text
\ /
 X
/ \
~~~

Result:

~~~text
point
~~~

### Parallel non-collinear

Result:

~~~text
none
~~~

### Shared endpoint

Result:

~~~text
point
~~~

### Endpoint on other segment interior

Result:

~~~text
point
~~~

### Collinear disjoint

Result:

~~~text
none
~~~

### Collinear single-point contact

Result:

~~~text
point
~~~

### Partial collinear overlap

Result:

~~~text
overlap
~~~

### Complete containment

Result:

~~~text
overlap
~~~

### Identical non-degenerate segments

Result:

~~~text
overlap
~~~

### Reversed identical segments

Result:

~~~text
overlap
~~~

### Point against segment, on segment

Result:

~~~text
point
~~~

### Point against segment, outside segment

Result:

~~~text
none
~~~

### Equal point segments

Result:

~~~text
point
~~~

### Unequal point segments

Result:

~~~text
none
~~~

---

## 16. Property and invariant tests

Tests should verify:

~~~text
intersection(a, b) == intersection(b, a)
~~~

and invariance under reversal of either segment.

For non-degenerate proper crossings, the result must remain `point`
under all endpoint-order permutations.

For collinear cases, classification should be checked against an
independent one-dimensional interval oracle.

Floating-point tests should include:

- near-collinear configurations;
- subnormal coordinates;
- extreme finite binary64 coordinates;
- cases that drive orientation through its exact fallback paths.

---

## 17. Consequences

### Positive

- topology classification remains exact;
- no new epsilon policy is introduced;
- the robust orientation work is immediately reused;
- integer inputs do not force an artificial rounded intersection point;
- degenerate geometry has explicit semantics;
- overlap is represented without prematurely designing a complex result
  object;
- the implementation remains small and allocation-free.

### Negative

- callers that need the actual intersection coordinate require a later
  API;
- callers that need the actual overlap segment require a later API;
- `real` remains unsupported until its robust orientation backend is
  defined.

These limitations are intentional.

---

## 18. Next implementation slice

The next implementation slice is limited to:

~~~text
SegmentIntersectionKind
segmentIntersectionKind(...)
~~~

for:

~~~text
int
long
float
double
~~~

No intersection-coordinate construction is part of that slice.

The implementation should reuse `orientation()` and exact endpoint
ordering and should introduce no additional numerical predicate
machinery.
