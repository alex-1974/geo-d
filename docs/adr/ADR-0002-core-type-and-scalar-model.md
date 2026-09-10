# ADR-0002 — Core type and scalar model

**Status:** Accepted
**Date:** 2026-09-09

## Context

ADR-0001 establishes `geo-d` as a coordinate-reference-system-independent Euclidean geometry library with an explicitly two-dimensional initial scope.

The first foundational value types are:

```text
Point2
Vector2
Bounds2
Segment2
```

Before these types become public API, their scalar model, algebra, default state, conversion semantics, non-finite-value policy, equality semantics, and basic representation rules must be explicit.

These choices affect almost every later geometry algorithm. They therefore form part of the architectural contract rather than being left to incidental implementation decisions.

This ADR deliberately does not define:

- robust orientation predicates;
- exact or adaptive arithmetic;
- intersection robustness;
- algorithm-specific tolerances;
- ownership of variable-sized geometries;
- polygon or polyline representation;
- three-dimensional geometry.

Numerical robustness is addressed separately by ADR-0004. Aggregate geometry ownership is addressed by ADR-0003.

## Decision

### 1. Core scalar types

The initial `geo-d` scalar contract supports exactly the unqualified built-in D types:

```d
int
long
float
double
real
```

Accordingly, valid initial instantiations include:

```d
Point2!int
Point2!long
Point2!float
Point2!double
Point2!real
```

and the corresponding `Vector2`, `Bounds2`, and `Segment2` types.

The same scalar policy applies consistently to all four foundational geometry types.

### 2. Types deliberately excluded from the initial scalar contract

The following are not core geometry scalars in v0.1:

```text
byte
ubyte
short
ushort
uint
ulong
bool
char
wchar
dchar
enum types
cent / ucent
complex types
user-defined numeric types
qualified scalar types
```

The exclusion is deliberate.

#### `byte` and `short`

D promotes arithmetic on small integral types to `int`.

Allowing `Point2!short`, for example, would therefore create a public algebra in which ordinary operations change the geometry scalar type:

```text
Point2!short - Point2!short
    -> Vector2!int
```

This complicates operator consistency, particularly compound assignment, for limited practical benefit in the foundational value types.

Compact storage requirements should be addressed by appropriate storage or view abstractions rather than by distorting the mathematical core type algebra.

#### Unsigned integers

Euclidean vector displacement requires negative values.

For example:

```text
Point - Point -> Vector
```

cannot in general be represented by an unsigned scalar.

Attempting to repair this through implicit result widening produces an incomplete and increasingly complicated type algebra, particularly for `ulong`.

Unsigned coordinates are therefore outside the initial core scalar model.

#### User-defined numeric types

Supporting arbitrary fixed-point, rational, decimal, unit-aware, arbitrary-precision, or other numeric types would require defining a general numeric concept before concrete consumers demonstrate its requirements.

`geo-d` does not attempt this in v0.1.

Such support may be added later when justified by real use cases.

### 3. Type qualification

Scalar qualification is not part of the geometry template parameter.

This is not supported:

```d
Point2!(const int)
Point2!(immutable double)
```

Qualification applies to the complete geometry value instead:

```d
const(Point2!int)
immutable(Point2!double)
```

### 4. `real`

`real` is a supported scalar.

No public API may assume a particular byte size, alignment, binary layout, or excess precision for `real`.

Its platform-dependent representation must not become part of portable serialized or foreign-memory-layout contracts.

---

## Point and vector semantics

### 5. `Point2` is an affine point

`Point2!T` represents a position in a two-dimensional affine Euclidean space.

It is not a vector from an implicit origin.

The public API therefore does not provide general vector-space algebra for points.

### 6. `Vector2` is a displacement

`Vector2!T` represents a displacement in the underlying two-dimensional vector space.

Point and vector remain distinct public types even though both contain two scalar components.

There is no `alias this` relationship between them.

### 7. Fundamental affine algebra

For equal scalar type `T`, the following operations are part of the core algebra:

```text
Point2!T  + Vector2!T -> Point2!T
Vector2!T + Point2!T  -> Point2!T

Point2!T  - Vector2!T -> Point2!T
Point2!T  - Point2!T  -> Vector2!T

Vector2!T + Vector2!T -> Vector2!T
Vector2!T - Vector2!T -> Vector2!T

-Vector2!T             -> Vector2!T
```

These operations preserve the scalar type.

### 8. Deliberately unsupported point algebra

The following operations are not part of the public core algebra:

```text
Point + Point
-Point
Point * scalar
scalar * Point
Point / scalar
```

These expressions have no origin-independent affine meaning.

Scaling, reflection, or other transformations of points require an explicit transformation model rather than implicit vector-space semantics.

### 9. Same-scalar geometry operations

Binary operations between geometry values require equal scalar types in v0.1.

For example:

```d
Point2!int    + Vector2!int       // allowed
Point2!double - Point2!double     // allowed
```

but:

```d
Point2!int    + Vector2!double    // not allowed
Point2!float  - Point2!double     // not allowed
Vector2!int   + Vector2!long      // not allowed
```

Mixed geometry scalar types must be converted explicitly before the operation.

This prevents D's primitive arithmetic promotion rules from implicitly defining `geo-d` geometry semantics.

---

## Vector scaling

### 10. Scalar multiplication

Vector scaling may use a different supported scalar type.

Conceptually:

```d
Vector2!T * S
S * Vector2!T
```

is allowed when:

- `T` is a supported geometry scalar;
- `S` is a supported scalar;
- the scalar result type of the corresponding D multiplication is itself a supported geometry scalar.

The resulting vector uses that arithmetic result type.

Examples:

```d
Vector2!int    * int
    -> Vector2!int

Vector2!int    * double
    -> Vector2!double

Vector2!double * int
    -> Vector2!double
```

Scalar multiplication is therefore allowed to change the vector scalar type when the scalar operand explicitly requests such arithmetic.

This differs intentionally from geometry-to-geometry operations.

### 11. Scalar division

Vector division is available only when the resulting scalar type is floating point.

Examples:

```d
Vector2!double / int
    -> Vector2!double

Vector2!int / double
    -> Vector2!double
```

Integer-result division such as:

```d
Vector2!int(3, 5) / 2
```

is not part of the geometry API because silent truncation would make an apparently geometric scaling operation discard information.

Explicit integer quantisation may be introduced separately if justified.

### 12. Compound assignment

Compound geometry operators are available only where the operation preserves the left-hand scalar type.

Accordingly:

```d
p += v;
p -= v;

v += w;
v -= w;
```

are valid for equal scalar type `T`.

Scalar compound operations such as:

```d
v *= s;
v /= s;
```

are only available when their result scalar is exactly the existing vector scalar type.

A compound assignment never performs an implicit narrowing conversion.

---

## Conversion policy

### 13. No implicit conversion between geometry scalar types

Different instantiations do not implicitly convert.

For example:

```d
Point2!int p;

Point2!double q = p;   // not allowed
```

The same rule applies to `Vector2`, `Bounds2`, and `Segment2`.

This remains true even when the corresponding primitive conversion would normally be accepted by D.

### 14. Explicit conversion

Scalar conversion of geometry values must be requested explicitly.

The public conversion API must distinguish conversions according to their numerical semantics rather than silently applying arbitrary casts component by component.

The exact final helper names are API details, but the following semantic classes are required.

#### Direct explicit conversion

Conversions whose target range can represent all source values may use a simple explicit conversion operation.

Examples include:

```text
int   -> long
int   -> double
float -> double
```

Such a conversion does not necessarily promise exact preservation of every source value unless that property is separately documented.

#### Checked narrowing conversion

Conversions that can fail because the source value lies outside the target range must expose that possibility explicitly.

Examples include:

```text
long   -> int
double -> float
```

They must not silently wrap, overflow, or become an unrelated finite value.

#### Floating-point to integer conversion

Floating-point to integer conversion must express the quantisation rule explicitly.

The API must distinguish operations equivalent to:

```text
round
floor
ceil
truncate
```

A generic geometry conversion must not silently choose truncation merely because the D primitive cast does so.

Range and non-finite conditions must also be handled explicitly.

### 15. Mixed-scalar operations use explicit conversion

When two geometry values have different scalar types, the caller chooses the common representation.

Conceptually:

```d
Point2!double p2;
Vector2!double v2;

assert(p.tryConvert(p2));
assert(v.tryConvert(v2));

auto q = p2 + v2;
```

rather than relying on implicit geometry promotion.

---

## Default initialization

### 16. `Point2.init`

The default value of `Point2!T` is the origin:

```text
(0, 0)
```

Therefore:

```d
Point2!T.init
```

is a valid point.

### 17. `Vector2.init`

The default value of `Vector2!T` is the zero vector:

```text
(0, 0)
```

Therefore:

```d
Vector2!T.init
```

is a valid vector.

### 18. `Segment2.init`

The default value of `Segment2!T` is the degenerate segment whose two endpoints are the origin:

```text
a = Point2!T.init
b = Point2!T.init
```

A zero-length segment is valid geometry.

Degeneracy is not an invalid sentinel.

### 19. `Bounds2.init`

The default value of `Bounds2!T` is **empty**.

An empty bounds contains no point.

It is distinct from a degenerate non-empty bounds:

```text
empty bounds
    contains no location

Bounds2(p, p)
    contains the location p
    has zero extent
```

This distinction is part of the public contract.

It allows natural accumulation:

```d
Bounds2!double bounds;

foreach (p; points)
    assert(bounds.tryExtend(p));
```

with the conceptual transition:

```text
empty
  + first point p
  -> Bounds2(p, p)
```

The internal representation of the empty state is not defined by this ADR and must not become public API.

---

## Bounds semantics

### 20. Non-empty invariant

A non-empty `Bounds2!T` represents an axis-aligned closed region satisfying:

```text
min.x <= max.x
min.y <= max.y
```

For floating-point scalars, a non-empty bounds must not contain NaN coordinates.

### 21. Empty bounds identities

The following semantic identities hold:

```text
empty.contains(p)       == false

empty.intersects(b)     == false
b.intersects(empty)     == false

empty extended by p     == Bounds2(p, p)

empty extended by b     == b
b extended by empty     == b

```

All empty bounds of the same public type compare equal regardless of internal representation.

### 22. `min` and `max` access

`min` and `max` have meaningful values only for non-empty bounds.

The public API must not expose internal sentinel coordinates as meaningful geometry.

Accessing `min` or `max` therefore has the documented precondition:

```text
!bounds.empty
```

### 23. Bounds mutation preserves invariants

Operations that construct or extend a bounds must never leave it in an invalid state.

For floating-point input, a point containing NaN cannot be incorporated into a non-empty `Bounds2`.

Such input must be rejected through an explicit checked API or equivalent invariant-preserving mechanism.

It must not:

- silently create an invalid bounds;
- turn NaN into an empty bounds;
- silently reinterpret NaN as a valid coordinate.

The exact checked API surface is an implementation/API-design decision, but the invariant is architectural.

---

## Non-finite floating-point values

### 24. `Point2` and `Vector2`

Floating-point `Point2` and `Vector2` may represent:

```text
NaN
+Infinity
-Infinity
```

They are numerical value types, not validated finite-coordinate wrappers.

This permits ordinary IEEE floating-point arithmetic to remain visible and prevents basic value operations from requiring hidden error paths merely to preserve a finite-only invariant.

A public finiteness query should be available.

For integral scalar types, the equivalent finiteness predicate is trivially true if exposed through generic API.

### 25. `Segment2`

`Segment2` inherits the representability of its endpoints.

A segment containing non-finite endpoint coordinates may therefore exist as a value.

This does not imply that every geometry algorithm accepts it.

### 26. `Bounds2`

`Bounds2` treats NaN and infinity differently.

For a non-empty floating-point bounds:

```text
NaN        prohibited
±Infinity  permitted
```

Infinity remains orderable and can represent an unbounded axis-aligned extent.

For example:

```text
min = (-Infinity, 0)
max = (+Infinity, 10)
```

is a valid ordered bounds.

NaN is not used as the semantic representation of emptiness.

### 27. Representability versus algorithm validity

A representable geometry value is not necessarily valid input to every algorithm.

For example, later algorithms such as:

```text
orientation
segment intersection
point-in-polygon
```

may require finite coordinates.

Such algorithm-specific preconditions belong to their numerical contracts and ADR-0004.

---

## Representation and encapsulation

### 28. Private representation

The foundational geometry types use encapsulated storage.

Conceptually:

```d
struct Point2(T)
{
private:
    T _x;
    T _y;

public:
    @property T x() const;
    @property T y() const;
}
```

The same principle applies to the other foundational types.

Coordinate fields are not public mutable implementation state.

This preserves freedom to strengthen invariants or change internal representation without unnecessarily expanding the public API.

### 29. Read-only component access

`Point2` and `Vector2` expose read-only coordinate properties:

```text
x
y
```

`Segment2` exposes read-only endpoint properties:

```text
a
b
```

`Bounds2` exposes semantic properties such as:

```text
empty
min
max
```

subject to the bounds-state rules above.

### 30. Construction

`Point2` and `Vector2` require no numeric validation merely to exist and may therefore use direct value construction:

```d
Point2!double(1.0, 2.0)
Vector2!double(3.0, 4.0)
```

`Segment2` may similarly be constructed from two points.

`Bounds2` construction must preserve its ordering and NaN invariants and therefore may require factories or checked construction rather than unrestricted raw field construction.

The exact constructor/factory names are not architectural.

### 31. No coordinate setters in the initial API

The initial public API does not require component setters such as:

```d
p.x = value;
p.y = value;
```

A point or vector may be replaced with another value rather than partially mutated through public coordinate state.

This keeps the foundational types small and their public surface deliberate.

Targeted mutating operations may still exist where they express a coherent geometry operation and preserve invariants.

`Bounds2` extension is such a case.

---

## Segment semantics

### 32. Endpoint naming

A segment exposes endpoints as:

```text
a
b
```

rather than:

```text
start
end
```

because ordinary segment geometry does not imply traversal direction.

The endpoint order is nevertheless preserved as part of the stored value representation.

### 33. Degenerate segments

A segment with equal endpoints is valid.

Algorithms operating on segments must define their own behaviour for this degenerate case.

They must not rely on construction having excluded it.

---

## Equality

### 34. Exact value equality

The fundamental `==` operation represents exact value equality.

It is not approximate geometric equality.

No global epsilon-based approximate equality is part of the core type model.

For `Point2` and `Vector2`, equality is based on exact scalar component equality.

For non-empty `Bounds2`, equality is based on exact public bounds values.

All empty bounds of the same type compare equal.

For `Segment2`, equality follows stored endpoint order:

```text
Segment2(a, b) == Segment2(a, b)
```

but does not automatically imply:

```text
Segment2(a, b) == Segment2(b, a)
```

A later operation may explicitly test undirected geometric equivalence when required.

### 35. Floating-point equality

Floating-point equality follows the scalar's normal exact IEEE/D semantics.

NaN is not made equal to itself by geometry-specific special handling.

Approximate and robust comparisons are algorithm-specific facilities rather than replacements for exact value equality.

---

## Methods and free functions

### 36. Intrinsic state belongs to the type

Properties intrinsic to one value are naturally exposed through the value type.

Examples include:

```d
p.x
p.y
p.isFinite

v.x
v.y
v.isFinite

segment.a
segment.b
segment.isFinite

bounds.empty
bounds.min
bounds.max
```

### 37. Geometric relationships are normally free functions

Operations describing a relationship between independent geometry values should normally be free functions.

Examples include:

```d
distance(a, b);
squaredDistance(a, b);
nearestPoint(segment, point);
orientation(a, b, c);
```

rather than artificially privileging one operand through method syntax.

This separation also keeps the public value types small and allows algorithms to evolve independently.

### 38. Operators are used where they express the mathematical algebra directly

Fundamental point/vector algebra uses D operators:

```d
auto v = q - p;
auto q2 = p + v;

auto u = v + w;
auto n = -v;
```

Named functions are not substituted for ordinary mathematical operators without reason.

---

## Safety and execution properties

### 39. Foundational operations

For the built-in v0.1 scalar types, ordinary foundational value operations should be designed to satisfy:

```d
@safe
pure
nothrow
@nogc
```

where their semantics permit it.

This includes, in particular, ordinary:

```text
construction
component access
Point/Vector algebra
exact equality
state queries
simple invariant-preserving value operations
```

These attributes describe useful API contracts, not stylistic decoration.

### 40. Checked operations

An operation must not claim `nothrow` or another attribute merely to preserve uniformity if its required error semantics make that contract inappropriate.

Where a non-throwing checked result can express the failure clearly, that form is preferred for low-level numerical paths.

### 41. Future user-defined scalars

The attributes above are contracts for the built-in v0.1 scalar set.

They do not imply that hypothetical future user-defined scalar types must satisfy identical compile-time attributes.

Support for such types requires a separate decision.

---

## Integer arithmetic

### 42. Ordinary value algebra

`int` and `long` value algebra follows the ordinary arithmetic behaviour of the corresponding D scalar operations.

The foundational operators do not automatically widen every calculation merely to guarantee mathematical overflow freedom.

For example:

```text
Point2!int - Point2!int
    -> Vector2!int
```

not `Vector2!long`.

### 43. Robust algorithm arithmetic is separate

The ordinary scalar behaviour of the value types does not determine the implementation arithmetic of numerical predicates.

Algorithms such as orientation may require:

- wider intermediate arithmetic;
- overflow detection;
- exact arithmetic;
- adaptive arithmetic;
- specialised predicates.

Those requirements belong to ADR-0004.

The distinction is intentional:

```text
value algebra
    !=
robust computational-geometry arithmetic
```

---

## Compile-time API contracts

### 44. Positive compile tests

The implementation must contain compile-time tests showing that intended algebra is available.

Examples include:

```d
Point2!double p;
Point2!double q;
Vector2!double v;

static assert(__traits(compiles, p + v));
static assert(__traits(compiles, v + p));
static assert(__traits(compiles, p - v));
static assert(__traits(compiles, p - q));
static assert(__traits(compiles, v + v));
static assert(__traits(compiles, -v));
```

### 45. Negative compile tests

Forbidden algebra is part of the public contract and must also be tested.

Examples include:

```d
static assert(!__traits(compiles, p + q));
static assert(!__traits(compiles, -p));
static assert(!__traits(compiles, p * 2));
```

Mixed-scalar geometry operations must likewise have negative compile coverage unless an explicit conversion is performed.

---

## Consequences

The core geometry types have a deliberately narrow scalar contract.

The public point/vector algebra directly represents affine geometry rather than exposing all operations that happen to be possible on two scalar components.

Common geometry expressions remain concise and idiomatic.

Invalid affine expressions become compile-time errors.

Integer geometry remains available for computational geometry, CAD-like coordinates, grids, and other exact-discrete use cases without introducing unsigned displacement problems.

Excluding `byte` and `short` avoids D-specific promotion behaviour leaking into the geometry result-type model.

Explicit scalar conversion prevents accidental mixed-precision geometry arithmetic.

The distinction between representable non-finite values and algorithm-specific validity keeps `Point2` and `Vector2` lightweight while allowing robust algorithms to impose stronger contracts.

`Bounds2.init == empty` permits natural incremental bounds construction without accidentally introducing the origin into every accumulated extent.

Bounds invariants require explicit handling of NaN-bearing input, but prevent a persistent invalid-bounds state from entering the public model.

The core value types remain suitable for `@safe`, `pure`, `nothrow`, and `@nogc` numerical use where appropriate.

Robustness remains a separate concern rather than being accidentally encoded through global epsilon comparisons or arbitrary scalar widening.

---

## Alternatives considered

### Floating-point-only scalar types

Rejected.

Unlike ellipsoidal geodesy, generic Euclidean and computational geometry has legitimate integer-coordinate use cases.

### All built-in numeric types

Rejected.

Unsigned values do not model arbitrary displacement, while `byte` and `short` introduce D-specific arithmetic promotion into the public geometry result types.

### Arbitrary numeric-like template types

Deferred.

The actual algebraic requirements for fixed-point, rational, arbitrary-precision, unit-aware, or other user-defined scalars should be learned from concrete consumers rather than guessed in v0.1.

### A single vector type for both points and displacements

Rejected.

It permits meaningless affine operations such as point addition and makes semantic correctness dependent on caller discipline.

### Implicit scalar promotion between geometry types

Rejected.

It makes the result of geometry expressions dependent on D's primitive promotion rules and weakens the explicit scalar contract.

### Point scaling

Rejected.

Scaling a point requires an origin or transformation context and is therefore not fundamental affine point algebra.

### Integer vector division

Rejected.

Ordinary integer division silently discards geometric information.

### Finite-only points and vectors

Rejected.

It would require basic floating-point value operations to introduce validation or error paths merely to preserve closure under a finite-only invariant.

### NaN as the empty-bounds sentinel contract

Rejected.

NaN represents numerical invalidity or indeterminacy, whereas an empty bounds represents the absence of contained geometry. These meanings must remain distinct.

### Origin-point `Bounds2.init`

Rejected.

It would cause incremental bounds accumulation to include the origin even when the input geometry does not.

### Public mutable coordinate fields

Rejected.

They unnecessarily expose representation, enlarge the stable API surface, and reduce freedom to preserve or evolve invariants.

---

## Deferred decisions

This ADR does not decide:

```text
internal Bounds2 empty representation
exact conversion helper names
orientation implementation
robust determinant arithmetic
intersection semantics
algorithm-specific finite-value requirements
approximate predicates
3D types
N-dimensional types
Polyline / Polygon ownership
aggregate geometry storage
```

The internal representation may evolve without changing the semantic contracts established here.

## Implementation status

The v0.1 core type model described by this ADR is implemented for:

```text
Point2<T>
Vector2<T>
Bounds2<T>
Segment2<T>
```

together with the algebra, checked conversion, bounds invariants, and scalar policies required by this ADR.

Before topology-sensitive algorithms become stable API, ADR-0004 — Numerical robustness must be accepted.

Before variable-sized geometries such as `Polyline`, `LinearRing`, or `Polygon` are introduced, ADR-0003 — Geometry ownership and views must be accepted.