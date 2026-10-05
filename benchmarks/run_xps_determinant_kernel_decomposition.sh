#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-0}
samples=${2:-12}
expected_head=${3:-}

actual_head=$(git rev-parse HEAD)
if [[ -n "$expected_head" && "$actual_head" != "$expected_head" ]]; then
    echo "ERROR: expected HEAD $expected_head, got $actual_head" >&2
    exit 1
fi

mkdir -p build
task_dir=$(mktemp -d "$root/build/determinant-kernel-decomposition-xps.XXXXXXXX")
record="$task_dir/record"
mkdir -p "$record"

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
} | tee "$record/provenance.txt"

echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd --force 2>&1 | tee "$record/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 --force 2>&1 | tee "$record/dub-test-ldc2.log"

build_probe() {
    local compiler=$1
    local source=$2
    local output=$3
    local -a flags=(-O -release -boundscheck=off)

    if [[ "$compiler" == "dmd" ]]; then
        flags+=(-inline)
    fi

    "$compiler" "${flags[@]}" \
        -Isource \
        "$source" \
        source/geo/internal/dyadic.d \
        source/geo/internal/fixed_uint.d \
        source/geo/internal/orientation_dyadic.d \
        -of="$output"
}

run_samples() {
    local compiler=$1
    local binary=$2
    local output=$3

    : > "$output"

    for ((sample=1; sample<=samples; ++sample)); do
        echo "=== sample $sample/$samples ===" | tee -a "$output"
        taskset -c "$cpu" "$binary" 2>&1 | tee -a "$output"
    done
}

echo
echo "=== BUILD DMD PROBE ==="
build_probe dmd benchmarks/determinant_kernel_decomposition_bench.d "$task_dir/probe-dmd"
build_probe dmd benchmarks/dyadic_product_subtraction_decomposition_bench.d "$task_dir/product-subtraction-probe-dmd"

echo
echo "=== BUILD LDC PROBE ==="
build_probe ldc2 benchmarks/determinant_kernel_decomposition_bench.d "$task_dir/probe-ldc"
build_probe ldc2 benchmarks/dyadic_product_subtraction_decomposition_bench.d "$task_dir/product-subtraction-probe-ldc"

echo
echo "=== DMD SAMPLES ==="
run_samples dmd "$task_dir/probe-dmd" "$record/dmd-samples.log"

echo
echo "=== DMD PRODUCT SUBTRACTION SAMPLES ==="
run_samples dmd "$task_dir/product-subtraction-probe-dmd" "$record/dmd-product-subtraction-samples.log"

echo
echo "=== LDC SAMPLES ==="
run_samples ldc2 "$task_dir/probe-ldc" "$record/ldc-samples.log"

echo
echo "=== LDC PRODUCT SUBTRACTION SAMPLES ==="
run_samples ldc2 "$task_dir/product-subtraction-probe-ldc" "$record/ldc-product-subtraction-samples.log"

tar --exclude='probe-*' --exclude='product-subtraction-probe-*'     -czf "$task_dir/geo-determinant-kernel-decomposition-xps.tar.gz"     -C "$task_dir" record

sha256sum "$task_dir/geo-determinant-kernel-decomposition-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-determinant-kernel-decomposition-xps.tar.gz"
