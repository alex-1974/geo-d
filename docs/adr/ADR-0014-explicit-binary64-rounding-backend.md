# ADR-0014: Explicit binary64 rounding backend

Status: Accepted

## Context

Robust floating-point predicates in geo-d depend on explicitly defined binary64 rounding points.

D floating-point expressions may in general be evaluated with excess intermediate precision. The existing implementation therefore uses `core.math.toPrec!double` after elementary additions, subtractions, and multiplications that participate in numerical error bounds or error-free transformations.

This is semantically conservative and portable, but under LDC 1.41 / LLVM 19 `toPrec!double(double)` forms a non-inlined function boundary. Robust orientation benchmarks show that these calls dominate the cost of both the certified floating-point filter and the exact expansion fallback.

Diagnostic measurements on x86-64 showed:

- direct binary64 arithmetic and explicit LLVM-IR binary64 arithmetic have effectively identical performance;
- explicit LLVM IR produces scalar binary64 `fadd`, `fsub`, and `fmul` operations;
- the resulting machine code contains no x87 arithmetic and no fused multiply-add contraction in the tested robust-predicate paths;
- a deterministic semantic probe covering edge cases and 1,000,000 additional finite binary64 operand pairs produced bit-identical add, subtract, and multiply results compared with `toPrec!double`;
- replacing `toPrec` calls with explicit LLVM binary64 operations reduced exact expansion orientation cost by approximately 2.6–2.7×.

The direct-D diagnostic implementation is not sufficient as a library contract because it relies on observed compiler code generation rather than explicitly requesting binary64 LLVM operations.

## Decision

geo-d will provide one internal binary64 rounding backend for elementary robust-predicate arithmetic.

The backend exposes operations equivalent to:

- rounded binary64 addition;
- rounded binary64 subtraction;
- rounded binary64 multiplication.

For LDC, these operations are implemented with `ldc.llvmasm.__ir_pure` using plain LLVM:

- `fadd double`;
- `fsub double`;
- `fmul double`.

No LLVM fast-math flags are attached.

For non-LDC compilers, the portable implementation continues to use `core.math.toPrec!double`.

Robust-predicate code must use this backend wherever its proof depends on an explicit binary64 rounding point. Individual predicate modules must not duplicate compiler-specific rounding implementations.

The backend remains internal implementation infrastructure and is not part of the public geo-d API.

## Consequences

### Positive

- LDC avoids the repeated non-inlined `toPrec!double` calls that dominate robust-predicate execution time.
- The required binary64 operation is explicit in the LLVM IR rather than inferred from current compiler behavior.
- LDC-specific implementation details are isolated in one internal module.
- DMD and other supported compilers retain the conservative portable `toPrec` implementation.
- The same backend can be shared by the orientation filter and exact expansion arithmetic.
- Numerical intent becomes easier to audit because explicit rounding points remain visible at the source level.

### Negative

- The LDC implementation depends on the compiler-specific `ldc.llvmasm` interface.
- Changes in LDC or LLVM semantics require regression testing.
- The project must retain tests that verify the compiler-specific backend against the portable reference semantics.

## Validation requirements

Changes to the binary64 rounding backend require:

1. semantic comparison with the portable `toPrec!double` reference on representative edge cases;
2. robust-predicate unit tests under DMD and LDC;
3. release builds under the supported compilers;
4. LDC code-generation checks confirming that the relevant hot paths contain no unintended x87 arithmetic, floating-point contraction, or calls to `toPrec`;
5. performance regression benchmarks for the certified filter and exact expansion fallback.

The compiler-specific optimization must never weaken the numerical guarantees of the robust predicates.