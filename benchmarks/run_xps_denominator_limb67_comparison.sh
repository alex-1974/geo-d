#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$root"

base=4828889625ff2dd25b44dc545a5e9addb27310ef
candidate=5fe9abcece98ad8c8d0c29d97c9aa28591d20bcc
cpu=${1:-0}
notes=${2:-Power/turbo/background settings not attested.}

echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2

echo
echo "=== XPS AB/BA COMPARISON ==="
mkdir -p build
task_dir=$(mktemp -d "$root/build/denominator-limb67-xps.XXXXXXXX")

python3 benchmarks/run_segment_polygon_comparison.py \
    --base="$base" \
    --candidate="$candidate" \
    --cpu="$cpu" \
    --compiler=dmd \
    --compiler=ldc2 \
    --blocks=2 \
    --rounds=7 \
    --target-ms=20 \
    --notes="$notes" \
    --output="$task_dir/record"

tar --exclude=benchmark --exclude=preflight --exclude='*.o' \
    -czf "$task_dir/geo-denominator-limb67-xps.tar.gz" \
    -C "$task_dir" record

sha256sum "$task_dir/geo-denominator-limb67-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-denominator-limb67-xps.tar.gz"
