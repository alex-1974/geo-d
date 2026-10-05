#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=${1:-7f9237f7c4be993b7ac987a46f40d05bde8355c8}
candidate=${2:-c72a9b9511d3183eb7f29d5aa9179214647c9765}
cpu=${3:-0}

mkdir -p build
task_dir=$(mktemp -d "$root/build/known-crossing-exact-xps.XXXXXXXX")

echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== PREBUILT ABBA ==="
python3 benchmarks/run_known_crossing_exact_abba.py \
  --base="$base" \
  --candidate="$candidate" \
  --cpu="$cpu" \
  --cycles=5 \
  --rounds=9 \
  --target-ms=75 \
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"

tar --exclude=benchmark --exclude='*.o' \
  -czf "$task_dir/geo-known-crossing-exact-xps.tar.gz" \
  -C "$task_dir" record run.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-known-crossing-exact-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-known-crossing-exact-xps.tar.gz"
