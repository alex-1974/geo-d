# External reference probes

This directory contains independent implementations used to validate selected
`geo-d` numerical or geometric behavior.

Reference code is diagnostic evidence. It is not linked into the library and
does not create a package or runtime dependency.

## Polygon union: CGAL/EPECK differential probe

The polygon-union P1 implementation can be compared with CGAL's regularized
2D Boolean-set union using the exact-predicates/exact-constructions kernel.

Files:

~~~text
benchmarks/polygon_union_cgal_reference_probe.d
benchmarks/reference/cpp/polygon_union_cgal_reference.cpp
benchmarks/run_polygon_union_cgal_reference.sh
~~~

Run from the repository root:

~~~sh
bash benchmarks/run_polygon_union_cgal_reference.sh
~~~

Requirements:

- `ldc2`;
- `dub`;
- `g++`;
- CGAL development headers plus GMP/MPFR development libraries.

On Ubuntu 24.04 the CGAL development package is available as:

~~~sh
sudo apt install libcgal-dev
~~~

CGAL is intentionally an **optional local reference dependency**. It is not
added to `dub.sdl`, the published package, or the ordinary Fast/Canary CI
matrix.

### What is compared

Both executables independently construct the same fixed set of small integral
polygon-union fixtures covering:

- disjoint components;
- ordinary area overlap;
- containment;
- a complete shared edge between adjacent polygons;
- point-only contact;
- exact hole filling;
- an island inside a hole;
- a crossing plus-shaped union.

The programs emit a representation-independent semantic signature for every
fixture:

- polygon-component count;
- total hole count;
- twice the union area;
- inside / boundary / outside classification over the same dense integer probe
  grid.

The runner requires byte-identical signatures.

### Why vertex arrays are not compared

The P1 implementation deliberately retains exact noding vertices on selected
straight spans. An independent Boolean-set implementation may legally remove
collinear intermediate vertices.

Comparing raw ring vertex counts or exact sequence storage would therefore
conflate representation with region semantics.

The semantic signature instead compares the regularized two-dimensional
result while still exercising disconnected components, holes, shared
boundaries, point contacts, and overlap reconstruction.

### Scope and limitations

The retained fixtures use small integral coordinates whose successful public
construction is exactly representable in binary64. This makes the differential
comparison about overlay semantics rather than about differing construction
rounding policies.

CGAL/EPECK is the primary independent exact-topology reference identified by
ADR-0023 research. The differential probe supplements, but does not replace,
the repository's exact-range, degeneracy, materialization-failure, and
metamorphic tests.

Adding CGAL to ordinary CI is intentionally not required by this harness.
A future dedicated reference workflow may do so if the maintenance benefit
justifies the additional external toolchain dependency.
