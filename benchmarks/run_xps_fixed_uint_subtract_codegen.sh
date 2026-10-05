#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

expected_head=${1:-}
actual_head=$(git rev-parse HEAD)

if [[ -n "$expected_head" && "$actual_head" != "$expected_head" ]]; then
    echo "ERROR: expected HEAD $expected_head, got $actual_head" >&2
    exit 1
fi

mkdir -p build
task_dir=$(mktemp -d "$root/build/fixed-uint-subtract-codegen.XXXXXXXX")
record="$task_dir/record"
mkdir -p "$record"

{
    echo "head=$actual_head"
    echo "uname=$(uname -a)"
    echo
    echo "=== DMD ==="
    dmd --version
    echo
    echo "=== LDC ==="
    ldc2 --version
    echo
    echo "=== OBJDUMP ==="
    objdump --version | head -1
} | tee "$record/provenance.txt"

build_probe() {
    local compiler=$1
    local output=$2
    local -a flags=(-O -release -boundscheck=off)

    if [[ "$compiler" == "dmd" ]]; then
        flags+=(-inline)
    fi

    "$compiler" "${flags[@]}"         -Isource         benchmarks/fixed_uint_subtract_codegen.d         source/geo/internal/dyadic.d         source/geo/internal/fixed_uint.d         -of="$output"
}

record_binary() {
    local name=$1
    local binary=$2

    "$binary" 2>&1 | tee "$record/$name-run.log"
    nm -n -C "$binary" > "$record/$name-nm.txt"
    nm -n "$binary" > "$record/$name-nm-raw.txt"
    objdump -d -Mintel --no-show-raw-insn -C "$binary" \
        > "$record/$name-full.asm"

    for symbol in         probe_compare_66         probe_subtract_66         probe_compare_then_subtract_66         probe_same_sign_coordinate
    do
        objdump -d -Mintel --no-show-raw-insn             --disassemble="$symbol" "$binary"             > "$record/$name-$symbol.asm"
    done
}

echo "=== BUILD DMD ==="
build_probe dmd "$task_dir/probe-dmd"

echo "=== BUILD LDC ==="
build_probe ldc2 "$task_dir/probe-ldc"

echo "=== RECORD DMD ==="
record_binary dmd "$task_dir/probe-dmd"

echo "=== RECORD LDC ==="
record_binary ldc "$task_dir/probe-ldc"

tar -czf "$task_dir/geo-fixed-uint-subtract-codegen.tar.gz"     -C "$task_dir" record

sha256sum "$task_dir/geo-fixed-uint-subtract-codegen.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-fixed-uint-subtract-codegen.tar.gz"
