# XPS event-capacity comparison — 2026-10-01

**Decision: keep PR #84 in draft.** The conservative reservation reduces GC
bytes and improves sparse workloads, but this run is supplementary evidence,
not qualification of the normal consumer release configuration. Some workloads
are slower and the original runner mistakenly disabled all bounds checks.
No production change has been merged from this experiment.

## Inputs and audit

- Base: `03f345acb6b922719108fd00b72bf105d20a8a21`.
- Candidate: `e86461ca2419f3ecc8b963d31de6c45ae0f22615`.
- Intel Core i7-9750H XPS, Linux 6.17.0-22, glibc 2.43; CPU 0 affinity.
- DMD 2.111.0, LDC 1.41.0, DUB 1.40.0; Core 0.1.2.
- Per compiler: base/candidate then candidate/base, serial; seven rounds per
  case/operation, adaptive target 20 ms, cap 65,536 iterations.
- Eight successful, clean-source runs, each with 184 summaries and 1,288 raw
  samples: 10,304 samples in total. Debug and release semantic preflights pass
  all 92 fixtures in both query directions for every run. Consumed-result
  checksums are nonzero. Every relationship sample reports zero GC bytes.
- Governor `powersave`, exposed limits 800–4,500 MHz. Notes were empty;
  AC power, turbo, temperatures, SMT sibling load and background controls were
  not attested. Do not infer fixed frequency from CPU affinity or the governor.
- DMD flags: `-O -inline -release -boundscheck=off`; LDC flags:
  `-O3 -release -boundscheck=off`. This disables checks in `@safe` code as well.

The uploaded archive SHA-256 and retained-file policy are in
[provenance.json](provenance.json). Raw text records retain the commands,
dependencies, metadata, source snapshots, all preflights and samples. Executable
binaries and object files are omitted. The original archive is retained by the
user. Source revisions and the historical runner are available in Git.

## Representative double clipping results

Each cell gives block 0 / block 1 medians in microseconds. Each ratio compares
candidate to base within that block. A ratio below one is faster; above one is
slower. No single aggregate score substitutes for individual workloads.

| Compiler | Case | Base us | Candidate us | Candidate/base |
|---|---|---:|---:|---:|
| DMD | crossing, 4 edges | 41.031 / 45.693 | 48.381 / 47.972 | 1.179 / 1.050 |
| DMD | sparse, 64 edges | 122.609 / 127.378 | 100.701 / 108.596 | 0.821 / 0.853 |
| DMD | sparse, 256 edges | 497.947 / 603.345 | 351.852 / 401.413 | 0.707 / 0.665 |
| DMD | dense, 256 edges / 64 components | 4672.275 / 4827.475 | 4688.150 / 5188.725 | 1.003 / 1.075 |
| DMD | hole, 8 edges | 94.717 / 109.278 | 108.313 / 102.454 | 1.144 / 0.938 |
| LDC | crossing, 4 edges | 22.925 / 18.735 | 21.920 / 20.718 | 0.956 / 1.106 |
| LDC | sparse, 64 edges | 59.684 / 54.569 | 55.011 / 47.730 | 0.922 / 0.875 |
| LDC | sparse, 256 edges | 178.756 / 320.431 | 153.687 / 138.171 | 0.860 / 0.431 |
| LDC | dense, 256 edges / 64 components | 2714.387 / 2085.831 | 2243.831 / 2276.369 | 0.827 / 1.091 |
| LDC | hole, 8 edges | 46.335 / 42.879 | 52.193 / 56.862 | 1.126 / 1.326 |

For double sparse-256, all seven-round medians improve in both orders on both
compilers, by 14–57% within the observed comparisons. Run-to-run drift is
substantial (for example, LDC base 178.756 versus 320.431 us). These percentages
are observations under the recorded configuration, not general speedup claims.

### GC bytes per call

These values are identical across both blocks and compilers for every measured
round of the listed double cases. They are cumulative allocated GC bytes, not
allocation-call counts, retained memory or peak heap size.

| Case | Base bytes | Candidate bytes | Reduction |
|---|---:|---:|---:|
| crossing | 24,752 | 16,560 | 33.1% |
| sparse, 64 edges | 278,704 | 16,560 | 94.1% |
| sparse, 256 edges | 1,093,808 | 16,560 | 98.5% |
| dense, 256 edges / 64 components | 1,100,800 | 556,032 | 49.5% |
| hole | 41,216 | 24,832 | 39.8% |

## Latency concerns and limits

DMD float isolated tangency is 28.4% / 13.2% slower, and float sparse-4-edges
44.2% / 14.0% slower. LDC double hole is 12.6% / 32.6% slower, and int
64-edge dense clipping 14.3% / 18.1% slower. These cases need investigation,
not an allocation-based dismissal.

LDC long empty/degenerate medians also rise from approximately 4–6 ns to
11–12 ns, even though those early exits precede the changed reservation pass.
Their capped rounds are very short; binary layout, wrapper overhead and host
variation cannot be separated here. The unchanged relationship family varies
as well. Do not attribute every ratio to the new counting pass or normalize
clipping timings by a different relationship workload.

[comparison-analysis.json](comparison-analysis.json) includes all 368
compiler/scalar/case/operation comparisons, block medians and paired ratios,
GC byte sets, and sample ranges. The geometric mean of the two paired ratios
is descriptive only. `analyze.py` regenerates the analysis from raw samples,
checks completeness and preflights, and rejects inconsistent records.

## Corrected measurement gate

Workspace QUALITY_GATES section 7 requires a consumer-representative release
configuration; disabled bounds checks may only be supplementary evidence.
The previous runner failed this requirement. It now defaults to explicit
`-boundscheck=safeonly`, retaining checks in `@safe` code, and snapshots its
own source/hash. `--boundscheck=off` remains an explicitly recorded additional
experiment, not the default.

The comparison runner now uses one recorded measurement runner for both
immutable source worktrees via `--source-root`. This is necessary because the
historical base's runner would otherwise still force `off`. Geometry and
benchmark source remain at the selected immutable commits; the external
measurement runner is identified separately. The comparison also snapshots
both Python runners and their hashes.

Next: repeat the same base/candidate pair using the corrected runner, with
`--boundscheck=safeonly` and recorded actual power/background conditions.
Investigate persistent small/dense-case regressions and then revise, accept
with an explicit justified trade-off, or reject the reservation candidate.
No C/C++ parity, API freeze, or completed #82/#52 qualification follows here.

The corrected runner passed a four-run baseline/candidate smoke on both
baseline compilers: clean immutable sources, identical runner hashes and
explicit `-boundscheck=safeonly` flags verified in every record. See
[runner-validation.json](runner-validation.json); smoke is not latency evidence.
The comparison verifies completed child metadata as well as process exit status.

Regenerate the audit: `python3 benchmarks/segment-polygon/results/20261001-xps/analyze.py`.

## Consumer-release follow-up

The [safeonly XPS comparison](../20261001-xps-safeonly/README.md)
now supplies the consumer-release evidence. It recommends PR #84 with an
explicit documented allocation/latency trade-off. The historical observations
above remain unchanged; the broader #82/#52 qualification remains open.
