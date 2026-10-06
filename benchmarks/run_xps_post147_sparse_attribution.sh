#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-0}
rounds=${2:-7}
iterations=${3:-1000}
notes=${4:-"XPS controlled sparse attribution run; otherwise idle."}

mkdir -p build
task_dir=$(mktemp -d "$root/build/post147-sparse-attribution-xps.XXXXXXXX")

echo "=== RESEARCH PROVENANCE ==="
git status --short --branch
git rev-parse HEAD
git log -1 --oneline --decorate

echo
echo "=== DMD/LDC UNIT TESTS ==="
dub test --compiler=dmd --force 2>&1 | tee "$task_dir/dub-test-dmd.log"
dub test --compiler=ldc2 --force 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== SPARSE STAGE ATTRIBUTION ==="
python3 benchmarks/run_sparse_clipping_attribution.py   --compiler=dmd   --compiler=ldc2   --cpu="$cpu"   --rounds="$rounds"   --iterations="$iterations"   --notes="$notes"   --output="$task_dir/record"   | tee "$task_dir/run.log"

tar --exclude='sparse-clipping-attribution' --exclude='*.o'   -czf "$task_dir/geo-post147-sparse-attribution-xps.tar.gz"   -C "$task_dir"   record   run.log   dub-test-dmd.log   dub-test-ldc2.log

sha256sum "$task_dir/geo-post147-sparse-attribution-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-post147-sparse-attribution-xps.tar.gz"
