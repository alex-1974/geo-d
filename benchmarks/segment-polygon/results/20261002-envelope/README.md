# Strict-envelope rejection candidate, 2026-10-02

Status: correctness gates pass; performance acceptance is OPEN. This is a
bounded implementation candidate, not closure of #82, #52 or #57.

Baseline: `7deb69f074208ddabe2b18316820965b16cf2966`.
Rejected fused scan: `2a2471f4d3468f5350521b296c275d916553b0c9`.
Current executed source: `95d9d844e7012868b364dd41960fbcd22c6b6bdc`.

The current helper proves strict separation using finite represented-coordinate
comparisons. Equality never rejects. Once every axis proof fails, later vertices
cannot restore a proof and the helper exits early. The helper is deliberately
not inlined into the large exact kernel. Worst-case scan cost is O(total ring
vertices), without allocation or persistent caching of borrowed input. Empty and
degenerate queries retain their previous behavior. Exact topology and checked
binary64 materialization remain unchanged for overlapping envelopes.

## Correctness

DMD 2.111.0 and LDC 1.41.0 each pass all 54 unit-test modules and the unchanged
independent public BigInt oracle: 125,686 directed queries per compiler. Oracle
SHA256: `ca012d85cc70e0fc56f914678a36971a25657a970a9a45a239df0bfa75f6ab3d`.
Source: geo-d-research,
`research/branches/verification__segment-polygon-clipping/docs/verification/segment_polygon_clip_public_differential.d`.
Tests additionally exercise four separation directions, translations and reversed
queries across int/long/float/double, and equality retaining boundary overlap.
The consumer archive passes all 63 required files.

## Diagnostic measurements

LDC 1.41.0 / LLVM 20.1.5, Linux x86-64, CPU 0, release `-O3 -release
-boundscheck=safeonly`, the existing 92-fixture public corpus, calibrated 10 ms,
seven rounds, base/candidate then candidate/base. Warm-up and consumed checksums
are unchanged. Full compiler/CPU/governor, commands and source provenance are in
the retained child metadata and parent manifest. Power/turbo/background settings
are not attested. These cloud runs do not replace XPS qualification.

| double clipping case | base ns, AB / BA | candidate ns, AB / BA | interpretation |
|---|---:|---:|---|
| exterior | 4302 / 3603 | 16.19 / 16.81 | clear empty-result fast path |
| crossing | 21998 / 20906 | 17530 / 23642 | mixed; no nonregression claim |
| sparse-64 (256 edges) | 137811 / 140523 | 127462 / 131220 | diagnostic improvement only |
| dense-64 (64 components) | 1839400 / 2189538 | 1958525 / 2376375 | 6.5% / 8.5% slower medians; NOT accepted |

Exterior GC bytes/call fall from 8,288 to zero in all seven rounds of both
blocks. Crossing, sparse-64 and dense-64 remain 16,560 / 16,560 / 556,032 bytes.
`paired-summary.csv` retains all 184 clipping pairs and each timed/allocation
round, rather than only selected wins. The first fused implementation was rejected
because its short three-round DMD/LDC run showed 18–21% LDC crossing regression;
selected results remain in `rejected-v1.csv` with the immutable source above.

The repeated dense median increase is an unresolved acceptance concern even
though the BA cloud candidate has a large outlier. Do not merge this draft based
on the exterior gain. Run the balanced XPS script and investigate remaining
cost/code-generation regressions before readiness. No general speedup, compiler
parity, GEOS parity or complete allocation-free clipping is claimed.

## Reproduction and next investigation

Run `benchmarks/run_segment_polygon_comparison.py --base=7deb69f074208ddabe2b18316820965b16cf2966
--candidate=95d9d844e7012868b364dd41960fbcd22c6b6bdc --cpu=0 --compiler=ldc2
--blocks=2 --rounds=7 --target-ms=10` with the pinned compilers and DUB on PATH.
The XPS helper runs both compilers with seven rounds and 20 ms and archives raw
records, snapshots and provenance. It defaults to this immutable candidate.

For crossing/dense queries, investigate the existing repeated exact crossing
construction (event generation and local topology), event sorting/search with
exact cross-products, full ring orientation evaluation, and 2,120-byte exact
point workspace. These are source-level candidates, not a profiler attribution.
Any caching/compact representation must preserve all supported exact input and
construction-failure semantics. GEOS's weaker contract does not excuse waste.
