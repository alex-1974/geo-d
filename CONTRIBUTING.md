# Contributing to geo-d

Contributions to `geo-d` are welcome.

## Branch workflow

Normal development and pull requests target `develop`.

`main` is reserved for qualified release states. Topic branches normally
start from `develop` and return to `develop`; release qualification is handled
separately before changes reach `main`.

The library aims to remain small, robust, explicit about numerical semantics, and useful independently of any particular GIS application.

## Development principles

Before changing public behaviour, read:

- `README.md`
- `ROADMAP.md`
- `DESIGN_PRINCIPLES.md`
- the relevant ADRs under `docs/adr/`

Public API changes should preserve the established separation between:

- geometry representation;
- ownership and lifetime;
- metric computation;
- robust topology;
- geometric construction;
- validation.

Avoid adding API merely because it is conventional in other geometry libraries. New functionality should be justified by a concrete use case.

## Architecture decisions

Changes that introduce or materially alter public semantics should normally be documented through an ADR before or together with implementation.

Examples include changes to:

- scalar support;
- ownership or lifetime rules;
- numerical robustness;
- topology semantics;
- error handling;
- allocation behaviour;
- geometry representation;
- public algorithm contracts.

Small implementation details that do not affect public semantics do not require an ADR.

## Numerical correctness

`geo-d` does not use a global epsilon to define computational topology.

Changes to topology-sensitive algorithms must not silently weaken exact or robust behaviour.

Optimisations of exact or robust code should demonstrate that the established numerical semantics are preserved.

Rounded geometric construction must not be substituted for authoritative topology predicates.

## Ownership and allocation

Prefer:

- explicit ownership;
- non-owning views where appropriate;
- caller-provided output storage;
- caller-provided workspace for variable temporary storage;
- allocation-free low-level algorithms where practical.

Do not introduce hidden deep copies or hidden allocation into established low-level APIs.

## Safety and execution attributes

Preserve useful API contracts such as:

~~~text
pure
nothrow
@safe
@nogc
~~~

where they are part of the existing operation.

Do not add attributes merely for uniformity when the semantics do not support them.

## Tests

Every behavioural change should include appropriate tests.

Depending on the change, useful tests include:

- ordinary unit tests;
- compile-time positive API tests;
- compile-time negative API tests;
- degenerate-geometry cases;
- full-range integral cases;
- floating-point extreme and subnormal cases;
- permutation and reversal invariants;
- independent numerical-oracle comparison;
- property-style tests.

Bug fixes should normally include a regression test.

## Compiler coverage

DMD and LDC are the required compiler families.

The minimum supported D frontend version is `2.111.0`.

The controlled Linux x86-64 baseline covers:

- DMD `2.111.0`, `2.112.1`, and `2.113.0`;
- LDC `1.41.0`, `1.42.0`, and `1.43.0`;
- DUB `1.40.0` for controlled comparisons.

Run the complete local baseline with:

    bash tools/test-compiler-matrix.sh

For ordinary focused development, at minimum run:

    dub test --compiler=dmd --force
    dub test --compiler=ldc2 --force
    dub build --build=release --compiler=ldc2 --force

See `docs/compiler-matrix.md` for the exact matrix, rolling CI canaries,
reproducibility rules, and compiler-specific-workaround policy.

GDC support is best effort unless explicitly stated otherwise.

## Formatting and repository hygiene

Before committing, run:

~~~sh
git diff --check
~~~

Keep commits focused and use concise imperative commit messages.

Examples:

~~~text
geometry: add ...
metric: fix ...
docs: define ...
test: cover ...
ci: add ...
~~~

Do not commit generated DUB build artefacts or local workspace context.

The `.workspace/` directory, when present, contains local context from `d-geospatial-workspace` and is not part of the repository.

## Benchmarks

Changes to performance-sensitive robust arithmetic should be benchmarked when runtime cost is material.

A faster implementation is only an improvement if it preserves the intended numerical contract.

Benchmark code belongs under `benchmarks/`.

## Scope

`geo-d` is a coordinate-system-agnostic Euclidean geometry library.

Features involving CRS databases, map projections, ellipsoidal geodesy, raster processing, spatial indexing, or format-specific bindings generally belong in separate libraries.

When in doubt, prefer a smaller `geo-d` API and a clear boundary.