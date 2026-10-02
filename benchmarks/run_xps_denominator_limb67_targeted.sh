#!/usr/bin/env bash
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$root"
cpu=${1:-0}
mkdir -p build
task_dir=$(mktemp -d "$root/build/denominator-limb67-targeted-xps.XXXXXXXX")
python3 benchmarks/run_segment_polygon_targeted_comparison.py \
  --cpu="$cpu" --cycles=3 --rounds=9 --target-ms=30 --output="$task_dir/record"
tar --exclude=benchmark -czf "$task_dir/geo-denominator-limb67-targeted-xps.tar.gz" -C "$task_dir" record
sha256sum "$task_dir/geo-denominator-limb67-targeted-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-denominator-limb67-targeted-xps.tar.gz"
