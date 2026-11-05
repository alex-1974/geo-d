#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=434671f826120b6a182885067df3748f1bfef577
candidate=e6c065ddab2c304d74047e8b8e5f0c83a94ac041
cpu=${1:-0}

mkdir -p build
task_dir=$(mktemp -d "$root/build/vertex-query-bounds-xps.XXXXXXXX")

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
  -czf "$task_dir/geo-vertex-query-bounds-xps.tar.gz" \
  -C "$task_dir" record run.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-vertex-query-bounds-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-vertex-query-bounds-xps.tar.gz"
