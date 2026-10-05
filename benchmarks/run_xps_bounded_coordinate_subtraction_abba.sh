#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=${1:-7f9237f7c4be993b7ac987a46f40d05bde8355c8}
candidate=${2:-6c46414ba70e2d5436b6c7333f97a5f4cccc14d4}
cpu=${3:-0}

actual_head=$(git rev-parse HEAD)
if [[ "$actual_head" != "$candidate" ]]; then
    echo "ERROR: expected candidate HEAD $candidate, got $actual_head" >&2
    exit 1
fi

mkdir -p build
task_dir=$(mktemp -d "$root/build/bounded-coordinate-subtraction-abba.XXXXXXXX")

{
    echo "base=$base"
    echo "candidate=$candidate"
    echo "head=$actual_head"
    echo "cpu=$cpu"
    echo "uname=$(uname -a)"
    echo
    echo "=== DMD ==="
    dmd --version
    echo
    echo "=== LDC ==="
    ldc2 --version
} | tee "$task_dir/provenance.txt"

echo
echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd --force 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 --force 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== PREBUILT ABBA ==="
python3 benchmarks/run_segment_polygon_prebuilt_abba.py \
  --base="$base" \
  --candidate="$candidate" \
  --cpu="$cpu" \
  --cycles=3 \
  --rounds=7 \
  --target-ms=50 \
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"

git diff "$base" "$candidate" -- source/geo/internal/dyadic.d \
  > "$task_dir/candidate.diff"

tar --exclude=benchmark --exclude='*.o' \
  -czf "$task_dir/geo-bounded-coordinate-subtraction-abba.tar.gz" \
  -C "$task_dir" \
  record provenance.txt run.log dub-test-dmd.log dub-test-ldc2.log candidate.diff

sha256sum "$task_dir/geo-bounded-coordinate-subtraction-abba.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-bounded-coordinate-subtraction-abba.tar.gz"
