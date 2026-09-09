

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

The next topology-oriented primitive is segment-segment intersection.

It will build on the robust `orientation` predicate rather than
introducing an independent tolerance or determinant implementation.
