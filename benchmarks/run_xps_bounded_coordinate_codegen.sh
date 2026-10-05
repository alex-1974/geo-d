#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

expected_head=${1:-1015067e6d07098c084eb54893383ddb6be3dcf4}
base=${2:-7f9237f7c4be993b7ac987a46f40d05bde8355c8}
candidate=${3:-38b0b095a0cfa232bc3609ba66927bc6b12a2516}

actual_head=$(git rev-parse HEAD)
if [[ "$actual_head" != "$expected_head" ]]; then
    echo "ERROR: expected recorder HEAD $expected_head, got $actual_head" >&2
    exit 1
fi

mkdir -p build
task_dir=$(mktemp -d "$root/build/bounded-coordinate-codegen-xps.XXXXXXXX")
record="$task_dir/record"

{
    echo "recorder_head=$actual_head"
    echo "base=$base"
    echo "candidate=$candidate"
    echo "uname=$(uname -a)"
    echo
    ldc2 --version
    echo
    objdump --version | head -1
} | tee "$task_dir/provenance.txt"

python3 benchmarks/record_bounded_coordinate_codegen.py \
    --base="$base" \
    --candidate="$candidate" \
    --output="$record" \
    | tee "$task_dir/run.log"

tar --exclude=benchmark --exclude='*.o' \
    -czf "$task_dir/geo-bounded-coordinate-codegen.tar.gz" \
    -C "$task_dir" record provenance.txt run.log

sha256sum "$task_dir/geo-bounded-coordinate-codegen.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-bounded-coordinate-codegen.tar.gz"
