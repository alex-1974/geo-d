#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=7deb69f074208ddabe2b18316820965b16cf2966
candidate=b34cf07dc70a1c3a62e04e10713f5bdeda6c521c
cpu=${1:-0}

mkdir -p build
task_dir=$(mktemp -d "$root/build/dense-event-prebuilt-abba-xps.XXXXXXXX")

echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== PREBUILT TARGETED ABBA ==="
python3 benchmarks/run_segment_polygon_prebuilt_abba.py \
  --base="$base" \
  --candidate="$candidate" \
  --cpu="$cpu" \
  --cycles=3 \
  --rounds=7 \
  --target-ms=50 \
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"

tar --exclude=benchmark -czf "$task_dir/geo-dense-event-prebuilt-abba-xps.tar.gz" \
  -C "$task_dir" record run.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-dense-event-prebuilt-abba-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-dense-event-prebuilt-abba-xps.tar.gz"
