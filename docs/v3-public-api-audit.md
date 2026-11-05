# geo-d v3 public API audit

Status: release-baseline audit for `freeze/feature-3.0.0` / `release/3.0`

Source pin:

```text
6d2f6d52fa0b821466e07b6a322df89b89c1312c
```

The v3 audit is generated with:

```text
python3 tools/audit-public-api.py --out-dir build/v3-api
```

The audit is derived from the package's public D declarations and is separate
from the v2 historical freeze document. It must be regenerated after any
release-baseline source change and before the v3 API freeze.

## Current inventory

| Quantity | Result |
|---|---:|
| Public modules | 23 |
| Package exports through `import geo;` | 67 |
| Top-level public declarations | 81 |
| Public aggregate members | 96 |
| Private aggregate members | 22 |
| Public enum members | 39 |
| Relocated reflection matches | 4 |
| Unresolved members | 0 |
| Total audited declarations | 216 |

Surface hash:

```text
b55433799612df97eb11996a18e69acffe877807f130b86f09149511c03e4a50
```

## v3 additions covered by the external consumer

The external consumer verifies the package-root presence and representative
use of the v3 additions:

- `Line2` and line-intersection declarations;
- `PolygonRelationship` and its checked result/status API;
- `SegmentPolygonRelationship`;
- `SegmentPolygonClipResult`, its status API, and clipping construction;
- existing polygon-union owning results;
- supported robust scalar domains and rejection of `real` for exact overlay
  families;
- owner-to-view retention and caller-input independence.

The consumer test is intentionally independent of implementation modules. It
does not replace the declaration inventory, generated Ddoc audit, compiler
matrix, lifetime tests, or platform gates required by the v3 release issue.

## Release interpretation

This document records the release baseline only. It does not itself create an
API freeze, release tag, or DUB publication. Those actions require the
remaining v3 ownership/safety, compatibility, documentation, compiler,
platform, consumer, and packaging evidence to pass at the selected release
pin.
