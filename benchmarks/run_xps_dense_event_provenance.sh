#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=5b7867ec0ee1c2fe6e47639b3b31445525bf6784
candidate=0371474be38aedaea278bf14c4f3c181d12af829
cpu=${1:-0}

mkdir -p build
task_dir=$(mktemp -d "$root/build/dense-event-provenance-xps.XXXXXXXX")

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
  -czf "$task_dir/geo-dense-event-provenance-xps.tar.gz" \
  -C "$task_dir" record run.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-dense-event-provenance-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-dense-event-provenance-xps.tar.gz"
