# Compiler matrix

`geo-d` supports DMD and LDC as its required compiler families.

The minimum supported D frontend version is `2.111.0`.

This document defines the reproducible compiler baseline used to compare
compiler compatibility, regressions, code generation, and performance without
accidentally changing multiple toolchain variables at once.

## Controlled Linux x86-64 baseline

The controlled baseline is:

| D frontend generation | DMD | LDC | LDC frontend / LLVM |
| --- | --- | --- | --- |
| 2.111 | 2.111.0 | 1.41.0 | DMD 2.111.0 / LLVM 20.1.5 |
| 2.112 | 2.112.1 | 1.42.0 | DMD 2.112.1 / LLVM 21.1.8 |
| 2.113 | 2.113.0 | 1.43.0 | DMD 2.113.0 / LLVM 22.1.8 |

DMD `2.112.0` is retained as a diagnostic intermediate point when a change
between the 2.111, 2.112, and 2.113 generations needs to be narrowed down.
It is not part of the ordinary six-compiler baseline.

DMD and LDC are treated as separate compiler families even where they use
the same D frontend generation.

## Controlled DUB

Compiler-comparison runs use:

    DUB 1.40.0

Keeping DUB fixed ensures that a compiler comparison does not also become a
build-tool comparison.

The local controlled environment uses the stable command
`dub-dlang-baseline`. Repository scripts do not activate compiler
installations because activation can mutate `PATH`, `DMD`, `DC`,
`LIBRARY_PATH`, `LD_LIBRARY_PATH`, and the effective DUB version.

## Local verification

Run the complete six-compiler baseline with:

    bash tools/test-compiler-matrix.sh

The harness expects these stable compiler commands to be available:

    dmd-2.111.0
    dmd-2.112.1
    dmd-2.113.0
    ldc-1.41.0
    ldc-1.42.0
    ldc-1.43.0
    dub-dlang-baseline

Each compiler runs five gates:

1. library unit tests;
2. DIP1000 lifetime compile-positive and compile-negative probes;
3. external consumer test;
4. `geo-d` / `geo3-d` family consumer test;
5. release build.

A subset or diagnostic compiler can be selected explicitly, for example:

    bash tools/test-compiler-matrix.sh dmd-2.112.0

A different controlled DUB executable can be supplied explicitly with
`GEO_D_MATRIX_DUB`.

## CI policy

The Linux x86-64 compiler gate uses the six exact baseline compiler versions
above with DUB `1.40.0`.

`dmd-latest` and `ldc-latest` are additional rolling forward-compatibility
canaries. They do not change the declared minimum frontend or replace the
exact baseline.

Cross-platform jobs remain a separate portability layer. They use current LDC
on Linux ARM64, Windows x86-64, macOS x86-64, and macOS ARM64 rather than
forming a Cartesian product of every compiler and platform.

The controlled Linux x86-64 compiler comparison fixes DUB to `1.40.0`.
Portability jobs use the DUB available with the selected toolchain and record
its version. They are platform-compatibility probes rather than controlled
compiler comparisons.

DUB `1.40.0` is not explicitly installed for portability jobs because its
published releases do not provide a Linux ARM64 binary. Requiring that exact
DUB version would therefore prevent the Linux ARM64 toolchain from being
installed before `geo-d` itself is tested.

## Compiler-specific behaviour

Compiler-specific workarounds or optimisations require evidence.

For each such case, record:

- exact compiler version or affected version range;
- D frontend version;
- LLVM backend version for LDC where relevant;
- architecture and operating system;
- build mode and relevant flags;
- a reproducer, test, or benchmark;
- the measured or correctness reason for the workaround.

Do not add compiler-version branches merely because a newer compiler exists.
Introduce an optimisation or workaround boundary only when measurement or a
reproduced correctness difference justifies it.

## Baseline evidence

On 2026-09-24, the six-compiler baseline was run against `geo-d` main commit
`9ce6d1c90e7a65a8208b030cb064b73daf522510` with DUB `1.40.0`.

All 30 checks passed: six compilers multiplied by the five gates above.

No compiler-specific correctness failure or workaround was identified by
that baseline run.
