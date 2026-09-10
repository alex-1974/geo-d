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
