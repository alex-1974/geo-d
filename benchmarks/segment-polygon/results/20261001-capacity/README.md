# Clipping event capacity — allocation prototype, 2026-10-01

**Status: draft; controlled latency qualification is outstanding.**
Tracking: #82, parent #52. No speedup, C++ parity or release-performance claim
is made. The new comparison runner prepares the next controlled-machine gate.

## Audited cause and bound

Baseline `03f345acb6b922719108fd00b72bf105d20a8a21` allocates `2n + 2`
`ExactOverlayPoint` records before collecting events for n polygon edges.
The record is 2,120 bytes on both tested Linux x86-64 baseline compilers.
At n=256, that requests 514 × 2,120 = 1,089,680 bytes for the event array alone.
Shrinking the slice after deduplication does not undo that allocation.

The candidate reserves `2 + 2c` records, where c is the number of edges whose
closed represented coordinate intervals may meet the query bounds. Strict
separation on either axis proves zero contact; equality remains a candidate.
A candidate edge writes at most two raw events (overlap). Shared vertices,
query endpoints and other duplicates are still reserved before deduplication.
Thus every original writer insertion is covered, and `2 + 2c <= 2n + 2`.
False-positive bounds only over-reserve; they never establish contact.

The added pass uses finite comparisons, no subtraction or epsilon, no robust
orientation/contact predicates and no coordinate materialization. The event
writer, exact sorting/deduplication, labeling, component selection, construction
checks and immutable result ownership remain unchanged. Capacity addition and
byte-size overflow retain normal resource-failure handling. Worst-case O(n)
workspace and O(n log n) event sorting remain unchanged. There is one extra
O(n) pass; queries whose bounds overlap every edge receive no event-space
saving and can incur extra time. Small-polygon tradeoffs also need measurement.

## Rejected prototype and retained evidence

An earlier contact-count prototype reserved exactly the raw event count using
one additional robust `segmentContactKind` pass. It saved more bytes but added
predicate work. Its DMD diagnostic timings did not justify adopting that
tradeoff. Its source diff, metadata and raw samples are retained under
`contact-count-dmd/`; it is not the candidate production change.

`before-dmd/` and `before-ldc/` are clean baseline records. `bounds-dmd/` and
`bounds-ldc/` are dirty diagnostic records reconstructed by their identical
`source-diff.patch` against the baseline. `provenance.json` records the exact
candidate source SHA-256 and unchanged independent verifier SHA-256.

Every benchmark run was serial, pinned to allowed CPU 0 on the same shared
Linux x86-64 cloud host (reported AMD EPYC 9V74). Five rounds per case/operation
used ten-millisecond calibration, with actual counts in the raw samples.
DMD 2.111.0, LDC 1.41.0, DUB 1.40.0 and Core 0.1.2 were used. Frequency/turbo
and host-load controls were not imposed, so latency differences remain
provisional. The metadata preserves commands and exposed environment details.

## Measured GC-byte deltas

These are cumulative current-thread GC bytes per clipping call, including
workspace/result allocation and complete coordinate consumption. They are
neither allocation-call counts nor retained/peak memory. Both compilers
reported these values for the double fixtures:

| Fixture | Edges | Components | Before bytes/call | Bounds candidate bytes/call |
| --- | ---: | ---: | ---: | ---: |
| crossing | 4 | 1 | 24,752 | 16,560 |
| sparse-64 | 256 | 1 | 1,093,808 | 16,560 |
| dense-64 | 256 | 64 | 1,100,800 | 556,032 |

The sparse fixture reserves 6 records (two candidate edges) instead of 514;
the dense comb reserves 258 (128 candidate edges) instead of 514. Runtime byte
accounting includes pool rounding and the other arrays. This explains the
measured allocation reduction without attributing a speedup to it.

## Diagnostic clipping medians (µs/call)

These times include automatic GC and result consumption. Distributions in the
raw records are authoritative. They must not be used as release thresholds.

| Double fixture | DMD before | DMD bounds | LDC before | LDC bounds |
| --- | ---: | ---: | ---: | ---: |
| crossing | 68.585 | 76.598 | 32.980 | 36.320 |
| sparse-64 | 324.525 | 579.228 | 288.575 | 248.662 |
| dense-64 | 8119.800 | 8115.500 | 3723.175 | 2776.675 |
| boundary-overlap | 22.927 | 53.519 | 23.441 | 27.177 |

The DMD sparse and boundary-overlap measurements are materially higher in this
run; LDC sparse/dense are lower, while some small cases are higher. Even the
unchanged relationship measurements vary across phases. Shared-host timings
do not resolve whether these are repeatable regressions or host/GC effects.
The draft must be evaluated with an alternating-revision comparison on a
controlled machine before treating the allocation saving as an accepted
performance improvement. A confirmed harmful latency tradeoff requires
revision or rejection; reduced bytes alone do not settle that decision.

## Fresh correctness verification

- DMD and LDC: 54 modules pass unit tests, including the new capacity/writer
  checks across all four scalar domains, both directions, duplicate endpoint
  contacts and overlapping bounds without actual contact.
- Both debug and release benchmark preflights pass all 92 fixtures, including
  subnormal/large finite inputs and both binary64 collapse failures.
- The unchanged archived public BigInt/rational differential was freshly run
  against the bounds candidate on **both** baseline compilers: 125,686 queries
  and both construction-collapse families PASS. Logs are retained here.
- The serial comparison runner also passed a baseline/candidate smoke on both
  compilers using disposable worktrees and retained output. This validates the
  measurement workflow, not its performance conclusions.
- These runs are new candidate evidence, distinct from the historical archive
  preservation checks. The oracle uses only `import geo;` for production.

The retained compiler records contain metadata, the resolved DUB graph, both
preflight outputs and all raw samples; successful empty build logs and
reproducible binaries are omitted. Literal patch context and raw tool-output
trailing spaces are preserved; path-specific Git whitespace attributes prevent
those evidence bytes from being mistaken for source formatting defects.

## Controlled comparison

Use both baseline compilers on PATH, AC power and an otherwise-idle machine;
record the actual governor/turbo/background controls rather than assuming
pinning controls frequency. Select an allowed CPU. The comparison runner uses
immutable detached worktrees, validates both revisions in debug/release, and
runs baseline/candidate then candidate/baseline serially for each compiler:

```sh
python3 benchmarks/run_segment_polygon_comparison.py --cpu=0 \
  --base=03f345acb6b922719108fd00b72bf105d20a8a21 --candidate=HEAD \
  --blocks=2 --rounds=7 --target-ms=20 \
  --notes='Record actual power, frequency, turbo and background controls here'
```

Outputs remain outside the disposable worktrees in a new `build/` directory;
`--output` selects another new directory. `--smoke` validates the comparison
mechanics but produces no performance evidence. Share the entire output with
`comparison.json`, per-run metadata, raw samples and logs. #82/#52 stay open.

## XPS follow-up

The [XPS comparison](../20261001-xps/README.md) confirms allocation savings and
sparse-workload gains but identifies latency concerns and the historical
`-boundscheck=off` runner error. PR #84 remains a draft. Use the corrected
comparison runner with its default `--boundscheck=safeonly`; it applies one
recorded runner to both immutable source revisions.
