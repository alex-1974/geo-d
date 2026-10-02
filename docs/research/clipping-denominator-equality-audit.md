# Denominator equality audit

Status: research evidence for PR #89; no production contract change.

## Representation trace

- Every supported coordinate is expanded exactly onto one common `2^-1074` integer scale in `geo.internal.dyadic`.
- `SignedDyadicDifference` retains only sign plus the 66-limb magnitude.
- `multiplyDyadicDifferences` materializes the positive denominator magnitude as a 132-limb fixed product.
- `ExactOverlayPoint` stores that denominator by value. Input vertices use denominator 1; proper intersections copy the exact product denominator.
- Event arrays are copied and heap-sorted by value, so object/pointer identity is not a stable denominator-identity mechanism.
- Unreduced equivalent rationals are intentionally supported; denominator inequality cannot prove coordinate inequality.

## Consequence

There is no existing exponent, normalization token, or provenance identifier that can replace the 132-limb equality check. Adding a semantic denominator ID would require a wider representation and propagation contract.

A compact fingerprint is safe only as a rejection filter:

1. unequal fingerprint => denominators are definitely unequal, provided the fingerprint is a deterministic function of every limb;
2. equal fingerprint => still compare all 132 limbs before using the equal-denominator shortcut;
3. collisions affect performance only, never numerical/topological correctness.

The next experiment therefore measures a cached full-denominator fingerprint on `ExactOverlayPoint` before considering any production representation change.
