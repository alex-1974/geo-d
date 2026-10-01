# C/C++ reference assessment

Tracking: [#82](https://github.com/alex-1974/geo-d/issues/82), qualification [#52](https://github.com/alex-1974/geo-d/issues/52).
Baseline: geo-d `1ed69cb77ad55fcb89bfbbabc38360fbcdb6431f`.
This is an untimed semantic assessment, not a latency comparison or release qualification.

## Candidate matrix

| Contract dimension | geo-d | GEOS 3.13.1 | Boost.Geometry candidate | CGAL 6.1.1 candidate |
|---|---|---|---|---|
| Input | validated polygon view, segment; int/long/float/double | binary64 coordinates; original long input can change | generic geometry/scalar/strategy design; strategy must be selected and qualified | EPECK provides exact predicates and constructions; integral input must enter exactly |
| Operation | segment clipped against closed polygon including holes | native line/polygon intersection | documented intersection and line/polygon example | documented linear-kernel segment intersections are building blocks; no equivalent polygon-view operation established here |
| Isolated contact | omitted | can return points; adapter omits them | output geometry type and strategy need assessment | exact point/segment events require one-dimensional regularization |
| Boundary spans | retained | ordinary spans retained in observed corpus | unexecuted | two-dimensional regularized polygon Boolean operations are a different operation |
| Components | maximal, query ordered and oriented | adapter sorts, orients and joins equal adjacent endpoints | adapter and semantic preflight required | full exact event/classification adapter required |
| Output construction | checked binary64; collapse returns unrepresentableConstruction | no equivalent checked-construction contract established | no equivalent checked-construction contract established | exact coordinates alone do not implement checked binary64 export and gap/component collapse failure |
| Ownership/cost | public end-to-end owned result; allocation measured | native owned geometry plus normalization and disposal must be timed | native result/container plus adapter must be timed | exact arithmetic, classification, conversion and owned output must be timed |
| Evidence here | existing public corpus and baseline | executed through Shapely, untimed | source/documentation assessment only | source/documentation assessment only |

The generic Boost interface is not evidence that every strategy is inexact, nor
that a custom exact strategy supplies geo-d's complete output contract. CGAL's
exact kernel is a credible basis for a full-contract reference, but the proposed
adapter is substantial new work and must itself be independently qualified.

## Observed GEOS results

The same D benchmark exports 92 preflighted fixtures, tested in both query
directions (184 records). Integer JSON preserves signed integral coordinates;
floating coordinates and expected output use binary64 bit patterns. Widening
binary32 to binary64 is exact. No decimal serialization tolerance is introduced.

With Shapely 2.1.2, GEOS 3.13.1 and NumPy 2.5.3:

| Assessment | Directed records | Meaning |
|---|---:|---|
| matches_after_adapter | 174 | exact numerical endpoint/order equality after the described adapter |
| excluded_input_domain | 6 | long wide-integral, endpoint-collapse and gap-collapse, both directions; integer-to-double changes original coordinates |
| output_mismatch | 4 | double subnormal and large-finite, both directions |

The retained records include native geometry type, validity, normalized output,
input-loss flags and captured native overflow/invalid warnings. The subnormal
case produces no retained component. The large-finite case differs from expected
endpoints and also depends on traversal direction. These are observed results
for this version and corpus, not general claims about all GEOS configurations.

The ordinary adapter drops isolated points, takes endpoint-distinct line
components, orients and sorts them by the query's nonconstant axis, and joins
adjacent exactly equal endpoints. It neither repairs exact topology nor detects
geo-d's construction-collapse failures. No epsilon or precision grid is supplied.
Agreement of the admitted fixtures does not prove general contract equivalence.
Degenerate queries are legal in geo-d but become native-invalid zero-length
LineStrings here; their observed empty intersections match. A native driver
must preflight this behavior explicitly rather than add a validity rejection
that changes the admitted geo-d input domain.
Shapely dispatches to native GEOS, but Python overhead is irrelevant to this
untimed assessment and must not enter a future D-versus-C++ timing comparison.

## Reproduce

Build the existing benchmark with the normal compiler/dependency configuration
from the parent README, then run its new export-only mode:

```sh
./segment-polygon-bench --export-corpus > corpus.json
python3 -m venv reference-venv
reference-venv/bin/pip install -r benchmarks/segment-polygon/reference/requirements.txt
reference-venv/bin/python benchmarks/segment-polygon/reference/geos_semantics_probe.py --corpus corpus.json --output geos-assessment.json
```

Export runs semantic preflight, including both query directions, before writing
JSON; it does not execute timing rounds. The output path must be new. The probe
refuses different Shapely/GEOS versions, unexpected scalar counts, duplicate
fixture identities or mismatched coordinate encodings. Wheel availability and
bundled GEOS version depend on platform; the version check is authoritative.
Retained artifacts are in `results/`, with corpus/probe hashes in the report and
build provenance in `results/provenance.json`.

## Next measurement decision

1. Implement a native C++ driver calling the stable GEOS C API, pinned to 3.13.1.
   Admit only the 87 matched undirected fixtures from this assessment, and list
   all five exclusions before measurement. Repeat semantic preflight in the
   native driver; admission is not inherited blindly from Shapely. Describe this
   as an ordinary-domain comparison with weaker construction semantics.
2. Use the same runtime inputs and query directions. Input construction and
   polygon validation occur outside timing on both sides. Time native clipping,
   the complete point-removal/order/coalescing adapter, owned output and disposal;
   consume a checksum. Include geo-d's public checked result costs. Keep safety
   checks in normal consumer release builds. Do not prebuild a native spatial
   index unless preprocessing cost and query amortization are separately stated.
3. Run controlled serial AB/BA rounds with exact source hashes, C++/D compiler
   versions and flags, CPU/affinity, power/frequency controls, warmup, calibration,
   per-case distributions and raw records. Do not compare GEOS native allocations
   directly with D GC bytes as if they were the same metric. Relationship queries
   need a separate semantic assessment; this probe assesses clipping only.
4. For full-domain comparisons, separately qualify a CGAL EPECK adapter using
   exact input conversion, event ordering, cell classification, closed-boundary
   retention and one-dimensional regularization. Add checked binary64 export
   including endpoint and gap collapse. Compare only once its independent
   correctness evidence covers the entire contract. Boost remains an alternative
   pending explicit strategy and contract qualification.

Neither #82 nor #52 is closed by this assessment. There is no measured native
C/C++ performance gap yet, and no library speed ranking is justified.

## Primary sources

- [GEOS precision FAQ](https://libgeos.org/usage/faq/): binary64 coordinate model.
- [GEOS stable C API](https://libgeos.org/usage/c_api/): native driver interface.
- [GEOS 3.13.1 OverlayNG source](https://github.com/libgeos/geos/blob/3.13.1/include/geos/operation/overlayng/OverlayNG.h) and [robust overlay source](https://github.com/libgeos/geos/blob/3.13.1/src/operation/overlayng/OverlayNGRobust.cpp): pinned implementation, not current development documentation.
- [Boost intersection documentation](https://www.boost.org/doc/libs/latest/libs/geometry/doc/html/geometry/reference/algorithms/intersection/intersection_3.html) and [Boost 1.89.0 line/polygon example](https://github.com/boostorg/geometry/blob/boost-1.89.0/example/05_b_overlay_linestring_polygon_example.cpp).
- [CGAL 6.1.1 EPECK](https://doc.cgal.org/6.1.1/Kernel_23/classCGAL_1_1Exact__predicates__exact__constructions__kernel.html), [linear intersections](https://doc.cgal.org/6.1.1/Kernel_23/group__intersection__linear__grp.html), [regularized polygon Boolean operations](https://doc.cgal.org/6.1.1/Boolean_set_operations_2/index.html).
