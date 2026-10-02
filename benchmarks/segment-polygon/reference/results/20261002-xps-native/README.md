# XPS native GEOS comparison — 2026-10-02

Executed source: `7deb69f074208ddabe2b18316820965b16cf2966` (PR #86 merged).
Uploaded archive SHA-256: `43982c77f6c30aa70560fcfcdcf3a74682df2cf17903c0e2ba0e850210b56c87`.

## Audit

- Eight complete serial D/native then native/D runs; 348 pairs; seven rounds.
- Native debug/release preflight covers 87 fixtures / 174 directed queries.
- DMD/LDC debug/release preflight and fresh 92-case corpus equality pass.
- Parent and all four D children are clean at the same immutable source commit.
- Executed C++/runner/corpus/assessment and D benchmark snapshots match Git hashes.
- Independent record analysis passes all sample counts, rounds, pairs and consumed checksums.

Platform: Intel i7-9750H, Linux XPS, affinity CPU 0. DMD 2.111.0; LDC 1.41.0
built against LLVM 19.1.7 (the earlier cloud LDC used LLVM 20.1.5); GCC 15.2.0.
DMD `-O -inline -release -boundscheck=safeonly`; LDC
`-O3 -release -boundscheck=safeonly`; native C++17 `-O3`, no fast-math/LTO.
GEOS 3.13.1 from the Shapely 2.1.2 wheel; native library build flags are not
attested. Exact linked-library/header/source hashes are retained in metadata.

The recorded note is **Power/turbo/background settings not attested.**
Governor is powersave, exposed frequency range 800–4500 MHz. There is no
fixed-frequency or confirmed AC-power/background-control claim. This is
repeatable XPS evidence in two run orders, with those limitations; not a
universal performance guarantee or full-contract D/C++ equivalence.

## Observed paired medians

D/native above 1 means greater observed D latency. AB/BA values are separate
block medians; no cross-fixture aggregate score or regression threshold.

| Compiler | Double fixture | D median μs, AB/BA | GEOS median μs, AB/BA | D/GEOS, AB/BA |
|---|---|---:|---:|---:|
| dmd | exterior | 6.822/7.003 | 0.137/0.142 | 49.97/49.17 |
| dmd | crossing | 44.573/44.654 | 8.230/8.183 | 5.42/5.46 |
| dmd | boundary-only | 26.746/26.881 | 4.947/4.950 | 5.41/5.43 |
| dmd | rational-crossing | 44.330/44.422 | 8.304/8.290 | 5.34/5.36 |
| dmd | sparse-64 | 322.883/329.627 | 27.645/27.676 | 11.68/11.91 |
| dmd | dense-64 | 5237.300/5195.025 | 627.417/620.622 | 8.35/8.37 |
| ldc2 | exterior | 3.378/3.393 | 0.143/0.134 | 23.68/25.39 |
| ldc2 | crossing | 17.840/17.951 | 8.422/8.301 | 2.12/2.16 |
| ldc2 | boundary-only | 11.341/11.365 | 5.060/5.079 | 2.24/2.24 |
| ldc2 | rational-crossing | 18.059/17.888 | 8.364/8.295 | 2.16/2.16 |
| ldc2 | sparse-64 | 125.986/127.618 | 28.147/27.842 | 4.48/4.58 |
| ldc2 | dense-64 | 2023.025/2021.756 | 630.370/625.655 | 3.21/3.23 |

Across 87 admitted identities, D/GEOS exceeds 1.1 in both orders for
75 DMD and 71 LDC identities. D/GEOS is below 0.9 in both orders for 12 DMD
and 14 LDC identities. These describe this dataset only, not statistical
significance or qualification tolerances. Inspect tiny-case timer resolution
and calibration caps before using individual ratios.

The direction of the material exterior, sparse and dense gaps observed in
the cloud persists on the XPS. Absolute values cannot be compared as a
controlled cross-platform experiment: CPU, C++ compiler, LDC LLVM build and
unattested power/background conditions differ.

## Interpretation and next bounded investigation

The existing source investigation remains applicable: GEOS can reject a
disjoint-envelope intersection before overlay, whereas geo-d nondegenerate,
nonempty clipping enters exact event allocation/collection/classification.
The double exterior fixture still records 8,288 GC bytes/call; crossing and
sparse-256 16,560; dense-256 556,032. These are cumulative GC bytes, not peak
memory, allocation counts or comparable native allocation measurements.

First candidate: conservative whole-polygon envelope rejection for provably
disjoint nondegenerate inputs, before exact event allocation. It must use
finite represented comparisons with strict separation, retain touching/overlap
cases, avoid subtraction/epsilon, and preserve empty/degenerate/scalar/failure
contracts. An O(n) scan of a borrowed view cannot be described as GEOS-style
cached O(1) bounds. This is an investigation proposal, not an implemented change.

This candidate addresses exterior work only. Crossing/sparse/dense gaps
require separate profiling of exact arithmetic, boundary passes, event ordering
and ownership costs. Stronger geo-d semantics are a real comparison boundary;
they do not establish that every observed cost is necessary or optimized.
Do not translate GEOS blindly or weaken ADR-0024 to improve a ratio.

Any production candidate needs ordinary DMD/LDC tests, the unchanged independent
public differential verifier, repeat allocation accounting and paired latency
measurement against this immutable baseline. No arbitrary universal speedup
target is inferred. #82/#52/#57 remain open.

## Reproduce and retained evidence

```sh
python3 benchmarks/segment-polygon/reference/analyze_native_record.py benchmarks/segment-polygon/reference/results/20261002-xps-native
```

The condensed repository record preserves parent metadata/admission/comparison,
executed native source/runner snapshots, native preflights and dependency paths,
all four native sample streams, and all four D child metadata/sample/preflight/
dependency-graph records. Checksums cover every retained file. The supplied
archive is the full record, including build logs and generated/header/source
snapshots; regenerable binaries/objects were excluded by the wrapper.

Primary implementation comparison and earlier source audit:
[cloud investigation](../20261001-cloud-native/README.md).
