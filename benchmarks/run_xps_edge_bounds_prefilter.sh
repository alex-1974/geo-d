#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=ac98f4b039b682ec954ab646c6220d1103ce4a5c
candidate=2e1cc1a67b8dc913fbda03408dd33f58f8952dde
cpu=${1:-0}
notes=${2:-"XPS controlled serial run; otherwise idle."}

mkdir -p build
task_dir=$(mktemp -d "$root/build/edge-bounds-prefilter-xps.XXXXXXXX")

echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== FULL CORPUS AB/BA ==="
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
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"

tar --exclude=benchmark --exclude=preflight --exclude='*.o' \
  -czf "$task_dir/geo-edge-bounds-prefilter-xps.tar.gz" \
  -C "$task_dir" record run.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-edge-bounds-prefilter-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-edge-bounds-prefilter-xps.tar.gz"
