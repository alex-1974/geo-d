# XPS consumer-release comparison — 2026-10-01

**Decision: recommend PR #84 for merge with the documented allocation/latency
trade-off.** This qualifies the reservation change for the measured XPS,
compilers and corpus. It does not establish a universal speedup, C++ parity,
or completion of the broader #82/#52 release qualification.

## Audited inputs

- Base geometry: `03f345acb6b922719108fd00b72bf105d20a8a21`.
- Candidate geometry: `e86461ca2419f3ecc8b963d31de6c45ae0f22615`.
- Both executed Python runners match commit
  `56256ec74265620a721fa82e1ed95ca7a0befc41` byte for byte.
- Intel Core i7-9750H XPS, Linux 6.17.0-22, glibc 2.43; CPU 0 affinity.
- DMD 2.111.0, LDC 1.41.0, DUB 1.40.0, Core 0.1.2.
- DMD: `-O -inline -release -boundscheck=safeonly`; LDC:
  `-O3 -release -boundscheck=safeonly`. Bounds checks in `@safe` code remain.
- Per compiler: base/candidate then candidate/base, serial. Seven rounds per
  case/operation, adaptive target 20 ms, cap 65,536 iterations, warm-up and GC
  policy unchanged from the recorded harness.
- Eight successful clean-source runs, 184 summaries and 1,288 samples each:
  10,304 samples. Debug/release semantic preflights pass all 92 fixtures in
  both query directions for every run. Every relationship sample allocates
  zero GC bytes; consumed checksums are nonzero.
- Comparison and child metadata agree on source revisions, runner hashes,
  build mode and CPU. Audit checks all rounds, summaries, source snapshots,
  immutable-source diffs and preflights.

Notes are empty. Governor is `powersave`, limits 800–4,500 MHz. AC power,
turbo, thermals, SMT sibling load and background controls were not attested;
affinity does not imply fixed frequency. The evidence supports substantial
observed sparse-workload gains and exact GC-byte differences. Smaller timing
changes do not have an isolated causal explanation or statistical guarantee.

## Double clipping timings

Each cell gives block 0 / block 1 medians in microseconds; ratios compare
candidate to base within that block. Raw seven-round ranges remain available
in the machine-readable analysis and samples.

| Compiler | Case | Base us | Candidate us | Candidate/base |
|---|---|---:|---:|---:|
| DMD | crossing, 4 edges | 45.743 / 45.445 | 44.555 / 46.987 | 0.974 / 1.034 |
| DMD | boundary overlap, 4 edges | 31.318 / 30.840 | 30.277 / 30.285 | 0.967 / 0.982 |
| DMD | hole, 8 edges | 109.316 / 106.934 | 105.859 / 111.063 | 0.968 / 1.039 |
| DMD | sparse, 64 edges | 141.686 / 133.543 | 110.925 / 117.324 | 0.783 / 0.879 |
| DMD | sparse, 256 edges | 509.300 / 506.497 | 320.500 / 335.903 | 0.629 / 0.663 |
| DMD | dense, 16 edges / 4 components | 256.081 / 251.341 | 249.280 / 248.290 | 0.973 / 0.988 |
| DMD | dense, 256 edges / 64 components | 5614.600 / 5551.725 | 5484.700 / 5250.650 | 0.977 / 0.946 |
| LDC | crossing, 4 edges | 19.537 / 18.465 | 19.929 / 18.144 | 1.020 / 0.983 |
| LDC | boundary overlap, 4 edges | 13.359 / 13.464 | 15.111 / 13.427 | 1.131 / 0.997 |
| LDC | hole, 8 edges | 43.127 / 44.951 | 48.183 / 43.657 | 1.117 / 0.971 |
| LDC | sparse, 64 edges | 58.628 / 58.989 | 48.751 / 46.490 | 0.832 / 0.788 |
| LDC | sparse, 256 edges | 333.072 / 352.548 | 147.699 / 134.172 | 0.443 / 0.381 |
| LDC | dense, 16 edges / 4 components | 100.006 / 92.537 | 106.293 / 102.658 | 1.063 / 1.109 |
| LDC | dense, 256 edges / 64 components | 2145.244 / 2126.475 | 2284.600 / 2195.331 | 1.065 / 1.032 |

Double sparse-256 is 34–37% faster on DMD and 56–62% faster on LDC in the
observed paired medians. These ranges describe this experiment, not all
polygons or platforms. The previous LDC hole slowdown does not repeat in both
orders. Neither compiler has a clipping case whose median is more than 10%
slower in both blocks. That observation is not an acceptance threshold;
smaller repeated slowdowns are explicitly retained below.

## GC bytes and accepted trade-off

Both blocks and compilers report identical per-call GC byte values in every
round for the listed double cases:

| Case | Base bytes | Candidate bytes | Reduction |
|---|---:|---:|---:|
| crossing | 24,752 | 16,560 | 33.1% |
| boundary-only | 24,720 | 20,624 | 16.6% |
| hole | 41,216 | 24,832 | 39.8% |
| sparse, 64 edges | 278,704 | 16,560 | 94.1% |
| sparse, 256 edges | 1,093,808 | 16,560 | 98.5% |
| dense, 16 edges / 4 components | 74,128 | 41,360 | 44.2% |
| dense, 256 edges / 64 components | 1,100,800 | 556,032 | 49.5% |

Counters describe cumulative allocated GC bytes, not allocation-call counts,
retained memory, or peak heap use.

Investigated remaining costs:

- DMD double boundary-only is 5.4% / 6.0% slower, approximately 1.46 / 1.60 us
  extra, while GC volume falls 16.6%.
- DMD long dense-16-edges is 6.7% / 5.3% slower.
- LDC double dense-16-edges is 6.3% / 10.9% slower, approximately 6.29 / 10.12
  us extra, while GC volume falls 44.2%.
- LDC double dense-256-edges is 6.5% / 3.2% slower, while GC volume falls 49.5%.
- DMD long empty changes by approximately 2 ns (8.1% / 6.1%). The empty early
  exit precedes the changed reservation code and allocates nothing. Capped
  nanosecond-scale samples include wrapper overhead; causality is unresolved.

The implementation adds one linear pass of finite comparisons before event
allocation. It reduces reserved storage but deliberately leaves exact event
collection and subsequent processing unchanged. A counting-pass cost on
small/dense polygons is therefore a plausible trade-off, not proof of the
cause of every measured ratio. No compiler dispatch, threshold heuristic,
weaker numeric semantics, or disabled safety checks were introduced to hide it.

Accept the observed costs for this bounded reservation change: substantial
sparse latency improvements, 98.5% less sparse-256 GC volume, and roughly half
the dense-256 GC volume justify the recorded modest small/dense timing costs.
Applications dominated by those slower cases should consult these records;
the current change makes no per-case non-regression promise. Further workspace
or compiler-specific tuning remains part of #82. This is an explicit engineering
trade-off under QUALITY_GATES section 7, not a claim that all regressions vanish.

## Reproduction and retention

[comparison-analysis.json](comparison-analysis.json) contains all 368
compiler/scalar/case/operation comparisons, paired medians and ratios, sample
ranges and GC-byte sets. `analyze.py` reproduces it from the retained raw text:

```sh
python3 benchmarks/segment-polygon/results/20261001-xps-safeonly/analyze.py
```

[provenance.json](provenance.json) records the uploaded archive hash; SHA256SUMS
covers all retained raw files. Both runner sources and per-child runner
snapshots are retained. Binaries/object files are omitted; source, commands,
dependencies, semantic checks and raw measurements suffice for reproduction.
The [earlier bounds-disabled comparison](../20261001-xps/README.md) remains
supplementary historical evidence and is not substituted for this safeonly run.

The exact geometry source is unchanged by this evidence commit. Its previously
retained 54-module tests and independent 125,686-query BigInt checks on each
compiler remain applicable. Package export boundaries are unchanged.
