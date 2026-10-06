#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-0}
rounds=${2:-7}
iterations=${3:-1000}
notes=${4:-"XPS post-157 boundary clipping attribution"}

mkdir -p build
task_dir=$(mktemp -d "/var/tmp/geo-d-boundary-attribution-xps.XXXXXXXX")
archive="$root/build/geo-post157-boundary-attribution-xps.tar.gz"

echo "=== PROVENANCE ==="
git status --short --branch
git rev-parse HEAD
git log -1 --oneline --decorate

echo
echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd --force 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 --force 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== BOUNDARY ATTRIBUTION ==="
python3 benchmarks/run_boundary_clipping_attribution.py   --compiler=dmd   --compiler=ldc2   --cpu="$cpu"   --rounds="$rounds"   --iterations="$iterations"   --notes="$notes"   --output="$task_dir/record"   | tee "$task_dir/run.log"

tar   --exclude='boundary-clipping-attribution'   --exclude='*.o'   -czf "$task_dir/geo-post157-boundary-attribution-xps.tar.gz"   -C "$task_dir"   record   run.log   dub-test-dmd.log   dub-test-ldc2.log

cp "$task_dir/geo-post157-boundary-attribution-xps.tar.gz" "$archive"
sha256sum "$archive"
printf 'Scratch: %s\n' "$task_dir"
printf 'Archive: %s\n' "$archive"
