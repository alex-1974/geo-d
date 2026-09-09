

## Current implementation status

The initial fixed-size geometry foundation currently provides:

- `Point2`
- `Vector2`
- `Bounds2`
- `Segment2`
- explicit checked scalar conversions
- point distance and squared distance
- segment length
- nearest point on a segment
- robust orientation predicates
- exact segment-intersection classification
- exact positive-length segment-overlap construction
- correctly rounded unique segment-intersection point construction

### Robust orientation

`orientation(a, b, c)` is currently available for:

| Scalar | Status | Numerical strategy |
|---|---|---|
| `int` | complete | exact over the complete `int` domain |
| `long` | complete | exact over the complete `long` domain |
| `float` | complete | exact promotion to the binary64 backend |
| `double` | complete | certified filter with exact fallbacks |
| `real` | deferred | requires a platform-aware robust backend |

For `double`, the implementation uses progressively more expensive
internal stages:

~~~text
certified binary64 filter
        ↓ uncertain
exact floating-point expansions
        ↓ unsupported exponent range
exact fixed-width dyadic fallback
~~~

The final fallback represents finite binary64 coordinates exactly as
dyadic integers. This is an internal implementation technique rather
than part of the public API contract.

The predicate implementation is allocation-free and targets
`pure nothrow @safe @nogc`.

### Segment intersection

Segment-segment intersection is implemented for:

| Scalar | Classification | Overlap construction | Point construction |
|---|---|---|---|
| `int` | exact | exact `Segment2!int` | rounded `Point2!double` |
| `long` | exact | exact `Segment2!long` | rounded `Point2!double` |
| `float` | exact | exact `Segment2!float` | rounded `Point2!double` |
| `double` | exact | exact `Segment2!double` | rounded `Point2!double` |
| `real` | deferred | deferred | deferred |

The public operations are:

~~~d
SegmentIntersectionKind segmentIntersectionKind(...);

bool trySegmentIntersectionOverlap(...);

bool trySegmentIntersectionPoint(...);
~~~

`segmentIntersectionKind()` remains the authoritative topological
operation.

Overlap construction is exact because its endpoints are selected
directly from the input geometry and returned in canonical
lexicographic order.

Unique-point construction is deliberately separate from topology.
Endpoint contacts and T-junctions reuse a known input endpoint. Proper
crossings are constructed through exact bounded dyadic arithmetic:

~~~text
exact orient2d determinants
        ↓
exact barycentric weights
        ↓
exact weighted rational coordinates
        ↓
round-to-nearest, ties-to-even
        ↓
Point2!double
~~~

The construction path does not first form a rounded binary64 line or
segment parameter.

Verification includes:

- classifier/construction consistency;
- proper and non-dyadic rational crossings;
- shared endpoints and T-junctions;
- equal degenerate segments;
- full-range `long`;
- full-range finite binary64;
- subnormal coordinates;
- near-parallel binary64 crossings;
- explicit binary64 rounding boundary cases;
- parameter-underflow cases;
- bit-identical argument-order and endpoint-reversal invariance.

As with all construction results, a rounded intersection point must not
be used as a replacement for the exact topology API.

### Predicate verification

The orientation implementation is tested against an independent
`std.bigint.BigInt` oracle in unittest builds.

The verification suite includes:

- full-range `int` and `long` coordinates;
- arbitrary finite binary32 and binary64 bit patterns;
- smallest subnormal values;
- maximum finite binary64 values;
- coordinate differences exceeding ordinary binary64 range;
- exact collinearity;
- near-degenerate cases;
- cyclic-permutation invariants;
- sign reversal when two points are exchanged.

`BigInt` is test-only and is not a production dependency.

### Next geometry slice

Segment-segment intersection is complete and verified.

The next geometry primitive is intentionally not fixed by this status
document. It should be selected from the remaining `geo-d` roadmap
according to a concrete consumer need rather than by extending the
geometry model speculatively.
