# Native comparison: shared-host diagnostics — 2026-10-01

Executed clean source: `10511d707968d2dddb74f3fa374051a045268f2e`.
DMD 2.111.0, LDC 1.41.0, GCC 13.3.0, GEOS 3.13.1 from the Shapely 2.1.2 wheel.
Native library build flags are not attested. Core v0.1.2 was DUB-resolved from
the clean registered checkout `e727c58d7e6bea35de1cf6eeb2c806480c631e28`.

Eight completed serial runs: D/native then native/D for each D compiler.
Each uses CPU 0, three rounds, 5 ms calibration target, at most 65,536 iterations
and normal D `safeonly` checks. All native debug/release and D debug/release
preflights passed; fresh exported D corpora match the retained 92 fixtures.
87 fixtures / 174 directed native queries are admitted. No incomplete child
is interpreted: an earlier run whose checkout changed was rejected and is
excluded. These records come from the subsequent detached immutable checkout.

The shared/virtualized host has no imposed power, background-load or fixed
frequency controls. These are diagnostics, not controlled release performance
or a generally applicable D/C++ speed ranking. Retained metadata, raw samples,
and the weaker GEOS semantic boundary must accompany every interpretation.

## Observed paired medians

D/native ratios above 1 mean higher observed D latency. Each pair shows AB
then BA; all table values are descriptive, with no acceptance threshold.

| Compiler | Double fixture | D median ns, AB/BA | Native median ns, AB/BA | D/native, AB/BA |
|---|---|---:|---:|---:|
| dmd | exterior | 10626/11329 | 182/191 | 58.28/59.41 |
| dmd | crossing | 80244/69772 | 8969/11126 | 8.95/6.27 |
| dmd | boundary-only | 42267/45910 | 5946/5108 | 7.11/8.99 |
| dmd | rational-crossing | 66330/68608 | 11492/9587 | 5.77/7.16 |
| dmd | sparse-64 | 443081/475012 | 34176/36670 | 12.96/12.95 |
| dmd | dense-64 | 10025900/6771600 | 1143562/874994 | 8.77/7.74 |
| ldc2 | exterior | 4287/5552 | 183/222 | 23.48/25.01 |
| ldc2 | crossing | 20370/21330 | 9211/13169 | 2.21/1.62 |
| ldc2 | boundary-only | 15746/18231 | 6462/5333 | 2.44/3.42 |
| ldc2 | rational-crossing | 20010/22542 | 13700/9184 | 1.46/2.45 |
| ldc2 | sparse-64 | 185992/132053 | 38422/35019 | 4.84/3.77 |
| ldc2 | dense-64 | 2227925/2345750 | 806365/1088661 | 2.76/2.15 |

Across all 87 admitted scalar/fixture identities, D/native exceeds 1.1 in
both blocks for 75 DMD and 72 LDC identities; it is below 0.9 in both blocks
for 12 identities on each compiler. These cutoffs describe this record only;
they are not significance tests or a regression gate. Inspect raw rounds,
iteration caps and tiny-case timer resolution before drawing a performance
conclusion. The expected checksum is consumed but differs globally because
D also times non-admitted cases and relationship operations.

## First material-work investigation

The exterior fixture exposes a concrete work difference. GEOS 3.13.1
`OverlayNG::getResult` checks `OverlayUtil::isEmptyResult` before overlay;
floating intersection can return empty using disjoint input envelopes.
geo-d nondegenerate/nonempty clipping instead computes candidate capacity,
allocates and seeds exact events, visits boundary pairs and proceeds through
event classification. Its double exterior result records 8,288 cumulative
GC bytes per call on both D compilers; crossing and sparse-256 record 16,560,
dense-256 records 556,032. These are GC accounting bytes, not peak memory or
native-comparable allocation counts.

The source difference and allocation record identify a bounded investigation
target; they do not attribute the full timing ratio to one cause. An exact,
conservative whole-polygon envelope rejection is a possible next candidate
for the nondegenerate exterior case, subject to proof that valid scalar
bounds and all contact/failure policies are preserved. Dense and crossing
gaps need separate profiling of exact event work, ordering and allocations;
the ordinary-admitted GEOS results do not weaken geo-d's domain or contract.

No production geometry code changes are made by this benchmark PR.
Repeat the same native/D comparison on the controlled XPS before accepting
a platform latency decision. Any subsequent optimization must repeat unit
and unchanged independent public differential verification.

Pinned primary implementation evidence:
[GEOS OverlayNG](https://github.com/libgeos/geos/blob/3.13.1/src/operation/overlayng/OverlayNG.cpp),
[GEOS OverlayUtil](https://github.com/libgeos/geos/blob/3.13.1/src/operation/overlayng/OverlayUtil.cpp);
geo-d `source/geo/internal/segment_polygon_clip_p1.d` at the executed commit.

## Retained records

The directory contains top-level metadata/admission/comparison, executed
C++ and runner snapshots, native debug/release preflights, native linked-library
paths and hashes, all four native raw sample streams, and each of four D child
metadata/raw sample/preflight/dependency-graph records. `geos-installation.json`
identifies the independently prepared wheel/header configuration used for the
run. Compiler commands and source/header/library hashes are in metadata.

Generated headers, third-party header copies, regenerable executables/objects,
duplicate export JSON and build logs are omitted from this condensed repository
record. The shared corpus and pinned setup/generator remain available in the
parent reference directory and the executed source snapshot. The complete
original run remains under `build/native-geos-cloud-frozen`. For XPS transfer,
use the wrapper archive, which retains the complete provenance and raw output.

#82/#52/#57 remain open.
