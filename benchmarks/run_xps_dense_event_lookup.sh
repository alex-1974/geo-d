#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=71a269a5ade75b987f9f63d4dcdd174e5241f3a1
candidate=c4309d056b05f4b641902fb0dc2c2069c0bb4e90
cpu=${1:-0}

mkdir -p build
task_dir=$(mktemp -d "$root/build/dense-event-lookup-xps.XXXXXXXX")

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
  -czf "$task_dir/geo-dense-event-lookup-xps.tar.gz" \
  -C "$task_dir" record run.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-dense-event-lookup-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-dense-event-lookup-xps.tar.gz"
