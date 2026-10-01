#!/usr/bin/env python3
"""Configure pinned GEOS headers for the installed Shapely Linux wheel (no timing)."""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys
import urllib.request

import shapely

BASE = "https://raw.githubusercontent.com/libgeos/geos/3.13.1/"
SOURCES = {
    "capi/geos_c.h.in": "8fff7e7f7ced2c73ba9b8e0bfd3d30340af060e7de30632b79aed56c0adf7322",
    "include/geos/export.h": "7a92f7925a89128de5e18def3d9bdb36f8c123bdfb0c3fba1c42fd78bd9a9f0d",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="new configured header directory")
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("this helper supports Linux shared-library wheels only")
    if shapely.__version__ != "2.1.2" or shapely.geos_version_string != "3.13.1":
        parser.error("install requirements.txt: Shapely 2.1.2 with GEOS 3.13.1 required")
    libraries = list((Path(shapely.__file__).resolve().parent.parent / "shapely.libs").glob("libgeos_c-*.so.*"))
    if len(libraries) != 1:
        parser.error("expected one bundled wheel libgeos_c; supply your own headers/library otherwise")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    (out / "geos").mkdir()
    downloaded = {}
    for path, digest in SOURCES.items():
        with urllib.request.urlopen(BASE + path, timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != digest:
            raise RuntimeError("pinned GEOS source hash mismatch: " + path)
        downloaded[path] = data.decode()
    text = downloaded["capi/geos_c.h.in"]
    # Values from the pinned 3.13.1 Version.txt and its CMake C-API version rules.
    for key, value in {"VERSION_MAJOR": "3", "VERSION_MINOR": "13", "VERSION_PATCH": "1",
                       "VERSION": "3.13.1", "JTS_PORT": "1.18.0", "CAPI_VERSION_MAJOR": "1",
                       "CAPI_VERSION_MINOR": "19", "CAPI_VERSION_PATCH": "2", "CAPI_VERSION": "1.19.2"}.items():
        text = text.replace("@" + key + "@", value)
    (out / "geos_c.h").write_text(text)
    (out / "geos/export.h").write_text(downloaded["include/geos/export.h"])
    manifest = {"header": str(out / "geos_c.h"), "library": str(libraries[0].resolve()),
                "shapely": shapely.__version__, "geos": shapely.geos_version_string,
                "sources": {BASE + path: digest for path, digest in SOURCES.items()},
                "wheel_metadata": importlib.metadata.distribution("shapely").read_text("WHEEL"),
                "library_build_flags": "not attested by this helper; wheel binary, not rebuilt here"}
    (out / "installation.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest))


if __name__ == "__main__":
    main()
