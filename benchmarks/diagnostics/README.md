# Diagnostic benchmarks

This directory contains one-off diagnostic tools used to investigate
numerical implementation and compiler-code-generation behavior.

They are not part of the regular performance regression benchmark suite.

## `run_toprec_probe.sh`

Compares the production robust-expansion implementation using
`core.math.toPrec!double` with a diagnostic variant using direct binary64
arithmetic.

The probe was used to isolate the runtime cost of LDC's non-inlined
`toPrec!double` calls.

Removing only those rounding-call boundaries reduced the cost of the
error-free-transformation and exact-expansion paths substantially, showing
that the principal performance deficit was not caused by the expansion
algorithms themselves.

The direct-arithmetic variant intentionally does not provide the portable
D-language rounding guarantee and must not be used as the production
implementation.

## `run_ldc_ir_rounding_probe.sh`

Compares three implementations derived from the current rounding backend:

1. a portable `core.math.toPrec!double` reference variant;
2. a direct-D binary64 diagnostic variant;
3. the production LDC backend using explicit plain LLVM binary64 arithmetic
   through `ldc.llvmasm.__ir_pure`.

The diagnostic was used to validate the LDC-specific rounding backend
adopted in ADR-0014 and is kept aligned with the current
`geo.internal.binary64_rounding` architecture.

The probe checks:

- bitwise agreement of the production backend with `toPrec!double` on
  selected edge cases and 1,000,000 additional deterministic finite
  binary64 operand pairs;
- a negative control that deliberately corrupts the addition backend and
  verifies that a mismatch terminates the semantic probe with non-zero status
  even when compiled with `-release`;
- generated hot-path instructions;
- absence of unintended x87 arithmetic;
- absence of fused multiply-add contraction;
- absence of residual `toPrec` calls;
- component and exact-expansion performance.

The explicit LLVM-IR implementation matched direct binary64 arithmetic
performance while preserving the tested `toPrec!double` results.

## Status

These tools document the investigation that led to the explicit binary64
rounding backend.

Normal performance regression testing should use the benchmark runners in
the parent `benchmarks/` directory instead.
