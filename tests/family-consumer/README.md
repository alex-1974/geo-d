# Euclidean family coexistence test

This directory contains the durable cross-repository coexistence test for the
`geo-d` / `geo3-d` API family.

The test verifies that one consumer can import both dimensional public package
facades while preserving one shared `euclid-core-d` declaration origin.

The test deliberately:

- uses the current `geo-d` checkout under test;
- fetches `geo3-d` at the exact commit recorded in `geo3-d.commit`;
- pins the transitive Core package to the exact version recorded in
  `euclid-core.version`;
- generates its DUB selection file only inside a temporary consumer;
- does not add `euclid-core-d` as a direct root dependency;
- requires exactly one Core import path from the DUB package cache;
- verifies common D declaration identity for all seven admitted shared
  contracts;
- verifies simultaneous unqualified use of shared declarations;
- verifies representative 2D and 3D overload-family coexistence.

The sibling commit and Core version pins are updated deliberately only after a
compatible family state has been independently verified. They must not track
moving branches or an unpinned Core version, because this test is intended to
remain reproducible.
