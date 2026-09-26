# ADR-0022: Line2 semantics and exact-coordinate architecture

**Status:** Accepted

**Date:** 2026-09-26

## Context

`geo-d` v2.0.0 is the current stable API baseline.

New public geometry functionality is admitted only from concrete consumer
requirements or sufficiently strong research evidence.

OSM-editor research identified two operations that require an unbounded
Euclidean two-dimensional line rather than a bounded `Segment2`:

- projecting a point onto the line through two points;
- constructing the unique intersection point of two unbounded lines.

JOSM's Align Nodes in Line workflow and iD straightening behaviour provide
concrete examples of the first requirement. Line/line construction is also
needed where corresponding unbounded support lines must be intersected.

These operations belong to coordinate-system-agnostic Euclidean geometry and
therefore fit the scope of `geo-d`.

The research was tracked in GitHub issue #27 and promoted into the design gate
in issue #28.

Several questions required explicit decisions before production
implementation:

- whether a line should store two points or a point plus a direction;
- whether both construction forms can preserve the complete supported scalar
  domain;
- whether degenerate and non-finite line values can exist;
- whether ordinary value equality has useful geometric meaning;
- how parallel and coincident lines should be classified;
- how exact topology remains separate from rounded coordinate construction;
- how line-intersection coordinates outside finite binary64 range are handled;
- whether unbounded-line projection belongs to the existing
  `tryNearestPoint` family;
- whether metric `real` support must be preserved;
- whether the existing exact segment-intersection machinery contains
  geometry-neutral construction infrastructure that should be reused.

The resulting design must remain compatible with the established
`geo-d` / `geo3-d` API-family conventions without adding `Line3` merely for
symmetry.

## Decision

### 1. Add `Line2` as the unbounded Euclidean line value type

`Line2!T` represents an unbounded affine line in two-dimensional Euclidean
space.

The public type constraint is:

~~~d
struct Line2(T)
if (isGeoScalar!T);
~~~

It belongs in:

~~~text
geo.line
~~~

and supports the established general geo-d scalar domain:

~~~text
int
long
float
double
real
~~~

The type has two first-class public construction forms:

~~~d
Line2!T(a, b);
Line2!T(point, direction);
~~~

with constructor parameter names:

~~~text
point/point       a, b
point/vector      point, direction
~~~

Conceptually, the corresponding constructor declarations are:

~~~d
this(
    Point2!T a,
    Point2!T b
)
    pure nothrow @safe @nogc;

this(
    Point2!T point,
    Vector2!T direction
)
    pure nothrow @safe @nogc;
~~~

Both constructors are direct and infallible over the represented scalar
values.

They do not validate that the resulting line is finite or nondegenerate.

This follows the existing geo-d distinction between representation and
validation/operation preconditions.

### 2. The internal representation preserves the caller's source form

Neither four-scalar canonical representation can preserve both constructor
domains over the complete supported scalar set.

A two-point representation:

~~~text
Point2!T
Point2!T
~~~

cannot faithfully encode every point/vector input.

For example, with binary64:

~~~text
anchor    = (2^53, 0)
direction = (1, 1)
~~~

materializing `anchor + direction` produces a second point whose x increment
has rounded away.

For integral coordinates, a point plus direction may also require a second
point outside the representable range of `T`.

Conversely, a point/direction representation:

~~~text
Point2!T
Vector2!T
~~~

cannot faithfully encode every point/point input.

For example:

~~~text
a.x = long.min
b.x = long.max
~~~

has exact direction component:

~~~text
18446744073709551615
~~~

which is not representable as `long`.

`Line2!T` therefore uses a private tagged dual representation conceptually
equivalent to:

~~~text
anchor Point2!T
+
union
{
    secondPoint Point2!T
    direction   Vector2!T
}
+
private representation tag
~~~

The representation supplied by the caller is preserved without destructive
canonicalization.

The tag is an implementation detail and is not public geometry state.

A2 deliberately exposes no representation-dependent public accessor such as:

~~~text
anchor
secondPoint
direction
storageForm
~~~

The two construction forms are public semantics; the retained PP/PV storage
form is not.

Future observations must be justified by their own consumer semantics rather
than by the current private layout.

### 3. The representation-size cost is accepted

The representation probe measured the following layouts on the tested x86_64
DMD and LDC ABI:

~~~text
T          PP/PV canonical     tagged dual

int        16 B                20 B
long       32 B                40 B
float      16 B                20 B
double     32 B                40 B
real       64 B                80 B
~~~

The measured cost is 25 percent relative to either four-scalar canonical
representation.

This cost is accepted because it preserves both valid construction domains
without:

- lossy scalar conversion;
- overflow-prone canonicalization;
- hidden allocation;
- fallible construction caused solely by internal storage choice.

No portable spare scalar state is reserved for encoding the representation
tag.

### 4. `Line2.init` is deterministic, finite, and degenerate

Default initialization remains a valid representable value.

~~~text
Line2!T.init
~~~

is:

- deterministic;
- finite;
- degenerate.

This provides an inert default state without pretending that the value
defines a usable mathematical line.

The public representation-independent observations are:

~~~text
line.isFinite
line.isDegenerate
~~~

They retain the candidate execution contract:

~~~text
pure
nothrow
@safe
@nogc
~~~

Degeneracy is exact.

No epsilon or tolerance defines whether a line direction is zero.

### 5. Ordinary equality is deliberately disabled

Two stored `Line2` values may define the same geometric line while differing
in:

- anchor point;
- direction magnitude;
- direction sign;
- point/point versus point/vector storage form.

For example, all of the following can describe the same mathematical line:

~~~text
p + t d
q + u d
p + v (-d)
two different point pairs on the same line
~~~

Research confirmed that, if no explicit equality declaration is provided, D
generates struct equality for the candidate `Line2` representation.

That generated equality follows stored representation rather than geometric
line identity.

The equality probe established:

~~~text
same PP storage             -> true
PP vs PV same geometry      -> false
shifted same geometry       -> false
reversed same geometry      -> false
~~~

Using compiler-generated equality would therefore expose a valid D operation
with the wrong domain meaning.

`Line2` consequently disables ordinary equality explicitly:

~~~d
@disable bool opEquals(ref const Line2 rhs) const;
~~~

This suppresses both:

~~~d
==
!=
~~~

while preserving construction, `isFinite`, and `isDegenerate`.

The compile-negative equality contract was verified across all six controlled
DMD/LDC compiler configurations.

Geometric coincidence is instead represented by the exact
`lineIntersectionKind` classification.

No separate approximate or representation-equality API is introduced by A2.

### 6. Exact line relationship classification is a topology operation

The public classification type is:

~~~d
enum LineIntersectionKind : ubyte
{
    none,
    point,
    coincident,
}
~~~

The public operation is:

~~~d
LineIntersectionKind lineIntersectionKind(T)(
    Line2!T first,
    Line2!T second
)
    pure nothrow @safe @nogc
if (isIntersectionScalar!T);
~~~

The accepted parameter names are:

~~~text
first
second
~~~

The result semantics are:

~~~text
none
    the two valid unbounded lines are distinct and parallel

point
    the two valid unbounded lines contain exactly one common point

coincident
    the two values describe the same unbounded geometric line
~~~

The robust scalar domain follows `IntersectionScalar`:

~~~text
int
long
float
double
~~~

`real` is excluded according to the robust-real policy in ADR-0016.

### 7. Classification requires finite, nondegenerate lines

`lineIntersectionKind` is a mathematical topology classifier, not a
validation API.

Its preconditions are:

~~~d
assert(first.isFinite);
assert(second.isFinite);
assert(!first.isDegenerate);
assert(!second.isDegenerate);
~~~

Non-finite and degenerate values are therefore not additional enum states.

In particular, the public enum does not contain states such as:

~~~text
invalid
degenerate
unknown
~~~

Validation and topology remain separate contracts.

### 8. Relationship classification is exact for its supported scalar domain

For each valid line, the implementation derives an exact internal direction
without converting the stored line to the other public representation.

For point/point storage:

~~~text
direction = exact(secondPoint - anchor)
~~~

where the differences are represented by the existing fixed-width dyadic
backend.

For point/vector storage, the stored vector components are decoded exactly.

For lines with anchors `p`, `q` and exact directions `d1`, `d2`:

~~~text
cross(d1, d2) != 0
    -> point

cross(d1, d2) == 0
and cross(q - p, d1) == 0
    -> coincident

otherwise
    -> none
~~~

These determinant decisions are evaluated exactly with the existing
fixed-width dyadic arithmetic.

The implementation must not materialize:

- a same-`T` vector from a PP line when the exact difference does not fit;
- a second same-`T` point from a PV line when that point is not representable.

### 9. The public classifier is required by topology/construction separation

Early A2 research considered keeping the three-way classifier private.

Later construction research established a reason for public classification.

Two valid unbounded lines can have an exact unique intersection point whose
coordinate lies outside the finite range of the public construction result.

In that case:

~~~text
lineIntersectionKind(...) == LineIntersectionKind.point
~~~

remains mathematically correct, while coordinate construction must fail.

A construction-only API would otherwise collapse at least two materially
different conditions:

~~~text
no unique intersection exists

unique intersection exists,
but its rounded public coordinate is not finite
~~~

The public classifier therefore preserves the established geo-d distinction:

~~~text
topological answer
    !=
constructed coordinate
~~~

### 10. Unique line-intersection construction is a separate fallible operation

The accepted public construction API is:

~~~d
bool tryLineIntersectionPoint(T, R)(
    Line2!T first,
    Line2!T second,
    out Point2!R point
)
    pure nothrow @safe @nogc
if (
    isIntersectionScalar!T &&
    is(R == IntersectionScalar!T)
);
~~~

The accepted parameter names are:

~~~text
first
second
point
~~~

The operation has the same finite/nondegenerate line preconditions as
`lineIntersectionKind`.

It returns `true` exactly when:

1. the exact topology classification is `point`; and
2. both exact intersection coordinates round to finite values in
   `Point2!(IntersectionScalar!T)`.

It returns `false` for:

- distinct parallel lines;
- coincident lines;
- a mathematically unique intersection whose public rounded coordinate is not
  finite.

Every `false` path leaves:

~~~d
point == Point2!R.init
~~~

The authoritative topology answer is not inferred from the rounded
construction.

### 11. Line-intersection construction is exact before final rounding

For exact-supported scalar inputs, write the two lines as:

~~~text
first  = p + t d1
second = q + u d2
~~~

For a unique intersection:

~~~text
den  = cross(d1, d2)
tNum = cross(q - p, d2)
t    = tNum / den
~~~

Each coordinate is constructed from the exact rational expression:

~~~text
x = (p.x * den + d1.x * tNum) / den
y = (p.y * den + d1.y * tNum) / den
~~~

The denominator sign is normalized positive.

The existing dyadic representation expresses finite binary32/binary64 and
integral coordinates in a common exact scale.

The established width proof gives:

~~~text
coordinate/difference domain     66 limbs
dyadic products                  132 limbs
coordinate numerator             198 limbs
~~~

A 198-limb numerator provides 6336 bits.

The conservative A2 construction bound remains below `2^6299`, leaving at
least 37 bits of storage headroom.

The numerator has scale `2^-3222`, the denominator has scale `2^-2148`, so
their ratio is naturally interpreted as:

~~~text
numerator / denominator * 2^-1074
~~~

which matches the existing exact binary64 coordinate-rounding model.

No floating-point arithmetic participates before the final rounding step.

### 12. Unbounded projection extends the existing `tryNearestPoint` family

Point projection onto a line is exposed as an overload of the existing
metric-family operation:

~~~d
bool tryNearestPoint(T, R)(
    Line2!T line,
    Point2!T point,
    out Point2!R result
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
);
~~~

The accepted parameter names are:

~~~text
line
point
result
~~~

The operation belongs in:

~~~text
geo.metric
~~~

rather than introducing a second spelling such as:

~~~text
projectPoint
project
~~~

This preserves the existing geometry-first argument order:

~~~d
tryNearestPoint(line, point, result);
line.tryNearestPoint(point, result);
~~~

and follows the UFCS conventions established by ADR-0019 and the workspace D
practices.

### 13. Line projection preserves the complete metric scalar domain

The public scalar policy remains the established `MetricScalar` policy:

~~~text
input      result

int        double
long       double
float      double
double     double
real       real
~~~

Line projection is a numerical metric construction, not a robust topology
predicate.

Supporting `real` is therefore part of the established metric-family
contract.

The new overload must not narrow the public scalar domain merely because the
existing exact dyadic backend currently excludes `real`.

### 14. Projection uses a hybrid numerical implementation

For:

~~~text
int
long
float
double
~~~

line projection uses exact dyadic rational construction followed by one
correctly-rounded binary64 conversion per coordinate.

For:

~~~text
real
~~~

line projection uses a scaled `MetricScalar!real` floating implementation.

Conceptually:

~~~text
int/long/float/double
    exact represented input
        -> exact direction and point offset
        -> exact dot products
        -> exact rational coordinate numerator/denominator
        -> finite-result test
        -> one correctly-rounded binary64 conversion

real
    scaled MetricScalar!real arithmetic
        -> finite-result validation
~~~

This asymmetry is deliberate.

It preserves the public metric contract while using the stronger exact backend
where its representation has been proven.

For `int`, `long`, `float`, and `double`, exact-before-round construction is a
specific implementation requirement of this `Line2` overload because research
demonstrated a concrete finite-input failure in the ordinary floating
construction path.

This stronger implementation does not redefine `MetricScalar`, does not make
other metric-family operations exact-before-round, and does not turn
`tryNearestPoint(Line2, ...)` into a topology predicate.

It does not imply robust topology support for `real`.

### 15. Exact-before-round projection is justified by a concrete failure

A purely floating projection implementation was investigated, including
vector-wide and per-component exponent scaling.

Per-component exponent scaling solves important overflow, underflow, and
mixed-scale cases, but it cannot recover information already lost by rounded
floating products.

A concrete binary64 counterexample used:

~~~text
D = 2^53

a = (D - 20) / D
b = (D - 18) / D
c = (D - 19) / D
~~~

Mathematically:

~~~text
a * b - c * c = -1 / D^2 = -2^-106
~~~

but ordinary binary64 multiplication yields equal rounded products for this
case.

For a line with direction:

~~~text
(a, c)
~~~

and query offset:

~~~text
(b, -c)
~~~

the resulting projection is non-zero.

The floating candidate lost that result.

The exact dyadic candidate preserved it and produced the independently
verified correctly-rounded coordinate.

This is negative evidence against using scaling alone as the binary64
projection contract.

### 16. Projection failure semantics differ deliberately from the topology API

`tryNearestPoint(Line2, Point2, result)` returns `false` when:

- the line contains a non-finite represented component;
- the query point is non-finite;
- the line is degenerate;
- the required successful constructed result is not finite.

Every failure path leaves:

~~~d
result == Point2!R.init
~~~

A degenerate `Segment2` can still have a meaningful nearest point: its
endpoint.

A degenerate `Line2` does not define an unbounded supporting line.

The line overload therefore does not inherit the segment overload's
degenerate-endpoint behaviour.

### 17. Exact-coordinate construction infrastructure becomes geometry-neutral

Existing segment-intersection construction already contains internal machinery
whose mathematical contract is not specific to segments.

A2 establishes genuine second-use evidence for that machinery.

The geometry-neutral internal layer owns concepts equivalent to:

~~~text
198-limb exact coordinate numerator magnitude
signed exact coordinate numerator
signed numerator addition/subtraction/negation
dyadic coordinate × dyadic product
dyadic difference × dyadic product
finite binary64 range decision for an exact rational coordinate
correctly-rounded exact rational coordinate -> binary64
~~~

The intended internal layering is:

~~~text
geo.internal.fixed_uint
        |
        v
geo.internal.dyadic
        |
        v
geometry-neutral exact-coordinate construction
        |
        +-------------------------+
        |                         |
        v                         v
segment-specific             Line2-specific
construction                 construction
~~~

Internal module names may evolve without public compatibility consequences.

The intended implementation may use names such as:

~~~text
geo.internal.exact_coordinate
geo.internal.exact_coordinate_round
~~~

but those module names are not public API commitments.

### 18. Segment-specific construction remains segment-specific

The following concepts remain in the segment-intersection implementation:

~~~text
ExactProperIntersection
proper-crossing barycentric construction
Segment2-specific orientation relationships
segment-specific endpoint/contact handling
~~~

In particular, the exact proper-segment intersection formula:

~~~text
(|dB| A + |dA| B) / (|dB| + |dA|)
~~~

is not generalized into a fake geometry-neutral abstraction.

The common layer provides arithmetic mechanisms, not a generic
"intersection object".

### 19. Internal reuse does not justify a new public or shared package

The exact-coordinate layer remains private to `geo-d`.

It does not belong in `euclid-core-d` merely because more than one algorithm
inside `geo-d` uses it.

ADR-0020 admits declarations to `euclid-core-d` when common public declaration
identity between `geo-d` and `geo3-d` is required.

That condition is not established here.

This ADR therefore does not add:

- public arbitrary-precision types;
- public exact rational coordinate types;
- new `euclid-core-d` declarations;
- a new workspace-level common numerical package.

### 20. `real` robust topology remains deferred

This ADR does not alter ADR-0016.

The general geometry and metric scalar domain remains:

~~~text
int
long
float
double
real
~~~

The current robust/exact topology domain remains:

~~~text
int
long
float
double
~~~

`Line2!real` is a valid representable line type.

`tryNearestPoint(Line2!real, ...)` is part of the metric family.

The exact line topology and line-intersection construction APIs remain
unavailable for `real` until a separate consumer-driven, platform-aware robust
backend is researched and verified.

No conversion from `real` to `double` is permitted to simulate such support.

### 21. Public operation ownership

The accepted public ownership is:

~~~text
geo.line
    Line2

geo.intersection
    LineIntersectionKind
    lineIntersectionKind
    tryLineIntersectionPoint

geo.metric
    tryNearestPoint(Line2, Point2, result)
~~~

The root `geo` package may re-export these declarations according to the
existing public package policy.

No representation tag or exact-arithmetic implementation type is public.

### 22. The 2D/3D family implication is intentionally limited

`Line2` follows the established dimension-explicit type naming convention.

A future `geo3-d` consumer may independently justify:

~~~text
Line3
~~~

and shared operation vocabulary where the mathematics genuinely matches.

This ADR does not authorize `Line3`, does not require simultaneous 3D
implementation, and does not move `LineIntersectionKind` into
`euclid-core-d`.

Three-dimensional line relationships also require their own consumer and
semantic review.

The family rule remains:

~~~text
symmetry where the mathematics is symmetric;
specialization where it is not
~~~

## Evidence

### Consumer evidence

A2 derives from concrete OSM-editor geometry workflows requiring unbounded
projection and line/line intersection rather than bounded-segment behaviour.

The research history and intermediate decisions are recorded in GitHub issue
#27.

The design promotion is tracked in GitHub issue #28.

### Representation evidence

The research compared:

- two-point storage;
- point-plus-direction storage;
- private tagged dual storage.

It demonstrated concrete loss of representability in both canonical
four-scalar alternatives and measured the tagged representation's x86_64
layout cost.

### Exact relationship evidence

The exact relationship probe covered:

- PP/PP;
- PP/PV;
- PV/PP;
- PV/PV;
- crossing;
- distinct parallel;
- coincident;
- degenerate cases;
- full-range integral differences;
- the binary64 `2^53` representability boundary;
- subnormal inputs;
- near-parallel one-ULP cases.

The exact dyadic backend was sufficient for all supported robust scalar types.

### Line-intersection construction evidence

The construction probe established:

- exact line/line rational construction;
- the 198-limb numerator width bound;
- finite-binary64 overflow-boundary behaviour;
- correct use of the existing rational coordinate rounder.

### Projection evidence

Research evaluated:

- the existing segment nearest-point scaling strategy;
- vector-wide scaling;
- per-component exponent-aware scaling;
- mixed-scale extreme values;
- near-cancellation;
- product-rounding cancellation;
- exact dyadic projection;
- the hybrid `real`/non-`real` scalar policy.

The original floating candidate is retained as negative evidence because it
fails the product-rounding cancellation regression.

The exact and hybrid candidates pass that case.

### Equality evidence

A dedicated equality probe first established that D's compiler-generated
struct equality is available for the tagged-dual `Line2` candidate but does
not represent geometric equality.

A second compile probe added:

~~~d
@disable bool opEquals(ref const Line2 rhs) const;
~~~

and verified that:

- both `Line2 == Line2` and `Line2 != Line2` are compile-negative;
- both public construction forms remain available;
- `isFinite` remains available;
- `isDegenerate` remains available.

The disabled-equality probe passed the complete controlled compiler matrix.

Frozen probe SHA-256 values:

~~~text
source/app.d
7a894f2d4fe8fc11dd2960ff0e444801b07b808175eaa9516dd8727875e7d13f

dub.json
075634b4b8274a76913f86ad2fedd2c2537699d0fbabf1a3271146b0af7fe216
~~~

### Controlled compiler matrix

The accepted candidate API and numerical paths were verified across:

~~~text
DMD 2.111.0
DMD 2.112.1
DMD 2.113.0

LDC 1.41.0
LDC 1.42.0
LDC 1.43.0
~~~

The final hybrid projection candidate passed all six controlled compiler
configurations.

Its frozen SHA-256 was:

~~~text
6043b700bcb189a3d81e9caabc9b98e47a1b2a647ff9ad1f8eb852714cbaa095
~~~

The final hybrid test application was byte-identical to the earlier floating
probe application that exposed the product-rounding regression. Only the
candidate implementation changed.

## Consequences

### Positive

- `geo-d` gains the smallest consumer-backed unbounded-line abstraction.
- Both natural construction forms preserve caller scalar data.
- Topology remains exact for the established robust scalar domain.
- Exact topology remains independent of coordinate representability.
- Unique line intersections outside finite binary64 range are not
  misclassified as topologically absent.
- Projection remains part of the established `tryNearestPoint` family.
- `real` retains its existing metric support.
- Exact-before-round projection removes a demonstrated binary64 cancellation
  defect for supported exact scalars.
- Segment and Line2 construction can share genuinely geometry-neutral exact
  coordinate machinery.
- Internal reuse does not enlarge the public API or shared-core contract.
- The implementation can remain allocation-free and `@nogc`.

### Costs and limitations

- `Line2` has a measured 25 percent representation-size premium on the tested
  x86_64 ABI.
- Operations branch on a private representation tag.
- Exact line construction requires fixed-width wide-integer arithmetic.
- Projection has two numerical implementation paths because portable robust
  `real` support is not available.
- Ordinary `Line2` equality is unavailable.
- Robust line topology remains unavailable for `real`.
- Exact rational construction is more complex than textbook floating-point
  formulas.

These costs are accepted because they preserve the represented input domain
and the established geo-d numerical contracts.

## Alternatives considered

### Store only two points

Rejected because point/vector construction cannot be represented losslessly
over the full scalar domain.

### Store only point plus direction

Rejected because point/point construction can require a direction component
outside the source scalar range.

### Make one constructor fallible

Rejected because a mathematically valid line should not fail merely because an
arbitrary private canonical storage representation cannot encode it.

### Promote canonicalized representation to `MetricScalar`

Rejected because full-range integral information, particularly `long`
differences, can be lost before robust predicates use it.

### Give ordinary equality storage semantics

Rejected because representation equality is not geometric line coincidence.

### Use a global epsilon for parallelism or coincidence

Rejected because line relationship is topology.

### Keep the line classifier private

Rejected after construction research established that an exact unique
intersection may exist even when its public coordinate cannot be represented
as finite binary64.

The public classifier is required to keep that topological fact observable
without redefining construction failure.

### Let `tryLineIntersectionPoint` define intersection existence

Rejected because rounded-coordinate representability must not determine
topology.

### Add `projectPoint` as a separate public operation

Rejected because line projection is the same nearest-point concept already
represented by the `tryNearestPoint` family.

### Use the scaled floating projection for all scalars

Rejected because the product-rounding cancellation probe demonstrates a finite
binary64 case where scaling cannot recover the exact projection result.

### Exclude `real` from line projection

Rejected because projection is a metric operation and the established
`MetricScalar` family includes `real`.

### Extend the exact dyadic backend to `real` now

Deferred.

Such work requires separate platform-aware robustness research and is not
needed to satisfy the current metric contract.

### Keep exact-coordinate arithmetic named as segment intersection machinery

Rejected because A2 establishes a genuine independent Line2 use of the same
rational-coordinate representation and rounding mechanism.

### Move exact-coordinate machinery to `euclid-core-d`

Rejected because no common 2D/3D public declaration identity has been
established.

Implementation reuse inside one package is insufficient under ADR-0020.

### Add `Line3` simultaneously

Rejected.

API-family symmetry is not implementation authorization.

## Relationship to other decisions

ADR-0002 defines the core geometry and scalar model.

ADR-0004 separates numerical metric construction from robust topological
predicates and prohibits a global topology epsilon.

ADR-0005 and ADR-0006 establish segment-intersection classification and
construction semantics and provide the existing topology/construction
precedent.

ADR-0014 establishes explicit binary64 rounding discipline where numerical
proofs depend on defined rounding points. The exact rational coordinate
rounder used here is separate internal machinery but follows the same
principle that required rounding semantics must be explicit rather than
accidental compiler behaviour.

ADR-0016 defines the deliberate difference between the complete general/metric
scalar domain and the narrower current robust `real` policy.

ADR-0019 defines dimension-explicit geometry type names, dimension-neutral
operation names, free-function/UFCS conventions, and the independent
`geo-d` / `geo3-d` family relationship.

ADR-0020 limits `euclid-core-d` admission to contracts whose common public
declaration identity is genuinely required by both sibling libraries.

ADR-0021 confirms that metric operations remain distinct from robust topology
and that `MetricScalar` policy is not automatically an exact-predicate policy.

`docs/v2-api-conventions.md` defines the current public naming and UFCS grammar.

## Implementation gate

This ADR records the accepted A2 design.

It does not itself authorize unrelated line algebra or additional geometry
families.

Production implementation following this ADR must remain limited to the
consumer-backed A2 scope:

~~~text
Line2 value type
line relationship classification
unique line-intersection construction
point-to-line nearest-point projection
required internal exact-coordinate extraction
tests and public documentation for those contracts
~~~

Explicitly outside this gate remain:

- rays;
- offsets and buffers;
- generic `Direction2`;
- line-string aggregation;
- CRS or geodesic semantics;
- spatial indexing;
- editor selection/UI policy;
- `Line3`;
- robust `real` topology.

Production work must be tracked separately from research issue #27 and design
issue #28.
