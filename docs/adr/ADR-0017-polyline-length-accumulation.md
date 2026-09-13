# ADR-0017: Polyline length accumulation

**Status:** Accepted

**Date:** 2026-09-12

## Context

`polylineLength()` computes the Euclidean length of a `PolylineView` by
summing the lengths of its consecutive segments in stored point order.

Each individual segment length follows the public metric policy:

- integer coordinate differences are obtained without signed overflow;
- `int`, `long`, and `float` geometry compute in `double`;
- `double` geometry computes in `double`;
- `real` geometry computes in `real`;
- segment length is a floating-point metric computation rather than an exact
  geometric predicate.

The original implementation accumulated segment lengths using ordinary
sequential floating-point addition:

```text
sum += segmentLength(segment)
```

This has minimal arithmetic overhead, but small segment lengths can be lost
when the running total is much larger.

A deterministic finite test case demonstrates this effect.

A polyline containing 256 repetitions of the walk

```text
0 -> 2^52 -> 0 -> 1 -> 0
```

has the exactly representable mathematical length:

```text
2^61 + 512
```

With binary64 metric arithmetic, ordinary sequential accumulation produced:

```text
2^61
```

and therefore lost 512 units.

A Kahan-style compensated accumulation produced the exactly representable
expected result on both DMD and LDC.

## Performance evaluation

The first compensated prototype performed explicit finite checks on both the
incoming segment length and the running sum. That implementation was
unnecessarily expensive.

A reduced implementation performs the compensated arithmetic first and tests
only the resulting candidate sum.

On ordinary finite binary64 polylines, measured steady-state performance was
approximately:

```text
LDC, 10,000 points:
    ordinary accumulation    4.019 ns/segment
    compensated              4.509 ns/segment

    overhead                 about 12.2 %

DMD, 10,000 points:
    ordinary accumulation   16.799 ns/segment
    compensated             18.517 ns/segment

    overhead                 about 10.2 %
```

At 1,000 points the measured overhead was approximately 19.6 % under LDC and
8.9 % under DMD.

The additional arithmetic is therefore considered acceptable for the
improved numerical behaviour.

Absolute benchmark timings are development measurements and are not part of
the public API contract.

## Decision

`polylineLength()` will use Kahan-style compensated summation in
`MetricScalar!T`.

Segment lengths continue to be processed in stored order.

For each segment length `value`, the accumulation uses conceptually:

```text
adjusted = value - correction
next     = sum + adjusted

correction = (next - sum) - adjusted
sum        = next
```

### Non-finite results

A single finite check is applied to `next`.

When `next` is not finite:

```text
sum        = next
correction = 0
```

and accumulation continues.

This preserves the existing floating-point result semantics for:

- NaN segment lengths;
- infinite segment lengths;
- overflow of an otherwise finite accumulated length;
- a running result that has already become non-finite.

Resetting the correction prevents compensation state from turning an already
established infinity into NaN merely because later finite segments are
processed.

## Numerical contract

Compensated accumulation improves the accuracy of summing individually
computed segment lengths.

It does not make `polylineLength()` an exact operation.

In particular:

- every individual `segmentLength()` remains a floating-point metric result;
- accumulated rounding error can still remain;
- results remain dependent on stored segment order;
- no order-independent result is promised;
- no correctly-rounded exact-sum guarantee is promised;
- sufficiently large finite accumulated lengths may still overflow to
  infinity.

The public documentation must therefore describe compensated accumulation
without claiming exact summation.

## Allocation and complexity

The change does not alter the existing resource contract.

`polylineLength()` remains:

```text
time   O(n)
space  O(1)
```

for `n` stored points.

No allocation or point copying is introduced.

The implementation remains:

```d
pure nothrow @safe @nogc
```

## Consequences

The public operation gains materially better accumulation behaviour for
mixed-scale polylines at a modest measured performance cost.

The implementation requires one additional compensation value and additional
floating-point arithmetic per segment.

The numerical policy remains distinct from geo-d's exact and robust topology
contracts.

Future performance work may optimize the implementation, but must preserve
the documented compensated-accumulation semantics and non-finite behaviour.
