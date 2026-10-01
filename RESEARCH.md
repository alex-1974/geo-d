# geo-d Research

Detailed research, experiments, compiler probes, measurements, rejected
designs, and supporting evidence for geo-d live in the separate research
repository:

https://github.com/alex-1974/geo-d-research

## Repository roles

### geo-d

The production and release repository contains:

- public library source;
- compact architecture documentation;
- accepted ADRs;
- production tests and consumer gates;
- release and contribution metadata.

### geo-d-research

The research repository contains:

- experimental implementations;
- compiler and language probes;
- performance and code-generation evidence;
- design alternatives;
- rejected approaches;
- detailed research notes;
- historical research snapshots.

Research does not become public API merely by existing in the research
repository. Decisions are promoted into geo-d through ADRs, architecture
documentation, tests, and production code.

The research repository preserves provenance for the research material moved
out of the production repository. The production Git history is not rewritten.
