#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${1:-$(cd "$script_dir/.." && pwd)}"
cd "$repo_root"

D_SOURCE=benchmarks/polygon_union_cgal_reference_probe.d
CPP_SOURCE=benchmarks/reference/cpp/polygon_union_cgal_reference.cpp

D_BIN=/tmp/geo-d-polygon-union-reference-ldc
CPP_BIN=/tmp/geo-d-polygon-union-reference-cgal

D_OUT=/tmp/geo-d-polygon-union-reference-d.txt
CPP_OUT=/tmp/geo-d-polygon-union-reference-cgal.txt

if ! command -v ldc2 >/dev/null 2>&1; then
    printf '%s\n'         'error: ldc2 is required for the geo-d side of the differential probe'         >&2
    exit 2
fi

if ! command -v dub >/dev/null 2>&1; then
    printf '%s\n'         'error: dub is required to resolve geo-d dependency import paths'         >&2
    exit 2
fi

if ! command -v g++ >/dev/null 2>&1; then
    printf '%s\n'         'error: g++ is required for the CGAL reference probe'         >&2
    exit 2
fi

if [ ! -r /usr/include/CGAL/Exact_predicates_exact_constructions_kernel.h ]; then
    cat >&2 <<'EOF'
error: CGAL development headers were not found.

On Ubuntu 24.04 the reference dependency is available as:

    sudo apt install libcgal-dev

CGAL is used only by this optional external reference probe. It is not a
geo-d package, runtime, or ordinary CI dependency.
EOF
    exit 2
fi


printf '\n=== toolchains ===\n'
ldc2 --version | head -n 3
g++ --version | head -n 1


import_args=()

while IFS= read -r import_path
do
    [ -n "$import_path" ] || continue
    import_args+=("-I$import_path")
done < <(
    python3 tools/dub-import-paths.py         --compiler=ldc2
)


printf '\n=== build geo-d P1 semantic probe ===\n'
ldc2     -O3     -release     -boundscheck=off     -i     "${import_args[@]}"     "$D_SOURCE"     -of="$D_BIN"


printf '\n=== build independent CGAL/EPECK semantic oracle ===\n'
g++     -O2     -DNDEBUG     -std=c++20     "$CPP_SOURCE"     -lgmp     -lmpfr     -o "$CPP_BIN"


printf '\n=== run probes ===\n'
"$D_BIN" >"$D_OUT"
"$CPP_BIN" >"$CPP_OUT"


printf '\n=== geo-d P1 signature ===\n'
cat "$D_OUT"

printf '\n=== CGAL/EPECK signature ===\n'
cat "$CPP_OUT"


printf '\n=== differential comparison ===\n'
if diff -u "$CPP_OUT" "$D_OUT"; then
    printf '%s\n'         'PASS: geo-d P1 semantic signatures match CGAL/EPECK'
else
    printf '%s\n'         'FAIL: geo-d P1 differs from CGAL/EPECK'         >&2
    exit 1
fi
