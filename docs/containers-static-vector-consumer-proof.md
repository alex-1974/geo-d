# containers-d StaticVector consumer proof

Status: qualified research evidence  
Branch: `research/containers-static-vector-proof`  
Draft PR: #44  
containers-d research: issue #25 / PR #33

## Purpose

This experiment tests whether the fixed-capacity container family being
researched in containers-d can replace geo-d's duplicated local
`ExpansionBuffer!Capacity` mechanics without weakening:

- robust expansion arithmetic semantics;
- `pure nothrow @safe @nogc` hot-path attributes;
- fixed inline storage;
- DMD 2.111 performance;
- LDC 1.41 performance.

The dependency is pinned to an exact containers-d research commit. No released
geo-d dependency decision is implied by this branch.

## Baseline

The develop implementation stores:

```d
double[Capacity] _data;
size_t _length;
```

and provides:

- `length`;
- `empty`;
- `clear`;
- `append`;
- indexed access.

The type is internal to geo-d but used heavily by exact binary64 orientation
and expansion arithmetic.

## Integration experiments

### 1. Owning StaticVector wrapper

The first real-consumer form kept `ExpansionBuffer` as a struct containing:

```d
StaticVector!(double, Capacity) _data;
```

and forwarded the domain API to that member.

This form passed the complete geo-d compiler/test matrix.

Real branch-vs-develop Callgrind comparison on the same runner showed:

#### DMD 2.111

| Operation | Develop Ir | Wrapper Ir | Delta |
|---|---:|---:|---:|
| scaleExpansion 2→4 | 61,866,004 | 62,390,292 | +0.847% |
| fastExpansionSum 4+4 | 81,002,516 | 82,444,308 | +1.780% |
| orientation exact collinear | 266,338,324 | 273,940,500 | +2.854% |
| orientation exact near | 292,945,940 | 300,285,972 | +2.506% |

The scaleExpansion body itself was instruction-identical; the candidate changed
higher-level DMD inlining/code-shape decisions. In orientation, DMD stopped
inlining `copyExpansionZeroElim` in one path.

Adding `pragma(inline, true)` to the geo-d forwarding methods did not change
these counts.

Decision: **reject wrapper form for DMD baseline performance**.

#### LDC 1.41

The wrapper form was neutral or faster in all measured paths, including
material reductions in the two orientation fallback probes.

That compiler-specific difference is useful evidence but does not justify
accepting the DMD regression.

### 2. alias-this forwarding

A second experiment attempted to keep the domain wrapper but forward the
StaticVector surface via `alias this`.

Both DMD 2.111 and LDC 1.41 rejected the required consumer expressions:
`clear`, `length`, `empty`, and indexed access were not transparently
available in the required form.

Decision: **reject**. The family architecture should not depend on fragile
language forwarding tricks merely to remove wrapper code.

### 3. Consumer composition mixin

The admitted research form uses the containers-d research-only:

```d
ScalarStaticVectorOps!(double, Capacity)
```

inside geo-d's own type:

```d
struct ExpansionBuffer(size_t Capacity)
{
    mixin ScalarStaticVectorOps!(double, Capacity);

    void append(double value)
        pure nothrow @safe @nogc
    {
        assert(isFinite(value));
        pushBack(value);
    }
}
```

The mixin:

- injects its own fixed inline scalar storage;
- injects logical length and ordinary vector operations;
- depends on no host fields;
- creates no wrapper object;
- leaves geo-d free to add the finite-component invariant and keep its domain
  type/name;
- is known entirely at compile time.

This is a direct example of a consumer adapting a generic container family
without runtime policy dispatch.

## Functional qualification

The composition form passes the complete geo-d CI matrix:

- DMD 2.111;
- LDC 1.41;
- dmd-latest canary;
- ldc-latest canary;
- all unit tests;
- lifetime compile-negative tests;
- external consumer test;
- 2D/3D coexistence test;
- release builds;
- public documentation build where applicable.

The robust predicate result/checksum gates in the performance probe are also
identical to develop.

## Real consumer performance qualification

Probe:

`benchmarks/static_vector_consumer_probe.d`

Workflow:

`.github/workflows/perf-static-vector-consumer.yml`

The workflow compiles the same probe source twice on the same GitHub runner:

1. against a fresh checkout of `geo-d develop`;
2. against the research branch plus the exact containers-d candidate commit.

Each operation performs 262,144 measured calls under Callgrind.

### DMD 2.111

| Operation | Develop Ir | Composition Ir | Delta |
|---|---:|---:|---:|
| scaleExpansion 2→4 | 61,866,004 | 61,866,004 | 0 |
| fastExpansionSum 4+4 | 81,002,516 | 81,002,516 | 0 |
| orientation exact collinear | 266,338,324 | 266,338,324 | 0 |
| orientation exact near | 292,945,940 | 292,945,940 | 0 |

The real geo-d consumer is **instruction-identical** to develop for every
measured DMD path.

### LDC 1.41

| Operation | Develop Ir | Composition Ir | Delta |
|---|---:|---:|---:|
| scaleExpansion 2→4 | 31,457,311 | 31,457,311 | 0 |
| fastExpansionSum 4+4 | 74,580,003 | 75,104,291 | +524,288 (+0.703%) |
| orientation exact collinear | 171,966,485 | 171,966,485 | 0 |
| orientation exact near | 200,671,253 | 200,146,965 | −524,288 (−0.261%) |

The two non-zero deltas are exactly +2 and −2 retired instructions per measured
operation respectively.

This small, opposing LDC code-generation difference is not sufficient evidence
for a compiler-specific consumer policy. Adding such a branch would violate the
research rule against speculative over-optimization unless a real workload
shows material impact.

## Architecture conclusion

The geo-d experiment supports the container-family model more strongly than a
simple wrapper would have.

The successful shape is:

```text
containers-d
    scalar fixed-vector family mechanics
                |
                | compile-time typed composition
                v
geo-d ExpansionBuffer
    + finite-component invariant
    + numerical domain vocabulary
```

The consumer keeps semantic ownership of the domain type while reusing generic
container mechanics.

There is:

- no virtual dispatch;
- no runtime policy object;
- no allocator;
- no additional object layer;
- no DMD hot-path regression in the measured real consumer.

## What this does not yet prove

- ScalarStaticVectorOps is research-only and not a proposed stable API yet.
- Non-scalar T uses the broader StaticVector/lifetime/storage research path and
  needs separate qualification.
- geo3-d must independently reproduce the result.
- A dependency/versioning decision belongs after the containers-d milestone is
  promoted and released.
- The +2-instruction LDC sum path should only be revisited if an end-to-end
  workload demonstrates material impact.

## Next gate

Repeat the consumer-composition proof in geo3-d. If the independent sibling
library also accepts the same family primitive without semantic/performance
regression, M4.3 gains two real consumers rather than one synthetic and one
local proof.
