#!/usr/bin/env bash
set -euo pipefail
root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=4828889625ff2dd25b44dc545a5e9addb27310ef
candidate=e8c0608970a3be17836f6f3b25a3886facb92023
cpu=${1:-0}

mkdir -p build
task_dir=$(mktemp -d "$root/build/equal-denominator-unittest-only-xps.XXXXXXXX")

echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== TARGETED PREBUILT ABBA ==="
python3 benchmarks/run_segment_polygon_prebuilt_abba.py \
  --base="$base" --candidate="$candidate" --cpu="$cpu" \
  --cycles=3 --rounds=7 --target-ms=50 \
  --output="$task_dir/record" | tee "$task_dir/run.log"

tar --exclude=benchmark -czf "$task_dir/geo-equal-denominator-unittest-only-xps.tar.gz" \
  -C "$task_dir" record run.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-equal-denominator-unittest-only-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-equal-denominator-unittest-only-xps.tar.gz"
