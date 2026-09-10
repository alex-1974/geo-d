# geo-d benchmarks

These benchmarks measure the performance of robust segment-intersection
classification and exact unique-point construction.

They are intended primarily for:

- detecting performance regressions;
- comparing implementation changes;
- identifying expensive exact-arithmetic paths.

Absolute timings are machine-, compiler- and build-dependent and are not
part of the public API contract.

## Benchmarks

`intersection_bench.d` measures end-to-end operations including:

- ordinary disjoint classification;
- ordinary proper-crossing classification;
- collinear overlap classification;
- near-parallel binary64 classification;
- full-range binary64 classification;
- shared-endpoint construction;
- T-junction construction;
- integer proper-crossing construction;
- binary64 proper-crossing construction;
- non-dyadic rational construction;
- near-parallel construction;
- full-range binary64 construction;
- parameter-underflow construction.

`intersection_exact_bench.d` isolates selected exact-arithmetic
components:

- one exact orientation determinant;
- exact proper-intersection rational construction;
- one exact rational-to-binary64 rounding operation.

## LDC release build

From the repository root:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/intersection_bench.d \
        -of=/tmp/geo-d-intersection-bench-ldc

    /tmp/geo-d-intersection-bench-ldc

For the component benchmark:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/intersection_exact_bench.d \
        -of=/tmp/geo-d-intersection-exact-bench-ldc

    /tmp/geo-d-intersection-exact-bench-ldc

## DMD release build

From the repository root:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/intersection_bench.d \
        -of=/tmp/geo-d-intersection-bench-dmd

    /tmp/geo-d-intersection-bench-dmd

For the component benchmark:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/intersection_exact_bench.d \
        -of=/tmp/geo-d-intersection-exact-bench-dmd

    /tmp/geo-d-intersection-exact-bench-dmd

## Signed-area benchmarks

`area_bench.d` compares the correctly-rounded exact `signedArea()` path
with a local naive binary64 shoelace implementation.

The naive implementation exists only as a performance baseline and does
not provide the numerical contract of the public geo-d operation.

The benchmark covers:

- ordinary integer and binary64 triangles;
- translated full-range integer coordinates;
- ordinary binary64 rings with 10, 100, 1,000 and 10,000 vertices;
- a finite full-range binary64 triangle.

`area_exact_bench.d` isolates selected exact signed-area components:

- one exact orientation determinant;
- first determinant accumulation;
- two determinant accumulations;
- one exact dyadic-to-binary64 area rounding operation.

For the area benchmarks, build with LDC using:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/area_bench.d \
        -of=/tmp/geo-d-area-bench-ldc

    /tmp/geo-d-area-bench-ldc

For the component benchmark:

    ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/area_exact_bench.d \
        -of=/tmp/geo-d-area-exact-bench-ldc

    /tmp/geo-d-area-exact-bench-ldc

With DMD:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/area_bench.d \
        -of=/tmp/geo-d-area-bench-dmd

    /tmp/geo-d-area-bench-dmd

and:

    dmd \
        -O \
        -release \
        -inline \
        -boundscheck=off \
        -i \
        -Isource \
        benchmarks/area_exact_bench.d \
        -of=/tmp/geo-d-area-exact-bench-dmd

    /tmp/geo-d-area-exact-bench-dmd

### Initial signed-area baseline

On the development machine, the initial exact implementation showed
approximately linear cost for ordinary binary64 rings.

    LDC release:
        n=100       62.27 us/op
        n=1,000    634.92 us/op
        n=10,000     6.20 ms/op

        steady-state cost:
            about 0.62-0.64 us per vertex

    DMD release:
        n=100      149.68 us/op
        n=1,000      1.54 ms/op
        n=10,000    15.21 ms/op

        steady-state cost:
            about 1.50-1.54 us per vertex

The initial component measurements were:

    LDC release:
        exact determinant             728.53 ns
        first accumulator write        29.85 ns
        second/additional add         ~102.53 ns
        final area rounding           188.71 ns

    DMD release:
        exact determinant            1266.91 ns
        first accumulator write       108.49 ns
        second/additional add        ~373.96 ns
        final area rounding           306.29 ns

The additional-add values are derived from the difference between the
two-add and first-add benchmark cases.

These measurements indicate that the principal cost is per-vertex exact
determinant construction, with exact accumulation also significant,
especially under DMD. Final binary64 rounding is performed only once per
ring and is not the dominant cost for non-trivial rings.

The full-range binary64 triangle benchmark is intentionally adversarial
for numerical range, but its axis-aligned geometry creates exact zero
differences and products. Its timing must therefore not be interpreted as
representative full-range determinant throughput.

No floating-point fast path is implied by these measurements. The first
performance work should remove redundant work from the exact implementation
while preserving the signed-area numerical contract.

## Intersection optimisation history

The initial exact construction implementation deliberately favoured a
simple and obviously bounded fixed-width arithmetic design.

Benchmarking later identified three major optimisation opportunities:

1. Fixed-width multiplication now skips inactive leading and trailing
   limb ranges while preserving all arithmetic inside the active range.

2. Exact rational-to-binary64 rounding compares and subtracts shifted
   divisors directly instead of repeatedly materialising large shifted
   fixed-width integers.

3. The public unique-point construction path avoids two redundant exact
   orientation determinants after the authoritative classifier and
   endpoint handling have already established a strict proper crossing.

These changes do not alter the public intersection semantics or the
correctly-rounded binary64 construction contract.

## Observed development result

On the development machine used during the optimisation work, ordinary
binary64 proper-crossing construction changed approximately as follows:

    LDC release:
        59.05 us/op -> 3.03 us/op
        about 19.5x faster

    DMD release:
        130.10 us/op -> 7.29 us/op
        about 17.8x faster

These values are historical reference measurements only. They are not
portable performance guarantees.

Ordinary segment-intersection classification remained around the
sub-microsecond range, while exact full-range and construction paths
benefited most from the fixed-width arithmetic improvements.
