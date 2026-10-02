## Verification correction — 2026-10-02

Earlier public BigInt verifier invocations used `-release`, which disabled its
runtime `assert` comparisons. Their independent PASS claims below are withdrawn.
Superseding runs without `-release` pass all 125,686 queries for develop 7deb69f
and the retained envelope source b47bac9 with each of DMD 2.111.0 and LDC 1.41.0.
Same-flags assertion-side-effect probes confirm active assertions. Rejected
98e0e7 and 4354545 variants remain independently unqualified by the old runs.
Unit tests and release-active benchmark preflights are unaffected. Raw timings
remain valid within their stated measurement limits. See the adjacent
`../assert-enabled-verification-20261002.json` for flags and provenance.

# Audited XPS envelope-rejection comparison — 2026-10-02

Status: record audit PASS; overall performance acceptance remains OPEN.
Source candidate `95d9d844e7012868b364dd41960fbcd22c6b6bdc` versus baseline
`7deb69f074208ddabe2b18316820965b16cf2966`. Uploaded archive SHA256:
`64e8bdbf9bdc6352ab51a346be557ed326957a55337a69127c6bd7212860170c`.

Eight clean-source runs, AB then BA for each compiler; seven rounds, calibrated
20 ms, all 92 fixtures, CPU 0, safeonly bounds checks. Audit checks parent and
child success, exact commits/trees, runner hashes, benchmark snapshots against
Git, unique fixture/operation/round matrices, complete positive finite medians,
preflight records and consumed sinks. All 10,304 samples and 368 clipping pairs
pass. Retained CSV includes every clipping case and every timing/allocation
round; child metadata retains exact commands, versions and environment.

XPS Intel i7-9750H. DMD 2.111.0; LDC 1.41.0 / LLVM 19.1.7 (cloud LLVM 20.1.5).
Power/turbo/background settings are explicitly NOT attested. These repeated
paired observations are not a fixed-frequency or statistical nonregression gate.
GC bytes are cumulative timed-thread allocation, not peak live memory or counts.

| double case | DMD candidate change AB / BA | LDC candidate change AB / BA |
|---|---:|---:|
| exterior | −98.93% / −98.90% | −99.43% / −99.46% |
| crossing | +0.62% / +0.76% | +1.78% / +0.65% |
| sparse-64, 256 edges | +1.88% / +1.10% | −0.68% / −0.53% |
| dense-64, 64 components | −1.00% / −0.42% | −5.76% / −1.11% |

The cloud double dense-64 slowdown does not reproduce on this XPS. This is a
platform/toolchain observation, not proof of a resolved cloud codegen regression.
Exterior medians are DMD 76.733 / 76.537 ns and LDC 19.571 / 18.575 ns. Exterior
GC allocation falls from 8,288 to zero bytes/call in all seven rounds of all
four candidate runs. No new paired GEOS run is present in this archive: the
preceding native baseline is context, not direct proof of current GEOS parity.
Crossing/dense allocation and the broader gap are not eliminated by this change.

## Residual acceptance concerns

To avoid selecting only favorable double cases, the following clipping medians
increase by more than a descriptive 3% in both blocks. This threshold identifies
investigation candidates; it is not a predeclared statistical acceptance gate.

| compiler | scalar / case | slower AB / BA |
|---|---|---:|
| DMD | float / degenerate-interior | 5.39% / 4.58% |
| LDC | int / degenerate-boundary | 5.17% / 9.10% |
| LDC | int / empty | 4.23% / 6.63% |
| LDC | float / dense-1 | 6.10% / 3.05% |
| LDC | float / subnormal | 7.23% / 3.38% |

Some tiny empty/degenerate cases bypass the new scan; code layout or measurement
may contribute, but that has NOT been established as their cause. float dense-1
and subnormal require investigation along with cloud regressions. Do not promote
this record to a universal nonregression claim or close #82/#52/#57. PR #88 stays
draft until these tradeoffs are eliminated or explicitly accepted.

The unchanged public BigInt verifier and 54-module unit suites were already
qualified for this exact source on DMD/LDC (125,686 queries each). This archive
contains benchmark preflights, not a new independent-oracle execution.

Reproduce with `benchmarks/run_xps_envelope_comparison.sh 0` on the PR branch;
the script pins the above source candidate and baseline, records both compiler
orders and emits the complete checksummed raw archive. The original uploaded
archive remains unchanged; this directory is the condensed repository record.
