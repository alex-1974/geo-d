# geo-d technical documentation

This directory contains the architectural and numerical documentation for
`geo-d`.

The repository `README.md` provides the public introduction and usage
overview. `ROADMAP.md` tracks release preparation and possible future work.
This document describes the current technical model in more detail.

Detailed research, experiments, compiler probes, measurements, rejected
designs, and supporting evidence live in the separate research repository:

~~~text
https://github.com/alex-1974/geo-d-research
~~~

Research is evidence for production decisions. Accepted conclusions are
promoted into `geo-d` through ADRs, architecture documentation, tests, and
production code.

## Documentation map

Architecture decisions are recorded under:

~~~text
docs/adr/
~~~

The ADRs define stable semantic contracts for:

- library scope and boundaries;
- scalar and core geometry types;
- ownership and non-owning views;
- numerical robustness;
- segment intersection;
- ring and polygon representation;
- area semantics;
- point-in-polygon classification;
- topology validation;
- polyline simplification;
- polygon-union exact-overlay and result semantics in
  `ADR-0023-polygon-union-exact-overlay-and-result-contract.md`.

ADR status is authoritative. ADR-0023 is Accepted and defines the semantic,
numerical, ownership, allocation, and failure contract implemented by the
public polygon-union API.

Performance-specific material is documented under:

~~~text
benchmarks/
~~~

Public API documentation conventions are defined in:

~~~text
docs/ddoc-style.md
~~~

This guide defines the documentation contract for symbols exposed through
`import geo;`, including semantics, input domains, failure behaviour,
allocation, complexity, numerical guarantees, and examples.

Practical installation and task-oriented usage examples are collected in:

~~~text
docs/getting-started.md
~~~

The current v2 API-family conventions and migration audit are recorded in:

~~~text
docs/v2-api-conventions.md
docs/v2-public-api-audit.md
~~~

Canonical current documentation uses the dimension-explicit v2 names.
Deprecated v1 names are documented only where compatibility or migration
behaviour is the subject.
