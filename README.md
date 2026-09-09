# d-geospatial

`d-geospatial` is a workspace for **independent, reusable D libraries** covering geometry, geodesy, spatial data structures, raster processing, geospatial formats, algorithms, and related infrastructure.

It is not a framework, not a monolithic SDK, and not a single versioned software stack.

Each library contained in this workspace is intended to:

- be useful on its own;
- be published and versioned independently;
- have its own Git repository and DUB package;
- remain usable outside the application or project that originally motivated it;
- follow the shared engineering principles in `DESIGN_PRINCIPLES.md`.

## Goals

The workspace exists to encourage a small ecosystem of high-quality D libraries with a shared engineering philosophy.

The main goals are:

- provide reusable geospatial and spatial infrastructure for D;
- favour small, composable libraries over monolithic frameworks;
- make ownership, memory layout, lifetime and allocation behaviour explicit;
- provide efficient APIs suitable for large datasets;
- integrate mature native infrastructure where appropriate while allowing bounded pure-D mathematical kernels when they provide independent value;
- use modern D idioms and safety features;
- maintain strong tests, benchmarks and documentation;
- allow the libraries to work well together without coupling them unnecessarily.

## What d-geospatial is not

`d-geospatial` does not provide a common runtime.

There is no:

```d
import d_geospatial;
```

and there is no requirement to install all libraries together.

Applications are not part of this workspace.

Application-specific GUI code, editor logic, workflows and product features belong in separate repositories.

Experimental code should remain outside `d-geospatial` until it has matured into a generally useful library with a clearly defined domain.

## Workspace structure

The local workspace is organised approximately as follows:

```text
d-geospatial/
├── DESIGN_PRINCIPLES.md
├── README.md
├── ROADMAP.md
│
├── docs/
│   └── adr/
│
├── libs/
│   ├── geodesy-d/
│   ├── geo-d/
│   ├── georef-d/
│   ├── raster-d/
│   ├── spatial-d/
│   └── ...
│
└── tools/
    ├── link-design-principles.sh
    ├── check-workspace.sh
    ├── run-all-tests.sh
    └── run-all-benchmarks.sh
```

Every directory below `libs/` is an independent Git repository and DUB package.

The workspace itself is not a DUB package and does not impose a common package version.

# Workspace conventions

## Licence

Libraries developed as part of `d-geospatial` use the **MIT License** unless a compelling technical or legal reason requires otherwise.

Each independent library repository contains its own `LICENSE` file.

Dependencies retain their respective upstream licences.

## Repository and package naming

Repository and DUB package names use the `-d` suffix:

```text
geodesy-d
geo-d
georef-d
raster-d
spatial-d
proj-d
gdal-d
osm-d
```

The suffix identifies the project as a D package but is not part of the D module namespace.

For example:

```text
repository:   geo-d
DUB package:  geo-d
module root:  geo
```

Typical imports therefore look like:

```d
import geodesy;
import geodesy.ellipsoid;

import geo;
import geo.geometry;

import georef;

import raster;
import raster.resize;

import spatial;
import spatial.rtree;
```

rather than:

```d
import geod;
import rasterd;
```

Library-specific submodule naming is defined by the respective library.

## Compiler policy

Primary supported compilers are:

```text
DMD
LDC
```

Both are required CI targets.

GDC support is maintained on a **best-effort** basis where practical.

CI should normally test against the current stable DMD and LDC releases.

The usable D language baseline is determined by the older common D frontend supported by those required compiler versions.

Initial baseline:

```text
D frontend 2.112.1
```

The baseline may advance as compiler support advances. Libraries should not retain obsolete compiler compatibility indefinitely when it materially constrains API quality, correctness or use of modern D features.

Each library must document its actual minimum supported compiler/frontend version.

## Minimum quality baseline

Every active library must at minimum support:

```text
dub test
```

and CI must verify:

1. tests with DMD;
2. tests/build with LDC;
3. a release build with LDC;
4. repository/documentation structure expected for that library.

Where applicable, libraries should additionally maintain:

- benchmarks;
- fuzz tests;
- property tests;
- interoperability tests;
- large-input tests;
- cross-platform CI.

Benchmarks and fuzzing are domain requirements, not ceremonial checkboxes. They should be added where they provide real value.

# Candidate libraries

The following libraries are currently considered useful candidates.

Their presence here does not mean they must all be created immediately.

## `geodesy-d`

Pure-D geodetic mathematics for positions on or relative to the Earth.

Initial scope includes:

- angles, latitude and longitude;
- reference ellipsoids;
- geodetic coordinates;
- geocentric/ECEF coordinates;
- geodetic ↔ geocentric conversion.

Later scope may include:

- Helmert and related frame transformations;
- Transverse Mercator and UTM;
- direct and inverse ellipsoidal geodesics;
- additional well-defined geodetic operations when justified by real consumers.

`geodesy-d` is intentionally not a replacement for PROJ's CRS/authority infrastructure. It does not own an EPSG database, WKT/PROJJSON parsing, grid resources, or automatic transformation selection.

## `geo-d`

Coordinate-system-agnostic Euclidean geometry types and algorithms.

Potential scope includes:

- points, vectors and bounds;
- segments, polylines and polygons;
- intersections;
- distance and nearest-point operations;
- clipping;
- simplification;
- area and orientation.

`geo-d` assigns no geographic, geodetic, CRS, unit, or Earth-model semantics to coordinates. It should remain useful in GIS and non-GIS domains such as CAD, simulation, robotics and games.

## `georef-d`

Compact and discrete geographic reference/coding systems.

Potential scope includes:

- MGRS;
- Geohash;
- Open Location Code / Plus Codes;
- other independent location-reference encodings when justified.

`georef-d` may depend on `geodesy-d` where the reference system genuinely builds on geodetic mathematics, for example MGRS on UTM. It should not become a CRS database, address geocoder or general geometry library.

## `raster-d`

Generic raster representation and raster-processing algorithms.

Potential scope includes:

- owning raster buffers and non-owning views;
- multidimensional raster access;
- regions of interest;
- sampling and interpolation;
- resizing;
- convolution;
- Gaussian filtering;
- Sobel and Scharr gradients;
- histograms;
- normalisation;
- morphology;
- raster pyramids.

The library should focus on raster semantics and algorithms rather than file-format or GIS-specific I/O.

## `spatial-d`

Generic spatial indexing and spatial-query infrastructure.

Potential scope includes:

- bounding-box queries;
- nearest-neighbour queries;
- R-trees;
- packed spatial indexes;
- spatial hashes or grids;
- efficient static and mutable index variants.

The library should remain useful outside GIS, for example in CAD, simulation, robotics or games.

## `proj-d`

Idiomatic D integration for PROJ or equivalent coordinate-reference-system infrastructure.

Its role is the complete CRS/authority side of the stack: CRS definitions, EPSG/authority metadata, operation selection, grids and other PROJ capabilities. It complements rather than replaces the bounded pure-D mathematics in `geodesy-d`.

This should remain a focused interoperability library rather than becoming the geometry or geodesy library itself.

## `gdal-d`

Idiomatic D integration for GDAL.

Potential scope includes:

- deterministic dataset lifetime;
- raster bands;
- windowed reads;
- resampling;
- geotransforms;
- CRS access;
- metadata;
- efficient integration with D raster buffers.

## `osm-d`

Reusable OpenStreetMap data and format infrastructure.

Potential scope includes:

- nodes, ways and relations;
- tags and object metadata;
- OSM XML;
- OSM PBF;
- change files;
- streaming and large-data processing.

Rendering, GUI code and editor behaviour do not belong in this library.

## `smarttrace-d`

A possible generic tracing and path-assistance library if the underlying algorithms prove useful beyond one application.

Its public API must remain sufficiently domain-neutral to justify an independent library.

It should not exist merely as a place to move application-specific code.

# Library admission criteria

A library belongs in `d-geospatial` when all of the following are reasonably true:

1. It represents a coherent technical or domain concept.
2. It is useful independently of one particular application.
3. It can be distributed as an independent DUB package.
4. Its public API does not expose application-specific concepts.
5. It has a credible path toward tests, documentation and maintenance.
6. Its functionality is substantial enough to justify a separate package.
7. It fits naturally within geometry, spatial computing, raster processing, geospatial data or closely related infrastructure.

A useful helper module is not automatically a useful library.

# Independence

Libraries may depend on one another when the dependency reflects a genuine conceptual relationship.

They must not depend on one another merely to share small utility functions.

There is intentionally no mandatory:

```text
common-d
core-d
foundation-d
```

package.

Shared abstractions should only become libraries after repeated real-world use demonstrates that they deserve an independent existence.

# Shared workspace documentation

The canonical workspace copies are:

```text
d-geospatial/README.md
d-geospatial/ROADMAP.md
d-geospatial/DESIGN_PRINCIPLES.md
```

Each participating library repository also contains these three files at its repository root:

```text
<library>/README.md
<library>/ROADMAP.md
<library>/DESIGN_PRINCIPLES.md
```

Within the local `d-geospatial` workspace these files are hardlinked to the canonical root copies. This keeps the workspace documentation identical while allowing each independent Git repository to version the files in its own history.

Git does not preserve hardlink relationships. Workspace tooling is therefore responsible for restoring the links after clone, checkout, or repository creation.

# Library repository expectations

A mature library should normally contain:

```text
library/
├── source/
├── tests/
├── examples/
├── benchmark/
├── docs/
│   └── adr/
│
├── DESIGN_PRINCIPLES.md
├── README.md
├── CHANGELOG.md
├── ROADMAP.md
├── CONTRIBUTING.md
├── LICENSE
└── dub.sdl
```

The exact structure may vary when the domain requires it.

# Development philosophy

The general preference is:

```text
small public API
        +
explicit ownership
        +
predictable memory behaviour
        +
appropriate algorithms
        +
tests
        +
benchmarks
        +
documentation
```

rather than:

```text
large feature surface
        +
hidden allocation
        +
deep dependency graph
        +
application-specific abstractions
```

Performance-sensitive code should be designed with data layout and algorithmic complexity in mind from the beginning, while low-level optimisation should follow measurement.

# Native libraries

D has strong C interoperability and should use it.

Mature systems such as GDAL or PROJ should not be reimplemented simply to create a pure-D stack.

The preferred pattern is:

```text
mature native library
        ↓
small binding layer
        ↓
idiomatic D API
```

Pure-D implementations are most valuable where D can provide a genuinely useful reusable abstraction or algorithm rather than duplicate an established specialist project.

# Status

`d-geospatial` is currently in the **foundation stage**.

The workspace-wide architectural conventions have been established.

The next step is to begin a small number of fundamental libraries and refine the shared conventions through real implementation experience.

See `ROADMAP.md` for the planned sequence.