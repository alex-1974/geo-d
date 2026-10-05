#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

expected_head=${1:-}
cpu=${2:-0}
samples=${3:-12}

actual_head=$(git rev-parse HEAD)
if [[ -n "$expected_head" && "$actual_head" != "$expected_head" ]]; then
    echo "ERROR: expected HEAD $expected_head, got $actual_head" >&2
    exit 1
fi

if ! taskset -pc "$cpu" $$ >/dev/null 2>&1; then
    echo "ERROR: CPU $cpu is not available" >&2
    exit 1
fi

mkdir -p build
task_dir=$(mktemp -d "$root/build/normalized-dyadic-xps.XXXXXXXX")

{
    echo "head=$actual_head"
    echo "cpu=$cpu"
    echo "samples=$samples"
    echo "uname=$(uname -a)"
    echo
    echo "=== DMD ==="
    dmd --version
    echo
    echo "=== LDC ==="
    ldc2 --version
    echo
    echo "=== DUB ==="
    dub --version
} | tee "$task_dir/provenance.txt"

echo
echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 2>&1 | tee "$task_dir/dub-test-ldc2.log"

build_one() {
    local compiler=$1
    local label=$2
    local out="$task_dir/$label"
    local binary="$out/benchmark"

    mkdir -p "$out"

    mapfile -t import_paths < <(
        python3 tools/dub-import-paths.py --compiler="$compiler"
    )

    args=()
    for path in "${import_paths[@]}"; do
        args+=("-I$path")
    done

    if [[ "$label" == dmd ]]; then
        "$compiler" -i "${args[@]}"             benchmarks/normalized_dyadic_representation_bench.d             -O -inline -release -boundscheck=safeonly             -of="$binary"             >"$out/build.stdout" 2>"$out/build.stderr"
    else
        "$compiler" -i "${args[@]}"             benchmarks/normalized_dyadic_representation_bench.d             -O3 -release -boundscheck=safeonly             -of="$binary"             >"$out/build.stdout" 2>"$out/build.stderr"
    fi

    sha256sum "$binary" > "$out/binary.sha256"

    for sample in $(seq 1 "$samples"); do
        taskset -c "$cpu" "$binary"             >"$out/sample-${sample}.stdout"             2>"$out/sample-${sample}.stderr"
    done
}

echo
echo "=== BUILD + RUN DMD ==="
build_one dmd dmd

echo
echo "=== BUILD + RUN LDC ==="
build_one ldc2 ldc

tar --exclude=benchmark --exclude='*.o'     -czf "$task_dir/geo-normalized-dyadic-xps.tar.gz"     -C "$task_dir"     provenance.txt dub-test-dmd.log dub-test-ldc2.log dmd ldc

sha256sum "$task_dir/geo-normalized-dyadic-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-normalized-dyadic-xps.tar.gz"
