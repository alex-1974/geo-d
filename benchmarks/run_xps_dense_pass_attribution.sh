#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-0}
iterations=${2:-200}

mkdir -p build
task_dir=$(mktemp -d "$root/build/dense-pass-attribution-xps.XXXXXXXX")

echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== MECHANISM PROFILE ==="
python3 benchmarks/profile_dense_clipping_passes.py \
  --cpu="$cpu" \
  --iterations="$iterations" \
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"

tar --exclude=profile --exclude='*.o'   -czf "$task_dir/geo-dense-pass-attribution-xps.tar.gz"   -C "$task_dir" record run.log dub-test-dmd.log

sha256sum "$task_dir/geo-dense-pass-attribution-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-dense-pass-attribution-xps.tar.gz"
