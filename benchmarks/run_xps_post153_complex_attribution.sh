#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-0}
rounds=${2:-7}
iterations=${3:-1000}
notes=${4:-"XPS controlled post-153 complex clipping attribution"}

mkdir -p build
task_dir=$(mktemp -d "$root/build/complex-clipping-attribution-xps.XXXXXXXX")

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
echo "=== COMPLEX CLIPPING ATTRIBUTION ==="
python3 benchmarks/run_complex_clipping_attribution.py   --compiler=dmd   --compiler=ldc2   --cpu="$cpu"   --rounds="$rounds"   --iterations="$iterations"   --notes="$notes"   --output="$task_dir/record"   | tee "$task_dir/run.log"

tar   --exclude='complex-clipping-attribution'   --exclude='*.o'   -czf "$task_dir/geo-post153-complex-attribution-xps.tar.gz"   -C "$task_dir"   record   run.log   dub-test-dmd.log   dub-test-ldc2.log

sha256sum "$task_dir/geo-post153-complex-attribution-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-post153-complex-attribution-xps.tar.gz"
