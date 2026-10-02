# Native C++ / GEOS clipping comparison

Tracking: [#82](https://github.com/alex-1974/geo-d/issues/82), parent [#52](https://github.com/alex-1974/geo-d/issues/52).
Read the [semantic assessment](README.md) first. The 87 admitted fixtures cover
174 directed queries. The five exclusions (long wide-integral, endpoint-collapse,
gap-collapse; double subnormal, large-finite) are selected before timing, retained
in `admission.json`, and never silently removed from results after measurement.
GEOS uses binary64 and supplies weaker topology/construction semantics even where
this corpus agrees. This is a native baseline on an explicitly admitted subset,
not full-contract equivalence or a replacement for exact-reference qualification.

## Cost boundaries

| Work | geo-d | Native C++ GEOS driver |
|---|---|---|
| Corpus, rings and query storage | outside timing | same exported coordinates; generated C++ input storage outside timing |
| Polygon validation | outside timing | GEOS validation outside timing; valid admitted polygons required |
| Degenerate query | legal geo-d segment | zero-length LineString can be native-invalid; exact expected empty output preflighted in both directions, no added validity rejection |
| Query directions | runtime alternating forward/reverse | runtime alternating prebuilt forward/reverse native LineStrings |
| Clipping | public checked owning result | GEOSIntersection_r; no explicit grid, epsilon or prepared spatial index |
| Output | ordered maximal components | native geometry traversal, omit isolated points, orient/sort, coalesce exactly adjacent endpoints into an owning vector |
| Consumption | component/status/endpoint-bit checksum | same endpoint signature arithmetic with success status 1 |
| Disposal | normal automatic GC; explicit collection before timed rounds | native geometry and owning vector freed during each timed operation |
| Allocations | existing current-thread GC-byte accounting | not instrumented; NA is never zero and cannot be equated to D GC bytes |

Native results are checked for finite endpoints and unexpected types. The adapter
does not implement exact topology or geo-d's checked binary64 construction policy.
Neither implementation receives a reusable result workspace. The native adapter
coalesces in place in its per-call owning vector. Native geometry disposal occurs
before the endpoint checksum; vector disposal occurs on return from the timed
wrapper. This explicit release versus automatic GC distinction is part of the
comparison, not an equalized allocation metric.

## Build and run (Linux)

The runner uses the selected D compiler and DUB on PATH. The ordinary D runner
resolves Core through DUB; no dependency sources are copied into the benchmark.
Use DMD 2.111.0 / LDC 1.41.0 and record the exact C++ compiler version.

For a reproducible convenient native installation:

```sh
python3 -m venv build/native-geos-venv
build/native-geos-venv/bin/pip install --only-binary=:all: -r benchmarks/segment-polygon/reference/requirements.txt
build/native-geos-venv/bin/python benchmarks/segment-polygon/reference/prepare_geos_wheel.py --output=build/native-geos-headers
GEOS_NATIVE_LIB=$(python3 -c 'import json; print(json.load(open("build/native-geos-headers/installation.json"))["library"])')
python3 benchmarks/segment-polygon/reference/run_native_comparison.py --compiler=dmd --compiler=ldc2 --geos-header=build/native-geos-headers/geos_c.h --geos-library="$GEOS_NATIVE_LIB" --cpu=0 --smoke --output=build/native-geos-smoke
```

Choose an allowed CPU. Every output/header directory must be new. The helper
requires the Shapely 2.1.2 Linux wheel with GEOS 3.13.1, downloads the pinned GEOS
header sources with verified SHA-256, and configures the documented Version.txt
constants. It preserves their licence headers and records the wheel metadata.
Shapely is used to locate the installed native library; Python never participates
in a timed clipping loop. GEOS library build flags from the supplied wheel are
not attested. For a compiler-controlled native baseline, build GEOS 3.13.1 yourself
and supply `--geos-header` and `--geos-library` directly with the complete library
build record. The C++ harness is compiled with `-std=c++17 -O3`, without fast-math
or LTO; compile commands, native version and linked-library hashes are retained.
The Linux runner records native dependencies with `ldd` and uses an inherited
library search path for the wheel's bundled dependent GEOS library.

After smoke, use a clean immutable checkout for measurements:

```sh
python3 benchmarks/segment-polygon/reference/run_native_comparison.py --compiler=dmd --compiler=ldc2 --geos-header=build/native-geos-headers/geos_c.h --geos-library="$GEOS_NATIVE_LIB" --cpu=0 --rounds=7 --target-ms=20 --notes="record actual power/turbo/background settings here" --output=build/native-geos-comparison
```

On the XPS, the convenience wrapper sets up a fresh pinned wheel/header directory,
runs both D compilers and creates an archive containing all raw records and
provenance (regenerable executables/objects excluded):

```sh
bash benchmarks/segment-polygon/reference/run_xps_native_comparison.sh 0 "record actual power/turbo/background settings here"
```

It removes nothing and prints the record, archive path and archive checksum.
Before archiving it independently verifies child completion, paired medians,
run order and raw sample integrity with `analyze_native_record.py`.

The runner performs native debug/release preflight, D debug/release preflight,
and equality of fresh D exports to the retained 92-case corpus before measurement.
For each D compiler it runs D/native, then native/D serially. Both programs use
independent per-case calibration up to 65,536 iterations, warmup of iterations/10
+1, and per-round distributions. The D runner also records relationship queries
and all 92 fixtures; analysis selects only admitted clipping summaries. Native
relationship queries are not assessed or compared by this driver.

`metadata.json` records source identity, source/library/header hashes, commands,
affinity, exposed frequency settings, notes, individual completion and limitations.
Every D child has its own complete ordinary benchmark record. Raw native output,
admission, generated input header and source snapshots are retained. The runner
refuses changed source unless `--allow-dirty` explicitly marks diagnostics.
It checks child completion, exact summary/sample counts, unique rounds and consumed
checksums; an apparently successful but incomplete child is a failure.

`comparison.json` records 87 per-case median pairs in each block per D compiler;
`d_over_native` above 1 means greater observed D latency. Smoke uses two iterations
and one round, permits timer-resolution zeroes, and emits no ratios. Measurement
mode rejects zero/nonfinite medians. Tiny-case ratios on coarse timers require
inspection of iteration counts and raw timing distributions; no threshold is
automatically a regression verdict.

The CI Fast DMD job runs native semantic preflight and smoke only. Shared-host
runs are diagnostics. Controlled wall-clock runs on the XPS still require actual
power/background attestations; the runner records settings but imposes no fixed
frequency. Retain the full output directory when transferring results.

## Qualification still open

[Retained shared-host diagnostics](results/20261001-cloud-native/README.md)
contain eight clean-source runs, 348 paired records, observed gaps and the first
material-work investigation. They do not establish controlled XPS performance.
To independently verify the retained dataset:

```sh
python3 benchmarks/segment-polygon/reference/analyze_native_record.py benchmarks/segment-polygon/reference/results/20261001-cloud-native
```

Investigate material measured gaps case by case, including compiler differences,
exact-arithmetic work, event/component scaling and allocation policy. A weaker
reference is evidence, not the specification; admitting ordinary cases does not
remove geo-d's general-domain obligations. Full-contract exact reference work and
the broader release qualification remain open under #82/#52/#57.

Primary native API and ownership reference:
[GEOS C API programming](https://libgeos.org/usage/c_api/).
Header configuration source:
[GEOS 3.13.1 Version.txt](https://github.com/libgeos/geos/blob/3.13.1/Version.txt).

[XPS evidence and bounded follow-up](results/20261002-xps-native/README.md):
eight audited runs with seven rounds; actual power/background limitations and
material gaps remain explicit.
