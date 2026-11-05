#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=c3a27454e0ae6f68d7108d4f0eafb9c6188448ba
candidate=6ca8786c8db0fdfb0b5287ae96d3114c3540614b
cpu=${1:-0}

mkdir -p build
task_dir=$(mktemp -d "$root/build/known-crossing-exact-xps.XXXXXXXX")

echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== PREBUILT ABBA ==="
python3 benchmarks/run_segment_polygon_contact_reuse_abba.py \
  --base="$base" \
  --candidate="$candidate" \
  --cpu="$cpu" \
  --cycles=3 \
  --rounds=7 \
  --target-ms=50 \
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"

tar --exclude=benchmark --exclude='*.o' \
  -czf "$task_dir/geo-known-crossing-exact-xps.tar.gz" \
  -C "$task_dir" record run.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-known-crossing-exact-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-known-crossing-exact-xps.tar.gz"
